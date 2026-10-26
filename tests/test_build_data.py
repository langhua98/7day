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
  <item name="gunTest">
    <property class="Action0">
      <property name="Magazine_items" value="ammo9mmBulletBall,ammo9mmBulletHP"/>
      <property name="Reload_time" value="1.8"/>
    </property>
    <effect_group>
      <passive_effect name="MagazineSize" value="15"/>
      <passive_effect name="RoundsPerMinute" value="180"/>
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

    def test_gun_stats(self):
        items = build_data.parse_items_xml(ITEMS_XML)
        gun = items["gunTest"]
        self.assertEqual(gun["magazine"], 15)
        self.assertEqual(gun["rpm"], 180.0)
        self.assertEqual(gun["ammo"], "ammo9mm")
        self.assertAlmostEqual(gun["reload"], 1.8)

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

MATERIALS_XML = """<materials>
  <material id="Mwood">
    <property name="damage_category" value="wood"/>
    <property name="stability_glue" value="40"/>
    <property name="Mass" value="5"/>
    <property name="MaxDamage" value="500"/>
  </material>
</materials>
"""

BLOCKS_TEST_XML = """<blocks>
  <block name="frameShapes">
    <property name="Material" value="Mwood"/>
    <property name="Texture" value="65"/>
    <property name="UpgradeSound" value="place_block_wood"/>
    <property class="RepairItems">
      <property name="resourceWood" value="3"/>
    </property>
    <property class="UpgradeBlock">
      <property name="ToBlock" value="woodShapes"/>
      <property name="Item" value="resourceWood"/>
      <property name="ItemCount" value="8"/>
      <property name="UpgradeHitCount" value="4"/>
    </property>
  </block>
  <block name="woodShapes">
    <property name="Extends" value="frameShapes"/>
    <property name="Texture" value="241"/>
    <property class="UpgradeBlock">
      <property name="ToBlock" value="unknownShapes"/>
      <property name="Item" value="resourceWood"/>
      <property name="ItemCount" value="10"/>
    </property>
  </block>
</blocks>
"""


class BlockDataTest(unittest.TestCase):
    def test_official_block_stats(self):
        blocks = build_data.parse_blocks_xml(BLOCKS_TEST_XML)
        materials = build_data.parse_materials_xml(MATERIALS_XML)
        out = build_data.build_blocks(blocks, materials, ["frameShapes", "woodShapes"])
        frame = out["frameShapes"]
        self.assertEqual(frame["hp"], 500.0)  # 材质血量
        self.assertEqual(frame["overhang"], 8)  # stability_glue / Mass
        self.assertEqual(frame["texture"], 65)
        self.assertEqual(frame["repair"], [{"item": "resourceWood", "count": 3}])
        self.assertEqual(frame["upgrade"]["to"], "woodShapes")
        self.assertEqual(frame["upgrade"]["count"], 8)
        self.assertEqual(frame["upgrade"]["hits"], 4)
        self.assertEqual(frame["upgrade"]["sound"], "place_block_wood")
        # 继承父方块；升级到未知方块时不生效
        self.assertEqual(out["woodShapes"]["texture"], 241)
        self.assertEqual(out["woodShapes"]["upgrade"], {})


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


BUFFS_XML = """<buffs>
  <buff name="buffInjuryBleeding" name_key="buffInjuryBleedingName" description_key="buffInjuryBleedingDesc" icon="ui_game_symbol_bleeding"/>
  <buff name="buffOther" name_key="buffOtherName"/>
</buffs>
"""

BUFF_LOC = {"buffInjuryBleedingName": "流血", "buffInjuryBleedingDesc": "正在失血", "buffOtherName": "别的"}


class BuffDataTest(unittest.TestCase):
    def test_parse_buffs_only_wanted(self):
        out = build_data.parse_buffs(BUFFS_XML, BUFF_LOC, ["buffInjuryBleeding", "buffMissing"])
        self.assertEqual(list(out), ["buffInjuryBleeding"])
        self.assertEqual(out["buffInjuryBleeding"]["zh"], "流血")
        self.assertEqual(out["buffInjuryBleeding"]["icon"], "ui_game_symbol_bleeding")

    def test_status_buffs_from_config(self):
        text = (Path(__file__).resolve().parents[1] / "scripts" / "config.gd").read_text(encoding="utf-8")
        names = build_data.status_buffs_from_gd(text)
        self.assertIn("buffInjuryBleeding", names)
        self.assertIn("buffDysenteryMain", names)


RECIPES_XML = """<recipes>
  <recipe name="meleeToolStoneAxe" count="1" tags="learnable,tool">
    <ingredient name="resourceRockSmall" count="2"/>
    <ingredient name="resourceYuccaFibers" count="2"/>
    <ingredient name="resourceWood" count="2"/>
  </recipe>
  <recipe name="campfire" count="1" craft_time="5">
    <ingredient name="resourceRockSmall" count="5"/>
  </recipe>
  <recipe name="frameShapes:VariantHelper" count="1" craft_area="workbench" craft_time="2">
    <ingredient name="resourceWood" count="4"/>
  </recipe>
  <recipe name="frameShapes:VariantHelper" count="1">
    <ingredient name="resourceWood" count="4"/>
  </recipe>
  <recipe name="drinkJarBoiledWater" count="1" craft_area="campfire" craft_tool="toolCookingPot" craft_time="10">
    <ingredient name="drinkJarRiverWater" count="1"/>
  </recipe>
  <recipe name="resourceForgedIron" count="1" material_based="true">
    <wildcard_forge_category/>
    <ingredient name="unit_iron" count="5"/>
  </recipe>
  <recipe name="meleeToolMissing" count="1"><ingredient name="resourceWood" count="1"/></recipe>
  <recipe name="meleeToolStoneAxe" count="1"><ingredient name="resourceUnknown" count="1"/></recipe>
</recipes>
"""

ITEMS_TIME_XML = """<items>
  <item name="resourceBase"><property name="CraftingIngredientTime" value="0.5"/></item>
  <item name="resourceWood"><property name="Extends" value="resourceBase"/></item>
</items>
"""


class RecipesTest(unittest.TestCase):
    def setUp(self):
        self.items = {i: {"zh": i + "中文", "tags": ""} for i in [
            "meleeToolStoneAxe", "resourceRockSmall", "resourceYuccaFibers", "resourceWood",
            "frameShapes", "drinkJarBoiledWater", "drinkJarRiverWater", "toolCookingPot", "resourceForgedIron"]}
        self.blocks = {"campfire"}

    def test_filter_and_fields(self):
        raw = build_data.parse_recipes_xml(RECIPES_XML)
        self.assertEqual(len(raw), 8)
        times = build_data.parse_ingredient_times(ITEMS_TIME_XML)
        self.assertEqual(times["resourceWood"], 0.5)
        out, dropped = build_data.build_recipes(raw, self.items, self.blocks, {"campfire": "篝火"}, times)
        axe = out["meleeToolStoneAxe"]
        self.assertTrue(axe["learnable"])
        self.assertEqual(axe["cat"], "tool")
        self.assertEqual(axe["area"], "")
        self.assertEqual([i["id"] for i in axe["ingredients"]], ["resourceRockSmall", "resourceYuccaFibers", "resourceWood"])
        # 没写 craft_time：2×1 + 2×1 + 2×0.5
        self.assertEqual(axe["time"], 5.0)
        self.assertTrue(out["campfire"]["block"])
        self.assertEqual(out["campfire"]["zh"], "篝火")
        self.assertEqual(out["frameShapes"]["area"], "workbench")
        self.assertEqual(out["frameShapes@backpack"]["area"], "")
        self.assertEqual(out["frameShapes"]["cat"], "build")
        self.assertEqual(out["drinkJarBoiledWater"]["tool"], "toolCookingPot")
        self.assertEqual(out["drinkJarBoiledWater"]["cat"], "food")
        self.assertNotIn("resourceForgedIron", out)
        self.assertNotIn("meleeToolMissing", out)
        self.assertEqual(sum(dropped.values()), 3)
        self.assertEqual(len(out), 5)


if __name__ == "__main__":
    unittest.main()


LOOT_XML = """<loot>
  <lootprobtemplate name="med"><loot level="1,999999" prob="0.5"/></lootprobtemplate>
  <lootqualitytemplate name="qualBase">
    <qualitytemplate level="0,9" default_quality="1">
      <loot quality="1" prob="0.8"/><loot quality="3" prob="1"/>
    </qualitytemplate>
    <qualitytemplate level="50,999999" default_quality="1">
      <loot quality="4" prob="0.5"/><loot quality="6" prob="1"/>
    </qualitytemplate>
  </lootqualitytemplate>
  <lootgroup name="g1" count="all">
    <item name="knownA" count="1,3"/>
    <item name="unknown" count="1"/>
    <item group="g2" count="1" loot_prob_template="med"/>
    <item name="knownB" count="1"><requirement class="RandomRoll"/></item>
  </lootgroup>
  <lootgroup name="g2"><item name="knownA" count="1" prob="0.5"/></lootgroup>
  <lootgroup name="g3"><item name="knownA" count="1"/></lootgroup>
  <lootgroup name="gone"><item name="unknown"/></lootgroup>
  <lootcontainer name="c1" count="1" loot_quality_template="qualBase"><item group="g1"/></lootcontainer>
  <lootcontainer name="empty" count="1"><item name="unknown"/></lootcontainer>
</loot>"""


class LootDataTest(unittest.TestCase):
    def test_parse_loot_xml(self):
        loot = build_data.parse_loot_xml(LOOT_XML)
        self.assertEqual(loot["prob"]["med"], [(1, 999999, 0.5)])
        self.assertEqual(len(loot["quality"]["qualBase"]), 2)
        self.assertEqual(loot["quality"]["qualBase"][0]["level"], [0, 9])
        self.assertEqual(loot["quality"]["qualBase"][1]["default"], 1)
        g1 = loot["groups"]["g1"]
        self.assertEqual(g1["count"], "all")
        # requirement 条目丢掉
        self.assertEqual(len(g1["items"]), 3)
        self.assertEqual(g1["dropped"], 1)
        self.assertEqual(g1["items"][0]["count"], (1, 3))
        self.assertEqual(g1["items"][2]["prob_template"], "med")
        self.assertEqual(loot["groups"]["g3"]["count"], (1, 1))
        self.assertEqual(loot["containers"]["c1"]["quality"], "qualBase")
        self.assertEqual(loot["containers"]["c1"]["count"], (1, 1))

    def test_build_loot_prunes_unknown_and_empty(self):
        pruned, stats = build_data.build_loot(LOOT_XML, {"knownA": {}, "knownB": {}})
        self.assertIn("g1", pruned["groups"])
        self.assertIn("g2", pruned["groups"])
        self.assertNotIn("gone", pruned["groups"])
        self.assertIn("c1", pruned["containers"])
        self.assertNotIn("empty", pruned["containers"])
        # c1 → g1；g1 只剩 knownA 和嵌套的 g2（knownB 需要技能，unknown 不在物品表）
        items = pruned["containers"]["c1"]["items"]
        self.assertEqual(items[0]["group"], "g1")
        self.assertEqual([e.get("item") or e.get("group") for e in pruned["groups"]["g1"]["items"]],
                         ["knownA", "g2"])
        self.assertEqual(stats["items"], 3)
        self.assertEqual(stats["groups"], 1)
        self.assertEqual(stats["containers"], 1)
        self.assertEqual(stats["requirements"], 1)


HARVEST_XML = """<blocks>
  <block name="cntTiltTruckEmpty">
    <drop event="Harvest" name="knownA" count="1,3" />
    <drop event="Harvest" name="unknownItem" count="2" />
    <drop event="Destroy" name="knownB" count="4" prob="0.5" />
    <drop event="Fall" name="knownC" count="1" />
  </block>
  <block name="woodShapes">
    <drop event="Harvest" name="knownA" count="2" />
  </block>
  <block name="unwanted"><drop event="Harvest" name="knownA" count="1" /></block>
</blocks>"""


class HarvestDataTest(unittest.TestCase):
    def test_build_harvest(self):
        out = build_data.build_harvest(HARVEST_XML, {"knownA": {}, "knownB": {}})
        metal = out["materials"]["metal"]
        self.assertEqual([r["id"] for r in metal["harvest"]], ["knownA"])
        self.assertEqual(metal["harvest"][0]["count"], [1, 3])
        self.assertEqual([r["id"] for r in metal["destroy"]], ["knownB"])
        self.assertEqual(metal["destroy"][0]["prob"], 0.5)
        self.assertEqual([r["id"] for r in out["materials"]["wood"]["harvest"]], ["knownA"])
        all_ids = [r["id"] for m in out["materials"].values()
                   for key in ("harvest", "destroy") for r in m[key]]
        self.assertNotIn("unknownItem", all_ids)
        self.assertNotIn("knownC", all_ids)


ENTITY_XML = """<entity_classes>
  <replace_properties>
    <property name="xpSlim01" value="400"/>
    <property name="xpNormal01" value="300"/>
  </replace_properties>
  <replace_passive_effect>
    <property name="healthSlim" value="125"/>
    <property name="healthSlimFeral" value="500"/>
  </replace_passive_effect>
  <entity_class name="zombieTemplateMale">
    <property name="Tags" value="entity,zombie,walker"/>
    <property name="MoveSpeedAggro" value=".2, 1.25"/>
    <property name="HandItem" value="meleeHandZombie01"/>
    <property name="ExperienceGain" value="^xpNormal01"/>
    <effect_group><passive_effect name="HealthMax" operation="base_set" value="^healthSlim"/></effect_group>
  </entity_class>
  <entity_class name="zombieJoe" extends="zombieTemplateMale">
    <property name="ExperienceGain" value="^xpSlim01"/>
  </entity_class>
  <entity_class name="zombieJoeFeral" extends="zombieJoe">
    <property name="Tags" value="entity,zombie,walker,feral"/>
    <effect_group><passive_effect name="HealthMax" operation="base_set" value="^healthSlimFeral"/></effect_group>
  </entity_class>
  <entity_class name="zombieUnknown" extends="zombieTemplateMale">
    <property name="Mesh" value="x"/>
  </entity_class>
</entity_classes>"""


class EntityClassDataTest(unittest.TestCase):
    def test_build_entityclasses(self):
        items = {"meleeHandZombie01": {"damage": 10.0}}
        loc = {"zombieJoe": "乔", "zombieJoeFeral": "野性乔"}
        out = build_data.build_entityclasses(ENTITY_XML, items, loc)
        self.assertIn("zombieJoe", out)
        self.assertIn("zombieJoeFeral", out)
        self.assertNotIn("zombieUnknown", out)  # 没有模型映射
        joe = out["zombieJoe"]
        self.assertEqual(joe["model"], "joe")
        self.assertEqual(joe["hp"], 125)
        self.assertAlmostEqual(joe["speed"], 1.25)
        self.assertEqual(joe["damage"], 10.0)
        self.assertEqual(joe["xp"], 400)
        self.assertFalse(joe["feral"])
        feral = out["zombieJoeFeral"]
        self.assertEqual(feral["hp"], 500)
        self.assertTrue(feral["feral"])


SLEEPERS_XML = """<prefab>
  <property name="SleeperVolumeStart" value="10, 2, 20#0, 0, 0" />
  <property name="SleeperVolumeSize" value="4, 3, 6#2, 2, 2" />
  <property name="SleeperVolumeGroup" value="GroupGenericZombie,1,2,GroupAllFeral,0,3" />
</prefab>"""


class SleepersDataTest(unittest.TestCase):
    def test_parse_sleepers(self):
        import build_sleepers
        vols = build_sleepers.parse_sleepers_xml(SLEEPERS_XML)
        self.assertEqual(len(vols), 2)
        first = vols[0]
        self.assertEqual(first["x"], 12.0)
        self.assertEqual(first["y"], 3.5)
        self.assertEqual(first["z"], 23.0)
        self.assertEqual(first["sx"], 4.0)
        self.assertEqual(first["group"], "GroupGenericZombie")
        self.assertEqual(first["min"], 1)
        self.assertEqual(first["max"], 2)
        self.assertEqual(vols[1]["group"], "GroupAllFeral")
        self.assertEqual(vols[1]["max"], 3)
