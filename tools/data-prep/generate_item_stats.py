"""Fetch per-item stat metadata (primary/secondary stat types) for every
item referenced in Where2Go/Core/Sources.lua, from the Battle.net Game
Data API. Stages output at tools/data-prep/scratch/ItemStats.lua.new and
prints a diff against the committed Where2Go/Core/ItemStats.lua for
review -- never writes that file directly.

Usage:
    $env:BLIZZARD_CLIENT_ID="<your id>"; $env:BLIZZARD_CLIENT_SECRET="<your secret>"; python tools/data-prep/generate_item_stats.py

See docs/SEASON_CHECKLIST.md for the full season-changeover procedure.
"""

import difflib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_sources import get_token, api_get  # noqa: E402

SCRATCH = os.path.join(HERE, "scratch")
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Sources.lua")
ITEM_STATS_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "ItemStats.lua")

PRIMARY_STAT_TYPES = {"STRENGTH", "AGILITY", "INTELLECT"}
SECONDARY_STAT_TYPES = {"CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY"}


def extract_item_ids(sources_lua_text):
    item_ids = set()
    for match in re.finditer(r"itemIds\s*=\s*\{([^}]*)\}", sources_lua_text):
        for piece in match.group(1).split(","):
            piece = piece.strip()
            if piece:
                item_ids.add(int(piece))
    return item_ids


def fetch_item_stats(token, item_id):
    data = api_get(token, f"/data/wow/item/{item_id}")
    preview = data.get("preview_item", {})
    stats = preview.get("stats", [])
    primary_stats = []
    secondary_stats = []
    for stat in stats:
        if stat.get("is_negated"):
            continue
        stat_type = stat.get("type", {}).get("type")
        if stat_type in PRIMARY_STAT_TYPES:
            primary_stats.append(stat_type)
        elif stat_type in SECONDARY_STAT_TYPES:
            secondary_stats.append(stat_type)
    return {"primaryStats": primary_stats, "secondaryStats": secondary_stats}
