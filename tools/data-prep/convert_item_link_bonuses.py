"""Convert a reviewed Where2Go item-link SavedVariables export into Lua.

Usage (PowerShell):
    python tools/data-prep/convert_item_link_bonuses.py "C:\\...\\WTF\\Account\\<account>\\SavedVariables\\Where2Go.lua"

The script reads only the supplied SavedVariables file and writes only
tools/data-prep/scratch/ItemLinkBonuses.lua.new. It rejects a stale or invalid
export, conflicts, unresolved full links, and incomplete tracked-item coverage.
It preserves Encounter Journal context and modifiers while removing volatile
character fields and upgrade-track bonuses. Review the printed diff before
manually applying the staged file to Core/ItemLinkBonuses.lua.
"""

import argparse
import difflib
import os
import re
import sys


HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRATCH_PATH = os.path.join(HERE, "scratch", "ItemLinkBonuses.lua.new")
SOURCES_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Sources.lua")
CONSTANTS_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Constants.lua")
TRACKS_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Tracks.lua")
RAID_RANKS_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "RaidRanks.lua")
CURRENT_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "ItemLinkBonuses.lua")
SCHEMA_VERSION = 2


class LuaParseError(ValueError):
    pass


TOKEN_RE = re.compile(
    r'''\s*(?:--[^\n]*\n\s*)*(?:(?P<string>"(?:\\.|[^"\\])*")|(?P<number>-?\d+(?:\.\d+)?)|(?P<identifier>[A-Za-z_][A-Za-z0-9_]*)|(?P<symbol>[{}\[\]=,;]))'''
)


def tokenize(text):
    tokens = []
    position = 0
    while position < len(text):
        match = TOKEN_RE.match(text, position)
        if not match:
            if text[position:].strip() == "":
                break
            raise LuaParseError(f"unsupported Lua syntax at character {position}")
        position = match.end()
        kind = match.lastgroup
        value = match.group(kind)
        if kind == "string":
            try:
                value = bytes(value[1:-1], "utf-8").decode("unicode_escape")
            except UnicodeDecodeError as error:
                raise LuaParseError(f"invalid Lua string: {error}") from error
        elif kind == "number":
            value = int(value) if "." not in value else float(value)
        tokens.append((kind, value))
    return tokens


class LuaTableParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def take(self, expected=None):
        token = self.peek()
        if token is None:
            raise LuaParseError("unexpected end of SavedVariables file")
        if expected is not None and token[1] != expected:
            raise LuaParseError(f"expected {expected!r}, got {token[1]!r}")
        self.position += 1
        return token

    def parse_value(self):
        token = self.peek()
        if token is None:
            raise LuaParseError("expected a value")
        if token[1] == "{":
            return self.parse_table()
        self.position += 1
        if token[0] in ("string", "number"):
            return token[1]
        if token[0] == "identifier" and token[1] in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[token[1]]
        raise LuaParseError(f"unsupported Lua value {token[1]!r}")

    def parse_table(self):
        self.take("{")
        table = {}
        next_array_index = 1
        while self.peek() and self.peek()[1] != "}":
            token = self.peek()
            following = self.tokens[self.position + 1] if self.position + 1 < len(self.tokens) else None
            if token[1] == "[":
                self.take("[")
                key = self.parse_value()
                self.take("]")
                self.take("=")
                value = self.parse_value()
            elif token[0] == "identifier" and following and following[1] == "=":
                key = self.take()[1]
                self.take("=")
                value = self.parse_value()
            else:
                key = next_array_index
                next_array_index += 1
                value = self.parse_value()
            table[key] = value
            if self.peek() and self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return table


def parse_where2go_db(text):
    tokens = tokenize(text)
    for index in range(len(tokens) - 2):
        if tokens[index] == ("identifier", "Where2GoDB") and tokens[index + 1][1] == "=":
            parser = LuaTableParser(tokens[index + 2:])
            value = parser.parse_value()
            if not isinstance(value, dict):
                raise LuaParseError("Where2GoDB is not a table")
            return value
    raise LuaParseError("Where2GoDB assignment not found")


def table_list(value, label):
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a Lua array table")
    keys = sorted(value)
    if any(type(key) is not int for key in keys):
        raise ValueError(f"{label} must have exact integer keys")
    if keys != list(range(1, len(keys) + 1)):
        raise ValueError(f"{label} must have contiguous numeric keys")
    return [value[index] for index in keys]


def expected_season():
    text = read_text(CONSTANTS_PATH)
    match = re.search(r'Where2GoConstants\.SEASON_LABEL\s*=\s*"([^"]+)"', text)
    if not match:
        raise ValueError("could not read Where2GoConstants.SEASON_LABEL")
    return match.group(1)


def tracked_item_ids():
    item_ids = set()
    for match in re.finditer(r"itemIds\s*=\s*\{([^}]*)\}", read_text(SOURCES_PATH)):
        for value in match.group(1).split(","):
            value = value.strip()
            if value:
                item_ids.add(int(value))
    if not item_ids:
        raise ValueError("Sources.lua contains no tracked item IDs")
    return item_ids


def parse_upgrade_tracks(text):
    assignment = re.search(r"Where2GoTracks\s*\.\s*UPGRADE_TRACKS\s*=", text)
    if not assignment:
        raise ValueError("could not find Where2GoTracks.UPGRADE_TRACKS")
    try:
        tracks = LuaTableParser(tokenize(text[assignment.end():])).parse_value()
    except LuaParseError as error:
        raise ValueError(f"could not parse Where2GoTracks.UPGRADE_TRACKS: {error}") from error
    if not isinstance(tracks, dict) or not tracks:
        raise ValueError("Where2GoTracks.UPGRADE_TRACKS must be a non-empty table")
    return tracks


def track_bonus_ids(tracks_text=None, raid_ranks_text=None):
    tracks = parse_upgrade_tracks(tracks_text if tracks_text is not None else read_text(TRACKS_PATH))
    track_ids = set()
    for track_name, track in tracks.items():
        if not isinstance(track_name, str) or not isinstance(track, dict):
            raise ValueError("every UPGRADE_TRACKS entry must be a named table")
        start = track.get("bonusIdStart")
        if type(start) is not int or start <= 0:
            raise ValueError(f"UPGRADE_TRACKS.{track_name} lacks a valid bonusIdStart")
        try:
            ilvls = table_list(track.get("ilvls"), f"UPGRADE_TRACKS.{track_name}.ilvls")
        except ValueError as error:
            raise ValueError(f"UPGRADE_TRACKS.{track_name} lacks a valid ilvls list") from error
        if not ilvls or any(type(ilvl) is not int or ilvl <= 0 for ilvl in ilvls):
            raise ValueError(f"UPGRADE_TRACKS.{track_name} lacks a valid ilvls list")
        track_ids.update(range(start, start + len(ilvls)))
    raid_ranks_text = raid_ranks_text if raid_ranks_text is not None else read_text(RAID_RANKS_PATH)
    final_match = re.search(r"MYTH_FINAL_BONUS_ID\s*=\s*(\d+)", raid_ranks_text)
    if not final_match:
        raise ValueError("could not derive Where2GoRaidRanks.MYTH_FINAL_BONUS_ID")
    track_ids.add(int(final_match.group(1)))
    return track_ids


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def validate_export(export):
    if not isinstance(export, dict):
        raise ValueError("Where2GoDB.itemLinkBonusesExport is missing or not a table")
    if type(export.get("schemaVersion")) is not int or export.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError(f"unsupported item-link export schema {export.get('schemaVersion')!r}")
    season = expected_season()
    if export.get("seasonVersion") != season:
        raise ValueError(f"export season {export.get('seasonVersion')!r} does not match {season!r}")

    conflicts = export.get("conflicts")
    if not isinstance(conflicts, dict):
        raise ValueError("export conflicts diagnostic is missing")
    if conflicts:
        raise ValueError("export contains conflicting residual bonus lists; resolve them in-game before conversion")

    unresolved_link_items = table_list(export.get("unresolvedLinkItems"), "unresolvedLinkItems")
    if any(type(item_id) is not int or item_id <= 0 for item_id in unresolved_link_items):
        raise ValueError("unresolvedLinkItems contains an invalid item ID")
    if unresolved_link_items:
        raise ValueError(
            f"export has {len(unresolved_link_items)} tracked item(s) with unresolved full links: {unresolved_link_items}")

    missing_items = table_list(export.get("missingItems"), "missingItems")
    if any(type(item_id) is not int or item_id <= 0 for item_id in missing_items):
        raise ValueError("missingItems contains an invalid item ID")
    if missing_items:
        raise ValueError(f"export is missing {len(missing_items)} tracked item(s): {missing_items}")

    expected_ids = tracked_item_ids()
    if type(export.get("trackedItemCount")) is not int or export.get("trackedItemCount") != len(expected_ids):
        raise ValueError("trackedItemCount does not match the current Sources.lua pool")
    if type(export.get("observedItemCount")) is not int or export.get("observedItemCount") != len(expected_ids):
        raise ValueError("observedItemCount is incomplete; refuse suspicious coverage")

    by_item = export.get("byItem")
    if not isinstance(by_item, dict):
        raise ValueError("export byItem table is missing")
    if any(type(item_id) is not int or item_id <= 0 for item_id in by_item):
        raise ValueError("export byItem contains an invalid item ID")
    actual_ids = set(by_item)
    if actual_ids != expected_ids:
        missing = sorted(expected_ids - actual_ids)
        unexpected = sorted(actual_ids - expected_ids)
        raise ValueError(f"byItem coverage differs from Sources.lua (missing={missing}, unexpected={unexpected})")

    raw_links = export.get("rawLinks")
    if not isinstance(raw_links, dict):
        raise ValueError("export rawLinks diagnostic is missing")
    raw_link_ids = set(raw_links)
    if raw_link_ids != expected_ids:
        missing = sorted(expected_ids - raw_link_ids)
        unexpected = sorted(raw_link_ids - expected_ids)
        raise ValueError(f"rawLinks coverage differs from Sources.lua (missing={missing}, unexpected={unexpected})")
    for item_id in sorted(expected_ids):
        links = table_list(raw_links[item_id], f"rawLinks[{item_id}]")
        if not links or any(type(link) is not str or not link for link in links):
            raise ValueError(f"rawLinks[{item_id}] must contain one or more non-empty strings")

    forbidden = track_bonus_ids()
    validated = {}
    for item_id in sorted(expected_ids):
        if type(item_id) is not int or item_id <= 0:
            raise ValueError(f"invalid byItem item ID {item_id!r}")
        bonuses = table_list(by_item[item_id], f"byItem[{item_id}]")
        if any(type(bonus_id) is not int or bonus_id <= 0 for bonus_id in bonuses):
            raise ValueError(f"byItem[{item_id}] contains an invalid bonus ID")
        if len(bonuses) != len(set(bonuses)):
            raise ValueError(f"byItem[{item_id}] contains duplicate bonus IDs")
        if forbidden.intersection(bonuses):
            raise ValueError(f"byItem[{item_id}] still contains an upgrade-track bonus ID")
        validated[item_id] = bonuses

    return validated


def normalize_template(raw_link, expected_item_id, residual_bonuses):
    match = re.search(r"(?:^|\|H)(item:[^|]+)(?:\|h|$)", raw_link)
    if not match:
        raise ValueError(f"raw link for item {expected_item_id} has no item payload")
    fields = match.group(1).split(":")
    if len(fields) < 14 or fields[0] != "item":
        raise ValueError(f"raw link for item {expected_item_id} is truncated")
    try:
        item_id = int(fields[1])
        bonus_count = int(fields[13])
    except ValueError as error:
        raise ValueError(f"raw link for item {expected_item_id} has invalid numeric fields") from error
    if item_id != expected_item_id or bonus_count < 0 or len(fields) < 14 + bonus_count:
        raise ValueError(f"raw link for item {expected_item_id} does not match its export entry")

    try:
        item_context = int(fields[12])
    except ValueError as error:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid item context") from error
    if item_context < 0:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid item context")

    parsed_bonuses = []
    try:
        parsed_bonuses = [int(value) for value in fields[14:14 + bonus_count]]
    except ValueError as error:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid bonus ID") from error
    residual_from_link = [bonus for bonus in parsed_bonuses if bonus not in track_bonus_ids()]
    if residual_from_link != residual_bonuses:
        raise ValueError(f"raw link bonuses disagree with byItem[{expected_item_id}]")

    modifier_count_index = 14 + bonus_count
    if len(fields) <= modifier_count_index:
        raise ValueError(f"raw link for item {expected_item_id} is missing its modifier count")
    modifier_count_text = fields[modifier_count_index]
    try:
        modifier_count = int(modifier_count_text) if modifier_count_text else 0
    except ValueError as error:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid modifier count") from error
    if modifier_count < 0:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid modifier count")
    modifier_end = modifier_count_index + 1 + (modifier_count * 2)
    if len(fields) < modifier_end:
        raise ValueError(f"raw link for item {expected_item_id} has a truncated modifier pair")
    try:
        modifier_values = [int(value) for value in fields[modifier_count_index + 1:modifier_end]]
    except ValueError as error:
        raise ValueError(f"raw link for item {expected_item_id} has an invalid modifier pair") from error
    if any(value < 0 for value in modifier_values):
        raise ValueError(f"raw link for item {expected_item_id} has an invalid modifier pair")

    # Item fields before itemContext contain character/cache-specific values
    # such as link level and specialization. Normalize them while preserving
    # itemContext, bonus order, modifiers, and the remaining full-link tail.
    normalized = fields[:]
    for index in range(2, 12):
        normalized[index] = "0"
    normalized[13] = str(len(residual_bonuses))
    normalized = (
        normalized[:14]
        + [str(bonus) for bonus in residual_bonuses]
        + fields[14 + bonus_count:]
    )
    return ":".join(normalized)


def build_templates(export, by_item):
    templates = {}
    raw_links = export["rawLinks"]
    for item_id, residual_bonuses in sorted(by_item.items()):
        alternatives = []
        for raw_link in table_list(raw_links[item_id], f"rawLinks[{item_id}]"):
            template = normalize_template(raw_link, item_id, residual_bonuses)
            if template not in alternatives:
                alternatives.append(template)
        if len(alternatives) != 1:
            raise ValueError(f"item {item_id} has conflicting full-link templates")
        templates[item_id] = alternatives[0]
    return templates


def render_lua(templates, season):
    lines = [
        "-- Regenerated by tools/data-prep/convert_item_link_bonuses.py from a",
        f"-- reviewed in-client Encounter Journal export for {season}. Do not hand-edit --",
        "-- rerun /w2g genlinks and this converter when the tracked item pool changes.",
        "-- luacheck: globals Where2GoItemLinkBonuses",
        "",
        "Where2GoItemLinkBonuses = {",
        "    TEMPLATES = {",
    ]
    for item_id in sorted(templates):
        lines.append(f'        [{item_id}] = "{templates[item_id]}",')
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def print_diff(new_content):
    current = read_text(CURRENT_PATH) if os.path.exists(CURRENT_PATH) else ""
    diff = difflib.unified_diff(
        current.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile="Where2Go/Core/ItemLinkBonuses.lua (current)",
        tofile="tools/data-prep/scratch/ItemLinkBonuses.lua.new (generated)",
    )
    text = "".join(diff)
    print(text if text else "No differences from the current ItemLinkBonuses.lua.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("saved_variables", help="path to WTF/.../SavedVariables/Where2Go.lua")
    args = parser.parse_args()

    try:
        database = parse_where2go_db(read_text(args.saved_variables))
        export = database.get("itemLinkBonusesExport")
        by_item = validate_export(export)
        templates = build_templates(export, by_item)
        output = render_lua(templates, expected_season())
    except (OSError, LuaParseError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    os.makedirs(os.path.dirname(SCRATCH_PATH), exist_ok=True)
    with open(SCRATCH_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(output)
    print(f"Staged output written to {SCRATCH_PATH} ({len(templates)} full item-link template(s))")
    print_diff(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
