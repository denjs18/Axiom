## R2Registry.gd — Maps Redstone 2.0 block IDs and type strings to entity classes.
## Block IDs: 4000–4074.  Type strings: "r2_wire", "r2_gate_not", etc.
##
## Used by BlockEntityManager to create entities when R2 blocks are placed,
## and to restore them during world deserialization.
class_name R2Registry
extends RefCounted

# ── Block ID ranges ───────────────────────────────────────────────────────────
# Transmission  4000–4009
# Logic         4010–4019
# Analog        4020–4027
# Sensors       4030–4037
# Memory/Time   4040–4047
# Control       4050–4054
# Actuators     4060–4066
# Diagnostics   4070–4074

static func is_r2_block(block_id: int) -> bool:
	return block_id >= 4000 and block_id <= 4074


static func is_r2_type(type_str: String) -> bool:
	return type_str.begins_with("r2_")


## Create a fresh entity for a newly placed block.
static func create_entity(block_id: int, pos: Vector3i) -> R2BlockEntity:
	match block_id:
		# Transmission
		4000: return WireEntity.new(pos)
		4001: return BusEntity.new(pos)
		4002: return Repeater2Entity.new(pos)
		4003: return BridgeEntity.new(pos)
		4004: return LegacyConverterEntity.new(pos)
		# Logic boolean
		4010: return GateNOTEntity.new(pos)
		4011: return GateANDEntity.new(pos)
		4012: return GateOREntity.new(pos)
		4013: return GateXOREntity.new(pos)
		4014: return GateNANDEntity.new(pos)
		4015: return GateNOREntity.new(pos)
		4016: return GateXNOREntity.new(pos)
		4017: return SelectorEntity.new(pos)
		4018: return MuxEntity.new(pos)
		4019: return DemuxEntity.new(pos)
		# Analog
		4020: return Comparator2Entity.new(pos)
		4021: return ThresholdEntity.new(pos)
		4022: return AdderEntity.new(pos)
		4023: return SubtractorEntity.new(pos)
		4024: return MultiplierEntity.new(pos)
		4025: return DividerEntity.new(pos)
		4026: return RangeMapperEntity.new(pos)
		4027: return QuantifierEntity.new(pos)
		# Sensors
		4030: return Observer2Entity.new(pos)
		4031: return PresenceDetectorEntity.new(pos)
		4032: return ZoneDetectorEntity.new(pos)
		4033: return InventorySensorEntity.new(pos)
		4034: return BlockStateSensorEntity.new(pos)
		4035: return EnvironmentalSensorEntity.new(pos)
		4036: return MovementSensorEntity.new(pos)
		4037: return VibrationSensorEntity.new(pos)
		# Memory & time
		4040: return FlipFlopTEntity.new(pos)
		4041: return FlipFlopSREntity.new(pos)
		4042: return FlipFlopDEntity.new(pos)
		4043: return RegisterEntity.new(pos)
		4044: return CounterEntity.new(pos)
		4045: return TimerEntity.new(pos)
		4046: return ClockEntity.new(pos)
		4047: return EventQueueEntity.new(pos)
		# Control & orchestration
		4050: return LogicControllerEntity.new(pos)
		4051: return SequencerEntity.new(pos)
		4052: return StateMachineEntity.new(pos)
		4053: return SchedulerEntity.new(pos)
		4054: return VisualScriptEntity.new(pos)
		# Actuators
		4060: return UniversalActuatorEntity.new(pos)
		4061: return Piston2Entity.new(pos)
		4062: return SmartDispenserEntity.new(pos)
		4063: return SmartDropperEntity.new(pos)
		4064: return LogicLampEntity.new(pos)
		4065: return DoorLogicEntity.new(pos)
		4066: return MechanicalMotorEntity.new(pos)
		# Diagnostics
		4070: return LogicProbeEntity.new(pos)
		4071: return Monitor2Entity.new(pos)
		4072: return OscilloscopeEntity.new(pos)
		4073: return NetworkColorizerEntity.new(pos)
		4074: return LoopAnalyzerEntity.new(pos)
	return null


## Restore a saved entity from its serialized type string.
static func create_from_type(type_str: String, pos: Vector3i) -> R2BlockEntity:
	match type_str:
		"r2_wire":          return WireEntity.new(pos)
		"r2_bus":           return BusEntity.new(pos)
		"r2_repeater":      return Repeater2Entity.new(pos)
		"r2_bridge":        return BridgeEntity.new(pos)
		"r2_legacy_conv":   return LegacyConverterEntity.new(pos)
		"r2_gate_not":      return GateNOTEntity.new(pos)
		"r2_gate_and":      return GateANDEntity.new(pos)
		"r2_gate_or":       return GateOREntity.new(pos)
		"r2_gate_xor":      return GateXOREntity.new(pos)
		"r2_gate_nand":     return GateNANDEntity.new(pos)
		"r2_gate_nor":      return GateNOREntity.new(pos)
		"r2_gate_xnor":     return GateXNOREntity.new(pos)
		"r2_selector":      return SelectorEntity.new(pos)
		"r2_mux":           return MuxEntity.new(pos)
		"r2_demux":         return DemuxEntity.new(pos)
		"r2_comparator2":   return Comparator2Entity.new(pos)
		"r2_threshold":     return ThresholdEntity.new(pos)
		"r2_adder":         return AdderEntity.new(pos)
		"r2_subtractor":    return SubtractorEntity.new(pos)
		"r2_multiplier":    return MultiplierEntity.new(pos)
		"r2_divider":       return DividerEntity.new(pos)
		"r2_range_mapper":  return RangeMapperEntity.new(pos)
		"r2_quantifier":    return QuantifierEntity.new(pos)
		"r2_observer2":     return Observer2Entity.new(pos)
		"r2_presence":      return PresenceDetectorEntity.new(pos)
		"r2_zone":          return ZoneDetectorEntity.new(pos)
		"r2_inv_sensor":    return InventorySensorEntity.new(pos)
		"r2_block_state":   return BlockStateSensorEntity.new(pos)
		"r2_env_sensor":    return EnvironmentalSensorEntity.new(pos)
		"r2_movement":      return MovementSensorEntity.new(pos)
		"r2_vibration":     return VibrationSensorEntity.new(pos)
		"r2_ff_t":          return FlipFlopTEntity.new(pos)
		"r2_ff_sr":         return FlipFlopSREntity.new(pos)
		"r2_ff_d":          return FlipFlopDEntity.new(pos)
		"r2_register":      return RegisterEntity.new(pos)
		"r2_counter":       return CounterEntity.new(pos)
		"r2_timer":         return TimerEntity.new(pos)
		"r2_clock":         return ClockEntity.new(pos)
		"r2_event_queue":   return EventQueueEntity.new(pos)
		"r2_controller":    return LogicControllerEntity.new(pos)
		"r2_sequencer":     return SequencerEntity.new(pos)
		"r2_state_machine": return StateMachineEntity.new(pos)
		"r2_scheduler":     return SchedulerEntity.new(pos)
		"r2_visual_script": return VisualScriptEntity.new(pos)
		"r2_actuator":      return UniversalActuatorEntity.new(pos)
		"r2_piston2":       return Piston2Entity.new(pos)
		"r2_dispenser2":    return SmartDispenserEntity.new(pos)
		"r2_dropper2":      return SmartDropperEntity.new(pos)
		"r2_logic_lamp":    return LogicLampEntity.new(pos)
		"r2_door_logic":    return DoorLogicEntity.new(pos)
		"r2_motor":         return MechanicalMotorEntity.new(pos)
		"r2_probe":         return LogicProbeEntity.new(pos)
		"r2_monitor":       return Monitor2Entity.new(pos)
		"r2_oscilloscope":  return OscilloscopeEntity.new(pos)
		"r2_colorizer":     return NetworkColorizerEntity.new(pos)
		"r2_loop_analyzer": return LoopAnalyzerEntity.new(pos)
	return null
