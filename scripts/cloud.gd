class_name CloudAssets
extends Node
## 混合加载：楼、车和杂物、音乐、音效、部分僵尸放在云盘的素材包（.pck）里。
## 第一次打开时下载到手机（user://packs/），以后直接加载；下载失败就用手机里上一次的素材包。
## 安装包里的 cloud.json 由编译时的 tools/cloud_pack.py 写入；没有这个文件（比如在电脑上调试）就什么也不做。

signal progress(text: String, value: float)
## ok=false 时 message 说明原因，可以重试或者跳过
signal finished(ok: bool, message: String)

const INFO_PATH := "res://cloud.json"
const DIR := "user://packs"

var info := {}
var _http: HTTPRequest
var _part := ""
var _final := ""


func needed() -> bool:
	return FileAccess.file_exists(INFO_PATH)


func start() -> void:
	if not needed():
		finished.emit(true, "")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
	if not (parsed is Dictionary) or not parsed.has("file"):
		finished.emit(true, "")
		return
	info = parsed
	DirAccess.make_dir_recursive_absolute(DIR)
	_final = "%s/%s" % [DIR, info.file]
	_part = _final + ".part"
	if _have_full(_final):
		_load(_final)
		return
	progress.emit("正在连接云盘…", 0.0)
	_request("%s/api/s/%s" % [info.site, info.share], _on_share)


func _have_full(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	return f != null and f.get_length() == int(info.get("size", -1))


func _request(url: String, done: Callable, to_file := "") -> void:
	if _http:
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 0.0 if to_file != "" else 30.0
	_http.download_chunk_size = 1 << 20
	if to_file != "":
		_http.download_file = to_file
	add_child(_http)
	_http.request_completed.connect(done)
	var err := _http.request(url)
	if err != OK:
		_fail("连不上云盘（%d）" % err)


## 分享口令换出下载直链
func _on_share(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		_fail("云盘分享打不开（%s）" % (str(code) if result == HTTPRequest.RESULT_SUCCESS else "网络错误 %d" % result))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var url := ""
	if data is Dictionary:
		for it in data.get("items", []):
			if it is Dictionary and str(it.get("url", "")) != "":
				url = str(it.url)
				break
	if url == "":
		_fail("云盘分享里没找到素材包，可能已过期")
		return
	if not url.begins_with("http"):
		url = str(info.site) + url
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_part))
	_request(url, _on_download, _part)


func _process(_delta: float) -> void:
	if _http and _http.download_file != "" and _http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := float(info.get("size", _http.get_body_size()))
		var got := float(_http.get_downloaded_bytes())
		if total > 0.0:
			progress.emit("正在下载游戏素材（楼、车、音乐、音效）… %d / %d MB" % [int(got / 1e6), int(total / 1e6)], got / total)


func _on_download(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300 or not _have_full(_part):
		_fail("素材包没下载完（%s）" % (str(code) if result == HTTPRequest.RESULT_SUCCESS else "网络错误 %d" % result))
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_part), ProjectSettings.globalize_path(_final))
	# 删掉以前版本的素材包，省手机空间
	for f in DirAccess.get_files_at(DIR):
		if "%s/%s" % [DIR, f] != _final:
			DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [DIR, f]))
	_load(_final)


func _load(path: String) -> void:
	progress.emit("正在加载游戏素材…", 1.0)
	# 不替换安装包里已有的文件：素材包里顺带的脚本可能是旧版本
	if ProjectSettings.load_resource_pack(path, false):
		finished.emit(true, "")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_fail("素材包损坏，已删除，请重试")


## 下载失败：手机里有以前版本的素材包就先用着
func _fail(msg: String) -> void:
	if _http:
		_http.cancel_request()
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			var p := "%s/%s" % [DIR, f]
			if f.ends_with(".pck") and p != _final and ProjectSettings.load_resource_pack(p, false):
				finished.emit(true, "")
				return
	finished.emit(false, msg)
