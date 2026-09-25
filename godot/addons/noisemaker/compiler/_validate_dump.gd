# _validate_dump.gd — CANDIDATE for the validator parity gate. Lexes + parses + validates each DSL
# path passed after `--` and prints JSON { path: {ok, out} } on a single VALIDATEDUMP: marker line.
# Pure logic -> runs --headless.
#   Godot --headless --path godot --script res://addons/noisemaker/compiler/_validate_dump.gd -- <f...>
extends SceneTree

const Lexer := preload("res://addons/noisemaker/compiler/lang/lexer.gd")
const Parser := preload("res://addons/noisemaker/compiler/lang/parser.gd")
const Validator := preload("res://addons/noisemaker/compiler/lang/validator.gd")
const EffectRegistry := preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")

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
	var reg := EffectRegistry.new()
	reg.load_all()
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
		var v := Validator.new(reg)
		var res = v.validate(ast)
		out[f] = {"ok": not p._err, "out": _strip_internal_keys(res)}
	print("VALIDATEDUMP:", JSON.stringify(out))
	quit(0)
