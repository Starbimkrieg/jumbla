-- Item generation. Items are plain tables stored in SavedVariables.
local ADDON, ns = ...

local Items = {}
ns.Items = Items

ns.SLOTS = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED" }
ns.SLOT_NAMES = {
    HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs", FEET = "Feet",
    MAINHAND = "Main Hand", OFFHAND = "Off Hand", RANGED = "Ranged",
}
ns.STAT_NAMES = {
    str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit",
}

local ARMOR_SLOTS = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET" }
local SLOT_WEIGHT = { HEAD = 0.8, SHOULDER = 0.75, CHEST = 1.0, HANDS = 0.6, LEGS = 0.9, FEET = 0.65,
    MAINHAND = 1.0, OFFHAND = 0.6, RANGED = 0.5 }
-- Each armor type is a clear tier above the last.
local ARMOR_MULT = { CLOTH = 1.0, LEATHER = 2.0, MAIL = 4.0, PLATE = 7.0 }

local BASE_NAMES = {
    CLOTH   = { HEAD = "Hood", SHOULDER = "Mantle", CHEST = "Robe", HANDS = "Gloves", LEGS = "Pants", FEET = "Sandals" },
    LEATHER = { HEAD = "Cap", SHOULDER = "Shoulderpads", CHEST = "Tunic", HANDS = "Gloves", LEGS = "Leggings", FEET = "Boots" },
    MAIL    = { HEAD = "Coif", SHOULDER = "Pauldrons", CHEST = "Hauberk", HANDS = "Gauntlets", LEGS = "Legguards", FEET = "Sabatons" },
    PLATE   = { HEAD = "Helm", SHOULDER = "Spaulders", CHEST = "Breastplate", HANDS = "Gauntlets", LEGS = "Legplates", FEET = "Greaves" },
}
local ADJECTIVES = {
    { max = 9,  words = { "Worn", "Frayed", "Rough" } },
    { max = 14, words = { "Sturdy", "Stitched", "Ragged" } },
    { max = 19, words = { "Reinforced", "Hardened", "Rugged" } },
    { max = 24, words = { "Ornate", "Polished", "Heavy" } },
    { max = 99, words = { "Superior", "Gleaming", "Fine" } },
}

local ARMOR_ICONS = {
    HEAD = "INV_Helmet_01", SHOULDER = "INV_Shoulder_01", HANDS = "INV_Gauntlets_01", LEGS = "INV_Pants_01",
    FEET = "INV_Boots_01",
    CHEST = { CLOTH = "INV_Chest_Cloth_01", LEATHER = "INV_Chest_Leather_01", MAIL = "INV_Chest_Chain",
        PLATE = "INV_Chest_Plate01" },
}

-- hand: 1H / 2H / RANGED / OFFHAND
ns.WEAPON_TYPES = {
    DAGGER  = { name = "Dagger", slot = "MAINHAND", hand = "1H", speed = { 1.6, 1.9 }, icon = "INV_Weapon_ShortBlade_01" },
    SWORD   = { name = "Sword", slot = "MAINHAND", hand = "1H", speed = { 2.3, 2.7 }, icon = "INV_Sword_04" },
    MACE    = { name = "Mace", slot = "MAINHAND", hand = "1H", speed = { 2.4, 2.8 }, icon = "INV_Mace_01" },
    AXE     = { name = "Axe", slot = "MAINHAND", hand = "1H", speed = { 2.4, 2.8 }, icon = "INV_Axe_01" },
    SWORD2H = { name = "Greatsword", slot = "MAINHAND", hand = "2H", speed = { 3.2, 3.6 }, icon = "INV_Sword_06" },
    AXE2H   = { name = "Greataxe", slot = "MAINHAND", hand = "2H", speed = { 3.2, 3.6 }, icon = "INV_Axe_09" },
    MACE2H  = { name = "Maul", slot = "MAINHAND", hand = "2H", speed = { 3.3, 3.7 }, icon = "INV_Hammer_05" },
    STAFF   = { name = "Staff", slot = "MAINHAND", hand = "2H", speed = { 2.9, 3.2 }, icon = "INV_Staff_08" },
    BOW     = { name = "Bow", slot = "RANGED", hand = "RANGED", speed = { 2.5, 3.0 }, icon = "INV_Weapon_Bow_02" },
    GUN     = { name = "Rifle", slot = "RANGED", hand = "RANGED", speed = { 2.6, 3.0 }, icon = "INV_Weapon_Rifle_01" },
    WAND    = { name = "Wand", slot = "RANGED", hand = "RANGED", speed = { 1.5, 1.9 }, icon = "INV_Wand_01", magic = true },
    SHIELD  = { name = "Shield", slot = "OFFHAND", hand = "OFFHAND", icon = "INV_Shield_04" },
    HELD    = { name = "Orb", slot = "OFFHAND", hand = "OFFHAND", icon = "INV_Misc_Orb_01" },
}

-- Classic-style "of the X" suffixes. sp = spell damage/healing, heal = healing only.
ns.SUFFIXES = {
    BEAR      = { name = "of the Bear", stats = { str = 1, sta = 1 } },
    MONKEY    = { name = "of the Monkey", stats = { agi = 1, sta = 1 } },
    TIGER     = { name = "of the Tiger", stats = { str = 1, agi = 1 } },
    EAGLE     = { name = "of the Eagle", stats = { int = 1, sta = 1 } },
    OWL       = { name = "of the Owl", stats = { int = 1, spi = 1 } },
    WHALE     = { name = "of the Whale", stats = { sta = 1, spi = 1 } },
    GORILLA   = { name = "of the Gorilla", stats = { str = 1, int = 1 } },
    STRENGTH  = { name = "of Strength", stats = { str = 1 } },
    AGILITY   = { name = "of Agility", stats = { agi = 1 } },
    STAMINA   = { name = "of Stamina", stats = { sta = 1 } },
    INTELLECT = { name = "of Intellect", stats = { int = 1 } },
    SPIRIT    = { name = "of Spirit", stats = { spi = 1 } },
    WRATH     = { name = "of Wrath", stats = { sp = 1 } },
    SORCERY   = { name = "of Sorcery", stats = { int = 1, sp = 1 } },
    HEALING   = { name = "of Healing", stats = { heal = 1 } },
    DEFENSE   = { name = "of Defense", stats = { sta = 1, def = 1 } },
}
-- How much item budget one point of a stat costs.
local STAT_COST = { str = 1, agi = 1, sta = 1, int = 1, spi = 1, sp = 1.4, heal = 0.75, def = 1 }

ns.QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62, "ff9d9d9d" },
    [1] = { 1.00, 1.00, 1.00, "ffffffff" },
    [2] = { 0.12, 1.00, 0.00, "ff1eff00" },
    [3] = { 0.00, 0.44, 0.87, "ff0070dd" },
    [4] = { 0.64, 0.21, 0.93, "ffa335ee" },
}

local function pick(t) return t[math.random(#t)] end
local function round(x) return math.floor(x + 0.5) end
local function rnd(a, b) return a + (b - a) * math.random() end

local function Adjective(ilvl)
    for _, band in ipairs(ADJECTIVES) do
        if ilvl <= band.max then return pick(band.words) end
    end
end

local function Budget(ilvl, slot, quality)
    if quality <= 1 then return 0 end
    local mult = quality == 2 and 0.45 or 0.62
    return math.max(2, ilvl * SLOT_WEIGHT[slot] * mult)
end

local function ApplySuffix(item, suffixKey, budget)
    local suffix = ns.SUFFIXES[suffixKey]
    if not suffix or budget <= 0 then return end
    local n = 0
    for _ in pairs(suffix.stats) do n = n + 1 end
    item.stats = item.stats or {}
    for stat in pairs(suffix.stats) do
        local v = round(budget / n / STAT_COST[stat])
        if v > 0 then item.stats[stat] = (item.stats[stat] or 0) + v end
    end
    item.suffix = suffix.name
end

local function WeaponDPS(ilvl, hand, quality, magic)
    local dps = 1.2 + ilvl * 0.38
    if hand == "2H" then dps = dps * 1.35 end
    if magic then dps = dps * 1.25 end
    local q = ({ [0] = 0.8, [1] = 0.9, [2] = 1.0, [3] = 1.1, [4] = 1.2 })[quality] or 1
    return dps * q
end

--[[ opts:
    ilvl, quality, slot, armorType, wtype, suffix, name (overrides generated name)
]]
function Items.Generate(opts)
    local ilvl = opts.ilvl or 10
    local quality = opts.quality or 2
    local item = {
        id = ns.NewId(), ilvl = ilvl, quality = quality, reqLevel = math.max(1, ilvl - 2), stats = {},
    }

    if opts.wtype then
        local wt = ns.WEAPON_TYPES[opts.wtype]
        item.slot = wt.slot
        item.wtype = opts.wtype
        item.hand = wt.hand
        item.icon = wt.icon
        if opts.wtype == "SHIELD" then
            item.armor = round(ilvl * 12)
            item.block = round(3 + ilvl * 0.6)
        elseif opts.wtype == "HELD" then
            item.stats.int = round(1 + ilvl * 0.15)
        else
            local speed = rnd(wt.speed[1], wt.speed[2])
            speed = math.floor(speed * 10 + 0.5) / 10
            local avg = WeaponDPS(ilvl, wt.hand, quality, wt.magic) * speed
            item.speed = speed
            item.min = math.max(1, round(avg * 0.75))
            item.max = math.max(item.min + 1, round(avg * 1.25))
            if wt.magic then item.school = pick({ "arcane", "fire", "frost", "shadow" }) end
        end
        item.name = opts.name or (Adjective(ilvl) .. " " .. wt.name)
    else
        local slot = opts.slot or pick(ARMOR_SLOTS)
        local at = opts.armorType or pick({ "CLOTH", "LEATHER", "MAIL", "PLATE" })
        item.slot = slot
        item.armorType = at
        local qMult = quality >= 3 and 1.15 or (quality == 2 and 1.0 or 0.9)
        item.armor = round(ilvl * 1.5 * ARMOR_MULT[at] * SLOT_WEIGHT[slot] * qMult)
        local icon = ARMOR_ICONS[slot]
        item.icon = type(icon) == "table" and icon[at] or icon
        item.name = opts.name or (Adjective(ilvl) .. " " .. BASE_NAMES[at][slot])
    end

    if opts.stats then
        -- Hand-authored items list relative stat weights; scale them to budget.
        local budget = Budget(ilvl, item.slot, math.max(quality, 2))
        local total = 0
        for stat, w in pairs(opts.stats) do total = total + w * STAT_COST[stat] end
        for stat, w in pairs(opts.stats) do
            item.stats[stat] = (item.stats[stat] or 0) + math.max(1, round(budget * w / total))
        end
    elseif quality >= 2 then
        ApplySuffix(item, opts.suffix or pick({ "BEAR", "MONKEY", "TIGER", "EAGLE", "OWL", "WHALE" }),
            Budget(ilvl, item.slot, quality))
        if item.suffix and not opts.name then item.name = item.name .. " " .. item.suffix end
    end
    return item
end

-- Starter kit: white gear of the class armor type + a spec weapon.
function Items.StarterGear(specKey)
    local spec = ns.Specs[specKey]
    local cls = ns.Classes[spec.class]
    local gear = {}
    for _, slot in ipairs({ "CHEST", "LEGS", "FEET" }) do
        gear[slot] = Items.Generate({ ilvl = 8, quality = 1, slot = slot, armorType = cls.armor })
    end
    gear.MAINHAND = Items.Generate({ ilvl = 8, quality = 1, wtype = spec.mainhand[1] })
    if spec.offhand then
        gear.OFFHAND = Items.Generate({ ilvl = 8, quality = 1, wtype = spec.offhand[1] })
    end
    if spec.ranged then
        gear.RANGED = Items.Generate({ ilvl = 8, quality = 1, wtype = spec.ranged[1] })
    end
    for _, item in pairs(gear) do item.reqLevel = 1 end
    return gear
end

function Items.QualityHex(item)
    return (ns.QUALITY_COLORS[item.quality] or ns.QUALITY_COLORS[1])[4]
end

function Items.ColoredName(item)
    return "|c" .. Items.QualityHex(item) .. item.name .. "|r"
end

function Items.DPS(item)
    if item and item.min then return (item.min + item.max) / 2 / item.speed end
    return 0
end

-- Vendor price in copper.
function Items.SellValue(item)
    return math.floor(item.ilvl * ((item.quality or 1) + 1) ^ 2 * 2 + 1)
end

function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, sv, c) end
    if sv > 0 then return string.format("%ds %dc", sv, c) end
    return c .. "c"
end

-- Melee/ranged weapon types that need a trained weapon skill (melee classes).
ns.WEAPON_SKILL_NAMES = {
    DAGGER = "Daggers", SWORD = "One-Handed Swords", MACE = "One-Handed Maces", AXE = "One-Handed Axes",
    SWORD2H = "Two-Handed Swords", AXE2H = "Two-Handed Axes", MACE2H = "Two-Handed Maces", STAFF = "Staves",
    BOW = "Bows", GUN = "Guns",
}
ns.WEAPON_SKILL_ORDER = { "DAGGER", "SWORD", "MACE", "AXE", "SWORD2H", "AXE2H", "MACE2H", "STAFF", "BOW", "GUN" }

-- Score an item for a spec using its stat weights. slot = where it would go
-- (a weapon in the off hand only counts half its damage).
function Items.Score(item, specKey, slot)
    if not item then return 0 end
    local w = ns.Specs[specKey].weights
    local s = 0
    for stat, v in pairs(item.stats or {}) do s = s + (w[stat] or 0) * v end
    s = s + (item.armor or 0) * (w.armor or 0.01)
    s = s + (item.block or 0) * (w.block or 0)
    if item.min then
        local key = item.slot == "RANGED" and "rdps" or "wdps"
        local mult = (slot == "OFFHAND") and 0.5 or 1
        s = s + Items.DPS(item) * (w[key] or 0) * mult
    end
    return s
end

-- Tooltip lines: { text, r, g, b } (r,g,b optional) used by the UI.
function Items.TooltipLines(item)
    local lines = {}
    local c = ns.QUALITY_COLORS[item.quality] or ns.QUALITY_COLORS[1]
    lines[#lines + 1] = { item.name, c[1], c[2], c[3] }
    local typeText = item.armorType and ns.ARMOR_NAMES[item.armorType]
        or (item.wtype and ns.WEAPON_TYPES[item.wtype].name) or ""
    local hand = item.hand == "2H" and "Two-Hand" or (item.hand == "1H" and "One-Hand") or ns.SLOT_NAMES[item.slot]
    lines[#lines + 1] = { hand .. "    " .. typeText }
    if item.min then
        lines[#lines + 1] = { string.format("%d - %d %sDamage    Speed %.2f", item.min, item.max,
            item.school and (item.school:gsub("^%l", string.upper) .. " ") or "", item.speed) }
        lines[#lines + 1] = { string.format("(%.1f damage per second)", Items.DPS(item)) }
    end
    if item.armor and item.armor > 0 then lines[#lines + 1] = { item.armor .. " Armor" } end
    if item.block then lines[#lines + 1] = { item.block .. " Block" } end
    for _, stat in ipairs({ "str", "agi", "sta", "int", "spi" }) do
        local v = item.stats and item.stats[stat]
        if v and v > 0 then lines[#lines + 1] = { "+" .. v .. " " .. ns.STAT_NAMES[stat] } end
    end
    if item.stats and item.stats.sp then
        lines[#lines + 1] = { "Equip: Increases damage and healing done by spells by up to " .. item.stats.sp .. ".", 0.12, 1, 0 }
    end
    if item.stats and item.stats.def then
        lines[#lines + 1] = { "Equip: Increases defense rating by " .. item.stats.def .. ".", 0.12, 1, 0 }
    end
    if item.stats and item.stats.heal then
        lines[#lines + 1] = { "Equip: Increases healing done by spells by up to " .. item.stats.heal .. ".", 0.12, 1, 0 }
    end
    if item.wtype and ns.WEAPON_SKILL_NAMES[item.wtype] then
        lines[#lines + 1] = { "Weapon skill: " .. ns.WEAPON_SKILL_NAMES[item.wtype], 0.7, 0.7, 0.7 }
    end
    lines[#lines + 1] = { "Requires Level " .. item.reqLevel }
    lines[#lines + 1] = { "Item Level " .. item.ilvl, 1, 0.82, 0 }
    lines[#lines + 1] = { "Sell price: " .. ns.FormatMoney(Items.SellValue(item)), 1, 1, 1 }
    return lines
end
