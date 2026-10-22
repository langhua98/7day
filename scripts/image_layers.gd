extends Resource
## 一组同尺寸、同格式的图（已压缩、带 mipmap），游戏里用 to_texture() 拼成 Texture2DArray。
## 打包工具在没有显卡的环境下运行，Texture2DArray 存不下图片数据，所以存成这个。

@export var images: Array[Image] = []


func to_texture() -> Texture2DArray:
	if images.is_empty():
		return null
	var arr := Texture2DArray.new()
	if arr.create_from_images(images) != OK:
		return null
	return arr
