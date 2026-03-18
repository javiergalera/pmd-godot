class_name DungeonRandom
extends RefCounted
## RNG class for dungeon-mystery algorithm (PMD:EoS).
## Rand16Bit uses LCG; RandInt/RandRange use non-deterministic random (matches original).

var _primary_value: int = 0
var _secondary_value: int = 0
var _use_secondary: bool = false

const MULTIPLIER: int = 0x5D588B65
const INCREMENT_PRIMARY: int = 1
const INCREMENT_SECONDARY: int = 0x269EC3

func _init() -> void:
	_primary_value = randi()
	_secondary_value = randi()

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

## Non-deterministic random integer in [0, max) — matches original Math.random() usage
func rand_int(max_val: int) -> int:
	if max_val <= 0:
		return 0
	return randi() % max_val

## Non-deterministic random integer in [min_val, max_val] — matches original Math.random() usage
func rand_range(min_val: int, max_val: int) -> int:
	if max_val <= min_val:
		return min_val
	return min_val + (randi() % (max_val - min_val + 1))
