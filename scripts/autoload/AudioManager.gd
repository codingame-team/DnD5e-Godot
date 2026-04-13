## AudioManager.gd
## Autoload : gestion de la musique et des effets sonores.
extends Node

const BGM_VOLUME_DB := -10.0
const SFX_VOLUME_DB := 0.0

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_size := 8

var music_enabled: bool = true
var sfx_enabled: bool = true

func _settings_manager() -> Node:
	return get_node("/root/SettingsManager")

func _ready() -> void:
	_settings_manager().load_settings()
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Music"
	_bgm_player.volume_db = _settings_manager().get_setting("music_volume_db")
	add_child(_bgm_player)

	for idx in _sfx_pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = _settings_manager().get_setting("sfx_volume_db")
		add_child(p)
		_sfx_players.append(p)

	music_enabled = _settings_manager().get_setting("music_enabled")
	sfx_enabled = _settings_manager().get_setting("sfx_enabled")

# --------------------------------------------------------------------------
# Musique de fond
# --------------------------------------------------------------------------

func play_music(path: String, loop: bool = true) -> void:
	if not music_enabled:
		return
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: fichier audio introuvable : %s" % path)
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	elif stream is AudioStreamMP3:
		stream.loop = loop
	_bgm_player.stream = stream
	_bgm_player.play()

func stop_music() -> void:
	_bgm_player.stop()

func set_music_volume(volume_db: float) -> void:
	_bgm_player.volume_db = volume_db

func set_sfx_volume(volume_db: float) -> void:
	for p in _sfx_players:
		p.volume_db = volume_db

# --------------------------------------------------------------------------
# Effets sonores
# --------------------------------------------------------------------------

func play_sfx(path: String) -> void:
	if not sfx_enabled:
		return
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	var player := _get_free_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0] # recycle le premier si tous occupés

# --------------------------------------------------------------------------
# Sons de jeu prédéfinis (chemins configurables)
# --------------------------------------------------------------------------

func play_sword_hit() -> void: play_sfx("res://assets/audio/sfx/sword_hit.ogg")
func play_spell_cast() -> void: play_sfx("res://assets/audio/sfx/spell_cast.ogg")
func play_footstep() -> void: play_sfx("res://assets/audio/sfx/footstep.ogg")
func play_dice_roll() -> void: play_sfx("res://assets/audio/sfx/dice_roll.ogg")
func play_levelup() -> void: play_sfx("res://assets/audio/sfx/levelup.ogg")
func play_death() -> void: play_sfx("res://assets/audio/sfx/death.ogg")

func play_combat_music() -> void: play_music("res://assets/audio/bgm/combat.ogg")
func play_dungeon_music() -> void: play_music("res://assets/audio/bgm/dungeon.ogg")
func play_main_menu_music() -> void: play_music("res://assets/audio/bgm/main_menu.ogg")
