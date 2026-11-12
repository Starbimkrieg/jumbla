-- Hero abilities. Every ability has a resource cost and a cooldown, and all
-- abilities except off-GCD ones also trigger the 1.5s global cooldown.
--
-- Fields:
--   kind    "spell" | "melee" (melee = uses attack power / melee crit)
--   cost    resource cost (mana, rage or energy depending on the hero)
--   cd      cooldown in seconds
--   cast    cast time (0 = instant); channel/ticks for channelled spells
--   range   yards, or "melee"
--   ai      how the auto-battler decides to use it (see Engine/Combat.lua)
--   execute function(run, caster, target, ability)
local ADDON, ns = ...

local A = {}
ns.Abilities = A

local I = "Interface\\Icons\\"

-- Ability numbers grow ~12% per level above 10 (a stand-in for spell ranks).
local function S(u) return 1 + ((u.level or 10) - 10) * 0.12 end
ns.AbilityScale = S

---------------------------------------------------------------------------
-- DPS
---------------------------------------------------------------------------

A.MOONFIRE = {
    name = "Moonfire", icon = I .. "Spell_Nature_StarFall", kind = "spell", school = "arcane",
    cost = 30, cd = 0, cast = 0, range = 30, ai = "dot", aura = "MOONFIRE",
    desc = "Burns the target for arcane damage, then more over 9 sec.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(10, 13) * S(c), 0.15, "arcane", "Moonfire")
        run:ApplyDot(c, t, { key = "MOONFIRE", name = "Moonfire", icon = A.MOONFIRE.icon, school = "arcane",
            total = 24 * S(c), duration = 9, interval = 3, coef = 0.3 })
    end,
}

A.RAKE = {
    name = "Rake", icon = I .. "Ability_Druid_Disembowel", kind = "melee", school = "physical",
    cost = 35, cd = 0, cast = 0, range = "melee", ai = "dot", aura = "RAKE",
    desc = "Rakes the target for damage plus a bleed over 9 sec.",
    execute = function(run, c, t)
        if run:WeaponStrike(c, t, 6 * S(c), "Rake", { bonusOnly = true, apCoef = 0.12 }) then
            run:ApplyDot(c, t, { key = "RAKE", name = "Rake", icon = A.RAKE.icon, school = "bleed",
                total = 27 * S(c), duration = 9, interval = 3, apCoef = 0.06 })
        end
    end,
}

A.ARCANE_SHOT = {
    name = "Arcane Shot", icon = I .. "Ability_ImpalingBolt", kind = "melee", school = "arcane",
    cost = 25, cd = 6, cast = 0, range = 30, ai = "nuke",
    desc = "An instant shot for arcane damage (scales with attack power).",
    execute = function(run, c, t)
        run:PhysicalDamage(c, t, (15 * S(c)) + run:AP(c) * 0.15, "Arcane Shot", { school = "arcane", ranged = true })
    end,
}

A.RAPTOR_STRIKE = {
    name = "Raptor Strike", icon = I .. "Ability_MeleeDamage", kind = "melee", school = "physical",
    cost = 15, cd = 6, cast = 0, range = "melee", ai = "nuke",
    desc = "A strong attack that adds bonus damage to a weapon swing.",
    execute = function(run, c, t)
        run:WeaponStrike(c, t, 10 * S(c), "Raptor Strike")
    end,
}

A.KILL_COMMAND = {
    name = "Kill Command", icon = I .. "Ability_Hunter_KillCommand", kind = "melee", school = "physical",
    cost = 20, cd = 8, cast = 0, range = 40, ai = "petattack",
    desc = "Commands your wolf to savage the target. Requires a living pet.",
    execute = function(run, c, t)
        local pet = c.pet
        if pet and not pet.dead then
            run:PhysicalDamage(pet, t, (18 * S(c)) + run:AP(c) * 0.25, "Kill Command", { noMiss = true })
        end
    end,
}

A.FROSTBOLT = {
    name = "Frostbolt", icon = I .. "Spell_Frost_FrostBolt02", kind = "spell", school = "frost",
    cost = 25, cd = 0, cast = 2.0, range = 30, ai = "nuke",
    desc = "Frost damage that slows the target's movement by 40% and attack speed by 15% for 5 sec.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(19, 23) * S(c), 0.57, "frost", "Frostbolt")
        run:ApplyAura(t, { key = "FROSTBOLT", source = c, name = "Frostbolt", icon = A.FROSTBOLT.icon,
            duration = 5, mods = { moveMult = 0.6, hasteMult = 0.85 } })
    end,
}

A.FIRE_BOLT = {
    name = "Fire Bolt", icon = I .. "Spell_Fire_FireBolt", kind = "spell", school = "fire",
    cost = 30, cd = 0, cast = 2.25, range = 30, ai = "nuke",
    desc = "Fire damage, then additional fire damage over 4 sec.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(20, 25) * S(c), 0.6, "fire", "Fire Bolt")
        run:ApplyDot(c, t, { key = "FIRE_BOLT", name = "Fire Bolt", icon = A.FIRE_BOLT.icon, school = "fire",
            total = 6 * S(c), duration = 4, interval = 2, coef = 0.05 })
    end,
}

A.ARCANE_MISSILES = {
    name = "Arcane Missiles", icon = I .. "Spell_Nature_StarFall", kind = "spell", school = "arcane",
    cost = 35, cd = 0, channel = 3, ticks = 3, range = 30, ai = "nuke",
    desc = "Channels 3 arcane missiles at the target over 3 sec.",
    tick = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(9, 11) * S(c), 0.24, "arcane", "Arcane Missiles")
    end,
    execute = function() end,
}

A.SEAL_OF_RIGHTEOUSNESS = {
    name = "Seal of Righteousness", icon = I .. "Ability_ThunderBolt", kind = "melee", school = "holy",
    cost = 25, cd = 0, cast = 0, range = "self", ai = "selfbuff", aura = "SEAL_OF_RIGHTEOUSNESS",
    desc = "For 30 sec, melee swings deal extra holy damage and cleave up to 2 nearby enemies for 50%.",
    execute = function(run, c)
        run:ApplyAura(c, { key = "SEAL_OF_RIGHTEOUSNESS", source = c, name = "Seal of Righteousness",
            icon = A.SEAL_OF_RIGHTEOUSNESS.icon, duration = 30,
            onSwing = { holyPerSpeed = 2.2 * S(c), spCoef = 0.1, cleave = 2, cleavePct = 0.5 } })
    end,
}

A.MIND_BLAST = {
    name = "Mind Blast", icon = I .. "Spell_Shadow_UnholyFrenzy", kind = "spell", school = "shadow",
    cost = 45, cd = 8, cast = 1.5, range = 30, ai = "nuke",
    desc = "Blasts the target for heavy shadow damage.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(38, 44) * S(c), 0.43, "shadow", "Mind Blast")
    end,
}

A.SINISTER_STRIKE = {
    name = "Sinister Strike", icon = I .. "Spell_Shadow_RitualOfSacrifice", kind = "melee", school = "physical",
    cost = 45, cd = 0, cast = 0, range = "melee", ai = "nuke",
    desc = "An instant strike that deals weapon damage plus a bonus.",
    execute = function(run, c, t)
        run:WeaponStrike(c, t, 8 * S(c), "Sinister Strike")
    end,
}

A.ROCKBITER_WEAPON = {
    name = "Rockbiter Weapon", icon = I .. "Spell_Nature_RockBiter", kind = "melee", school = "nature",
    cost = 25, cd = 0, cast = 0, range = "self", ai = "selfbuff", aura = "ROCKBITER_WEAPON",
    desc = "Imbues your weapon for 5 min, adding damage to every swing.",
    execute = function(run, c)
        run:ApplyAura(c, { key = "ROCKBITER_WEAPON", source = c, name = "Rockbiter Weapon",
            icon = A.ROCKBITER_WEAPON.icon, duration = 300, onSwing = { flatPerSpeed = 3.0 * S(c) } })
    end,
}

A.LIGHTNING_BOLT = {
    name = "Lightning Bolt", icon = I .. "Spell_Nature_Lightning", kind = "spell", school = "nature",
    cost = 25, cd = 0, cast = 2.0, range = 30, ai = "nuke",
    desc = "Hurls a bolt of lightning for nature damage.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(23, 27) * S(c), 0.57, "nature", "Lightning Bolt")
    end,
}

A.CORRUPTION = {
    name = "Corruption", icon = I .. "Spell_Shadow_AbominationExplosion", kind = "spell", school = "shadow",
    cost = 30, cd = 0, cast = 0, range = 30, ai = "dot", aura = "CORRUPTION",
    desc = "Corrupts the target, dealing shadow damage over 12 sec.",
    execute = function(run, c, t)
        run:ApplyDot(c, t, { key = "CORRUPTION", name = "Corruption", icon = A.CORRUPTION.icon, school = "shadow",
            total = 52 * S(c), duration = 12, interval = 3, coef = 0.6 })
    end,
}

A.SHADOW_BOLT = {
    name = "Shadow Bolt", icon = I .. "Spell_Shadow_ShadowBolt", kind = "spell", school = "shadow",
    cost = 30, cd = 0, cast = 2.5, range = 30, ai = "nuke",
    desc = "Sends a shadowy bolt at the enemy.",
    execute = function(run, c, t)
        run:SpellDamage(c, t, run:Rnd(30, 36) * S(c), 0.71, "shadow", "Shadow Bolt")
    end,
}

A.SUMMON_IMP = {
    name = "Summon Imp", icon = I .. "Spell_Shadow_SummonImp", kind = "spell", school = "shadow",
    cost = 50, cd = 10, cast = 3, range = "self", ai = "summon", pet = "IMP",
    desc = "Summons an Imp that hurls Firebolts at your enemies.",
    execute = function(run, c)
        run:SummonPet(c, "IMP")
    end,
}

A.HEROIC_STRIKE = {
    name = "Heroic Strike", icon = I .. "Ability_Rogue_Ambush", kind = "melee", school = "physical",
    cost = 15, cd = 0, cast = 0, range = "melee", ai = "nextswing", offGCD = true,
    desc = "Your next melee swing deals bonus damage.",
    execute = function(run, c)
        c.queuedStrike = { bonus = 22 * S(c), name = "Heroic Strike" }
    end,
}

A.BLOODLUST = {
    name = "Bloodlust", icon = I .. "Spell_Nature_BloodLust", kind = "melee", school = "physical",
    cost = 20, cd = 20, cast = 0, range = "self", ai = "selfbuff", aura = "BLOODLUST", combatOnly = true,
    desc = "Increases your attack speed by 40% for 12 sec.",
    execute = function(run, c)
        run:ApplyAura(c, { key = "BLOODLUST", source = c, name = "Bloodlust", icon = A.BLOODLUST.icon,
            duration = 12, mods = { hasteMult = 1.4 } })
    end,
}

---------------------------------------------------------------------------
-- Tanks
---------------------------------------------------------------------------

A.TAUNT = {
    name = "Taunt", icon = I .. "Spell_Nature_Reincarnation", kind = "melee", school = "physical",
    cost = 0, cd = 8, cast = 0, range = "self", ai = "taunt", radius = 15, offGCD = true,
    desc = "Forces all enemies within 15 yards to attack you for 3 sec.",
    execute = function(run, c)
        run:Taunt(c, 15, 3)
    end,
}

A.SHIELD_BLOCK = {
    name = "Shield Block", icon = I .. "Ability_Defend", kind = "melee", school = "physical",
    cost = 10, cd = 6, cast = 0, range = "self", ai = "defensive", offGCD = true, needsShield = true,
    desc = "For 5 sec, increases your shield's block value and block chance.",
    execute = function(run, c)
        run:ApplyAura(c, { key = "SHIELD_BLOCK", source = c, name = "Shield Block", icon = A.SHIELD_BLOCK.icon,
            duration = 5, mods = { blockValue = 20 * S(c), blockChance = 50 } })
    end,
}

A.DEVOTION_AURA = {
    name = "Devotion Aura", icon = I .. "Spell_Holy_DevotionAura", kind = "spell", school = "holy",
    cost = 20, cd = 0, cast = 0, range = "self", ai = "partyaura", aura = "DEVOTION_AURA",
    desc = "Increases the armor of all party members by a flat amount.",
    execute = function(run, c)
        for _, u in ipairs(run:Allies(c)) do
            run:ApplyAura(u, { key = "DEVOTION_AURA", source = c, name = "Devotion Aura",
                icon = A.DEVOTION_AURA.icon, duration = 9999, mods = { armor = 80 * S(c) } })
        end
    end,
}

A.THORNS = {
    name = "Thorns", icon = I .. "Spell_Nature_Thorns", kind = "spell", school = "nature",
    cost = 35, cd = 0, cast = 0, range = "self", ai = "selfbuff", aura = "THORNS",
    desc = "Gain a large flat armor bonus and deal nature damage to melee attackers.",
    execute = function(run, c)
        run:ApplyAura(c, { key = "THORNS", source = c, name = "Thorns", icon = A.THORNS.icon,
            duration = 600, mods = { armor = 380 * S(c), thorns = 4 * S(c) } })
    end,
}

---------------------------------------------------------------------------
-- Healers
---------------------------------------------------------------------------

A.HEALING_WAVE = {
    name = "Healing Wave", icon = I .. "Spell_Nature_MagicImmunity", kind = "spell", school = "nature",
    cost = 25, cd = 0, cast = 2.0, range = 40, ai = "heal",
    desc = "Heals a friendly target.",
    execute = function(run, c, t)
        run:Heal(c, t, run:Rnd(42, 50) * S(c), 0.57, "Healing Wave")
    end,
}

A.REJUVENATION = {
    name = "Rejuvenation", icon = I .. "Spell_Nature_Rejuvenation", kind = "spell", school = "nature",
    cost = 25, cd = 0, cast = 0, range = 40, ai = "hot", aura = "REJUVENATION",
    desc = "Heals the target over 12 sec.",
    execute = function(run, c, t)
        run:ApplyHot(c, t, { key = "REJUVENATION", name = "Rejuvenation", icon = A.REJUVENATION.icon,
            total = 72 * S(c), duration = 12, interval = 3, coef = 0.8 })
    end,
}

A.HEAL = {
    name = "Heal", icon = I .. "Spell_Holy_Heal", kind = "spell", school = "holy",
    cost = 40, cd = 0, cast = 2.5, range = 40, ai = "heal",
    desc = "A slow but powerful heal.",
    execute = function(run, c, t)
        run:Heal(c, t, run:Rnd(66, 78) * S(c), 0.71, "Heal")
    end,
}

A.POWER_WORD_SHIELD = {
    name = "Power Word: Shield", icon = I .. "Spell_Holy_PowerWordShield", kind = "spell", school = "holy",
    cost = 35, cd = 2, cast = 0, range = 40, ai = "shield", aura = "POWER_WORD_SHIELD",
    desc = "Shields the target, absorbing damage for 30 sec. Target can't be shielded again for 12 sec.",
    execute = function(run, c, t)
        local amount = 70 * S(c) + run:HealPower(c) * 0.3
        run:ApplyAura(t, { key = "POWER_WORD_SHIELD", source = c, name = "Power Word: Shield",
            icon = A.POWER_WORD_SHIELD.icon, duration = 30, absorb = amount })
        run:ApplyAura(t, { key = "WEAKENED_SOUL", source = c, name = "Weakened Soul",
            icon = I .. "Spell_Holy_AshesToAshes", duration = 12 })
        run:Emit("heal", t, math.floor(amount), false, "shield")
        run:AddHealThreat(c, amount * 0.5)
    end,
}

A.HOLY_LIGHT = {
    name = "Holy Light", icon = I .. "Spell_Holy_HolyBolt", kind = "spell", school = "holy",
    cost = 30, cd = 0, cast = 2.5, range = 40, ai = "heal",
    desc = "Heals a friendly target with holy light.",
    execute = function(run, c, t)
        run:Heal(c, t, run:Rnd(52, 62) * S(c), 0.71, "Holy Light")
    end,
}

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------

ns.Pets = {
    IMP = {
        name = "Imp", icon = I .. "Spell_Shadow_SummonImp", ranged = true, hpMult = 0.35, dmgMult = 0.0,
        abilities = { { name = "Firebolt", icon = I .. "Spell_Fire_FireBolt", type = "nuke", cd = 0, cast = 1.5,
            dmg = 0.45, school = "fire", range = 30 } },
    },
    WOLF = {
        name = "Wolf", icon = I .. "Ability_Hunter_Pet_Wolf", ranged = false, hpMult = 0.6, dmgMult = 0.55,
    },
}
