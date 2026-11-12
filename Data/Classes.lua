-- Classes, specs and stat growth.
local ADDON, ns = ...

ns.ARMOR_RANK = { CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4 }
ns.ARMOR_NAMES = { CLOTH = "Cloth", LEATHER = "Leather", MAIL = "Mail", PLATE = "Plate" }

-- Stats are the values at level 10 (every drafted hero starts there);
-- growth is gained per level after that.
ns.Classes = {
    WARRIOR = {
        name = "Warrior", color = { 0.78, 0.61, 0.43 }, armor = "PLATE", resource = "RAGE",
        hp = { base = 70, perLevel = 14 },
        stats = { str = 26, agi = 20, sta = 24, int = 10, spi = 12 },
        growth = { str = 2.0, agi = 1.2, sta = 1.8, int = 0.3, spi = 0.5 },
        weapons = { DAGGER = true, SWORD = true, MACE = true, AXE = true, SWORD2H = true, AXE2H = true,
            MACE2H = true, STAFF = true, BOW = true, GUN = true, SHIELD = true },
    },
    PALADIN = {
        name = "Paladin", color = { 0.96, 0.55, 0.73 }, armor = "PLATE", resource = "MANA",
        hp = { base = 60, perLevel = 12 }, mana = { base = 60, perLevel = 14 },
        stats = { str = 24, agi = 17, sta = 23, int = 19, spi = 20 },
        growth = { str = 1.7, agi = 0.8, sta = 1.5, int = 1.0, spi = 1.0 },
        weapons = { SWORD = true, MACE = true, AXE = true, SWORD2H = true, AXE2H = true, MACE2H = true,
            SHIELD = true, HELD = true },
    },
    HUNTER = {
        name = "Hunter", color = { 0.67, 0.83, 0.45 }, armor = "MAIL", resource = "MANA",
        hp = { base = 50, perLevel = 12 }, mana = { base = 60, perLevel = 13 },
        stats = { str = 18, agi = 27, sta = 21, int = 17, spi = 19 },
        growth = { str = 0.8, agi = 2.0, sta = 1.4, int = 0.9, spi = 1.0 },
        weapons = { DAGGER = true, SWORD = true, AXE = true, SWORD2H = true, AXE2H = true, STAFF = true,
            BOW = true, GUN = true },
    },
    ROGUE = {
        name = "Rogue", color = { 1.00, 0.96, 0.41 }, armor = "LEATHER", resource = "ENERGY",
        hp = { base = 55, perLevel = 12 },
        stats = { str = 20, agi = 30, sta = 20, int = 12, spi = 14 },
        growth = { str = 1.0, agi = 2.0, sta = 1.2, int = 0.3, spi = 0.6 },
        weapons = { DAGGER = true, SWORD = true, MACE = true, BOW = true, GUN = true },
    },
    PRIEST = {
        name = "Priest", color = { 1.00, 1.00, 1.00 }, armor = "CLOTH", resource = "MANA",
        hp = { base = 40, perLevel = 10 }, mana = { base = 60, perLevel = 16 },
        stats = { str = 13, agi = 15, sta = 16, int = 28, spi = 30 },
        growth = { str = 0.3, agi = 0.4, sta = 0.8, int = 2.0, spi = 2.0 },
        weapons = { DAGGER = true, MACE = true, STAFF = true, WAND = true, HELD = true },
    },
    SHAMAN = {
        name = "Shaman", color = { 0.00, 0.44, 0.87 }, armor = "MAIL", resource = "MANA",
        hp = { base = 55, perLevel = 12 }, mana = { base = 60, perLevel = 14 },
        stats = { str = 21, agi = 17, sta = 22, int = 21, spi = 23 },
        growth = { str = 1.2, agi = 0.8, sta = 1.4, int = 1.3, spi = 1.4 },
        weapons = { MACE = true, AXE = true, STAFF = true, MACE2H = true, AXE2H = true, SHIELD = true, HELD = true },
    },
    MAGE = {
        name = "Mage", color = { 0.25, 0.78, 0.92 }, armor = "CLOTH", resource = "MANA",
        hp = { base = 40, perLevel = 10 }, mana = { base = 60, perLevel = 16 },
        stats = { str = 12, agi = 15, sta = 16, int = 30, spi = 26 },
        growth = { str = 0.3, agi = 0.4, sta = 0.8, int = 2.2, spi = 1.8 },
        weapons = { DAGGER = true, SWORD = true, STAFF = true, WAND = true, HELD = true },
    },
    WARLOCK = {
        name = "Warlock", color = { 0.53, 0.53, 0.93 }, armor = "CLOTH", resource = "MANA",
        hp = { base = 45, perLevel = 10 }, mana = { base = 60, perLevel = 16 },
        stats = { str = 14, agi = 16, sta = 19, int = 26, spi = 26 },
        growth = { str = 0.4, agi = 0.5, sta = 1.2, int = 1.8, spi = 1.8 },
        weapons = { DAGGER = true, SWORD = true, STAFF = true, WAND = true, HELD = true },
    },
    DRUID = {
        name = "Druid", color = { 1.00, 0.49, 0.04 }, armor = "LEATHER", resource = "MANA",
        hp = { base = 50, perLevel = 11 }, mana = { base = 60, perLevel = 15 },
        stats = { str = 18, agi = 18, sta = 19, int = 23, spi = 25 },
        growth = { str = 1.0, agi = 1.0, sta = 1.2, int = 1.4, spi = 1.5 },
        weapons = { DAGGER = true, MACE = true, STAFF = true, MACE2H = true, HELD = true },
    },
}

ns.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Stat weights drive auto-equip and which loot drops for whom.
local W = {
    tank   = { sta = 1.2, str = 0.8, agi = 0.8, armor = 0.06, block = 0.3, int = 0.1, wdps = 2 },
    melee  = { str = 1.0, agi = 0.9, sta = 0.4, wdps = 6 },
    hybrid = { str = 1.0, agi = 0.7, sta = 0.4, int = 0.3, sp = 0.2, wdps = 6 },
    hunter = { agi = 1.0, str = 0.6, sta = 0.4, int = 0.3, rdps = 6, wdps = 1 },
    caster = { int = 1.0, sp = 1.1, spi = 0.5, sta = 0.4, rdps = 1 },
    healer = { int = 1.0, heal = 0.7, spi = 0.8, sta = 0.4, rdps = 0.5 },
}

-- Suffix families (see Data/Items.lua) each archetype likes to see.
local SUFFIXES = {
    tank   = { "BEAR", "MONKEY", "STAMINA", "TIGER", "STRENGTH", "AGILITY" },
    melee  = { "TIGER", "MONKEY", "BEAR", "STRENGTH", "AGILITY" },
    hybrid = { "TIGER", "BEAR", "STRENGTH", "GORILLA" },
    hunter = { "MONKEY", "TIGER", "AGILITY", "EAGLE" },
    caster = { "EAGLE", "OWL", "INTELLECT", "WRATH", "SORCERY" },
    healer = { "OWL", "EAGLE", "SPIRIT", "HEALING", "INTELLECT" },
}

local function Spec(t)
    t.weights = W[t.archetype]
    t.suffixes = SUFFIXES[t.archetype]
    return t
end

-- role: TANK / HEALER / DPS. position: MELEE / RANGED.
-- abilities: { id, level } - only the level 10 abilities exist for now; the
-- level field is there so later ranks/branches (e.g. Rogue specs) can unlock.
ns.Specs = {
    WARRIOR_ARMS = Spec{ class = "WARRIOR", name = "Arms", role = "DPS", position = "MELEE", archetype = "melee",
        abilities = { { id = "HEROIC_STRIKE", level = 10 } },
        mainhand = { "SWORD2H", "AXE2H", "MACE2H" } },
    WARRIOR_FURY = Spec{ class = "WARRIOR", name = "Fury", role = "DPS", position = "MELEE", archetype = "melee",
        abilities = { { id = "BLOODLUST", level = 10 } },
        mainhand = { "AXE2H", "SWORD2H", "MACE2H" } },
    WARRIOR_PROT = Spec{ class = "WARRIOR", name = "Protection", role = "TANK", position = "MELEE", archetype = "tank",
        abilities = { { id = "TAUNT", level = 10 }, { id = "SHIELD_BLOCK", level = 10 } },
        mainhand = { "SWORD", "AXE", "MACE" }, offhand = { "SHIELD" } },

    PALADIN_RET = Spec{ class = "PALADIN", name = "Retribution", role = "DPS", position = "MELEE", archetype = "hybrid",
        abilities = { { id = "SEAL_OF_RIGHTEOUSNESS", level = 10 } },
        mainhand = { "MACE2H", "SWORD2H", "AXE2H" } },
    PALADIN_PROT = Spec{ class = "PALADIN", name = "Protection", role = "TANK", position = "MELEE", archetype = "tank",
        abilities = { { id = "TAUNT", level = 10 }, { id = "DEVOTION_AURA", level = 10 } },
        mainhand = { "MACE", "SWORD" }, offhand = { "SHIELD" } },
    PALADIN_HOLY = Spec{ class = "PALADIN", name = "Holy", role = "HEALER", position = "RANGED", archetype = "healer",
        abilities = { { id = "HOLY_LIGHT", level = 10 } },
        mainhand = { "MACE" }, offhand = { "SHIELD", "HELD" } },

    HUNTER_MM = Spec{ class = "HUNTER", name = "Marksmanship", role = "DPS", position = "RANGED", archetype = "hunter",
        abilities = { { id = "ARCANE_SHOT", level = 10 } },
        mainhand = { "AXE2H", "SWORD2H", "STAFF" }, ranged = { "BOW", "GUN" } },
    HUNTER_SV = Spec{ class = "HUNTER", name = "Survival", role = "DPS", position = "MELEE", archetype = "hunter",
        abilities = { { id = "RAPTOR_STRIKE", level = 10 } },
        mainhand = { "AXE2H", "SWORD2H", "STAFF" }, ranged = { "BOW", "GUN" } },
    HUNTER_BM = Spec{ class = "HUNTER", name = "Beast Mastery", role = "DPS", position = "RANGED", archetype = "hunter",
        abilities = { { id = "KILL_COMMAND", level = 10 } }, pet = "WOLF",
        mainhand = { "AXE2H", "SWORD2H", "STAFF" }, ranged = { "BOW", "GUN" } },

    ROGUE_ASSASSINATION = Spec{ class = "ROGUE", name = "Assassination", role = "DPS", position = "MELEE", archetype = "melee",
        abilities = { { id = "SINISTER_STRIKE", level = 10 } },
        mainhand = { "DAGGER" }, ranged = { "BOW", "GUN" } },
    ROGUE_COMBAT = Spec{ class = "ROGUE", name = "Combat", role = "DPS", position = "MELEE", archetype = "melee",
        abilities = { { id = "SINISTER_STRIKE", level = 10 } },
        mainhand = { "SWORD", "MACE" }, ranged = { "BOW", "GUN" } },
    ROGUE_SUBTLETY = Spec{ class = "ROGUE", name = "Subtlety", role = "DPS", position = "MELEE", archetype = "melee",
        abilities = { { id = "SINISTER_STRIKE", level = 10 } },
        mainhand = { "DAGGER", "SWORD" }, ranged = { "BOW", "GUN" } },

    PRIEST_SHADOW = Spec{ class = "PRIEST", name = "Shadow", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "MIND_BLAST", level = 10 } },
        mainhand = { "STAFF", "MACE" }, ranged = { "WAND" } },
    PRIEST_HOLY = Spec{ class = "PRIEST", name = "Holy", role = "HEALER", position = "RANGED", archetype = "healer",
        abilities = { { id = "HEAL", level = 10 } },
        mainhand = { "STAFF", "MACE" }, ranged = { "WAND" } },
    PRIEST_DISC = Spec{ class = "PRIEST", name = "Discipline", role = "HEALER", position = "RANGED", archetype = "healer",
        abilities = { { id = "POWER_WORD_SHIELD", level = 10 } },
        mainhand = { "STAFF", "MACE" }, ranged = { "WAND" } },

    SHAMAN_ELE = Spec{ class = "SHAMAN", name = "Elemental", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "LIGHTNING_BOLT", level = 10 } },
        mainhand = { "STAFF", "MACE" }, offhand = { "SHIELD", "HELD" } },
    SHAMAN_ENH = Spec{ class = "SHAMAN", name = "Enhancement", role = "DPS", position = "MELEE", archetype = "hybrid",
        abilities = { { id = "ROCKBITER_WEAPON", level = 10 } },
        mainhand = { "AXE2H", "MACE2H", "STAFF" } },
    SHAMAN_RESTO = Spec{ class = "SHAMAN", name = "Restoration", role = "HEALER", position = "RANGED", archetype = "healer",
        abilities = { { id = "HEALING_WAVE", level = 10 } },
        mainhand = { "MACE", "STAFF" }, offhand = { "SHIELD", "HELD" } },

    MAGE_FROST = Spec{ class = "MAGE", name = "Frost", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "FROSTBOLT", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },
    MAGE_FIRE = Spec{ class = "MAGE", name = "Fire", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "FIRE_BOLT", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },
    MAGE_ARCANE = Spec{ class = "MAGE", name = "Arcane", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "ARCANE_MISSILES", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },

    WARLOCK_AFFLICTION = Spec{ class = "WARLOCK", name = "Affliction", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "CORRUPTION", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },
    WARLOCK_DESTRUCTION = Spec{ class = "WARLOCK", name = "Destruction", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "SHADOW_BOLT", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },
    WARLOCK_DEMONOLOGY = Spec{ class = "WARLOCK", name = "Demonology", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "SUMMON_IMP", level = 10 } },
        mainhand = { "STAFF", "DAGGER" }, ranged = { "WAND" } },

    DRUID_BALANCE = Spec{ class = "DRUID", name = "Balance", role = "DPS", position = "RANGED", archetype = "caster",
        abilities = { { id = "MOONFIRE", level = 10 } },
        mainhand = { "STAFF", "MACE" }, offhand = { "HELD" } },
    DRUID_FERAL = Spec{ class = "DRUID", name = "Feral", role = "DPS", position = "MELEE", archetype = "melee",
        resource = "ENERGY", abilities = { { id = "RAKE", level = 10 } },
        mainhand = { "STAFF", "MACE2H" } },
    DRUID_GUARDIAN = Spec{ class = "DRUID", name = "Guardian", role = "TANK", position = "MELEE", archetype = "tank",
        resource = "RAGE", abilities = { { id = "TAUNT", level = 10 }, { id = "THORNS", level = 10 } },
        mainhand = { "STAFF", "MACE2H" } },
    DRUID_RESTO = Spec{ class = "DRUID", name = "Restoration", role = "HEALER", position = "RANGED", archetype = "healer",
        abilities = { { id = "REJUVENATION", level = 10 } },
        mainhand = { "STAFF", "MACE" }, offhand = { "HELD" } },
}

-- Draft pools.
ns.DRAFT = {
    TANK = { "WARRIOR_PROT", "PALADIN_PROT", "DRUID_GUARDIAN" },
    HEALER = { "SHAMAN_RESTO", "DRUID_RESTO", "PRIEST_HOLY", "PRIEST_DISC", "PALADIN_HOLY" },
    -- DPS slots offer two different classes, each with a random DPS spec already rolled.
    DPS_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" },
}

function ns.DPSSpecsFor(classToken)
    local out = {}
    for key, spec in pairs(ns.Specs) do
        if spec.class == classToken and spec.role == "DPS" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

function ns.SpecLabel(specKey)
    local spec = ns.Specs[specKey]
    return spec.name .. " " .. ns.Classes[spec.class].name
end

local NAMES = {
    "Aldric", "Brenna", "Corvin", "Dagny", "Eldra", "Fennick", "Garrow", "Hilde", "Isolde", "Jorund",
    "Kesha", "Lorcan", "Maelis", "Norvik", "Orla", "Pell", "Quilla", "Rurik", "Sable", "Torvald",
    "Ulfrik", "Vessa", "Wynn", "Xandra", "Yorick", "Zephyra", "Bram", "Cinder", "Dusk",
    "Ember", "Flint", "Grisha", "Hollis", "Ivo", "Juno", "Kael", "Lyra", "Mott", "Nessa",
}

function ns.RandomName(used)
    local pool = {}
    for _, n in ipairs(NAMES) do
        if not (used and used[n]) then pool[#pool + 1] = n end
    end
    if #pool == 0 then pool = NAMES end
    return pool[math.random(#pool)]
end
