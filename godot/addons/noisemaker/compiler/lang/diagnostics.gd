# diagnostics.gd — diagnostic codes + default messages. Port of the REFERENCE
# shaders/src/lang/diagnostics.js (cross-checked vs noisemaker-for-unity Diagnostics.cs). Sources:
# upstream noisemaker + noisemaker-for-unity ONLY.
#
# The validator COLLECTS diagnostics (it does not throw, except missing-search) and builds each
# record itself (shape {code, message, severity, [location], [identifier]} — see validator.gd). This
# module supplies the code -> [default message, severity] table the validator looks up.
extends RefCounted

const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"

# code -> [default message, severity, stage] (verbatim from diagnostics.js).
const _TABLE := {
	"L001": ["Unexpected character", "error", "lexer"],
	"L002": ["Unterminated string literal", "error", "lexer"],
	"L003": ["Unterminated comment", "error", "lexer"],
	"L004": ["Output surface reference out of range", "error", "lexer"],
	"P001": ["Unexpected token", "error", "parser"],
	"P002": ["Expected closing parenthesis", "error", "parser"],
	"P003": ["Invalid automation arguments", "error", "parser"],
	"P004": ["Invalid search directive", "error", "parser"],
	"S001": ["Unknown identifier", "error", "semantic"],
	"S002": ["Argument out of range", "warning", "semantic"],
	"S003": ["Variable used before assignment", "error", "semantic"],
	"S004": ["Cannot assign null or undefined", "error", "semantic"],
	"S005": ["Illegal chain structure", "error", "semantic"],
	"S006": ["Starter chain missing write() call", "error", "semantic"],
	"S007": ["Deprecated parameter alias", "warning", "semantic"],
	"S008": ["Deprecated effect", "warning", "semantic"],
	"R001": ["Runtime error", "error", "runtime"],
}

static func default_message(code: String) -> String:
	return _TABLE[code][0]

static func severity(code: String) -> String:
	return _TABLE[code][1]

static func stage(code: String) -> String:
	return _TABLE[code][2]

# Build a diagnostic record (the shape the reference compile() emits in `diagnostics`).
static func make(code: String, message = null, line = null, column = null, identifier = null) -> Dictionary:
	var d := {
		"code": code,
		"message": message if message != null else default_message(code),
		"severity": severity(code),
	}
	if line != null:
		d["line"] = line
	if column != null:
		d["column"] = column
	if identifier != null:
		d["identifier"] = identifier
	return d
