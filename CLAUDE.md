# Axiom — voxel survival (Godot 4.6, GL Compatibility)

Un « Minecraft nouvelle génération » : toutes les mécaniques de base de
Minecraft + des ajouts simples (saisons, nouveaux minerais, nouveaux biomes,
UI moderne). Le contenu avancé (redstone 2.0, classes/skills, lore) existe
dans le code mais est masqué par `ContentFlags.VANILLA_ONLY = true`.

## Lancer / tester

- Pas de binaire Godot requis pour la CI : Netlify exécute `build.sh`
  (télécharge Godot 4.6 headless + templates, export Web dans `build/web`).
- En local : ouvrir le projet avec Godot 4.6, scène principale
  `scenes/ui/MainMenu.tscn`.
- Validation statique sans Godot : `pip install gdtoolkit` puis
  `gdparse $(find src scenes -name '*.gd')`.
  Note : gdparse ne gère pas les lambdas contenant `if x: y` sur une ligne —
  éviter cette forme.

## Architecture

- `src/core/` — autoloads : BlockRegistry / ItemRegistry / RecipeRegistry /
  BiomeRegistry (chargent `data/*.json`), GameManager (états, monde courant),
  EventBus (tous les signaux), TimeManager (jour/nuit, lune, lune de sang),
  SeasonManager (4 saisons × 5 jours, météo), ContentFlags (mode vanilla).
- `data/` — JSON du contenu. IDs de blocs : overworld < 250 = vanilla,
  ≥ 250 = additions Axiom (masquées) ; nether offset 1000 ; end offset 2000.
  `ContentFlags.VANILLA_PLUS_*` = allowlist des nouveaux minerais actifs.
- `src/world/` — Chunk (16³, RLE + version de sauvegarde), ChunkManager
  (chargement asynchrone via WorkerThreadPool), WorldGenerator (overworld /
  nether à biomes / end en îles, arbres par essence via `build_tree()`,
  minerais, végétation, shrines de l'End), LightEngine (sky light par
  `chunk.world_surface`, block light BFS), DimensionManager (portails :
  allumage briquet, voyage, portail retour), BlockEntityManager +
  entities/ (coffre, four, objets au sol).
- `src/rendering/` — ChunkRenderer : greedy meshing + formes spéciales
  (croix/torche/dalle) + **lumière bakée dans COLOR** (r = ombrage de face,
  g = sky light, b = block light). Deux ShaderMaterials **statiques partagés**
  pilotés chaque frame par DayNightCycle (`sky_energy`, `sky_tint`).
  BlockTextureAtlas : atlas construit au démarrage depuis
  `assets/textures/blocks/*.png` (textures MC), teinte biome appliquée aux
  textures grises (herbe/feuillage), fallback procédural par nom.
- `src/mobs/` — BaseMob (corps multi-boîtes : `build_quadruped` /
  `build_biped`, `animate_walk`), BaseAnimal (troupeaux, apprivoisement,
  reproduction, génétique), BaseHostile (aggro/chase, `burns_in_daylight`),
  MobSpawner (animaux le jour, hostiles la nuit).
- `scenes/ui/` — UI construites en code sur `UITheme` (src/ui/UITheme.gd),
  design system sombre + accent vert. HUD (F3 = debug), InventoryUI (E),
  ChestUI, FurnaceUI, CraftingTableUI (3×3), RecipeCatalogUI (C),
  DeathScreen, PauseMenu, MainMenu.

## Pièges connus

- Le mesh terrain est **unshaded** : la luminosité vient des vertex colors ×
  uniforms — ne pas remettre de DirectionalLight dessus.
- Après un `set_block_at`, la lumière est recalculée par
  `World._relight_around` (branché sur block_placed/block_broken).
  Tout nouveau chemin de modification de blocs doit émettre ces signaux.
- `ensure_chunk_sync` et `force_initial_build` doivent passer la lumière
  (déjà fait) — sinon chunks noirs ou plein-jour.
- Les stacks d'items sont des Dictionaries `{id, count, meta}` partout
  (ChestEntity inclus).
- IDs critiques hardcodés : portail nether 93, portail end 94, obsidienne
  101, lit 92, canne à sucre 89 (voir constantes de WorldGenerator).
