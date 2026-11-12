-- Heroes: creation, derived stats, experience and equipment. Also the draft.
local ADDON, ns = ...

local Hero = {}
ns.Hero = Hero

ns.PRIMARY = { "str", "agi", "sta", "int", "spi" }
ns.MAX_LEVEL = 30

local floor = math.floor

function Hero.XPToLevel(level)
    return floor(100 + level * level * 5)
end

function Hero.Create(specKey, usedNames)
    local spec = ns.Specs[specKey]
    local h = {
        id = ns.NewId(), spec = specKey, class = spec.class, level = 10, xp = 0,
        name = ns.RandomName(usedNames), gear = ns.Items.StarterGear(specKey),
    }
    return h
end

function Hero.BaseStats(h)
    local cls = ns.Classes[h.class]
    local out = {}
    for _, s in ipairs(ns.PRIMARY) do
        out[s] = floor(cls.stats[s] + cls.growth[s] * (h.level - 10))
    end
    return out
end

function Hero.Resource(h)
    return ns.Specs[h.spec].resource or ns.Classes[h.class].resource
end

local FISTS = { min = 1, max = 3, speed = 2.0 }

-- Derived stats. Rules:
--   Agility   -> melee crit, armor, dodge
--   Strength  -> melee attack power, block value
--   Intellect -> max mana, spell crit
--   Stamina   -> health
--   Spirit    -> mana and health regeneration
function Hero.Compute(h)
    local cls = ns.Classes[h.class]
    local d = Hero.BaseStats(h)
    d.gearArmor, d.sp, d.heal, d.shieldBlock = 0, 0, 0, 0
    for _, item in pairs(h.gear) do
        for stat, v in pairs(item.stats or {}) do d[stat] = (d[stat] or 0) + v end
        d.gearArmor = d.gearArmor + (item.armor or 0)
        if item.block then d.shieldBlock = d.shieldBlock + item.block end
    end
    local res = Hero.Resource(h)
    d.resource = res
    d.maxHP = floor(cls.hp.base + cls.hp.perLevel * h.level + d.sta * 10)
    if res == "MANA" then
        d.maxPower = floor(cls.mana.base + cls.mana.perLevel * h.level + d.int * 15)
    else
        d.maxPower = 100
    end
    d.armor = d.gearArmor + d.agi * 2
    d.ap = d.str * 2
    d.meleeCrit = 5 + d.agi / 20
    d.dodge = 3 + d.agi / 25
    d.spellCrit = 2 + d.int / 25
    d.hasShield = h.gear.OFFHAND and h.gear.OFFHAND.wtype == "SHIELD" or false
    d.blockChance = d.hasShield and 5 or 0
    d.blockValue = d.hasShield and floor(d.shieldBlock + d.str / 2) or 0
    d.manaRegen = d.spi / 5      -- per second, halved in combat
    d.hpRegen = d.spi / 15       -- per second, boosted out of combat
    d.spellPower = d.sp
    d.healPower = d.sp + d.heal
    local mh = h.gear.MAINHAND
    d.weapon = mh and mh.min and { min = mh.min, max = mh.max, speed = mh.speed } or FISTS
    local rg = h.gear.RANGED
    d.rangedWeapon = rg and rg.min and { min = rg.min, max = rg.max, speed = rg.speed, school = rg.school } or nil
    return d
end

-- Returns number of levels gained.
function Hero.AddXP(h, amount)
    if h.level >= ns.MAX_LEVEL then return 0 end
    h.xp = h.xp + amount
    local gained = 0
    while h.level < ns.MAX_LEVEL and h.xp >= Hero.XPToLevel(h.level) do
        h.xp = h.xp - Hero.XPToLevel(h.level)
        h.level = h.level + 1
        gained = gained + 1
    end
    if h.level >= ns.MAX_LEVEL then h.xp = 0 end
    return gained
end

function Hero.Abilities(h)
    local out = {}
    for _, a in ipairs(ns.Specs[h.spec].abilities) do
        if h.level >= a.level then out[#out + 1] = a.id end
    end
    return out
end

---------------------------------------------------------------------------
-- Equipment
---------------------------------------------------------------------------

function Hero.CanEquip(h, item)
    local cls = ns.Classes[h.class]
    if h.level < item.reqLevel then return false, "Requires level " .. item.reqLevel end
    if item.armorType and ns.ARMOR_RANK[item.armorType] > ns.ARMOR_RANK[cls.armor] then
        return false, cls.name .. "s can't wear " .. ns.ARMOR_NAMES[item.armorType]
    end
    if item.wtype and not cls.weapons[item.wtype] then
        return false, cls.name .. "s can't use " .. ns.WEAPON_TYPES[item.wtype].name .. "s"
    end
    return true
end

-- Equips the item and returns a list of items that were removed.
function Hero.Equip(h, item)
    local removed = {}
    local slot = item.slot
    if h.gear[slot] then removed[#removed + 1] = h.gear[slot] end
    if slot == "MAINHAND" and item.hand == "2H" and h.gear.OFFHAND then
        removed[#removed + 1] = h.gear.OFFHAND
        h.gear.OFFHAND = nil
    elseif slot == "OFFHAND" and h.gear.MAINHAND and h.gear.MAINHAND.hand == "2H" then
        removed[#removed + 1] = h.gear.MAINHAND
        h.gear.MAINHAND = nil
    end
    h.gear[slot] = item
    return removed
end

function Hero.Unequip(h, slot)
    local item = h.gear[slot]
    h.gear[slot] = nil
    return item
end

-- Score of what an item would replace (a 2H also replaces the off hand).
local function ReplacedScore(h, item)
    local s = ns.Items.Score(h.gear[item.slot], h.spec)
    if item.slot == "MAINHAND" and item.hand == "2H" then
        s = s + ns.Items.Score(h.gear.OFFHAND, h.spec)
    elseif item.slot == "OFFHAND" and h.gear.MAINHAND and h.gear.MAINHAND.hand == "2H" then
        return math.huge -- never auto-break a two-hander for an off hand
    end
    return s
end

function Hero.UpgradeValue(h, item)
    if not Hero.CanEquip(h, item) then return nil end
    local spec = ns.Specs[h.spec]
    -- Respect the spec's weapon style (no shields on a Fury warrior, etc).
    if item.slot == "MAINHAND" then
        local ok = false
        for _, w in ipairs(spec.mainhand) do if w == item.wtype then ok = true end end
        if not ok then return nil end
    elseif item.slot == "OFFHAND" then
        if not spec.offhand then return nil end
        local ok = false
        for _, w in ipairs(spec.offhand) do if w == item.wtype then ok = true end end
        if not ok then return nil end
    elseif item.slot == "RANGED" and not spec.ranged then
        return nil
    end
    return ns.Items.Score(item, h.spec) - ReplacedScore(h, item)
end

---------------------------------------------------------------------------
-- Draft: Tank, Healer, then three DPS. Each slot offers two options; one
-- reroll is available for the whole draft.
---------------------------------------------------------------------------

local Draft = {}
ns.Draft = Draft
Draft.SLOTS = { "TANK", "HEALER", "DPS", "DPS", "DPS" }
Draft.REROLLS = 1

local function TwoDistinct(pool)
    local copy = {}
    for i, v in ipairs(pool) do copy[i] = v end
    ns.Shuffle(copy)
    return { copy[1], copy[2] }
end

function Draft.Roll(d)
    local role = Draft.SLOTS[d.slot]
    if role == "DPS" then
        local classes = TwoDistinct(ns.DRAFT.DPS_CLASSES)
        d.options = {}
        for i, cls in ipairs(classes) do
            local specs = ns.DPSSpecsFor(cls)
            d.options[i] = specs[math.random(#specs)]
        end
    else
        d.options = TwoDistinct(ns.DRAFT[role])
    end
end

function Draft.New()
    local d = { slot = 1, picks = {}, rerolls = Draft.REROLLS }
    Draft.Roll(d)
    return d
end

function Draft.Pick(d, index)
    d.picks[#d.picks + 1] = d.options[index]
    d.slot = d.slot + 1
    if d.slot <= #Draft.SLOTS then Draft.Roll(d) else d.options = nil end
end

function Draft.Reroll(d)
    if d.rerolls <= 0 or not d.options then return false end
    d.rerolls = d.rerolls - 1
    Draft.Roll(d)
    return true
end

function Draft.IsDone(d) return d.slot > #Draft.SLOTS end

function Draft.Finish(d)
    local heroes, used = {}, {}
    for _, specKey in ipairs(d.picks) do
        local h = Hero.Create(specKey, used)
        used[h.name] = true
        heroes[#heroes + 1] = h
    end
    return heroes
end
