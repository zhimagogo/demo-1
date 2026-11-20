class_name ResourceDef
extends Resource
## 资源类型定义（木材 / 石头 / 食物 / 金币 …）

@export var id: StringName
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var is_currency: bool = false
