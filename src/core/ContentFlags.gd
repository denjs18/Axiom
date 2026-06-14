## ContentFlags.gd
## Central switch for "vanilla Minecraft only" mode.
##
## When VANILLA_ONLY is true, every non-Minecraft addition is SKIPPED at load
## time: the "redstone2" logic system, custom weapons (spear/dagger/mace),
## the class/skill armor & altars, the extended End/Nether content, lore and
## quest items, etc. Nothing is deleted from disk — flip VANILLA_ONLY to false
## to bring it all back exactly as before.
##
## To re-enable a single feature later, either set VANILLA_ONLY = false (all
## content returns) or remove its matching rule below (that feature returns).
##
## Accessible globally as `ContentFlags` (registered via class_name).
class_name ContentFlags
extends RefCounted

## Master switch. true = pure vanilla Minecraft content only.
const VANILLA_ONLY := true

## Whole data files that hold non-vanilla content; skipped entirely while
## VANILLA_ONLY is on (currently the "redstone2" programmable-logic system).
const NONVANILLA_FILES := [
	"res://data/blocks/blocks_redstone2.json",
	"res://data/items/items_redstone2.json",
	"res://data/recipes/recipes_redstone2.json",
]

## First custom (non-vanilla) block id in each data file. Vanilla Minecraft
## blocks come first in every file; everything at or above this id is an Axiom
## addition (class altars, archives, quest board, extended End/Nether, ...).
const NONVANILLA_BLOCK_MIN_ID := {
	"blocks_overworld.json": 250,
	"blocks_nether.json": 1050,
	"blocks_end.json": 2010,
}

## Item/armor/material tags that mark non-vanilla content.
const NONVANILLA_ITEM_TAGS := [
	"end_item", "end_material", "endgame", "boss_drop", "mob_drop",
	"style_material", "style_armor", "lore", "quest", "soul_fragment",
	"cosmetic", "utility", "rare", "ultimate", "tier_6", "tier_7", "energy",
]

## Item tag prefixes that mark non-vanilla content (class / skill / module systems).
const NONVANILLA_TAG_PREFIXES := ["class_", "style_", "module_"]

## Tool types that do not exist in vanilla Minecraft.
const NONVANILLA_TOOLS := ["spear", "dagger", "mace"]


## True if an entire data file should be skipped while in vanilla mode.
static func is_file_disabled(path: String) -> bool:
	return VANILLA_ONLY and path in NONVANILLA_FILES


## True if a single block entry should be skipped. `file_name` is the bare
## file name (e.g. "blocks_overworld.json").
static func is_block_disabled(block_data: Dictionary, file_name: String) -> bool:
	if not VANILLA_ONLY:
		return false
	var min_id: int = NONVANILLA_BLOCK_MIN_ID.get(file_name, -1)
	if min_id >= 0 and int(block_data.get("id", 0)) >= min_id:
		return true
	return _tags_non_vanilla(block_data.get("tags", []))


## True if a single item/armor/material entry should be skipped.
static func is_item_disabled(item_data: Dictionary) -> bool:
	if not VANILLA_ONLY:
		return false
	if str(item_data.get("tool", "")) in NONVANILLA_TOOLS:
		return true
	return _tags_non_vanilla(item_data.get("tags", []))


static func _tags_non_vanilla(tags: Array) -> bool:
	for t in tags:
		var tag := str(t)
		if tag in NONVANILLA_ITEM_TAGS:
			return true
		for prefix in NONVANILLA_TAG_PREFIXES:
			if tag.begins_with(prefix):
				return true
	return false
