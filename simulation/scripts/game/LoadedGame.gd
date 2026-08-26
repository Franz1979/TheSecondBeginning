class_name LoadedGame
extends RefCounted

var world: World
var game_data: GameData
# Vector2i (coord macro) -> FogOfWarMemory, una per macrocella salvata nel file — vuoto per un
# save precedente l'introduzione di questa sezione (vedi GameLoadService, .get(key, []) sulla
# sezione "fog_of_war"). WorldScene lo propaga a GameSettings.active_fog_of_war_memories in
# _redirect_to_game_scene, stesso canale già in uso per world/game_data.
var fog_of_war_memories: Dictionary = {}
