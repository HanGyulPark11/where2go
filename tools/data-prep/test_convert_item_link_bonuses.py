"""Standard-library tests for convert_item_link_bonuses.py.

Run from the repository root:
    python tools/data-prep/test_convert_item_link_bonuses.py
"""

import importlib.util
import os
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER_PATH = os.path.join(HERE, "convert_item_link_bonuses.py")
SPEC = importlib.util.spec_from_file_location("item_link_bonus_converter", CONVERTER_PATH)
CONVERTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONVERTER)


class ConverterValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.item_ids = CONVERTER.tracked_item_ids()
        cls.season = CONVERTER.expected_season()

    def complete_export(self):
        return {
            "schemaVersion": CONVERTER.SCHEMA_VERSION,
            "seasonVersion": self.season,
            "trackedItemCount": len(self.item_ids),
            "observedItemCount": len(self.item_ids),
            "byItem": {item_id: {} for item_id in self.item_ids},
            "rawLinks": {item_id: {1: f"item:{item_id}:diagnostic"} for item_id in self.item_ids},
            "conflicts": {},
            "missingItems": {},
            "unresolvedLinkItems": {},
        }

    def test_accepts_complete_current_export(self):
        rows = ", ".join(f"[{item_id}] = {{}}" for item_id in sorted(self.item_ids))
        saved_variables = (
            "Where2GoDB = { itemLinkBonusesExport = { "
            f"schemaVersion = {CONVERTER.SCHEMA_VERSION}, "
            f"seasonVersion = \"{self.season}\", "
            f"trackedItemCount = {len(self.item_ids)}, "
            f"observedItemCount = {len(self.item_ids)}, "
            f"byItem = {{ {rows} }}, rawLinks = {{ {', '.join(f'[{item_id}] = {{\"item:{item_id}:diagnostic\"}}' for item_id in sorted(self.item_ids))} }}, "
            "conflicts = {}, missingItems = {}, unresolvedLinkItems = {} "
            "} }"
        )
        database = CONVERTER.parse_where2go_db(saved_variables)
        validated = CONVERTER.validate_export(database["itemLinkBonusesExport"])
        self.assertEqual(set(validated), self.item_ids)

    def test_rejects_stale_schema_and_season(self):
        export = self.complete_export()
        export["schemaVersion"] = 999
        with self.assertRaisesRegex(ValueError, "schema"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["seasonVersion"] = "Old Season"
        with self.assertRaisesRegex(ValueError, "season"):
            CONVERTER.validate_export(export)

    def test_rejects_boolean_schema_counts_and_item_ids(self):
        export = self.complete_export()
        export["schemaVersion"] = True
        with self.assertRaisesRegex(ValueError, "schema"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["trackedItemCount"] = True
        with self.assertRaisesRegex(ValueError, "trackedItemCount"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["observedItemCount"] = False
        with self.assertRaisesRegex(ValueError, "observedItemCount"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["missingItems"] = {1: True}
        with self.assertRaisesRegex(ValueError, "missingItems"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["byItem"][True] = {}
        with self.assertRaisesRegex(ValueError, "item ID"):
            CONVERTER.validate_export(export)

    def test_rejects_conflicts_and_missing_coverage(self):
        export = self.complete_export()
        item_id = min(self.item_ids)
        export["conflicts"] = {item_id: {1: {7777}, 2: {8888}}}
        with self.assertRaisesRegex(ValueError, "conflicting"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["missingItems"] = {1: item_id}
        export["observedItemCount"] -= 1
        export["byItem"].pop(item_id)
        with self.assertRaisesRegex(ValueError, "missing"):
            CONVERTER.validate_export(export)

    def test_rejects_unresolved_full_links(self):
        export = self.complete_export()
        export["unresolvedLinkItems"] = {1: min(self.item_ids)}
        with self.assertRaisesRegex(ValueError, "unresolved"):
            CONVERTER.validate_export(export)

    def test_requires_raw_link_diagnostics_for_every_tracked_item(self):
        export = self.complete_export()
        export["rawLinks"].pop(min(self.item_ids))
        with self.assertRaisesRegex(ValueError, "rawLinks coverage"):
            CONVERTER.validate_export(export)

        export = self.complete_export()
        export["rawLinks"][min(self.item_ids)] = {1: 123}
        with self.assertRaisesRegex(ValueError, "rawLinks.*string"):
            CONVERTER.validate_export(export)

    def test_accepts_shared_residual_when_full_links_supply_context(self):
        export = self.complete_export()
        export["byItem"] = {item_id: {1: 3524} for item_id in self.item_ids}
        validated = CONVERTER.validate_export(export)
        self.assertTrue(all(bonuses == [3524] for bonuses in validated.values()))

    def test_builds_locale_independent_templates_from_full_ej_links(self):
        item_id = min(self.item_ids)
        export = self.complete_export()
        export["rawLinks"][item_id] = {
            1: (
                f"|cnIQ4:|Hitem:{item_id}::::::::90:262::6:2:3524:12850:"
                "1:28:7362:::::|h[Localized name]|h|r"
            )
        }
        templates = CONVERTER.build_templates(export, {item_id: [3524]})
        self.assertEqual(
            templates[item_id],
            f"item:{item_id}:0:0:0:0:0:0:0:0:0:0:6:1:3524:1:28:7362:::::",
        )

    def test_rejects_conflicting_normalized_templates_for_one_item(self):
        item_id = min(self.item_ids)
        export = self.complete_export()
        export["rawLinks"][item_id] = {
            1: f"item:{item_id}::::::::90:262::6:1:3524:1:28:7362:::::",
            2: f"item:{item_id}::::::::90:262::2:1:3524:1:28:3024:::::",
        }
        with self.assertRaisesRegex(ValueError, "conflicting full-link templates"):
            CONVERTER.build_templates(export, {item_id: [3524]})

    def test_rejects_invalid_context_and_modifier_tail(self):
        item_id = min(self.item_ids)

        with self.assertRaisesRegex(ValueError, "item context"):
            CONVERTER.normalize_template(
                f"item:{item_id}::::::::90:262::bad:1:3524:1:28:7362:::::",
                item_id,
                [3524],
            )

        with self.assertRaisesRegex(ValueError, "modifier count"):
            CONVERTER.normalize_template(
                f"item:{item_id}::::::::90:262::6:1:3524:bad:28:7362:::::",
                item_id,
                [3524],
            )

        with self.assertRaisesRegex(ValueError, "modifier pair"):
            CONVERTER.normalize_template(
                f"item:{item_id}::::::::90:262::6:1:3524:1:28",
                item_id,
                [3524],
            )

        with self.assertRaisesRegex(ValueError, "modifier pair"):
            CONVERTER.normalize_template(
                f"item:{item_id}::::::::90:262::6:1:3524:1:kind:value:::::",
                item_id,
                [3524],
            )

    def test_rejects_upgrade_track_bonus(self):
        export = self.complete_export()
        item_id = min(self.item_ids)
        export["byItem"][item_id] = {1: min(CONVERTER.track_bonus_ids())}
        with self.assertRaisesRegex(ValueError, "upgrade-track"):
            CONVERTER.validate_export(export)

    def test_preserves_residual_bonus_order_and_rejects_duplicates(self):
        export = self.complete_export()
        item_id = min(self.item_ids)
        export["byItem"][item_id] = {1: 7003, 2: 7001}
        validated = CONVERTER.validate_export(export)
        self.assertEqual(validated[item_id], [7003, 7001])

        export["byItem"][item_id] = {1: 7003, 2: 7003}
        with self.assertRaisesRegex(ValueError, "duplicate"):
            CONVERTER.validate_export(export)

    def test_rejects_boolean_bonus_and_track_values(self):
        export = self.complete_export()
        item_id = min(self.item_ids)
        export["byItem"][item_id] = {1: True}
        with self.assertRaisesRegex(ValueError, "invalid bonus"):
            CONVERTER.validate_export(export)

        final_bonus = "Where2GoRaidRanks.MYTH_FINAL_BONUS_ID = 99"
        with self.assertRaisesRegex(ValueError, "bonusIdStart"):
            CONVERTER.track_bonus_ids(
                "Where2GoTracks.UPGRADE_TRACKS = { BROKEN = { bonusIdStart = true, ilvls = { 1 } } }",
                final_bonus)
        with self.assertRaisesRegex(ValueError, "ilvls"):
            CONVERTER.track_bonus_ids(
                "Where2GoTracks.UPGRADE_TRACKS = { BROKEN = { bonusIdStart = 10, ilvls = { true } } }",
                final_bonus)

    def test_rejects_malformed_saved_variables(self):
        with self.assertRaisesRegex(CONVERTER.LuaParseError, "unexpected end"):
            CONVERTER.parse_where2go_db("Where2GoDB = { itemLinkBonusesExport = {")

    def test_renders_static_bonus_rows_in_item_id_order(self):
        output = CONVERTER.render_lua(
            {200: "item:200:template", 100: "item:100:template"}, self.season)
        self.assertIn("-- luacheck: globals Where2GoItemLinkBonuses", output)
        self.assertIn('[100] = "item:100:template",', output)
        self.assertIn('[200] = "item:200:template",', output)
        self.assertLess(output.index("[100]"), output.index("[200]"))

    def test_parses_upgrade_tracks_regardless_of_field_order(self):
        tracks = '''
Where2GoTracks.UPGRADE_TRACKS = {
    FIRST = { ilvls = { 1, 2 }, label = "First", bonusIdStart = 10 },
    SECOND = { bonusIdStart = 20, ilvls = { 3 }, order = 2 },
}
'''
        final_bonus = "Where2GoRaidRanks.MYTH_FINAL_BONUS_ID = 99"
        self.assertEqual(CONVERTER.track_bonus_ids(tracks, final_bonus), {10, 11, 20, 99})

    def test_rejects_partial_or_malformed_upgrade_tracks(self):
        final_bonus = "Where2GoRaidRanks.MYTH_FINAL_BONUS_ID = 99"
        with self.assertRaisesRegex(ValueError, "bonusIdStart"):
            CONVERTER.track_bonus_ids(
                "Where2GoTracks.UPGRADE_TRACKS = { BROKEN = { ilvls = { 1 } } }", final_bonus)
        with self.assertRaisesRegex(ValueError, "ilvls"):
            CONVERTER.track_bonus_ids(
                "Where2GoTracks.UPGRADE_TRACKS = { BROKEN = { bonusIdStart = 10 } }", final_bonus)
        with self.assertRaisesRegex(ValueError, "could not parse"):
            CONVERTER.track_bonus_ids(
                "Where2GoTracks.UPGRADE_TRACKS = { BROKEN = { bonusIdStart = 10, ilvls = { 1 } }",
                final_bonus)


if __name__ == "__main__":
    unittest.main()
