# _smoke.gd — TEMPORARY foundation smoke test (deleted once the lexer gate exists).
# Validates the 7 foundation modules parse + behave, locking the GDScript conventions before
# the big stages stack on top. Pure logic → runs --headless.
#   Godot --headless --path godot --script res://addons/noisemaker/compiler/_smoke.gd
extends SceneTree

const Token = preload("res://addons/noisemaker/compiler/lang/token.gd")
const Lexer = preload("res://addons/noisemaker/compiler/lang/lexer.gd")
const Ast = preload("res://addons/noisemaker/compiler/lang/ast.gd")
const Parser = preload("res://addons/noisemaker/compiler/lang/parser.gd")
const Validator = preload("res://addons/noisemaker/compiler/lang/validator.gd")
const EffectRegistry = preload("res://addons/noisemaker/compiler/lang/effect_registry.gd")
const Diagnostics = preload("res://addons/noisemaker/compiler/lang/diagnostics.gd")
const EnumPaths = preload("res://addons/noisemaker/compiler/lang/enum_paths.gd")
const Enums = preload("res://addons/noisemaker/compiler/lang/enums.gd")
const Dim = preload("res://addons/noisemaker/compiler/graph/dim.gd")
const Resources = preload("res://addons/noisemaker/compiler/graph/resources.gd")

var _ok := true

func _init() -> void:
	# Token
	var t = Token.new(Token.NUMBER, "1.5", 2, 3)
	_expect(t.to_dict() == {"type": "NUMBER", "lexeme": "1.5", "line": 2, "col": 3}, "token.to_dict")

	# Ast
	_expect(Ast.number(1.5) == {"type": "Number", "value": 1.5}, "ast.number")
	_expect(Ast.member_of("oscKind", "sine") == {"type": "Member", "path": ["oscKind", "sine"]}, "ast.member_of")
	_expect(Ast.String_ == "String", "ast.String_-const")

	# Diagnostics
	var d = Diagnostics.make("S001", null, 1, 2, "foo")
	_expect(d["code"] == "S001" and d["severity"] == "error" and d["message"] == "Unknown identifier"
		and d["line"] == 1 and d["column"] == 2 and d["identifier"] == "foo", "diag.make-full")
	var d2 = Diagnostics.make("S007")
	_expect(d2["severity"] == "warning" and d2["message"] == "Deprecated parameter alias" and not d2.has("line"), "diag.make-min")
	_expect(Diagnostics.stage("L001") == "lexer" and Diagnostics.stage("L003") == "lexer" and Diagnostics.stage("L004") == "lexer", "diag.lexer-stage")
	_expect(Diagnostics.stage("P005") == "parser" and Diagnostics.default_message("P005") == "Invalid output operation", "diag.p005-meta")
	_expect(Diagnostics.stage("P006") == "parser" and Diagnostics.default_message("P006") == "Invalid subchain", "diag.p006-meta")
	_expect(Diagnostics.stage("P007") == "parser" and Diagnostics.default_message("P007") == "Invalid call expression", "diag.p007-meta")
	_expect(Diagnostics.default_message("L003") == "Unterminated comment" and Diagnostics.default_message("L004") == "Output surface reference out of range", "diag.lexer-messages")

	# Lexer structured diagnostics
	Lexer.lex("// 😀\r\n\t@")
	_expect(Lexer.last_diagnostic["code"] == "L001" and Lexer.last_diagnostic["location"] == {"line": 2, "column": 2} and Lexer.last_diagnostic["span"] == {"start": 8, "end": 9}, "lexer.diag-crlf-utf16")
	Lexer.lex("/* unterminated")
	_expect(Lexer.last_diagnostic["code"] == "L003" and Lexer.last_diagnostic["stage"] == "lexer" and Lexer.last_diagnostic["severity"] == "error", "lexer.diag-unterminated-comment")
	Lexer.lex("search synth\nrender(o99)")
	_expect(Lexer.last_diagnostic["code"] == "L004" and Lexer.last_diagnostic["location"] == {"line": 2, "column": 8} and Lexer.last_diagnostic["span"] == {"start": 20, "end": 23}, "lexer.diag-output-ref-range")
	Lexer.lex("\"😀\" @")
	_expect(Lexer.last_diagnostic["code"] == "L001" and Lexer.last_diagnostic["location"] == {"line": 1, "column": 6} and Lexer.last_diagnostic["span"] == {"start": 5, "end": 6}, "lexer.diag-astral-span")

	# Parser structured diagnostics
	var source_position = func(source: String, line: int, col: int) -> Dictionary:
		for tok in Lexer.lex(source):
			if tok.position is Dictionary and tok.position.get("line") == line and tok.position.get("column") == col:
				return {"start": tok.position["start"], "end": tok.position["end"]}
		return {}

	var p1 = Parser.new()
	p1.parse_tokens(Lexer.lex("search synth\nrender o0"))
	_expect(p1.last_diagnostic["code"] == "P001" and p1.last_diagnostic["stage"] == "parser"
		and p1.last_diagnostic["severity"] == "error"
		and p1.last_diagnostic["message"] == "Expect '(' at line 2 col 8"
		and p1.last_diagnostic["location"] == {"line": 2, "column": 8}
		and p1.last_diagnostic["span"] == source_position.call("search synth\nrender o0", 2, 8), "parser.diag-p001")
	var p2 = Parser.new()
	p2.parse_tokens(Lexer.lex("search synth\nrender(o0"))
	_expect(p2.last_diagnostic["code"] == "P002" and p2.last_diagnostic["stage"] == "parser"
		and p2.last_diagnostic["severity"] == "error"
		and p2.last_diagnostic["message"] == "Expect ')' at line 2 col 10"
		and p2.last_diagnostic["location"] == {"line": 2, "column": 10}
		and p2.last_diagnostic["span"] == source_position.call("search synth\nrender(o0", 2, 10), "parser.diag-p002")
	var p3 = Parser.new()
	var mock_tokens = [
		{"type": "SEARCH", "lexeme": "search", "line": 1, "col": 1},
		{"type": "IDENT", "lexeme": "synth", "line": 1, "col": 8},
		{"type": "RENDER", "lexeme": "render", "line": 2, "col": 1},
		{"type": "OUTPUT_REF", "lexeme": "o0"},
		{"type": "EOF", "lexeme": "", "line": 2, "col": 10},
	]
	p3.parse_tokens(mock_tokens)
	_expect(p3.last_diagnostic["code"] == "P001"
		and p3.last_diagnostic["location"] == null
		and p3.last_diagnostic["span"] == null, "parser.diag-unlocated")
	var p4 = Parser.new()
	p4.parse_tokens(Lexer.lex("search synth\nlet x = midi()"))
	_expect(p4.last_diagnostic["code"] == "P003" and p4.last_diagnostic["stage"] == "parser"
		and p4.last_diagnostic["severity"] == "error"
		and p4.last_diagnostic["message"] == "midi() requires 'channel' or 'zone' argument at line 2 col 9"
		and p4.last_diagnostic["location"] == {"line": 2, "column": 9}
		and p4.last_diagnostic["span"] == source_position.call("search synth\nlet x = midi()", 2, 9), "parser.diag-p003")
	var p5 = Parser.new()
	p5.parse_tokens(Lexer.lex("search bogus"))
	_expect(p5.last_diagnostic["code"] == "P004" and p5.last_diagnostic["stage"] == "parser"
		and p5.last_diagnostic["severity"] == "error"
		and p5.last_diagnostic["message"] == "Invalid namespace 'bogus' at line 1 col 8. Valid namespaces: io, classicNoisedeck, synth, mixer, filter, render, points, synth3d, filter3d, user"
		and p5.last_diagnostic["location"] == {"line": 1, "column": 8}
		and p5.last_diagnostic["span"] == source_position.call("search bogus", 1, 8), "parser.diag-p004")
	var p6 = Parser.new()
	p6.parse_tokens(Lexer.lex(""))
	_expect(p6.last_diagnostic["code"] == "P004" and p6.last_diagnostic["stage"] == "parser"
		and p6.last_diagnostic["severity"] == "error"
		and p6.last_diagnostic["message"] == "Missing required 'search' directive. Every program must start with 'search <namespace>, ...' to specify namespace search order."
		and p6.last_diagnostic["location"] == {"line": 1, "column": 1}
		and p6.last_diagnostic["span"] == source_position.call("", 1, 1), "parser.diag-p004-missing")
	var p7 = Parser.new()
	p7.parse_tokens(Lexer.lex("search synth\nrender(1)"))
	_expect(p7.last_diagnostic["code"] == "P005" and p7.last_diagnostic["stage"] == "parser"
		and p7.last_diagnostic["severity"] == "error"
		and p7.last_diagnostic["message"] == "Expected output reference in render()"
		and p7.last_diagnostic["location"] == {"line": 2, "column": 8}
		and p7.last_diagnostic["span"] == source_position.call("search synth\nrender(1)", 2, 8), "parser.diag-p005-render")
	var p8 = Parser.new()
	p8.parse_tokens(Lexer.lex("search synth\nlet x = foo().write(o0)"))
	_expect(p8.last_diagnostic["code"] == "P005" and p8.last_diagnostic["stage"] == "parser"
		and p8.last_diagnostic["severity"] == "error"
		and p8.last_diagnostic["message"] == "'.write()' is only allowed in statement context at line 2 col 15"
		and p8.last_diagnostic["location"] == {"line": 2, "column": 15}
		and p8.last_diagnostic["span"] == source_position.call("search synth\nlet x = foo().write(o0)", 2, 15), "parser.diag-p005-write-expr")
	var p9 = Parser.new()
	p9.parse_tokens(Lexer.lex("search synth\nfoo().write()"))
	_expect(p9.last_diagnostic["code"] == "P005" and p9.last_diagnostic["stage"] == "parser"
		and p9.last_diagnostic["severity"] == "error"
		and p9.last_diagnostic["message"] == "write() requires an explicit surface reference (e.g., o0, o1, xyz0, vel0, rgba0, mesh0, none) at line 2 col 13"
		and p9.last_diagnostic["location"] == {"line": 2, "column": 13}
		and p9.last_diagnostic["span"] == source_position.call("search synth\nfoo().write()", 2, 13), "parser.diag-p005-write-surface")
	var p10 = Parser.new()
	var mock_tokens_p005 = [
		{"type": "SEARCH", "lexeme": "search", "line": 1, "col": 1},
		{"type": "IDENT", "lexeme": "synth", "line": 1, "col": 8},
		{"type": "RENDER", "lexeme": "render", "line": 2, "col": 1},
		{"type": "LPAREN", "lexeme": "(", "line": 2, "col": 7},
		{"type": "NUMBER", "lexeme": "1"},
		{"type": "RPAREN", "lexeme": ")", "line": 2, "col": 9},
		{"type": "EOF", "lexeme": "", "line": 2, "col": 10},
	]
	p10.parse_tokens(mock_tokens_p005)
	_expect(p10.last_diagnostic["code"] == "P005"
		and p10.last_diagnostic["location"] == null
		and p10.last_diagnostic["span"] == null, "parser.diag-p005-unlocated")
	var p11 = Parser.new()
	p11.parse_tokens(Lexer.lex("search synth\nnoise().subchain(name: 1) { .noise() }"))
	_expect(p11.last_diagnostic["code"] == "P006" and p11.last_diagnostic["stage"] == "parser"
		and p11.last_diagnostic["severity"] == "error"
		and p11.last_diagnostic["message"] == "Expected string value for subchain name at line 2 col 24"
		and p11.last_diagnostic["location"] == {"line": 2, "column": 24}
		and p11.last_diagnostic["span"] == source_position.call("search synth\nnoise().subchain(name: 1) { .noise() }", 2, 24), "parser.diag-p006-arg-type")
	var p12 = Parser.new()
	p12.parse_tokens(Lexer.lex("search synth\nnoise().subchain(\"test\") { noise() }"))
	_expect(p12.last_diagnostic["code"] == "P006" and p12.last_diagnostic["stage"] == "parser"
		and p12.last_diagnostic["severity"] == "error"
		and p12.last_diagnostic["message"] == "Expected '.' before chain element in subchain body at line 2 col 28"
		and p12.last_diagnostic["location"] == {"line": 2, "column": 28}
		and p12.last_diagnostic["span"] == source_position.call("search synth\nnoise().subchain(\"test\") { noise() }", 2, 28), "parser.diag-p006-missing-dot")
	var p13 = Parser.new()
	p13.parse_tokens(Lexer.lex("search synth\nnoise().subchain(\"test\") {}"))
	_expect(p13.last_diagnostic["code"] == "P006" and p13.last_diagnostic["stage"] == "parser"
		and p13.last_diagnostic["severity"] == "error"
		and p13.last_diagnostic["message"] == "Subchain body cannot be empty at line 2 col 9"
		and p13.last_diagnostic["location"] == {"line": 2, "column": 9}
		and p13.last_diagnostic["span"] == source_position.call("search synth\nnoise().subchain(\"test\") {}", 2, 9), "parser.diag-p006-empty-body")
	var p14 = Parser.new()
	var mock_tokens_p006 = [
		{"type": "SEARCH", "lexeme": "search", "line": 1, "col": 1},
		{"type": "IDENT", "lexeme": "synth", "line": 1, "col": 8},
		{"type": "IDENT", "lexeme": "noise", "line": 2, "col": 1},
		{"type": "LPAREN", "lexeme": "(", "line": 2, "col": 6},
		{"type": "RPAREN", "lexeme": ")", "line": 2, "col": 7},
		{"type": "DOT", "lexeme": ".", "line": 2, "col": 8},
		{"type": "SUBCHAIN", "lexeme": "subchain"},
		{"type": "LPAREN", "lexeme": "(", "line": 2, "col": 17},
		{"type": "RPAREN", "lexeme": ")", "line": 2, "col": 18},
		{"type": "LBRACE", "lexeme": "{", "line": 2, "col": 20},
		{"type": "RBRACE", "lexeme": "}", "line": 2, "col": 21},
		{"type": "EOF", "lexeme": "", "line": 2, "col": 22},
	]
	p14.parse_tokens(mock_tokens_p006)
	_expect(p14.last_diagnostic["code"] == "P006"
		and p14.last_diagnostic["location"] == null
		and p14.last_diagnostic["span"] == null, "parser.diag-p006-unlocated")

	var p14_loc = Parser.new()
	var mock_tokens_p006_loc = [
		{"type": "SEARCH", "lexeme": "search", "line": 1, "col": 1},
		{"type": "IDENT", "lexeme": "synth", "line": 1, "col": 8},
		{"type": "IDENT", "lexeme": "noise", "line": 2, "col": 1},
		{"type": "LPAREN", "lexeme": "(", "line": 2, "col": 6},
		{"type": "RPAREN", "lexeme": ")", "line": 2, "col": 7},
		{"type": "DOT", "lexeme": ".", "line": 2, "col": 8},
		{"type": "SUBCHAIN", "lexeme": "subchain", "line": 2, "col": 9},
		{"type": "LPAREN", "lexeme": "(", "line": 2, "col": 17},
		{"type": "RPAREN", "lexeme": ")", "line": 2, "col": 18},
		{"type": "LBRACE", "lexeme": "{", "line": 2, "col": 20},
		{"type": "RBRACE", "lexeme": "}", "line": 2, "col": 21},
		{"type": "EOF", "lexeme": "", "line": 2, "col": 22},
	]
	p14_loc.parse_tokens(mock_tokens_p006_loc)
	_expect(p14_loc.last_diagnostic["code"] == "P006"
		and p14_loc.last_diagnostic["location"] == {"line": 2, "column": 9}
		and p14_loc.last_diagnostic["span"] == null, "parser.diag-p006-located-no-span")

	var p15 = Parser.new()
	p15.parse_tokens(Lexer.lex("search synth\nlet x = from(a: 1, b: 2)"))
	_expect(p15.last_diagnostic["code"] == "P007" and p15.last_diagnostic["stage"] == "parser"
		and p15.last_diagnostic["severity"] == "error"
		and p15.last_diagnostic["message"] == "'from' does not support named arguments at line 2 col 9"
		and p15.last_diagnostic["location"] == {"line": 2, "column": 9}
		and p15.last_diagnostic["span"] == source_position.call("search synth\nlet x = from(a: 1, b: 2)", 2, 9), "parser.diag-p007-from-named")
	var p16 = Parser.new()
	p16.parse_tokens(Lexer.lex("search synth\nnd.noise()"))
	_expect(p16.last_diagnostic["code"] == "P007" and p16.last_diagnostic["stage"] == "parser"
		and p16.last_diagnostic["severity"] == "error"
		and p16.last_diagnostic["message"] == "Inline namespace syntax 'nd.noise()' is not allowed. Use 'search nd' at the start of the program instead, at line 2 col 1"
		and p16.last_diagnostic["location"] == {"line": 2, "column": 1}
		and p16.last_diagnostic["span"] == source_position.call("search synth\nnd.noise()", 2, 1), "parser.diag-p007-inline-ns")
	var p17 = Parser.new()
	p17.parse_tokens(Lexer.lex("search synth\ndiagProbe(1, x: 2)"))
	_expect(p17.last_diagnostic["code"] == "P007" and p17.last_diagnostic["stage"] == "parser"
		and p17.last_diagnostic["severity"] == "error"
		and p17.last_diagnostic["message"] == "Cannot mix positional and keyword arguments at line 2 col 14"
		and p17.last_diagnostic["location"] == {"line": 2, "column": 14}
		and p17.last_diagnostic["span"] == source_position.call("search synth\ndiagProbe(1, x: 2)", 2, 14), "parser.diag-p007-mixed-args")
	var p18 = Parser.new()
	p18.parse_tokens(Lexer.lex("search synth\nlet x = 1 + o0"))
	_expect(p18.last_diagnostic["code"] == "P001" and p18.last_diagnostic["stage"] == "parser"
		and p18.last_diagnostic["severity"] == "error"
		and p18.last_diagnostic["message"] == "Expected number"
		and p18.last_diagnostic["location"] == null
		and p18.last_diagnostic["span"] == null, "parser.diag-p001-to-number-unlocated")

	var p19 = Parser.new()
	p19.parse_tokens(Lexer.lex("search synth\nlet x = [1] + 1"))
	_expect(p19.last_diagnostic["code"] == "P001" and p19.last_diagnostic["stage"] == "parser"
		and p19.last_diagnostic["severity"] == "error"
		and p19.last_diagnostic["message"] == "Expected number"
		and p19.last_diagnostic["location"] == {"line": 2, "column": 9}
		and p19.last_diagnostic["span"] == source_position.call("search synth\nlet x = [1] + 1", 2, 9), "parser.diag-p001-to-number-array-span")

	# Subchain argument diagnostics GAP-027
	var p_subchain_permissive = Parser.new()
	var ast_p = p_subchain_permissive.parse_tokens(Lexer.lex("search synth\nnoise().subchain(bad: \"x\", name: \"a\" name: \"b\") { .noise() }.write(o0)"))
	_expect(not p_subchain_permissive._err, "parser.subchain-permissive-ok")
	var subchain_node = ast_p["plans"][0]["chain"][1]
	_expect(subchain_node["subchainArgumentDiagnostics"].size() == 3, "parser.subchain-permissive-diag-count")
	_expect(subchain_node["subchainArgumentDiagnostics"][0]["code"] == "P008", "parser.subchain-p008")
	_expect(subchain_node["subchainArgumentDiagnostics"][1]["code"] == "P010", "parser.subchain-p010")
	_expect(subchain_node["subchainArgumentDiagnostics"][2]["code"] == "P009", "parser.subchain-p009")

	var p_subchain_strict = Parser.new()
	p_subchain_strict.parse_tokens(Lexer.lex("search synth\nnoise().subchain(bad: \"x\") { .noise() }.write(o0)"), {"subchainArguments": "strict"})
	_expect(p_subchain_strict.last_diagnostic["code"] == "P008" and p_subchain_strict.last_diagnostic["severity"] == "error", "parser.subchain-strict-p008")

	# Validator surfaces subchain argument diagnostics in permissive mode
	var reg_val = EffectRegistry.new()
	reg_val.load_all()
	var val_subchain = Validator.new(reg_val)
	var val_res = val_subchain.validate(ast_p)
	_expect(val_res.has("diagnostics"), "validator.subchain-permissive-ok")
	var p008_found := false
	var p010_found := false
	var p009_found := false
	for sub_d in val_res.get("diagnostics", []):
		if sub_d.get("code") == "P008":
			p008_found = true
		elif sub_d.get("code") == "P010":
			p010_found = true
		elif sub_d.get("code") == "P009":
			p009_found = true
	_expect(p008_found and p010_found and p009_found, "validator.subchain-permissive-surfaced")

	# Validator._push_diag column preservation
	var v_probe = load("res://addons/noisemaker/compiler/lang/validator.gd").new(null)
	v_probe._push_diag("S001", {"loc": {"line": 2, "column": 7}})
	_expect(v_probe._diagnostics.back()["location"] == {"line": 2, "column": 7}, "validator.diag-explicit-column")
	v_probe._push_diag("S001", {"loc": {"line": 4, "col": 12}})
	_expect(v_probe._diagnostics.back()["location"] == {"line": 4, "column": 12}, "validator.diag-col-fallback")
	v_probe._push_diag("S001", {"loc": {"line": 5, "column": 8, "col": 99}})
	_expect(v_probe._diagnostics.back()["location"] == {"line": 5, "column": 8}, "validator.diag-column-precedence")
	v_probe._push_diag("S001", {})
	_expect(not v_probe._diagnostics.back().has("location"), "validator.diag-unlocated")

	# EnumPaths
	_expect(EnumPaths.normalize_member_path("oscKind.sine") == ["oscKind", "sine"], "enumpaths.normalize-str")
	_expect(EnumPaths.normalize_member_path(["a", "", "b"]) == ["a", "b"], "enumpaths.normalize-arr")
	_expect(EnumPaths.normalize_member_path("") == null, "enumpaths.normalize-empty")
	_expect(EnumPaths.apply_enum_prefix(["sine"], ["oscKind"]) == ["oscKind", "sine"], "enumpaths.apply-prepend")
	_expect(EnumPaths.apply_enum_prefix(["oscKind", "sine"], ["oscKind"]) == ["oscKind", "sine"], "enumpaths.apply-already")

	# Enums
	var e = Enums.new()
	var pal = e.try_get_head("palette")
	_expect(pal != null and pal["none"] == {"type": "Number", "value": 0}, "enums.palette-none")
	_expect(pal["vintagePhoto"]["value"] == 55, "enums.palette-last")
	var osc = e.try_get_head("oscKind")
	_expect(osc["noise"]["value"] == 5 and osc["noise1d"]["value"] == 5, "enums.osckind-noise-alias")
	e.register_choice(["filter", "blur", "mode", "gaussian"], 0)
	var fhead = e.try_get_head("filter")
	_expect(fhead["blur"]["mode"]["gaussian"]["value"] == 0, "enums.register-choice")

	# Dim
	var sm := {}
	var scoped = Dim.scope_dim({"param": "stateSize"}, "n0", sm)
	_expect(scoped == {"param": "stateSize_n0"} and sm == {"stateSize": "stateSize_n0"}, "dim.scope")
	_expect(Dim.dim_references_param({"screenDivide": "x"}) == true, "dim.refs-param")
	_expect(Dim.parse_dim("screen") == "screen", "dim.parse-identity")

	# Resources — outputs allocated BEFORE inputs released within a pass (parity-critical):
	# t_b can't reuse t_a's slot because t_a is released only after t_b is allocated.
	var passes := [
		{"inputs": {}, "outputs": {"out": "t_a"}},
		{"inputs": {"in": "t_a"}, "outputs": {"out": "t_b"}},
	]
	_expect(Resources.allocate_resources(passes) == {"t_a": "phys_0", "t_b": "phys_1"}, "resources.alloc-order")
	# now a 3rd pass after t_a's release CAN reuse phys_0:
	var passes3 := [
		{"inputs": {}, "outputs": {"out": "t_a"}},
		{"inputs": {"in": "t_a"}, "outputs": {"out": "t_b"}},
		{"inputs": {"in": "t_b"}, "outputs": {"out": "t_c"}},
	]
	_expect(Resources.allocate_resources(passes3) == {"t_a": "phys_0", "t_b": "phys_1", "t_c": "phys_0"}, "resources.reuse")
	# global_ excluded
	var passes2 := [
		{"inputs": {}, "outputs": {"out": "global_o0"}},
		{"inputs": {"in": "global_o0"}, "outputs": {"out": "t_c"}},
	]
	_expect(Resources.allocate_resources(passes2) == {"t_c": "phys_0"}, "resources.global-excluded")

	# Orchestrator texture-spec policies (reference compiler.js extractTextureSpecs, GAP-004):
	# 3D specs carry an authorable `filter`; 2D specs carry `mipmaps`/`persistent` when authored.
	var Orchestrator = preload("res://addons/noisemaker/compiler/graph/orchestrator.gd")
	var o = Orchestrator.new(EffectRegistry.new())
	var specs := {
		"vol": {"width": 64, "is3D": true, "filter": "nearest"},
		"volNoFilter": {"width": 64, "is3D": true},
		"m": {"width": 128, "mipmaps": true, "persistent": true},
		"plain": {"width": 64},
	}
	var extracted: Dictionary = o._extract_texture_specs([], specs)
	_expect(extracted["vol"].get("filter") == "nearest", "orchestrator.tex-3d-filter")
	_expect(not extracted["volNoFilter"].has("filter"), "orchestrator.tex-3d-no-filter")
	_expect(extracted["m"].get("mipmaps") == true and extracted["m"].get("persistent") == true, "orchestrator.tex-2d-policies")
	_expect(not extracted["plain"].has("mipmaps") and not extracted["plain"].has("persistent"), "orchestrator.tex-2d-defaults")
	_expect(extracted["plain"]["width"] == 64 and extracted["plain"]["format"] == "rgba16f", "orchestrator.tex-spec-shape")

	# Runtime mip helpers (nm_backend mipLevelCount/mipLevelSize parity).
	var Backend = preload("res://addons/noisemaker/runtime/nm_backend.gd")
	_expect(Backend._mip_level_count(1, 1) == 1, "nm.mip-count-1")
	_expect(Backend._mip_level_count(128, 64) == 8, "nm.mip-count")
	_expect(Backend._mip_level_count(5, 3) == 3, "nm.mip-count-nonpow2")
	_expect(Backend._mip_level_size(128, 1) == 64 and Backend._mip_level_size(128, 7) == 1, "nm.mip-size")
	_expect(Backend._mip_level_size(3, 4) == 1, "nm.mip-size-clamp")
	# Power-of-two robustness: the chain count comes from integer halving, so it
	# cannot fall one short when a float log/log(2) ratio rounds below the integer.
	_expect(Backend._mip_level_count(1024, 1024) == 11, "nm.mip-count-pow2-1024")
	_expect(Backend._mip_level_count(4096, 1) == 13, "nm.mip-count-pow2-4096")
	_expect(Backend._mip_level_count(16384, 2) == 15, "nm.mip-count-pow2-16384")

	# Ping-pong half-key resolution: mip regeneration looks dims/format up through
	# the parent surface ("global_x_read"/"_write" -> "global_x"), whose allocation
	# carries the graph spec's real dims/format — not the screen/f16 fallbacks.
	var b = Backend.new()
	b._tex_dims["global_flow"] = Vector2i(64, 32)
	b._tex_fmt["global_flow"] = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	var dims_fmt: Array = b._mip_dims_fmt("global_flow_read")
	_expect(dims_fmt[0] == Vector2i(64, 32), "nm.mip-dims-pingpong-half")
	_expect(dims_fmt[1] == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, "nm.mip-fmt-pingpong-half")
	var write_dims_fmt: Array = b._mip_dims_fmt("global_flow_write")
	_expect(write_dims_fmt[0] == Vector2i(64, 32), "nm.mip-dims-pingpong-write")
	_expect(Backend._mip_owner_tex("global_flow") == "global_flow", "nm.mip-owner-flat")
	var unknown: Array = b._mip_dims_fmt("global_other_read")
	_expect(unknown[0] == b.screen, "nm.mip-dims-fallback")

	print("SMOKE: ", "ALL PASS" if _ok else "FAILURES ABOVE")
	quit(0 if _ok else 1)

func _expect(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_ok = false
