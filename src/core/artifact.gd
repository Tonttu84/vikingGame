class_name ArtifactData
extends RefCounted
## A run-long passive: one hook, one effect. Later the strategic map ties
## these to conquered locations; the engine only sees the hook.

enum Hook {
	BATTLE_START,      ## fires once in setup, after rosters are placed
	ALLY_DEATH_WAVE,   ## consulted when a player death would shake the line
}

enum EffectType {
	GAIN_MOMENTUM,        ## BATTLE_START: +amount momentum
	ENEMY_MORALE_DAMAGE,  ## BATTLE_START: amount morale damage to fielded enemies
	ALLY_MORALE_BONUS,    ## BATTLE_START: +amount morale and max morale, whole crew
	SUPPRESS_WAVE,        ## ALLY_DEATH_WAVE: swallow the first `amount` waves
}

var id: String
var display_name: String
var description: String
var hook: ArtifactData.Hook
var effect_type: ArtifactData.EffectType
var amount: int


func _init(p_id: String, p_name: String, p_description: String,
		p_hook: ArtifactData.Hook, p_effect: ArtifactData.EffectType, p_amount: int) -> void:
	id = p_id
	display_name = p_name
	description = p_description
	hook = p_hook
	effect_type = p_effect
	amount = p_amount
