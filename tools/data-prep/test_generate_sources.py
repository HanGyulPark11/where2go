"""Standard-library tests for generate_sources.py.

Run from the repository root:
    python tools/data-prep/test_generate_sources.py
"""

import importlib.util
import os
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
GENERATOR_PATH = os.path.join(HERE, "generate_sources.py")
SPEC = importlib.util.spec_from_file_location("sources_generator", GENERATOR_PATH)
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class SourcesGeneratorTests(unittest.TestCase):
    def test_keeps_equippable_armor_and_weapon_rewards(self):
        armor = {
            "item_class": {"name": "Armor"},
            "item_subclass": {"name": "Cloth"},
            "inventory_type": {"type": "HEAD"},
        }
        weapon = {
            "item_class": {"name": "Weapon"},
            "item_subclass": {"name": "Dagger"},
            "inventory_type": {"type": "WEAPON"},
        }

        self.assertTrue(GENERATOR.is_gear_reward(armor))
        self.assertTrue(GENERATOR.is_gear_reward(weapon))

    def test_rejects_non_equippable_and_cosmetic_rewards(self):
        cases = [
            {
                "item_class": {"name": "Housing"},
                "item_subclass": {"name": "Decor"},
                "inventory_type": {"type": "NON_EQUIP"},
            },
            {
                "item_class": {"name": "Recipe"},
                "item_subclass": {"name": "Tailoring"},
                "inventory_type": {"type": "NON_EQUIP"},
            },
            {
                "item_class": {"name": "Miscellaneous"},
                "item_subclass": {"name": "Mount"},
                "inventory_type": {"type": "NON_EQUIP"},
            },
            {
                "item_class": {"name": "Armor"},
                "item_subclass": {"name": "Cosmetic"},
                "inventory_type": {"type": "HEAD"},
            },
        ]

        for item_data in cases:
            self.assertFalse(GENERATOR.is_gear_reward(item_data))


if __name__ == "__main__":
    unittest.main()
