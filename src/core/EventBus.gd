## EventBus.gd
## Global event bus for decoupled communication between systems.
## Usage: EventBus.block_placed.emit(position, block_id)
extends Node

# World events
signal block_placed(position: Vector3i, block_id: int, metadata: Dictionary)
signal block_broken(position: Vector3i, block_id: int, player: Node)
signal block_interacted(position: Vector3i, block_id: int, player: Node)
signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)
signal chunk_generated(chunk_pos: Vector2i)

# Player events
signal player_spawned(player: Node)
signal player_died(player: Node, cause: String)
signal player_respawned(player: Node)
signal player_dimension_changed(player: Node, from_dim: String, to_dim: String)
signal player_health_changed(player: Node, new_health: float, max_health: float)
signal player_hunger_changed(player: Node, new_hunger: float, saturation: float)
signal player_xp_changed(player: Node, new_xp: int, level: int)
signal player_inventory_changed(player: Node, slot: int)

# Mob events
signal mob_spawned(mob: Node, position: Vector3)
signal mob_died(mob: Node, killer: Node)
signal mob_damaged(mob: Node, amount: float, source: Node)
signal mob_tamed(mob: Node, player: Node)
signal mob_bred(parent1: Node, parent2: Node, offspring: Node)

# Item events
signal item_dropped(item_stack: Dictionary, position: Vector3)
signal item_picked_up(item_stack: Dictionary, player: Node)
signal item_crafted(result: Dictionary, player: Node)

# Game state events
signal game_paused()
signal game_resumed()
signal world_saved()
signal world_loaded(world_name: String)
signal dimension_loaded(dimension_id: String)

# UI events
signal inventory_opened(player: Node)
signal inventory_closed(player: Node)
signal container_opened(container: Node, player: Node)
signal container_closed(container: Node, player: Node)
signal crafting_context_opened(engine: CraftingEngine, inventory: Inventory)
signal crafting_context_closed()
signal recipe_book_requested()

# Time / day-night events
signal time_updated(time: float, day: int)       # emitted every frame by TimeManager
signal day_changed(day: int)                     # new game-day started
signal lunar_phase_changed(phase: int, spawn_multiplier: float)  # phase 0=new moon, 4=full

# Blood moon events
signal blood_moon_warning()                      # emitted the afternoon before the blood moon
signal blood_moon_started(day: int)              # emitted at dusk on blood moon night
signal blood_moon_ended()                        # emitted at dawn after blood moon

# Boss events
signal boss_engaged(boss_name: String, boss: Node)           # player enters boss aggro range
signal boss_health_changed(boss_name: String, hp_ratio: float)
signal boss_defeated(boss_name: String)

# Skill tree events
signal skill_point_gained(amount: int)           # emitted when XP level awards a skill point
signal skill_unlocked(skill_id: String)          # emitted when a skill is unlocked

# Crafting catalog
signal open_crafting_table_with_recipe(recipe: Object, player: Node)  # from catalog → table

# Nexus dimension events
signal nexus_entered()
signal nexus_exited()

# HUD notifications
signal show_message(text: String, duration: float)  # brief centred message on screen
signal advancement_unlocked(id: String, title: String, description: String)  # → HUD toast

# Season / weather events
signal season_changed(season: int)    # Season enum index: 0=Spring 1=Summer 2=Autumn 3=Winter
signal weather_changed(weather: int)  # Weather enum index: 0=Clear 1=Cloudy 2=Rain 3=Storm 4=Blizzard

# Quest / reputation events
signal quest_accepted(quest: Dictionary)
signal quest_completed(quest: Dictionary, rewards: Dictionary)
signal quest_progress_updated(quest: Dictionary)
signal reputation_changed(new_value: int)

# Module events
signal module_enabled(module_id: String)
signal module_disabled(module_id: String)

# Redstone 2.0 events
signal r2_vibration_event(category: int, origin: Vector3i)   # broadcast to vibration sensors
signal r2_debug_toggled(enabled: bool)                        # overlay on/off

# Network events
signal player_connected(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int)
signal chat_message_received(sender: String, message: String, channel: String)
