-- Loot drops and auto-equip.
local ADDON, ns = ...

local Loot = {}
ns.Loot = Loot

local TRASH_DROP_CHANCE = 0.18
local TARGETED_CHANCE = 0.75   -- most drops are rolled for someone in the party

local function pick(t) return t[math.random(#t)] end

-- Build generation options aimed at one hero's spec.
local function OptionsFor(h, ilvl, quality)
    local spec = ns.Specs[h.spec]
    local cls = ns.Classes[h.class]
    local slots = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "MAINHAND", "MAINHAND" }
    if spec.offhand then slots[#slots + 1] = "OFFHAND" end
    if spec.ranged then slots[#slots + 1] = "RANGED" end
    local slot = pick(slots)
    local opts = { ilvl = ilvl, quality = quality, suffix = pick(spec.suffixes) }
    if slot == "MAINHAND" then
        opts.wtype = pick(spec.mainhand)
    elseif slot == "OFFHAND" then
        opts.wtype = pick(spec.offhand)
    elseif slot == "RANGED" then
        opts.wtype = pick(spec.ranged)
    else
        opts.slot = slot
        opts.armorType = cls.armor
        if math.random() < 0.15 and ns.ARMOR_RANK[cls.armor] > 1 then
            for k, r in pairs(ns.ARMOR_RANK) do
                if r == ns.ARMOR_RANK[cls.armor] - 1 then opts.armorType = k end
            end
        end
    end
    if opts.wtype == "SHIELD" or opts.wtype == "HELD" then opts.suffix = pick(spec.suffixes) end
    return opts
end

local function RandomOptions(ilvl, quality)
    if math.random() < 0.3 then
        local types = {}
        for k in pairs(ns.WEAPON_TYPES) do types[#types + 1] = k end
        table.sort(types)
        return { ilvl = ilvl, quality = quality, wtype = pick(types) }
    end
    return { ilvl = ilvl, quality = quality }
end

function Loot.RollItem(heroes, ilvl, quality)
    local opts
    if #heroes > 0 and math.random() < TARGETED_CHANCE then
        opts = OptionsFor(pick(heroes), ilvl, quality)
    else
        opts = RandomOptions(ilvl, quality)
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
            local best, bestValue = nil, 0.5
            for _, h in ipairs(heroes) do
                local v = ns.Hero.UpgradeValue(h, item)
                if v and v > bestValue then best, bestValue = h, v end
            end
            if best then
                table.remove(bag, i)
                for _, old in ipairs(ns.Hero.Equip(best, item)) do bag[#bag + 1] = old end
                equipped[#equipped + 1] = { hero = best, item = item }
                changed = true
                break
            end
        end
    end
    return equipped
end
