class_name DungeonRandom
extends RefCounted
## RNG class for dungeon generation.
## All random calls are derived from the same seed to keep floors reproducible.

var _primary_value: int = 0
var _secondary_value: int = 0
var _use_secondary: bool = false
var _stream_value: int = 0

const MULTIPLIER: int = 0x5D588B65
const INCREMENT_PRIMARY: int = 1
const INCREMENT_SECONDARY: int = 0x269EC3
const INCREMENT_STREAM: int = 0x6D2B79F5

func _init(seed_value: int = 0) -> void:
	var base_seed := seed_value & 0xFFFFFFFF
	if base_seed == 0:
		base_seed = 0xA341316C
	_primary_value = _mix_seed(base_seed ^ 0xA511E9B3)
	_secondary_value = _mix_seed(base_seed ^ 0x63D83595)
	_stream_value = _mix_seed(base_seed ^ 0xC2B2AE35)

func _mix_seed(value: int) -> int:
	var mixed := value & 0xFFFFFFFF
	mixed = (mixed ^ (mixed >> 16)) & 0xFFFFFFFF
	mixed = (mixed * 0x7FEB352D) & 0xFFFFFFFF
	mixed = (mixed ^ (mixed >> 15)) & 0xFFFFFFFF
	mixed = (mixed * 0x846CA68B) & 0xFFFFFFFF
	mixed = (mixed ^ (mixed >> 16)) & 0xFFFFFFFF
	return mixed

func _next_stream_value() -> int:
	_stream_value = (_stream_value * MULTIPLIER + INCREMENT_STREAM) & 0xFFFFFFFF
	return _stream_value

func dungeon_rng_set_secondary(seed_val: int) -> void:
	_secondary_value = seed_val
	_use_secondary = true

## LCG-based 16-bit random (matches original Rand16Bit)
func rand_16_bit() -> int:
	if _use_secondary:
		_secondary_value = (_secondary_value * MULTIPLIER + INCREMENT_SECONDARY) & 0xFFFFFFFF
		return (_secondary_value >> 16) & 0xFFFF
	else:
		_primary_value = (_primary_value * MULTIPLIER + INCREMENT_PRIMARY) & 0xFFFFFFFF
		return (_primary_value >> 16) & 0xFFFF

func rand_int(max_val: int) -> int:
	if max_val <= 0:
		return 0
	return int(_next_stream_value() % max_val)

func rand_range(min_val: int, max_val: int) -> int:
	if max_val <= min_val:
		return min_val
	return min_val + rand_int(max_val - min_val + 1)
