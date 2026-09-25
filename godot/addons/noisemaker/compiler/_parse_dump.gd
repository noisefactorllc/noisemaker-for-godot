# _parse_dump.gd — CANDIDATE for the parser parity gate. Lexes + parses each DSL path passed after
# `--` with the GDScript lexer + parser and prints JSON { path: {ok, ast} } on a single PARSEDUMP:
# marker line (so the harness can skip Godot's boot noise). Pure logic -> runs --headless.
#   Godot --headless --path godot --script res://addons/noisemaker/compiler/_parse_dump.gd -- <f...>
extends SceneTree

const Lexer := preload("res://addons/noisemaker/compiler/lang/lexer.gd")
const Parser := preload("res://addons/noisemaker/compiler/lang/parser.gd")

static func _strip_internal_keys(val):
	if val is Dictionary:
		var d := {}
		for k in val:
			if k == "subchainArgumentDiagnostics":
				continue
			if k == "position" and (val[k] is Dictionary and val[k].has("start") and val[k].has("end")):
				continue
			d[k] = _strip_internal_keys(val[k])
		return d
	elif val is Array:
		var a := []
		for item in val:
			a.append(_strip_internal_keys(item))
		return a
	return val

func _init() -> void:
	var out := {}
	var options := {}
	var files: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-subchain-args":
			options["subchainArguments"] = "strict"
		else:
			files.append(arg)
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		var toks := Lexer.lex(src)
		if Lexer.last_diagnostic != null:
			out[f] = {"ok": false, "error": Lexer.last_error, "diagnostic": Lexer.last_diagnostic}
			continue
		var p := Parser.new()
		var ast = p.parse_tokens(toks, options)
		if p.last_diagnostic != null:
			out[f] = {"ok": false, "error": p.last_error, "diagnostic": p.last_diagnostic}
			continue
		out[f] = {"ok": not p._err, "ast": _strip_internal_keys(ast)}
	print("PARSEDUMP:", JSON.stringify(out))
	quit(0)
