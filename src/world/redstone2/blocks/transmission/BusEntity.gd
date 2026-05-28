## BusEntity.gd — Multi-channel bus (Bus logique). ID 4001.
## Carries up to 8 (basic) or 16 (advanced) parallel channels simultaneously.
## Each channel is fully isolated from the others.
class_name BusEntity
extends R2BlockEntity

const MAX_CHANNELS_BASIC    := 8
const MAX_CHANNELS_ADVANCED := 16

var max_channels: int = MAX_CHANNELS_BASIC


func _init(pos: Vector3i) -> void:
	super(pos, "r2_bus")


func phase_acquire(tick: int) -> void:
	current_tick = tick
	_inputs.clear()
	_face_inputs.clear()
	for face in ALL_FACES:
		var nb: R2BlockEntity = R2Engine.get_block(world_pos + face)
		if nb == null:
			continue
		# Collect all channels emitted by this neighbor
		for ch in range(max_channels):
			var sig := nb.get_output(ch)
			if sig == null or not sig.to_bool():
				continue
			var ch_match := sig.channel
			if not _inputs.has(ch_match):
				_inputs[ch_match] = []
			(_inputs[ch_match] as Array).append(sig)


func phase_calculate() -> void:
	for ch in range(max_channels):
		emit_output(get_input(ch), ch)


func _get_output_toward(target_pos: Vector3i) -> R2Signal:
	# Bus exports all channels; caller picks the channel they need
	var dir := target_pos - world_pos
	if dir not in ALL_FACES:
		return null
	return get_output(0)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["max_channels"] = max_channels
	return d


func deserialize(data: Dictionary) -> void:
	max_channels = data.get("max_channels", MAX_CHANNELS_BASIC)
	super.deserialize(data)
