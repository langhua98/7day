import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_data


ITEMS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<items>
  <item name="baseItem">
    <property name="Stacknumber" value="10"/>
    <property name="EconomicValue" value="5"/>
    <property name="Tags" value="base,tag"/>
  </item>
  <item name="childItem">
    <property name="Extends" value="baseItem"/>
    <property name="Stacknumber" value="20"/>
  </item>
  <item name="toolItem">
    <property name="Extends" value="baseItem"/>
    <property name="Tags" value="tool"/>
    <effect_group>
      <passive_effect name="DegradationMax" operation="base_set" value="250,500"/>
    </effect_group>
  </item>
</items>
"""

LOC_CSV = """Key,File,Type,english,schinese
childItem,items,Ammo,Child EN,子物品
toolItem,items,Tool,Tool EN,子工具
"""

BLOCKS_GD = '''
const TYPES := [
	["frameShapes", "木框", "Wood Frame", 40.0, Color(0.66, 0.5, 0.32)],
	["woodShapes", "木块", "Wood Block", 100.0, Color(0.52, 0.36, 0.21)],
]
'''


class BuildDataTest(unittest.TestCase):
    def test_items_inherit_properties(self):
        items = build_data.parse_items_xml(ITEMS_XML)
        self.assertEqual(items["childItem"]["stack"], 20)
        self.assertEqual(items["childItem"]["value"], 5)
        self.assertEqual(items["childItem"]["tags"], "base,tag")
        self.assertEqual(items["baseItem"]["stack"], 10)

    def test_durability_from_passive_effect(self):
        items = build_data.parse_items_xml(ITEMS_XML)
        self.assertEqual(items["toolItem"]["durability"], 500.0)
        self.assertEqual(items["toolItem"]["tags"], "tool")
        self.assertEqual(items["toolItem"]["value"], 5)

    def test_localization_prefers_schinese(self):
        loc = build_data.load_localization(LOC_CSV)
        self.assertEqual(loc["childItem"], "子物品")
        self.assertEqual(loc["toolItem"], "子工具")

    def test_build_only_index_ids_and_blocks(self):
        items = build_data.parse_items_xml(ITEMS_XML)
        loc = build_data.load_localization(LOC_CSV)
        index_rows = [["childItem", "子索引", "Child EN", ""], ["missingItem", "缺少", "Missing", ""]]
        blocks = build_data.block_types_from_gd(BLOCKS_GD)
        out = build_data.build_items(items, loc, index_rows, blocks)
        self.assertIn("childItem", out)
        self.assertNotIn("missingItem", out)
        self.assertNotIn("toolItem", out)  # 不在物品索引里
        self.assertEqual(out["childItem"]["zh"], "子物品")
        self.assertEqual(out["childItem"]["stack"], 20)
        self.assertEqual(out["frameShapes"]["zh"], "木框")
        self.assertEqual(out["frameShapes"]["stack"], 999)
        self.assertEqual(out["woodShapes"]["durability"], 100.0)

GAMESTAGES_XML = """<gamestages>
  <spawner name="BloodMoonHorde">
    <gamestage stage="1">
      <spawn group="g1" num="2" maxAlive="3" duration="1" interval="5"/>
      <spawn group="g1" num="999" maxAlive="1"/>
    </gamestage>
    <gamestage stage="4">
      <spawn group="g2" num="4" maxAlive="5"/>
    </gamestage>
  </spawner>
</gamestages>
"""

ENTITYGROUPS_XML = """<entitygroups>
  <entitygroup name="g1">
    <e n="zombieJoe"/>
    <e n="zombieNurse" p="0.5"/>
  </entitygroup>
  <entitygroup name="g2">
    <e n="zombieBoeFeral"/>
    <e n="zombieUnknown"/>
  </entitygroup>
</entitygroups>
"""


class HordeDataTest(unittest.TestCase):
    def test_parse_gamestages(self):
        stages = build_data.parse_gamestages(GAMESTAGES_XML)
        bm = stages["BloodMoonHorde"]
        self.assertEqual(len(bm), 2)
        self.assertEqual(bm[0]["stage"], 1)
        self.assertEqual(bm[0]["spawns"][0]["num"], 2)
        self.assertEqual(bm[0]["spawns"][0]["max_alive"], 3)
        self.assertEqual(bm[0]["spawns"][1]["num"], 999)
        self.assertEqual(build_data.select_horde_stage(bm, 4)["stage"], 4)
        self.assertEqual(build_data.select_horde_stage(bm, 99)["stage"], 4)

    def test_map_entitygroups(self):
        groups = build_data.parse_entitygroups(ENTITYGROUPS_XML)
        self.assertEqual(groups["g1"][0]["name"], "zombieJoe")
        mapped = build_data.map_entitygroups(groups, {"joe", "nurse", "boe"})
        self.assertEqual(mapped["g1"][0]["id"], "joe")
        self.assertFalse(mapped["g1"][0]["feral"])
        self.assertEqual(mapped["g2"][0]["id"], "boe")
        self.assertTrue(mapped["g2"][0]["feral"])
        self.assertEqual(len(mapped["g2"]), 1)  # unknown 被过滤

    def test_blood_moon_total(self):
        stages = build_data.parse_gamestages(GAMESTAGES_XML)
        stage = build_data.select_horde_stage(stages["BloodMoonHorde"], 4)
        self.assertEqual(build_data.blood_moon_total(stage, 0.5), 2)


if __name__ == "__main__":
    unittest.main()
