# shader_diagnostics.gd — one structured diagnostic union for backend shader/compiler failures.
# Reference: shaders/src/runtime/backends/diagnostics.js (upstream f83a427e). Every shader
# compile / link / missing-source failure surfaced by nm_backend.gd is normalized to the
# same dictionary shape the reference's ShaderDiagnostic carries:
#
#   code      legacy machine code ('ERR_SHADER_COMPILE', 'ERR_SHADER_LINK',
#             'ERR_SHADER_MISSING', 'ERR_NO_WGSL_SOURCE' — the last has no
#             RenderingDevice analogue and is kept only for code-table parity);
#   backend   'renderingdevice' (the port's single backend);
#   stage     'compile' | 'link' | 'missing-source' | 'bind';
#   program   program/pass id, when known;
#   detail    the raw compiler string, byte-identical to the legacy push_error text
#             so `detail || message` consumers keep their output;
#   messages  the parsed diagnostic union — one entry per compiler message with
#             severity ('error'|'warning'|'info'), line, column (when reported)
#             and message — so retry logic and tooling never re-parse the string;
#   source    the offending shader source for compile diagnostics;
#   bindingIndex  parsed problem binding for bind-stage diagnostics.
#
# The reference throws a ShaderDiagnostic Error; this port has no throw convention —
# failures set `nm_backend.gd last_shader_diagnostic` (in addition to the unchanged
# legacy push_error) and return the legacy RID()/"" sentinel.
extends RefCounted

const DIAGNOSTIC_CODES := {
	"COMPILE": "ERR_SHADER_COMPILE",
	"LINK": "ERR_SHADER_LINK",
	"MISSING_SOURCE": "ERR_SHADER_MISSING",
	"NO_SOURCE": "ERR_NO_WGSL_SOURCE",
	# Port-side codes: RenderingDevice pipeline creation and draw-list
	# acquisition have no reference analogue (the WebGL2 backend throws from
	# the WebGL calls instead); they surface silent all-black renders.
	"PIPELINE": "ERR_PIPELINE_CREATE",
	"DRAW_LIST": "ERR_DRAW_LIST",
}

var last_diagnostic: Dictionary = {}

const _BINDING_RE := "binding index (\\d+) not present"
const _GLSL_LINE_RE := "^(ERROR|WARNING):\\s*\\d+:(\\d+):\\s*(.*)$"

var _binding_re: RegEx
var _glsl_line_re: RegEx


func _init() -> void:
	_binding_re = RegEx.new()
	_binding_re.compile(_BINDING_RE)
	_glsl_line_re = RegEx.new()
	_glsl_line_re.compile(_GLSL_LINE_RE)


# Parse a GLSL info log into the structured diagnostic union. Handles the
# ubiquitous `ERROR: 0:LINE: message` / `WARNING: 0:LINE: message` forms;
# unprefixed driver prose is kept as an info entry so nothing is lost.
# Mirrors reference parseGLSLInfoLog.
func parse_glsl_info_log(log: String) -> Array:
	if log.is_empty():
		return []
	var messages: Array = []
	for line in log.split("\n"):
		if line.is_empty():
			continue
		var m := _glsl_line_re.search(line)
		if m != null:
			messages.append({
				"severity": m.get_string(1).to_lower(),
				"line": int(m.get_string(2)),
				"message": m.get_string(3),
			})
		else:
			messages.append({"severity": "info", "message": line})
	return messages


# Parse a generic compiler error string into the pieces retry logic needs.
# Mirrors reference parseDiagnosticText: the only string-form contract the
# backends retry on is the "binding index N not present" validation error.
func parse_diagnostic_text(text: String) -> Dictionary:
	var parsed := {"stage": "", "bindingIndex": -1, "messages": []}
	if text.is_empty():
		return parsed
	var b := _binding_re.search(text)
	if b != null:
		parsed["stage"] = "bind"
		parsed["bindingIndex"] = int(b.get_string(1))
	parsed["messages"] = parse_glsl_info_log(text)
	return parsed


# Normalize any failure context into one diagnostic dictionary. Mirrors
# reference toDiagnostic/ShaderDiagnostic: existing detail passes through.
func make(spec: Dictionary) -> Dictionary:
	var detail := str(spec.get("detail", ""))
	var parsed := parse_diagnostic_text(detail)
	var diag := {
		"backend": str(spec.get("backend", "renderingdevice")),
		"stage": str(spec.get("stage", "")),
		"severity": str(spec.get("severity", "error")),
		"detail": detail,
		"messages": spec.get("messages", parsed["messages"]),
	}
	if spec.has("code"):
		diag["code"] = str(spec["code"])
	if spec.has("program"):
		diag["program"] = str(spec["program"])
	if spec.has("source"):
		diag["source"] = str(spec["source"])
	if parsed["bindingIndex"] >= 0:
		diag["bindingIndex"] = parsed["bindingIndex"]
	last_diagnostic = diag
	return diag
