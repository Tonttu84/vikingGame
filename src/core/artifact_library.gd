class_name ArtifactLibrary
extends RefCounted
## The v0 artifacts, built in code like CardLibrary. Debug toggles for now;
## the conquest map hands them out for real later.


static func lindisfarne_chalice() -> ArtifactData:
	return ArtifactData.new("lindisfarne_chalice", "Lindisfarne Chalice",
			"The first prize of the first raid. +1 momentum at the start of every battle.",
			ArtifactData.Hook.BATTLE_START, ArtifactData.EffectType.GAIN_MOMENTUM, 1)


static func raven_banner() -> ArtifactData:
	return ArtifactData.new("raven_banner", "Raven Banner",
			"While it flies, the first fallen crewman each battle shakes no one.",
			ArtifactData.Hook.ALLY_DEATH_WAVE, ArtifactData.EffectType.SUPPRESS_WAVE, 1)


static func serpent_prow() -> ArtifactData:
	return ArtifactData.new("serpent_prow", "Serpent Prow",
			"A dragon's head at the bow. Every fielded enemy takes 1 morale damage as you board.",
			ArtifactData.Hook.BATTLE_START, ArtifactData.EffectType.ENEMY_MORALE_DAMAGE, 1)


static func grilling_irons() -> ArtifactData:
	return ArtifactData.new("grilling_irons", "Grilling Irons",
			"A well-fed crew stands taller: +1 morale for everyone, cap included.",
			ArtifactData.Hook.BATTLE_START, ArtifactData.EffectType.ALLY_MORALE_BONUS, 1)


static func artifact_ids() -> Array[String]:
	return ["lindisfarne_chalice", "raven_banner", "serpent_prow", "grilling_irons"]


static func by_id(id: String) -> ArtifactData:
	match id:
		"lindisfarne_chalice": return lindisfarne_chalice()
		"raven_banner": return raven_banner()
		"serpent_prow": return serpent_prow()
		"grilling_irons": return grilling_irons()
	return null
