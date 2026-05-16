extends RefCounted

const BINARY_PLY_READER := preload("res://addons/gdgs/importers/parsers/binary_ply_reader.gd")

func read_ply(request: Dictionary) -> Dictionary:
	var format := String(request.get("format", ""))
	if format != "ply" and format != "compressed.ply":
		return {
			"ok": false,
			"error": ERR_UNAVAILABLE,
			"message": "Background loading currently supports .ply and .compressed.ply",
			"path": request.get("path", ""),
			"format": format
		}
	var path := String(request.get("path", ""))
	var ply := BINARY_PLY_READER.read(path, true)
	if not ply.get("ok", false):
		ply["path"] = path
		ply["format"] = format
		return ply
	return {
		"ok": true,
		"path": path,
		"format": format,
		"ply": ply
	}
