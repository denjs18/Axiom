## ArtifactGenerator.gd
## Static utility — generates procedural legendary artifact data from a seed.
## Artifacts are regular item stacks with extra keys:
##   artifact_name     : String   — procedurally generated French name
##   artifact_rarity   : int      — 1=Rare  2=Épique  3=Légendaire
##   artifact_bonuses  : Array    — [{type, value, label}, ...]
class_name ArtifactGenerator
extends RefCounted

# ── Name tables ────────────────────────────────────────────────────────────────

const _ADJECTIVES: Array[String] = [
	"Ancien", "Maudit", "Béni", "Infernal", "Céleste", "Abyssal",
	"Spectral", "Flamboyant", "Glacial", "Crépusculaire", "Primordial",
	"Oublié", "Brisé", "Éternel", "Sombre", "Sacré", "Corrompu", "Sauvage",
]

# Suffix phrases — grammatically correct French (connector already included)
const _SUFFIX_PHRASES: Array[String] = [
	"du Vide", "du Chaos", "du Sang", "du Givre", "du Crépuscule",
	"du Destin", "du Néant", "du Gouffre", "de la Tempête", "de la Ruine",
	"de la Mort", "de la Nuit", "de la Brume", "de la Forge",
	"des Ombres", "des Flammes", "des Cendres", "des Abysses", "des Âmes",
	"de l'Éternité", "de l'Aurore", "de l'Abîme", "de l'Oubli", "de l'Éveil",
]

# Weapon/tool base names by item ID suffix
const _BASE_NAMES: Dictionary = {
	"sword":    "Épée",
	"axe":      "Hache",
	"pickaxe":  "Pioche",
	"shovel":   "Pelle",
	"hoe":      "Faucille",
	"bow":      "Arc",
	"spear":    "Lance",
	"dagger":   "Dague",
	"mace":     "Masse",
}

# ── Bonus pool ─────────────────────────────────────────────────────────────────

const _BONUS_POOL: Array[Dictionary] = [
	{"type": "lifesteal",    "min": 0.05, "max": 0.20, "label": "Vol de vie",       "fmt": "%d%%"},
	{"type": "crit_chance",  "min": 0.10, "max": 0.35, "label": "Coup critique",    "fmt": "%d%%"},
	{"type": "aoe_damage",   "min": 0.25, "max": 0.70, "label": "Dégâts en zone",  "fmt": "%d%%"},
	{"type": "fast_mining",  "min": 0.20, "max": 0.60, "label": "Minage accéléré", "fmt": "+%d%%"},
	{"type": "double_drop",  "min": 0.15, "max": 0.45, "label": "Drop double",      "fmt": "%d%%"},
	{"type": "lightning",    "min": 0.06, "max": 0.18, "label": "Foudre",           "fmt": "%d%%"},
	{"type": "soul_harvest", "min": 5.0,  "max": 25.0, "label": "Récolte d'âmes",  "fmt": "+%d XP"},
	{"type": "shield_break", "min": 0.20, "max": 0.55, "label": "Brise-armure",    "fmt": "%d%%"},
	{"type": "knockback_amp","min": 1.5,  "max": 3.0,  "label": "Recul amplifié",  "fmt": "×%.1f"},
	{"type": "auto_repair",  "min": 1.0,  "max": 5.0,  "label": "Auto-réparation", "fmt": "%d/min"},
]

const _RARITY_NAMES: Array[String] = ["", "Rare", "Épique", "Légendaire"]


# ── Public API ─────────────────────────────────────────────────────────────────

## Generate artifact metadata dict from a deterministic seed.
## num_bonuses : 1 = Rare, 2 = Épique, 3 = Légendaire
static func generate(item_id: String, seed_val: int, num_bonuses: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(seed_val)

	# Derive base type from item_id suffix
	var base_name := "Arme"
	for suffix in _BASE_NAMES:
		if item_id.ends_with(suffix):
			base_name = _BASE_NAMES[suffix]
			break

	# Build name: "[BaseName] [Adjective] [SuffixPhrase]"
	# or "[Adjective] [BaseName] [SuffixPhrase]" (adj-first half the time)
	var adj    := _ADJECTIVES[rng.randi() % _ADJECTIVES.size()]
	var phrase := _SUFFIX_PHRASES[rng.randi() % _SUFFIX_PHRASES.size()]
	var art_name: String
	if rng.randf() > 0.5:
		art_name = "%s %s %s" % [base_name, adj, phrase]
	else:
		art_name = "%s %s %s" % [adj, base_name, phrase]

	# Pick num_bonuses unique bonuses from shuffled pool
	var pool := _BONUS_POOL.duplicate()
	# Fisher-Yates shuffle with our RNG
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = pool[i]; pool[i] = pool[j]; pool[j] = tmp

	var bonuses: Array = []
	for i in mini(num_bonuses, pool.size()):
		var b: Dictionary = (pool[i] as Dictionary).duplicate()
		b["value"] = rng.randf_range(b["min"], b["max"])
		# Round nicely
		if b["fmt"].contains("%%"):
			b["value"] = roundf(b["value"] * 100.0) / 100.0
		elif b["fmt"].contains("×"):
			b["value"] = snappedf(b["value"], 0.1)
		else:
			b["value"] = roundf(b["value"])
		bonuses.append(b)

	return {
		"artifact_name":        art_name,
		"artifact_rarity":      num_bonuses,
		"artifact_rarity_name": _RARITY_NAMES[clampi(num_bonuses, 0, 3)],
		"artifact_bonuses":     bonuses,
	}


## Format a single bonus as a display string, e.g. "Vol de vie : 12%"
static func format_bonus(b: Dictionary) -> String:
	var val: float = b.get("value", 0.0)
	var fmt: String = b.get("fmt", "%.1f")
	var label: String = b.get("label", "?")
	var val_str: String
	if fmt.contains("%%"):
		val_str = "%d%%" % int(val * 100.0)
	elif fmt.contains("×"):
		val_str = "×%.1f" % val
	elif fmt.contains("XP"):
		val_str = "+%d XP" % int(val)
	elif fmt.contains("/min"):
		val_str = "%d/min" % int(val)
	else:
		val_str = "%.1f" % val
	return "%s : %s" % [label, val_str]


## Build a complete item stack dict with artifact metadata embedded.
static func make_artifact_stack(item_id: String, seed_val: int, num_bonuses: int = 1) -> Dictionary:
	var data := generate(item_id, seed_val, num_bonuses)
	var stack := {"id": item_id, "count": 1}
	stack.merge(data)
	return stack
