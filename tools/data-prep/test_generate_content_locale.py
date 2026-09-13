"""Standard-library tests for generate_content_locale.py.

Run from the repository root:
    python tools/data-prep/test_generate_content_locale.py
"""

import importlib.util
import os
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR_PATH = os.path.join(HERE, "generate_content_locale.py")
SPEC = importlib.util.spec_from_file_location("content_locale_generator", GENERATOR_PATH)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class ContentLocaleGeneratorTests(unittest.TestCase):
    def test_builds_canonical_to_localized_mapping_by_id(self):
        canonical = {
            "dungeons": [
                {
                    "instanceId": 10,
                    "name": "English Dungeon",
                    "encounters": [
                        {"bossId": 101, "name": "English Boss", "itemIds": [1]},
                    ],
                },
            ],
            "raids": [
                {
                    "instanceId": 20,
                    "name": "English Raid",
                    "encounters": [
                        {"bossId": 201, "name": "English Raid Boss", "itemIds": [2]},
                    ],
                },
            ],
        }
        localized = {
            "dungeons": [
                {
                    "instanceId": 10,
                    "name": "한글 던전",
                    "encounters": [
                        {"bossId": 101, "name": "한글 보스", "itemIds": [1]},
                    ],
                },
            ],
            "raids": [
                {
                    "instanceId": 20,
                    "name": "한글 레이드",
                    "encounters": [
                        {"bossId": 201, "name": "한글 레이드 보스", "itemIds": [2]},
                    ],
                },
            ],
        }

        mapping = GENERATOR.build_content_name_mapping(canonical, localized)

        self.assertEqual(mapping["English Dungeon"], "한글 던전")
        self.assertEqual(mapping["English Boss"], "한글 보스")
        self.assertEqual(mapping["English Raid"], "한글 레이드")
        self.assertEqual(mapping["English Raid Boss"], "한글 레이드 보스")

    def test_rejects_missing_localized_ids(self):
        canonical = {
            "dungeons": [
                {
                    "instanceId": 10,
                    "name": "English Dungeon",
                    "encounters": [
                        {"bossId": 101, "name": "English Boss", "itemIds": [1]},
                    ],
                },
            ],
            "raids": [],
        }
        localized = {"dungeons": [{"instanceId": 10, "name": "한글 던전", "encounters": []}], "raids": []}

        with self.assertRaisesRegex(ValueError, "bossId 101"):
            GENERATOR.build_content_name_mapping(canonical, localized)

    def test_renders_locale_tables_for_manual_review(self):
        content = GENERATOR.render_lua_table(
            {
                "enUS": {"English Raid": "English Raid"},
                "koKR": {"English Raid": "한글 레이드"},
            }
        )

        self.assertIn('Where2GoLocale.CONTENT_NAMES = {', content)
        self.assertIn('["English Raid"] = "English Raid"', content)
        self.assertIn('["English Raid"] = "한글 레이드"', content)


if __name__ == "__main__":
    unittest.main()
