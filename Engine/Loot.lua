-- Loot drops and auto-equip.
local ADDON, ns = ...

local Loot = {}
ns.Loot = Loot

local TRASH_DROP_CHANCE = 0.18
local TARGETED_CHANCE = 0.75   -- most drops are rolled for someone in the party

local function pick(t) return t[math.random(#t)] end

-- Weapon types a hero would actually use in a slot: for melee classes, the
-- skills they have trained (mostly); otherwise the spec's list.
local function WeaponChoices(h, list, ranged)
    if not ns.Hero.UsesWeaponSkills(h) or math.random() < 0.2 then return list end
    local cls = ns.Classes[h.class]
    local out = {}
    for wtype in pairs(h.weaponSkills or {}) do
        local isRanged = ns.WEAPON_TYPES[wtype].hand == "RANGED"
        if cls.weapons[wtype] and isRanged == (ranged or false) then out[#out + 1] = wtype end
    end
    table.sort(out)
    return #out > 0 and out or list
end

-- Build generation options aimed at one hero's spec.
local function OptionsFor(h, ilvl, quality)
    local spec = ns.Specs[h.spec]
    local wear = ns.Hero.ArmorType(h)
    local slots = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "MAINHAND", "MAINHAND" }
    if spec.offhand then slots[#slots + 1] = "OFFHAND" end
    if spec.ranged then slots[#slots + 1] = "RANGED" end
    local slot = pick(slots)
    local opts = { ilvl = ilvl, quality = quality, suffix = pick(spec.suffixes) }
    if slot == "MAINHAND" then
        opts.wtype = pick(WeaponChoices(h, spec.mainhand))
    elseif slot == "OFFHAND" then
        opts.wtype = pick(spec.offhand)
    elseif slot == "RANGED" then
        opts.wtype = pick(WeaponChoices(h, spec.ranged, true))
    else
        opts.slot = slot
        opts.armorType = wear
        if math.random() < 0.15 and ns.ARMOR_RANK[wear] > 1 then
            for k, r in pairs(ns.ARMOR_RANK) do
                if r == ns.ARMOR_RANK[wear] - 1 then opts.armorType = k end
            end
        end
    end
    return opts
end

local function RandomOptions(heroes, ilvl, quality)
    if math.random() < 0.3 then
        local types = {}
        for k in pairs(ns.WEAPON_TYPES) do types[#types + 1] = k end
        table.sort(types)
        return { ilvl = ilvl, quality = quality, wtype = pick(types) }
    end
    -- Only armor types someone in the party can wear right now.
    local wearable, seen = {}, {}
    for _, h in ipairs(heroes) do
        local rank = ns.ARMOR_RANK[ns.Hero.ArmorType(h)]
        for k, r in pairs(ns.ARMOR_RANK) do
            if r <= rank and not seen[k] then seen[k] = true wearable[#wearable + 1] = k end
        end
    end
    table.sort(wearable)
    return { ilvl = ilvl, quality = quality, armorType = #wearable > 0 and pick(wearable) or nil }
end

function Loot.RollItem(heroes, ilvl, quality)
    local opts
    if #heroes > 0 and math.random() < TARGETED_CHANCE then
        opts = OptionsFor(pick(heroes), ilvl, quality)
    else
        opts = RandomOptions(heroes, ilvl, quality)
    end
    return ns.Items.Generate(opts)
end

-- Returns a list of items dropped by a mob.
function Loot.ForKill(dungeonKey, mobKey, mobLevel, heroes)
    local mob = ns.Mobs[mobKey]
    local drops = {}
    if mob.boss then
        local named = ns.Dungeons[dungeonKey].loot and ns.Dungeons[dungeonKey].loot[mobKey]
        if named and math.random() < 0.6 then
            local def = pick(named)
            local opts = {}
            for k, v in pairs(def) do opts[k] = v end
            opts.ilvl, opts.quality = mobLevel + 1, 3
            drops[#drops + 1] = ns.Items.Generate(opts)
        end
        drops[#drops + 1] = Loot.RollItem(heroes, mobLevel, math.random() < 0.2 and 3 or 2)
    elseif math.random() < TRASH_DROP_CHANCE then
        drops[#drops + 1] = Loot.RollItem(heroes, mobLevel, math.random() < 0.08 and 3 or 2)
    end
    return drops
end

-- Equip every upgrade in the bag onto whoever benefits most.
-- Returns a list of { hero, item } that were equipped.
function Loot.AutoEquip(heroes, bag)
    local equipped = {}
    local changed = true
    while changed do
        changed = false
        for i = #bag, 1, -1 do
            local item = bag[i]
            local best, bestValue, bestSlot = nil, 0.5, nil
            for _, h in ipairs(heroes) do
                local v, slot = ns.Hero.UpgradeValue(h, item)
                if v and v > bestValue then best, bestValue, bestSlot = h, v, slot end
            end
            if best then
                table.remove(bag, i)
                for _, old in ipairs(ns.Hero.Equip(best, item, bestSlot)) do bag[#bag + 1] = old end
                equipped[#equipped + 1] = { hero = best, item = item }
                changed = true
                break
            end
        end
    end
    return equipped
end
