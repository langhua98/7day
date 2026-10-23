class_name Survival
## 吃喝用药的效果，按七日杀物品名判断。返回字典：
##   food 饱食  water 水分  hp 血量  stamina 体力
##   stop_bleed 止血  cure 治腹泻  sick 生病几率(0~1)  buff 咖啡因游戏小时（这些都由 player.gd 转成状态效果，见 status_effects.gd）  msg 提示

## [名字里含的词, food, water, hp, 额外]
const TABLE := [
	["RiverWater", 0, 30, 0, {"sick": 0.45}],
	["BoiledWater", 0, 35, 0, {}],
	["PureMineralWater", 0, 40, 5, {}],
	["MegaCrush", 0, 20, 0, {"stamina": 100, "buff": 2.0}],
	["Coffee", 0, 20, 0, {"buff": 1.5}],
	["GoldenRodTea", 0, 25, 0, {"cure": true}],
	["RedTea", 0, 25, 5, {}],
	["HoneyTea", 0, 25, 8, {}],
	["Beer", 5, 15, 10, {}],
	["Moonshine", 0, 10, 20, {}],
	["Grandpas", 0, 15, 10, {}],
	["YuccaJuice", 5, 30, 0, {}],
	["Smoothie", 15, 30, 5, {}],
	["Grey", 0, 15, 0, {}],
	["RottingFlesh", 5, 0, -5, {"sick": 0.8}],
	["RawMeat", 10, 0, 0, {"sick": 0.5}],
	["Catfood", 15, 5, 0, {"sick": 0.15}],
	["Dogfood", 15, 5, 0, {"sick": 0.15}],
	["CanSoup", 15, 15, 0, {}],
	["CanStock", 10, 20, 0, {}],
	["CanPears", 12, 12, 0, {}],
	["CanPeas", 15, 5, 0, {}],
	["Can", 20, 3, 0, {}],
	["Stew", 40, 10, 10, {}],
	["Chowder", 35, 15, 5, {}],
	["Crop", 8, 3, 0, {}],
	["Egg", 12, 0, 0, {}],
	["Honey", 8, 0, 5, {"cure": true}],
	["Charred", 15, 0, 0, {}],
	["Bandage", 0, 0, 10, {"stop_bleed": true}],
	["FirstAidBandage", 0, 0, 25, {"stop_bleed": true}],
	["FirstAidKit", 0, 0, 60, {"stop_bleed": true, "cure": true}],
	["BloodBag", 0, 0, 45, {}],
	["AloeCream", 0, 0, 15, {}],
	["Splint", 0, 0, 10, {}],
	["PlasterCast", 0, 0, 15, {}],
]


static func effect(id: String, kind: int) -> Dictionary:
	var best: Array = []
	for row in TABLE:
		if id.contains(row[0]) and (best.is_empty() or row[0].length() > best[0].length()):
			best = row
	var e := {"food": 0.0, "water": 0.0, "hp": 0.0}
	if best.is_empty():
		# 没列出来的：做好的菜都算正经一顿饭
		match kind:
			Assets.Kind.FOOD: e.food = 30.0; e.water = 2.0; e.hp = 5.0
			Assets.Kind.DRINK: e.water = 25.0
			Assets.Kind.MEDICAL: e.hp = 25.0
		return e
	e.food = float(best[1])
	e.water = float(best[2])
	e.hp = float(best[3])
	e.merge(best[4])
	return e
