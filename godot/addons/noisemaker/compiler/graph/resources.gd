# resources.gd — liveness analysis + linear-scan texture pooling. Port of TD
# compiler/graph/resources.py (1:1 with hlsl Resources.cs / shaders/src/runtime/resources.js,
# reference/04 §1).
#
# allocate_resources(passes) maps virtual pooled texIds -> physical slots "phys_N" (the producer
# of RenderGraph.allocations). PARITY-CRITICAL (reference/04 §1.3): output allocation (insertion
# order of pass.outputs values) happens BEFORE input release (pass.inputs values) within a pass;
# the free-slot search picks the FIRST freeList entry with availableAfter < i; only 'global_' ids
# are excluded (infinite-lived). Fully deterministic, no float math.
extends RefCounted

static func _touch(lifetime: Dictionary, tex_id, index: int) -> void:
	if tex_id == null or tex_id == "":
		return
	if (tex_id as String).begins_with("global_"):
		return
	if not lifetime.has(tex_id):
		lifetime[tex_id] = [index, index]
	else:
		var l: Array = lifetime[tex_id]
		if index < l[0]:
			l[0] = index
		if index > l[1]:
			l[1] = index

static func _build_input_aliases(passes: Array) -> Dictionary:
	var aliases := {}
	var written := {}
	var node_output := RegEx.create_from_string("^node_\\d+_out$")
	for p in passes:
		if not p.get("outputs"):
			continue
		for tex_id in p["outputs"].values():
			if tex_id is String:
				written[tex_id] = true
	for index in range(passes.size()):
		var p: Dictionary = passes[index]
		var node_id = p.get("nodeId")
		if not p.get("inputs") or not node_id:
			continue
		for tex_id in p["inputs"].values():
			if not (tex_id is String) or written.has(tex_id) or aliases.has(tex_id):
				continue
			if tex_id != node_id + "_inputTex" and tex_id != node_id + "_inputColor":
				continue
			for previous in range(index - 1, -1, -1):
				if not passes[previous].get("outputs"):
					continue
				for upstream in passes[previous]["outputs"].values():
					if upstream is String and upstream != node_id + "_out" and node_output.search(upstream) != null:
						aliases[tex_id] = upstream
						break
				if aliases.has(tex_id):
					break
	return aliases

static func _analyze_liveness(passes: Array) -> Dictionary:
	var lifetime := {}  # texId -> [start, end]
	var aliases := _build_input_aliases(passes)
	for index in range(passes.size()):
		var p: Dictionary = passes[index]
		var inputs = p.get("inputs")
		if inputs != null:
			for tex in inputs.values():
				_touch(lifetime, aliases.get(tex, tex), index)
		var outputs = p.get("outputs")
		if outputs != null:
			for tex in outputs.values():
				_touch(lifetime, tex, index)
	return lifetime

static func allocate_resources(passes: Array) -> Dictionary:
	var lifetime := _analyze_liveness(passes)
	var aliases := _build_input_aliases(passes)
	var allocations := {}     # texId -> "phys_N" (insertion-ordered)
	var free_list: Array = [] # list of [phys_id, available_after]
	var physical_count := 0

	for i in range(passes.size()):
		var p: Dictionary = passes[i]
		# 1. allocate outputs (definitions)
		var outputs = p.get("outputs")
		if outputs != null:
			for tex_id in outputs.values():
				if tex_id == null:
					continue
				if (tex_id as String).begins_with("global_"):
					continue
				if allocations.has(tex_id):
					continue
				var free_idx := -1
				for k in range(free_list.size()):
					if free_list[k][1] < i:
						free_idx = k
						break
				if free_idx != -1:
					var phys_id = free_list[free_idx][0]
					free_list.remove_at(free_idx)
					allocations[tex_id] = phys_id
				else:
					allocations[tex_id] = "phys_%d" % physical_count
					physical_count += 1

		# 2. release inputs (last uses). A pass may read one texture under several
		# names (lighting's inputTex and heightMap); release it once, or its slot is
		# handed to two textures that are live together.
		var inputs = p.get("inputs")
		if inputs != null:
			var released := {}
			for input_id in inputs.values():
				var tex_id = aliases.get(input_id, input_id)
				if released.has(tex_id):
					continue
				released[tex_id] = true
				if tex_id == null:
					continue
				if (tex_id as String).begins_with("global_"):
					continue
				if lifetime.has(tex_id):
					var l: Array = lifetime[tex_id]
					if l[1] == i:
						if allocations.has(tex_id):
							free_list.append([allocations[tex_id], i])
	return allocations
