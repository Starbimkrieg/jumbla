-- Dungeons: level requirement, mob level range and waves.
-- A wave is either a list of mob keys or { boss = key, adds = { ... } }.
local ADDON, ns = ...

ns.Dungeons = {
    RFC = {
        name = "Ragefire Chasm", short = "RFC", reqLevel = 10, levels = { 10, 12 }, bossLevel = 13,
        color = { 0.35, 0.08, 0.04 }, bonusXP = 250,
        waves = {
            { "RFC_TROGG", "RFC_TROGG", "RFC_SHAMAN" },
            { "RFC_CULTIST", "RFC_CULTIST", "RFC_TROGG" },
            { boss = "RFC_OGGLEFLINT", adds = { "RFC_TROGG" } },
            { "RFC_EARTHBORER", "RFC_EARTHBORER", "RFC_ELEMENTAL" },
            { boss = "RFC_TARAGAMAN" },
            { "RFC_WARLOCK", "RFC_CULTIST", "RFC_CULTIST" },
            { boss = "RFC_JERGOSH", adds = { "RFC_CULTIST" } },
            { boss = "RFC_BAZZALAN", adds = { "RFC_CULTIST" } },
        },
        loot = {
            RFC_TARAGAMAN = {
                { name = "Cursed Felblade", wtype = "SWORD", stats = { str = 1, agi = 1 } },
                { name = "Hungerer's Hide Vest", slot = "CHEST", armorType = "LEATHER", stats = { agi = 2, sta = 1 } },
            },
            RFC_JERGOSH = {
                { name = "Invoker's Cord Wrap", slot = "HANDS", armorType = "CLOTH", stats = { int = 2, sp = 1 } },
                { name = "Chasm Ember Rod", wtype = "WAND" },
            },
            RFC_BAZZALAN = {
                { name = "Searing Blade Shank", wtype = "DAGGER", stats = { agi = 2, sta = 1 } },
                { name = "Molten Bulwark", wtype = "SHIELD", stats = { sta = 2, str = 1 } },
            },
        },
    },

    DM = {
        name = "The Deadmines", short = "DM", reqLevel = 15, levels = { 15, 17 }, bossLevel = 18,
        color = { 0.22, 0.16, 0.10 }, bonusXP = 500,
        waves = {
            { "DM_MINER", "DM_MINER", "DM_OVERSEER" },
            { boss = "DM_RHAHKZOR" },
            { "DM_EVOKER", "DM_MINER", "DM_OVERSEER" },
            { boss = "DM_SHREDDER" },
            { "DM_WOODCARVER", "DM_ENGINEER", "DM_WOODCARVER" },
            { boss = "DM_GILNID", adds = { "DM_ENGINEER" } },
            { "DM_PIRATE", "DM_PIRATE", "DM_SQUALLSHAPER" },
            { boss = "DM_SMITE" },
            { boss = "DM_GREENSKIN", adds = { "DM_PIRATE" } },
            { boss = "DM_COOKIE" },
            { boss = "DM_VANCLEEF" },
        },
        loot = {
            DM_SHREDDER = { { name = "Buzzer Blade", wtype = "DAGGER", stats = { agi = 1, sta = 1 } } },
            DM_SMITE = { { name = "Smite's Mighty Hammer", wtype = "MACE2H", stats = { str = 2, agi = 1 } } },
            DM_COOKIE = {
                { name = "Cookie's Tenderizer", wtype = "MACE", stats = { str = 1, sta = 1 } },
                { name = "Cookie's Stirring Rod", wtype = "WAND" },
            },
            DM_VANCLEEF = {
                { name = "Cruel Barb", wtype = "SWORD", stats = { str = 2, sta = 1 } },
                { name = "Blackened Defias Armor", slot = "CHEST", armorType = "LEATHER", stats = { agi = 2, sta = 1 } },
            },
        },
    },

    WC = {
        name = "Wailing Caverns", short = "WC", reqLevel = 20, levels = { 21, 23 }, bossLevel = 24,
        color = { 0.08, 0.20, 0.12 }, bonusXP = 800,
        waves = {
            { "WC_FANG", "WC_RAPTOR", "WC_RAPTOR" },
            { boss = "WC_ANACONDRA", adds = { "WC_FANG" } },
            { "WC_VIPER", "WC_VIPER", "WC_CROC" },
            { boss = "WC_COBRAHN" },
            { "WC_ECTOPLASM", "WC_ECTOPLASM", "WC_LASHER" },
            { boss = "WC_KRESH" },
            { boss = "WC_PYTHAS", adds = { "WC_FANG" } },
            { boss = "WC_SKUM" },
            { boss = "WC_SERPENTIS", adds = { "WC_FANG" } },
            { "WC_LASHER", "WC_LASHER", "WC_RAPTOR" },
            { boss = "WC_VERDAN" },
            { boss = "WC_MUTANUS" },
        },
        loot = {
            WC_ANACONDRA = { { name = "Belt of the Fang", slot = "HANDS", armorType = "LEATHER", stats = { agi = 1, sta = 1 } } },
            WC_COBRAHN = { { name = "Leggings of the Fang", slot = "LEGS", armorType = "LEATHER", stats = { agi = 2, sta = 1 } } },
            WC_PYTHAS = { { name = "Armor of the Fang", slot = "CHEST", armorType = "LEATHER", stats = { agi = 2, sta = 2 } } },
            WC_SERPENTIS = {
                { name = "Venomstrike", wtype = "BOW", stats = { agi = 1 } },
                { name = "Serpent's Shoulders", slot = "SHOULDER", armorType = "LEATHER", stats = { agi = 1, int = 1 } },
            },
            WC_VERDAN = { { name = "Living Root", wtype = "STAFF", stats = { int = 2, spi = 1, heal = 1 } } },
            WC_MUTANUS = { { name = "Mutant Scale Breastplate", slot = "CHEST", armorType = "MAIL", stats = { str = 1, agi = 1, sta = 1 } } },
        },
    },
}

ns.DUNGEON_ORDER = { "RFC", "DM", "WC" }
