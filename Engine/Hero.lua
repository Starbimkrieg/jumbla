-- Heroes: creation, derived stats, experience, weapon skills and equipment.
-- Also the draft.
local ADDON, ns = ...

local Hero = {}
ns.Hero = Hero

ns.PRIMARY = { "str", "agi", "sta", "int", "spi" }
ns.MAX_LEVEL = 30

local floor, max = math.floor, math.max

function Hero.XPToLevel(level)
    return floor(100 + level * level * 5)
end

function Hero.Create(specKey, usedNames)
    local spec = ns.Specs[specKey]
    local h = {
        id = ns.NewId(), spec = specKey, class = spec.class, level = 10, xp = 0,
        name = ns.RandomName(usedNames), gear = ns.Items.StarterGear(specKey),
    }
    Hero.EnsureSkills(h)
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

-- Armor type the hero can wear right now (plate/mail unlock at 40).
function Hero.ArmorType(h)
    local cls = ns.Classes[h.class]
    if cls.armorAt40 and h.level >= 40 then return cls.armorAt40 end
    return cls.armor
end

function Hero.CanDualWield(h)
    local lvl = ns.Classes[h.class].dualWield
    return lvl ~= nil and h.level >= lvl
end

---------------------------------------------------------------------------
-- Weapon skills (melee classes only). Max skill is 5 x level. The spec's
-- preferred weapon starts maxed; other types must be trained (bought) and
-- start at 1, rising as the hero swings that weapon in combat.
---------------------------------------------------------------------------

function Hero.UsesWeaponSkills(h)
    return ns.Classes[h.class].weaponSkills == true
end

function Hero.MaxSkill(h) return h.level * 5 end

function Hero.EnsureSkills(h)
    if h.weaponSkills or not Hero.UsesWeaponSkills(h) then return end
    local spec = ns.Specs[h.spec]
    local m = Hero.MaxSkill(h)
    h.weaponSkills = { [spec.mainhand[1]] = m }
    if spec.ranged and ns.WEAPON_SKILL_NAMES[spec.ranged[1]] then h.weaponSkills[spec.ranged[1]] = m end
    for _, item in pairs(h.gear) do
        if item.wtype and ns.WEAPON_SKILL_NAMES[item.wtype] then h.weaponSkills[item.wtype] = m end
    end
end

-- Returns current skill, or nil if the hero hasn't trained this type.
function Hero.Skill(h, wtype)
    if not Hero.UsesWeaponSkills(h) or not ns.WEAPON_SKILL_NAMES[wtype] then return Hero.MaxSkill(h) end
    Hero.EnsureSkills(h)
    local v = h.weaponSkills[wtype]
    return v and math.min(v, Hero.MaxSkill(h)) or nil
end

function Hero.SkillDeficit(h, wtype)
    if not wtype then return 0 end
    local v = Hero.Skill(h, wtype)
    return v and max(0, Hero.MaxSkill(h) - v) or 0
end

-- Weapon types this hero could train (class allows it, not yet known).
function Hero.Trainable(h)
    local out = {}
    if not Hero.UsesWeaponSkills(h) then return out end
    Hero.EnsureSkills(h)
    local cls = ns.Classes[h.class]
    for _, wtype in ipairs(ns.WEAPON_SKILL_ORDER) do
        if cls.weapons[wtype] and not h.weaponSkills[wtype] then out[#out + 1] = wtype end
    end
    return out
end

function Hero.TrainCost(h) return 5000 + 500 * h.level end   -- copper

function Hero.Train(h, wtype)
    local cls = ns.Classes[h.class]
    if not Hero.UsesWeaponSkills(h) or not cls.weapons[wtype] or not ns.WEAPON_SKILL_NAMES[wtype] then
        return false, cls.name .. "s can't learn that weapon."
    end
    Hero.EnsureSkills(h)
    if h.weaponSkills[wtype] then return false, "Already trained." end
    local cost = Hero.TrainCost(h)
    if (ns.db.gold or 0) < cost then return false, "Not enough gold." end
    ns.db.gold = ns.db.gold - cost
    h.weaponSkills[wtype] = 1
    return true
end

-- Called after every swing with a weapon; returns the new value if it rose.
function Hero.SkillUp(h, wtype)
    if not h.weaponSkills or not wtype then return nil end
    local cur = h.weaponSkills[wtype]
    local m = Hero.MaxSkill(h)
    if not cur or cur >= m then return nil end
    local chance = ns.Clamp((m - cur) / m * 1.5, 0.15, 1)
    if math.random() < chance then
        h.weaponSkills[wtype] = cur + 1
        return cur + 1
    end
end

---------------------------------------------------------------------------
-- Derived stats. Rules:
--   Agility   -> melee crit, armor, dodge (and 2 AP each for Agility specs)
--   Strength  -> 2 melee AP each (1 AP for Agility specs), block value
--   Intellect -> max mana, spell crit
--   Stamina   -> health
--   Spirit    -> mana and health regeneration
--   Defense rating -> block chance (+0.25% per point, needs a shield)
---------------------------------------------------------------------------

local FISTS = { min = 1, max = 3, speed = 2.0 }

local function WeaponStats(h, item)
    if not (item and item.min) then return nil end
    return { min = item.min, max = item.max, speed = item.speed, school = item.school, wtype = item.wtype,
        deficit = Hero.SkillDeficit(h, item.wtype) }
end

function Hero.Compute(h)
    Hero.EnsureSkills(h)
    local cls = ns.Classes[h.class]
    local spec = ns.Specs[h.spec]
    local d = Hero.BaseStats(h)
    d.gearArmor, d.sp, d.heal, d.def, d.shieldBlock = 0, 0, 0, 0, 0
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
    d.ap = spec.agiAP and (d.agi * 2 + d.str) or (d.str * 2)
    d.meleeCrit = 5 + d.agi / 20
    d.dodge = 3 + d.agi / 25
    d.spellCrit = 2 + d.int / 25
    d.hasShield = h.gear.OFFHAND and h.gear.OFFHAND.wtype == "SHIELD" or false
    d.blockChance = d.hasShield and (5 + d.def * 0.25) or 0
    d.blockValue = d.hasShield and floor(d.shieldBlock + d.str / 2) or 0
    d.manaRegen = d.spi / 5      -- per second, halved in combat
    d.hpRegen = d.spi / 15       -- per second, boosted out of combat
    d.spellPower = d.sp
    d.healPower = d.sp + d.heal
    d.weapon = WeaponStats(h, h.gear.MAINHAND) or FISTS
    d.offWeapon = WeaponStats(h, h.gear.OFFHAND)
    d.rangedWeapon = WeaponStats(h, h.gear.RANGED)
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

local function IsWeapon(item) return item.hand == "1H" or item.hand == "2H" end

-- slot defaults to the item's natural slot; pass "OFFHAND" to dual-wield a
-- one-hander.
function Hero.CanEquip(h, item, slot)
    slot = slot or item.slot
    local cls = ns.Classes[h.class]
    if h.level < item.reqLevel then return false, "Requires level " .. item.reqLevel end
    if item.armorType then
        local wear = Hero.ArmorType(h)
        if ns.ARMOR_RANK[item.armorType] > ns.ARMOR_RANK[wear] then
            if cls.armorAt40 and ns.ARMOR_RANK[item.armorType] <= ns.ARMOR_RANK[cls.armorAt40] then
                return false, ns.ARMOR_NAMES[item.armorType] .. " unlocks at level 40"
            end
            return false, cls.name .. "s can't wear " .. ns.ARMOR_NAMES[item.armorType]
        end
    end
    if item.wtype then
        if not cls.weapons[item.wtype] then
            return false, cls.name .. "s can't use " .. ns.WEAPON_TYPES[item.wtype].name .. "s"
        end
        if Hero.Skill(h, item.wtype) == nil then
            return false, "Requires " .. ns.WEAPON_SKILL_NAMES[item.wtype] .. " training"
        end
    end
    if slot ~= item.slot then
        if not (slot == "OFFHAND" and item.hand == "1H") then return false, "Doesn't fit that slot" end
        if not Hero.CanDualWield(h) then
            local lvl = cls.dualWield
            return false, lvl and ("Dual wield unlocks at level " .. lvl) or (cls.name .. "s can't dual wield")
        end
    end
    return true
end

-- Equips the item and returns a list of items that were removed.
function Hero.Equip(h, item, slot)
    slot = slot or item.slot
    local removed = {}
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
local function ReplacedScore(h, item, slot)
    local s = ns.Items.Score(h.gear[slot], h.spec, slot)
    if slot == "MAINHAND" and item.hand == "2H" then
        s = s + ns.Items.Score(h.gear.OFFHAND, h.spec, "OFFHAND")
    elseif slot == "OFFHAND" and h.gear.MAINHAND and h.gear.MAINHAND.hand == "2H" then
        return math.huge -- never auto-break a two-hander for an off hand
    end
    return s
end

local function Contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- Does this spec want the item in that slot at all?
local function FitsStyle(h, item, slot)
    local spec = ns.Specs[h.spec]
    if slot == "MAINHAND" then
        -- Melee classes may use anything they've trained; casters stick to their spec's weapons.
        return Hero.UsesWeaponSkills(h) or Contains(spec.mainhand, item.wtype)
    elseif slot == "OFFHAND" then
        if IsWeapon(item) then
            -- Shield/held-item specs keep their off hand style.
            return not (spec.offhand and (spec.offhand[1] == "SHIELD" or spec.offhand[1] == "HELD"))
        end
        return Contains(spec.offhand, item.wtype)
    elseif slot == "RANGED" then
        return spec.ranged ~= nil
    end
    return true
end

-- Best upgrade value for this hero and the slot it would go in (or nil).
function Hero.UpgradeValue(h, item)
    local slots = { item.slot }
    if item.hand == "1H" then slots[2] = "OFFHAND" end
    local best, bestSlot
    for _, slot in ipairs(slots) do
        if Hero.CanEquip(h, item, slot) and FitsStyle(h, item, slot) then
            local v = ns.Items.Score(item, h.spec, slot) - ReplacedScore(h, item, slot)
            if not best or v > best then best, bestSlot = v, slot end
        end
    end
    return best, bestSlot
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
