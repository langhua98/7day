extends Resource
## 一栋楼的完整网格，按 16 米分成好几块（每块一个 Mesh）。
## 分开放成几个 MeshInstance，手机上看不见的块会整块跳过不画。

@export var meshes: Array[Mesh] = []
