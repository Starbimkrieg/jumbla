-- The auto-battler. Pure Lua (no WoW API) so it can be simulated headless.
--
-- A Run owns every unit on a 2D field measured in yards (FIELD_W x FIELD_H).
-- The party starts on the left; each wave of enemies spawns on the right.
-- The simulation advances in fixed TICK steps.
local ADDON, ns = ...

local Run = {}
Run.__index = Run
ns.Run = Run

local TICK = 0.1
local GCD = 1.5
local NPC_GCD = 1.0
local FIELD_W, FIELD_H = 80, 40
local MELEE_REACH = 1.5
local RANGED_RANGE = 25
local PREP_TIME = 4
local REST_TIME = 6
local REVIVE_PCT = 0.3

ns.FIELD_W, ns.FIELD_H = FIELD_W, FIELD_H

local random, floor, sqrt, max, min = math.random, math.floor, math.sqrt, math.max, math.min

local function rnd(a, b) return a + (b - a) * random() end
local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

function Run:Rnd(a, b) return rnd(a, b) end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local HOME = {
    TANK = { { 26, 20 } },
    MELEE = { { 22, 13 }, { 22, 27 }, { 20, 20 } },
    RANGED = { { 11, 12 }, { 11, 28 }, { 9, 20 } },
    HEALER = { { 6, 20 }, { 6, 12 } },
}

function Run.New(dungeonKey, heroes)
    local r = setmetatable({}, Run)
    r.key = dungeonKey
    r.dungeon = ns.Dungeons[dungeonKey]
    r.units, r.byId, r.heroUnits = {}, {}, {}
    r.heroes = heroes
    r.nextUnitId = 1
    r.time, r.acc = 0, 0
    r.waveIndex = 0
    r.state, r.stateTimer = "rest", PREP_TIME
    r.events = {}
    r.loot, r.xp, r.levelUps = {}, {}, {}
    r.kills = 0

    local used = { TANK = 0, MELEE = 0, RANGED = 0, HEALER = 0 }
    for _, h in ipairs(heroes) do
        local spec = ns.Specs[h.spec]
        local group = spec.role == "TANK" and "TANK" or (spec.role == "HEALER" and "HEALER" or spec.position)
        used[group] = used[group] + 1
        local spot = HOME[group][used[group]] or { 12 + random(6), random(8, 32) }
        r:AddHero(h, spot)
    end
    return r
end

function Run:NewUnit(u)
    u.id = self.nextUnitId
    self.nextUnitId = self.nextUnitId + 1
    u.auras, u.gcd, u.swing = {}, 0, rnd(0, 0.6)
    u.threat = {}
    u.radius = u.radius or 1.2
    u.moveSpeed = u.moveSpeed or 7
    u.dmgDone, u.healDone = 0, 0
    self.units[#self.units + 1] = u
    self.byId[u.id] = u
    return u
end

function Run:AddHero(h, spot)
    local spec = ns.Specs[h.spec]
    local u = self:NewUnit({
        side = "party", kind = "hero", hero = h, spec = spec, class = h.class, name = h.name,
        role = spec.role, ranged = spec.position == "RANGED", attackRange = RANGED_RANGE,
        homeX = spot[1], homeY = spot[2], x = spot[1], y = spot[2],
        threatMod = spec.role == "TANK" and 2.5 or 1.0,
    })
    self:RefreshHero(u, true)
    self.heroUnits[#self.heroUnits + 1] = u
    if spec.role == "TANK" then self.tank = u end
    if spec.pet then self:SummonPet(u, spec.pet) end
    return u
end

-- Re-reads stats from the hero (after a level up); keeps health percentage.
function Run:RefreshHero(u, full)
    local h = u.hero
    local pctHP = u.maxHP and u.hp / u.maxHP or 1
    local pctPow = u.maxPower and u.maxPower > 0 and u.power / u.maxPower or 1
    u.level = h.level
    u.stats = ns.Hero.Compute(h)
    u.maxHP, u.maxPower, u.resource = u.stats.maxHP, u.stats.maxPower, u.stats.resource
    if full then
        u.hp = u.maxHP
        u.power = (u.resource == "RAGE") and 0 or u.maxPower
    else
        u.hp = max(1, floor(u.maxHP * pctHP))
        if u.resource == "MANA" then u.power = u.maxPower * pctPow end
    end
    local old = {}
    for _, ab in ipairs(u.abilities or {}) do old[ab.id] = ab.cd end
    u.abilities = {}
    for _, id in ipairs(ns.Hero.Abilities(h)) do
        u.abilities[#u.abilities + 1] = { id = id, def = ns.Abilities[id], cd = old[id] or 0 }
    end
end

local function CopyAbilities(list)
    local out = {}
    for i, ab in ipairs(list or {}) do
        local c = {}
        for k, v in pairs(ab) do c[k] = v end
        c.cdLeft = rnd(1, 1 + (ab.cd or 0) * 0.5)
        out[i] = c
    end
    return out
end

local function NpcWeapon(level, mult, speed)
    local avg = (4.5 + level * 1.6) * mult * speed
    return { min = max(1, floor(avg * 0.8)), max = max(2, floor(avg * 1.2)), speed = speed }
end

local function NpcStats(level, armor, weapon)
    return { armor = armor, ap = 0, meleeCrit = 5, spellCrit = 5, dodge = 5, blockChance = 0, blockValue = 0,
        spellPower = 0, healPower = 0, weapon = weapon }
end

function Run:SummonPet(owner, petKey)
    if owner.pet and not owner.pet.dead then return owner.pet end
    local def = ns.Pets[petKey]
    local level = owner.level
    local weapon = NpcWeapon(level, def.dmgMult > 0 and def.dmgMult or 0.1, 2.0)
    local pet = self:NewUnit({
        side = "party", kind = "pet", owner = owner, name = def.name, icon = def.icon, level = level,
        ranged = def.ranged, attackRange = RANGED_RANGE, radius = 1.0,
        x = owner.x + 1.5, y = owner.y + 1.5, threatMod = 1.0,
        stats = NpcStats(level, floor(owner.stats.armor * 0.5), weapon),
        npcAbilities = CopyAbilities(def.abilities), noAutoAttack = def.dmgMult <= 0,
    })
    pet.maxHP = floor(owner.maxHP * def.hpMult)
    pet.hp = pet.maxHP
    owner.pet = pet
    self:Emit("log", nil, owner.name .. " summons a " .. def.name .. ".")
    return pet
end

function Run:SpawnMob(key, level, x, y)
    local m = ns.Mobs[key]
    local speed = m.speed or 2.0
    local u = self:NewUnit({
        side = "enemy", kind = "mob", key = key, template = m, name = m.name, icon = m.icon,
        level = level, boss = m.boss, ranged = m.ranged, attackRange = RANGED_RANGE,
        radius = m.boss and 2.0 or 1.3, moveSpeed = 6.5, x = x, y = y, threatMod = 1,
        stats = NpcStats(level, floor(level * 20 * (m.armor or 1)), NpcWeapon(level, m.dmg, speed)),
        npcAbilities = CopyAbilities(m.abilities),
    })
    u.maxHP = floor((25 + level * 13) * m.hp)
    u.hp = u.maxHP
    return u
end

---------------------------------------------------------------------------
-- Events (consumed by the UI; ignored headless)
---------------------------------------------------------------------------

function Run:Emit(kind, unit, a, b, c, d)
    if not self.emit then return end
    local ev = self.events
    ev[#ev + 1] = { kind = kind, unit = unit, a = a, b = b, c = c, d = d }
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------

function Run:AuraSum(u, key)
    local s = 0
    for _, a in ipairs(u.auras) do
        if a.mods and a.mods[key] then s = s + a.mods[key] end
    end
    return s
end

function Run:AuraMult(u, key)
    local m = 1
    for _, a in ipairs(u.auras) do
        if a.mods and a.mods[key] then m = m * a.mods[key] end
    end
    return m
end

function Run:FindAura(u, key, source)
    for _, a in ipairs(u.auras) do
        if a.key == key and (source == nil or a.source == source) then return a end
    end
end

function Run:AP(u) return (u.stats.ap or 0) + self:AuraSum(u, "ap") end
function Run:Armor(u) return max(0, (u.stats.armor or 0) + self:AuraSum(u, "armor")) end
function Run:SpellPower(u) return u.stats.spellPower or 0 end
function Run:HealPower(u) return u.stats.healPower or 0 end
function Run:BlockValue(u) return (u.stats.blockValue or 0) + self:AuraSum(u, "blockValue") end
function Run:BlockChance(u)
    if not u.stats.hasShield then return 0 end
    return (u.stats.blockChance or 0) + self:AuraSum(u, "blockChance")
end
function Run:Haste(u) return self:AuraMult(u, "hasteMult") end
function Run:MoveMult(u) return self:AuraMult(u, "moveMult") end

function Run:Alive(side)
    local out = {}
    for _, u in ipairs(self.units) do
        if not u.dead and u.side == side then out[#out + 1] = u end
    end
    return out
end

function Run:Allies(u) return self:Alive(u.side) end
function Run:Opponents(u) return self:Alive(u.side == "party" and "enemy" or "party") end

function Run:Nearest(u, list)
    local best, bd
    for _, o in ipairs(list) do
        local d = dist(u, o)
        if not bd or d < bd then best, bd = o, d end
    end
    return best
end

function Run:InRange(u, t, range)
    if t == u then return true end
    return dist(u, t) <= range + u.radius + t.radius
end

local function AbilityRange(def)
    if def.range == "melee" then return MELEE_REACH end
    if def.range == "self" then return 0 end
    return def.range or MELEE_REACH
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------

function Run:Update(elapsed)
    if self.finished then return end
    self.acc = self.acc + elapsed
    local steps = 0
    while self.acc >= TICK and not self.finished and steps < 200 do
        self.acc = self.acc - TICK
        self:Step(TICK)
        steps = steps + 1
    end
end

function Run:Step(dt)
    self.time = self.time + dt
    local snapshot = {}
    for i, u in ipairs(self.units) do snapshot[i] = u end

    if self.state == "rest" then
        self.stateTimer = self.stateTimer - dt
        for _, u in ipairs(snapshot) do
            if not u.dead and u.side == "party" then self:UnitStep(u, dt, false) end
        end
        self:Separate()
        if self.stateTimer <= 0 then self:NextWave() end
        return
    end

    for _, u in ipairs(snapshot) do
        if not u.dead then self:UnitStep(u, dt, true) end
    end
    self:Separate()

    local heroesAlive = false
    for _, u in ipairs(self.heroUnits) do if not u.dead then heroesAlive = true end end
    if not heroesAlive then
        self:Finish("wipe")
        return
    end
    if #self:Alive("enemy") == 0 then self:WaveCleared() end
end

function Run:CurrentWave() return self.dungeon.waves[self.waveIndex] end
function Run:WaveCount() return #self.dungeon.waves end

function Run:WaveLabel()
    local w = self:CurrentWave()
    if not w then return "Preparing" end
    if w.boss then return ns.Mobs[w.boss].name end
    return "Trash"
end

function Run:NextWave()
    self.waveIndex = self.waveIndex + 1
    local wave = self:CurrentWave()
    if not wave then return self:Finish("victory") end
    local d = self.dungeon
    local list = {}
    if wave.boss then
        list[1] = { key = wave.boss, level = d.bossLevel }
        for _, k in ipairs(wave.adds or {}) do list[#list + 1] = { key = k, level = random(d.levels[1], d.levels[2]) } end
    else
        for _, k in ipairs(wave) do list[#list + 1] = { key = k, level = random(d.levels[1], d.levels[2]) } end
    end
    local n = #list
    for i, e in ipairs(list) do
        local y = 20 + (i - (n + 1) / 2) * 8
        local x = (i == 1 and wave.boss) and 70 or rnd(70, 76)
        self:SpawnMob(e.key, e.level, x, ns.Clamp(y, 4, FIELD_H - 4))
    end
    self.state = "fight"
    self:Emit("wave", nil, self.waveIndex, self:WaveLabel())
end

function Run:WaveCleared()
    -- Remove corpses, reset threat, revive the fallen.
    local keep = {}
    for _, u in ipairs(self.units) do
        if u.side == "party" and (u.kind == "hero" or not u.dead) then
            keep[#keep + 1] = u
        else
            self.byId[u.id] = nil
        end
    end
    self.units = keep
    for _, u in ipairs(self.heroUnits) do
        u.casting, u.queuedStrike, u.curTarget = nil, nil, nil
        if u.dead then
            u.dead = false
            u.hp = floor(u.maxHP * REVIVE_PCT)
            if u.resource == "MANA" then u.power = u.maxPower * REVIVE_PCT end
            self:Emit("log", u, u.name .. " is revived.")
        end
        if u.spec.pet and (not u.pet or u.pet.dead) then self:SummonPet(u, u.spec.pet) end
    end
    if self.waveIndex >= self:WaveCount() then return self:Finish("victory") end
    self.state, self.stateTimer = "rest", REST_TIME
    self:Emit("cleared", nil, self.waveIndex)
end

function Run:Finish(result)
    if self.finished then return end
    self.finished, self.result = true, result
    if result == "victory" then
        ns.db.clears[self.key] = (ns.db.clears[self.key] or 0) + 1
        for _, u in ipairs(self.heroUnits) do self:GiveXP(u, self.dungeon.bonusXP) end
    end
    self:Emit("finish", nil, result)
end

function Run:Retreat() self:Finish("retreat") end

---------------------------------------------------------------------------
-- Per-unit update
---------------------------------------------------------------------------

function Run:UnitStep(u, dt, inCombat)
    u.gcd = max(0, u.gcd - dt)
    u.swing = u.swing - dt
    if u.swingOH then u.swingOH = u.swingOH - dt end
    if u.forcedTimer then u.forcedTimer = u.forcedTimer - dt end
    if u.abilities then for _, ab in ipairs(u.abilities) do ab.cd = max(0, ab.cd - dt) end end
    if u.npcAbilities then for _, ab in ipairs(u.npcAbilities) do ab.cdLeft = ab.cdLeft - dt end end

    self:TickAuras(u, dt)
    if u.dead then return end
    self:Regen(u, dt, inCombat)

    if u.casting then
        self:TickCast(u, dt)
        return
    end

    if u.kind == "hero" then
        self:HeroAI(u, dt, inCombat)
    elseif inCombat then
        self:NpcAI(u, dt)
    else
        -- pets follow their owner while resting
        if u.owner then self:MoveToward(u, u.owner.x + 2, u.owner.y + 2, 0.5, dt) end
    end
end

function Run:Regen(u, dt, inCombat)
    if u.kind ~= "hero" then return end
    local s = u.stats
    if inCombat then
        u.hp = u.hp + s.hpRegen * dt
    else
        u.hp = u.hp + (s.hpRegen * 3 + u.maxHP * 0.04) * dt
    end
    if u.hp > u.maxHP then u.hp = u.maxHP end
    if u.resource == "MANA" then
        if inCombat then
            u.power = u.power + s.manaRegen * 0.5 * dt
        else
            u.power = u.power + (s.manaRegen * 2 + u.maxPower * 0.05) * dt
        end
    elseif u.resource == "ENERGY" then
        u.power = u.power + 10 * dt
    elseif u.resource == "RAGE" and not inCombat then
        u.power = u.power - 3 * dt
    end
    u.power = ns.Clamp(u.power, 0, u.maxPower)
end

function Run:MoveToward(u, tx, ty, stopDist, dt)
    local dx, dy = tx - u.x, ty - u.y
    local d = sqrt(dx * dx + dy * dy)
    if d <= stopDist then return true end
    local step = u.moveSpeed * self:MoveMult(u) * dt
    if step > d - stopDist then step = d - stopDist end
    u.x = ns.Clamp(u.x + dx / d * step, 1, FIELD_W - 1)
    u.y = ns.Clamp(u.y + dy / d * step, 1, FIELD_H - 1)
    return false
end

-- Moves into attack range of target; returns true when in range.
function Run:Engage(u, t, dt, range)
    range = range or (u.ranged and u.attackRange or MELEE_REACH)
    if self:InRange(u, t, range) then return true end
    self:MoveToward(u, t.x, t.y, range + u.radius + t.radius - 0.3, dt)
    return false
end

function Run:Separate()
    local list = {}
    for _, u in ipairs(self.units) do if not u.dead then list[#list + 1] = u end end
    for i = 1, #list do
        local a = list[i]
        for j = i + 1, #list do
            local b = list[j]
            local dx, dy = b.x - a.x, b.y - a.y
            local d = sqrt(dx * dx + dy * dy)
            local need = a.radius + b.radius
            if d < need then
                if d < 0.01 then dx, dy, d = rnd(-1, 1), rnd(-1, 1), 1 end
                local push = (need - d) / 2
                local px, py = dx / d * push, dy / d * push
                if not a.casting then a.x, a.y = a.x - px, a.y - py end
                if not b.casting then b.x, b.y = b.x + px, b.y + py end
            end
        end
    end
    for _, u in ipairs(list) do
        u.x = ns.Clamp(u.x, 1, FIELD_W - 1)
        u.y = ns.Clamp(u.y, 1, FIELD_H - 1)
    end
end

---------------------------------------------------------------------------
-- Targeting
---------------------------------------------------------------------------

function Run:PickTarget(u)
    local enemies = self:Opponents(u)
    if #enemies == 0 then u.curTarget = nil return nil end
    local t
    if u.role == "TANK" then
        -- Peel: grab anything that is hitting someone else.
        local loose = {}
        for _, e in ipairs(enemies) do
            if e.curTarget and e.curTarget ~= u then loose[#loose + 1] = e end
        end
        t = self:Nearest(u, loose)
        if not t and u.curTarget and not u.curTarget.dead then t = u.curTarget end
    else
        local leader = (u.owner and u.owner.curTarget) or (self.tank and not self.tank.dead and self.tank.curTarget)
        if leader and not leader.dead then t = leader end
        if not t and u.curTarget and not u.curTarget.dead then t = u.curTarget end
    end
    t = t or self:Nearest(u, enemies)
    u.curTarget = t
    return t
end

function Run:MobTarget(m)
    if m.forced and m.forcedTimer and m.forcedTimer > 0 and not m.forced.dead then
        m.curTarget = m.forced
        return m.forced
    end
    local best, bestThreat
    for id, v in pairs(m.threat) do
        local p = self.byId[id]
        if p and not p.dead and (not bestThreat or v > bestThreat) then best, bestThreat = p, v end
    end
    local cur = m.curTarget
    if best and cur and cur ~= best and not cur.dead and m.threat[cur.id] and bestThreat < m.threat[cur.id] * 1.1 then
        best = cur
    end
    if not best then
        best = self:Nearest(m, self:Opponents(m))
        if best then m.threat[best.id] = 1 end
    end
    m.curTarget = best
    return best
end

---------------------------------------------------------------------------
-- Hero AI
---------------------------------------------------------------------------

local OOC_OK = { selfbuff = true, partyaura = true, summon = true, heal = true, hot = true }

local function LowestAlly(run, u, threshold, filter)
    local best, bestPct
    for _, a in ipairs(run:Allies(u)) do
        local pct = a.hp / a.maxHP
        local limit = threshold
        if a.role == "TANK" then limit = threshold + 0.1 end
        if a.kind == "pet" then limit = threshold - 0.25 end
        if pct < limit and (not filter or filter(a)) and (not bestPct or pct < bestPct) then
            best, bestPct = a, pct
        end
    end
    return best
end

function Run:ChooseAbilityTarget(u, ab, inCombat)
    local def = ab.def
    local ai = def.ai
    if ai == "nuke" then
        return self:PickTarget(u)
    elseif ai == "dot" then
        local main = self:PickTarget(u)
        local function needs(t)
            local a = self:FindAura(t, def.aura, u)
            return not a or a.remaining < 1
        end
        if main and needs(main) then return main end
        for _, e in ipairs(self:Opponents(u)) do
            if needs(e) and self:InRange(u, e, AbilityRange(def)) and e.hp > e.maxHP * 0.25 then return e end
        end
    elseif ai == "selfbuff" then
        local a = self:FindAura(u, def.aura)
        if not a or a.remaining < 2 then return u end
    elseif ai == "partyaura" then
        for _, a in ipairs(self:Allies(u)) do
            if not self:FindAura(a, def.aura) then return u end
        end
    elseif ai == "summon" then
        if not u.pet or u.pet.dead then return u end
    elseif ai == "petattack" then
        if u.pet and not u.pet.dead then
            local t = self:PickTarget(u)
            if t and self:InRange(u.pet, t, MELEE_REACH + 1) then return t end
        end
    elseif ai == "nextswing" then
        if not u.queuedStrike and u.power >= def.cost + 10 then
            local t = self:PickTarget(u)
            if t and self:InRange(u, t, MELEE_REACH) then return t end
        end
    elseif ai == "taunt" then
        for _, e in ipairs(self:Opponents(u)) do
            if e.curTarget and e.curTarget ~= u and e.curTarget.side == "party" and dist(u, e) <= def.radius then
                return u
            end
        end
    elseif ai == "defensive" then
        if def.needsShield and not u.stats.hasShield then return nil end
        for _, e in ipairs(self:Opponents(u)) do
            if e.curTarget == u and self:InRange(u, e, MELEE_REACH + 1) then return u end
        end
    elseif ai == "heal" then
        return LowestAlly(self, u, inCombat and 0.7 or 0.95)
    elseif ai == "hot" then
        return LowestAlly(self, u, inCombat and 0.92 or 0.97, function(a) return not self:FindAura(a, def.aura, u) end)
    elseif ai == "shield" then
        if not inCombat then return nil end
        local function ok(a) return not self:FindAura(a, "WEAKENED_SOUL") and not self:FindAura(a, "POWER_WORD_SHIELD") end
        local tank = self.tank
        if tank and not tank.dead and ok(tank) then
            for _, e in ipairs(self:Opponents(u)) do
                if e.curTarget == tank then return tank end
            end
        end
        return LowestAlly(self, u, 0.85, ok)
    end
    return nil
end

function Run:CanAfford(u, def)
    return (u.power or 0) >= (def.cost or 0)
end

function Run:HeroAI(u, dt, inCombat)
    for _, ab in ipairs(u.abilities) do
        local def = ab.def
        if ab.cd <= 0 and (def.offGCD or u.gcd <= 0) and self:CanAfford(u, def)
            and (inCombat or (OOC_OK[def.ai] and not def.combatOnly)) then
            local t = self:ChooseAbilityTarget(u, ab, inCombat)
            if t then
                if t == u or self:InRange(u, t, AbilityRange(def)) then
                    self:BeginCast(u, ab, t)
                    if u.casting or not def.offGCD then return end
                else
                    self:Engage(u, t, dt, AbilityRange(def))
                    return
                end
            end
        end
    end
    if not inCombat then
        self:MoveToward(u, u.homeX, u.homeY, 0.3, dt)
        return
    end
    local t = self:PickTarget(u)
    if t and self:Engage(u, t, dt) then self:AutoAttack(u, t) end
end

function Run:BeginCast(u, ab, t)
    local def = ab.def
    u.power = u.power - (def.cost or 0)
    ab.cd = def.cd or 0
    if not def.offGCD then u.gcd = GCD end
    self:Emit("ability", u, def.icon, def.name)
    if def.channel then
        local every = def.channel / def.ticks
        u.casting = { ab = ab, def = def, target = t, remaining = def.channel, total = def.channel,
            channel = true, every = every, tickTimer = every }
    elseif (def.cast or 0) > 0 then
        u.casting = { ab = ab, def = def, target = t, remaining = def.cast, total = def.cast }
    else
        def.execute(self, u, t, ab)
    end
end

function Run:TickCast(u, dt)
    local c = u.casting
    local t = c.target
    if t and t ~= u and t.dead then
        u.casting = nil
        return
    end
    c.remaining = c.remaining - dt
    if c.channel then
        c.tickTimer = c.tickTimer - dt
        if c.tickTimer <= 0.001 then
            c.tickTimer = c.tickTimer + c.every
            c.def.tick(self, u, t)
        end
    end
    if c.remaining <= 0.001 then
        u.casting = nil
        if c.npc then
            self:ExecuteNpc(u, c.npc, t)
        elseif not c.channel then
            c.def.execute(self, u, t, c.ab)
        end
    end
end

---------------------------------------------------------------------------
-- NPC AI (enemies and pets)
---------------------------------------------------------------------------

local function NpcRange(ab)
    return ab.range or MELEE_REACH
end

function Run:NpcAI(u, dt)
    local t
    if u.side == "enemy" then t = self:MobTarget(u) else t = self:PickTarget(u) end
    if not t then return end

    if u.gcd <= 0 then
        for _, ab in ipairs(u.npcAbilities or {}) do
            if ab.cdLeft <= 0 then
                local target = self:NpcAbilityTarget(u, ab, t)
                if target then
                    ab.cdLeft = max(ab.cd or 0, 0.1)
                    u.gcd = NPC_GCD
                    self:Emit("ability", u, ab.icon, ab.name)
                    if (ab.cast or 0) > 0 then
                        u.casting = { npc = ab, target = target, remaining = ab.cast, total = ab.cast }
                    else
                        self:ExecuteNpc(u, ab, target)
                    end
                    return
                end
            end
        end
    end
    if self:Engage(u, t, dt) and not u.noAutoAttack then self:AutoAttack(u, t) end
end

function Run:NpcAbilityTarget(u, ab, t)
    local typ = ab.type
    if typ == "nuke" or typ == "dot" then
        local target = t
        if ab.random then
            local opp = self:Opponents(u)
            target = opp[random(#opp)]
        end
        if target and self:InRange(u, target, NpcRange(ab)) then return target end
    elseif typ == "strike" or typ == "cleave" then
        if self:InRange(u, t, MELEE_REACH) then return t end
    elseif typ == "aoe" then
        if ab.atTarget then
            if self:InRange(u, t, NpcRange(ab)) then return t end
        else
            for _, o in ipairs(self:Opponents(u)) do
                if dist(u, o) <= ab.radius + o.radius then return u end
            end
        end
    elseif typ == "heal" then
        if ab.self then
            if u.hp < u.maxHP * 0.6 then return u end
        else
            for _, a in ipairs(self:Allies(u)) do
                if a.hp < a.maxHP * 0.6 and self:InRange(u, a, NpcRange(ab)) then return a end
            end
        end
    elseif typ == "summon" then
        if not ab.used and u.hp < u.maxHP * (ab.hpBelow or 0.5) then return u end
    end
end

function Run:ExecuteNpc(u, ab, t)
    local base = (6 + u.level * 2.0) * (ab.dmg or 1)
    local w = u.stats.weapon
    local swing = (w.min + w.max) / 2 * (ab.dmg or 1)
    local typ = ab.type
    if typ == "nuke" then
        self:SpellDamage(u, t, base * rnd(0.9, 1.1), 0, ab.school or "shadow", ab.name)
    elseif typ == "strike" then
        self:PhysicalDamage(u, t, swing, ab.name, { melee = true })
    elseif typ == "cleave" then
        local victims = { t }
        for _, o in ipairs(self:Opponents(u)) do
            if o ~= t and #victims < 3 and dist(o, t) <= 5 then victims[#victims + 1] = o end
        end
        for _, v in ipairs(victims) do self:PhysicalDamage(u, v, swing, ab.name, { melee = true }) end
    elseif typ == "aoe" then
        local cx = ab.atTarget and t or u
        for _, o in ipairs(self:Opponents(u)) do
            if dist(cx, o) <= ab.radius + o.radius then
                self:Damage(u, o, base * rnd(0.9, 1.1), { school = ab.school or "physical", name = ab.name })
            end
        end
    elseif typ == "dot" then
        self:ApplyDot(u, t, { key = "NPC_" .. ab.name, name = ab.name, icon = ab.icon, school = ab.school or "nature",
            total = base, duration = ab.duration or 9, interval = 3 })
    elseif typ == "heal" then
        local amount = t.maxHP * (ab.healPct or 0.2)
        local eff = min(amount, t.maxHP - t.hp)
        t.hp = t.hp + eff
        self:Emit("heal", t, floor(eff), false)
    elseif typ == "summon" then
        ab.used = true
        for i, key in ipairs(ab.spawn) do
            self:SpawnMob(key, u.level - 1, u.x + 3, ns.Clamp(u.y + (i * 2 - 3) * 4, 3, FIELD_H - 3))
        end
        self:Emit("log", u, u.name .. " calls for help!")
    end
end

---------------------------------------------------------------------------
-- Combat resolution
---------------------------------------------------------------------------

local function RageConversion(level)
    return 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
end

-- Returns "miss", "dodge", "block", "crit" or "hit".
function Run:AttackRoll(att, def, opts)
    opts = opts or {}
    local r = random() * 100
    if not opts.noMiss then
        -- Low weapon skill: +0.1% miss per point below max. Dual-wield white swings: +16% miss.
        local miss = 5 + max(0, (def.level or 1) - (att.level or 1)) * 1.5 + (opts.deficit or 0) * 0.1
            + (opts.dualWield and 16 or 0)
        if r < miss then return "miss" end
        r = r - miss
        if not opts.ranged then
            local dodge = def.stats.dodge or 5
            if r < dodge then return "dodge" end
            r = r - dodge
        end
    end
    local block = opts.ranged and 0 or self:BlockChance(def)
    if r < block then return "block" end
    r = r - block
    if r < max(0, (att.stats.meleeCrit or 5) - (opts.deficit or 0) * 0.04) then return "crit" end
    return "hit"
end

function Run:Damage(src, dst, amount, opts)
    if dst.dead then return 0 end
    opts = opts or {}
    local school = opts.school or "physical"
    if school == "physical" then
        local armor = self:Armor(dst)
        amount = amount * (1 - armor / (armor + 400 + 85 * ((src and src.level) or dst.level)))
    end
    amount = max(1, floor(amount + 0.5))

    local absorbed = 0
    for i = #dst.auras, 1, -1 do
        local a = dst.auras[i]
        if a.absorb and a.absorb > 0 and amount > 0 then
            local take = min(a.absorb, amount)
            a.absorb = a.absorb - take
            amount = amount - take
            absorbed = absorbed + take
            if a.absorb <= 0 then table.remove(dst.auras, i) end
        end
    end

    dst.hp = dst.hp - amount
    if src and src.side ~= dst.side then
        local credit = src.owner or src
        credit.dmgDone = credit.dmgDone + amount
        if dst.side == "enemy" and not opts.noThreat then
            dst.threat[src.id] = (dst.threat[src.id] or 0) + (amount + absorbed) * (src.threatMod or 1)
        end
        if src.resource == "RAGE" and opts.melee then
            src.power = min(src.maxPower, src.power + amount / RageConversion(src.level) * 10)
        end
        if dst.resource == "RAGE" then
            dst.power = min(dst.maxPower, dst.power + (amount + absorbed) / RageConversion(dst.level) * 2.5)
        end
    end
    self:Emit("damage", dst, amount, opts.crit, school, absorbed)
    if dst.hp <= 0 then self:Kill(dst, src) end

    if opts.melee and src and not src.dead and src.side ~= dst.side then
        local thorns = self:AuraSum(dst, "thorns")
        if thorns > 0 then self:Damage(dst, src, thorns, { school = "nature", name = "Thorns" }) end
    end
    return amount
end

-- Generic physical hit (also used for "melee" abilities with a magic school).
function Run:PhysicalDamage(src, dst, amount, name, opts)
    opts = opts or {}
    local roll = self:AttackRoll(src, dst, opts)
    if roll == "miss" or roll == "dodge" then
        self:Emit("miss", dst, roll)
        return false
    end
    if roll == "crit" then amount = amount * 2 end
    if roll == "block" then
        amount = amount - self:BlockValue(dst)
        if amount <= 0 then self:Emit("miss", dst, "block") return true end
    end
    return self:Damage(src, dst, amount, { school = opts.school or "physical", crit = roll == "crit", melee = opts.melee, name = name })
end

local function WeaponRoll(run, u, w)
    local dmg = rnd(w.min, w.max)
    if u.kind == "hero" and not w.school then dmg = dmg + run:AP(u) / 14 * w.speed end
    return dmg
end

-- A melee ability built on a weapon swing (Sinister Strike, Raptor Strike...).
function Run:WeaponStrike(c, t, bonus, name, opts)
    opts = opts or {}
    local amount
    if opts.bonusOnly then
        amount = bonus + self:AP(c) * (opts.apCoef or 0)
    else
        amount = WeaponRoll(self, c, c.stats.weapon) + bonus
    end
    return self:PhysicalDamage(c, t, amount, name, { melee = true, deficit = c.stats.weapon.deficit })
end

function Run:AutoAttack(u, t)
    local ranged = u.ranged
    local oh = not ranged and u.stats.offWeapon
    if oh then
        if not u.swingOH then u.swingOH = 0.3 end -- staggered from the main hand; ticked in UnitStep
        if u.swingOH <= 0 then
            u.swingOH = oh.speed / self:Haste(u)
            self:Swing(u, t, false, oh, true)
        end
    end
    if u.swing > 0 then return end
    local w = ranged and u.stats.rangedWeapon or u.stats.weapon
    if not w then return end
    u.swing = w.speed / self:Haste(u)
    self:Swing(u, t, ranged, w)
end

-- Weapon skill rises with use (persisted on the hero).
function Run:SkillUp(u, w)
    if u.kind ~= "hero" or not w.wtype then return end
    local v = ns.Hero.SkillUp(u.hero, w.wtype)
    if v then
        w.deficit = max(0, ns.Hero.MaxSkill(u.hero) - v)
        if v % 10 == 0 or w.deficit == 0 then
            self:Emit("log", u, string.format("%s's %s skill increased to %d.", u.name,
                ns.WEAPON_SKILL_NAMES[w.wtype], v))
        end
    end
end

function Run:Swing(u, t, ranged, w, offhand)
    local dmg = WeaponRoll(self, u, w)
    local name
    self:SkillUp(u, w)
    if offhand then
        dmg = dmg * 0.5
    elseif not ranged then
        if u.queuedStrike then
            dmg = dmg + u.queuedStrike.bonus
            name = u.queuedStrike.name
            u.queuedStrike = nil
        end
        for _, a in ipairs(u.auras) do
            if a.onSwing and a.onSwing.flatPerSpeed then dmg = dmg + a.onSwing.flatPerSpeed * w.speed end
        end
    end
    if ranged and w.school then
        -- wands: magic damage, spell crit
        local crit = random() * 100 < (u.stats.spellCrit or 5)
        self:Damage(u, t, crit and dmg * 1.5 or dmg, { school = w.school, crit = crit, name = "Shoot" })
        return
    end
    local dualWield = not ranged and u.stats.offWeapon ~= nil and not name
    local hit = self:PhysicalDamage(u, t, dmg, name or (offhand and "Off-hand" or "Attack"),
        { melee = not ranged, ranged = ranged, deficit = w.deficit, dualWield = dualWield })
    if hit and not ranged and not offhand then
        for _, a in ipairs(u.auras) do
            local os = a.onSwing
            if os and os.holyPerSpeed and not t.dead then
                local holy = os.holyPerSpeed * w.speed + self:SpellPower(u) * (os.spCoef or 0)
                self:Damage(u, t, holy, { school = "holy", name = a.name })
            end
            if os and os.cleave then
                local n = 0
                for _, o in ipairs(self:Opponents(u)) do
                    if o ~= t and n < os.cleave and dist(o, t) <= 5 then
                        n = n + 1
                        self:Damage(u, o, dmg * (os.cleavePct or 0.5), { school = "physical", melee = true, name = a.name })
                    end
                end
            end
        end
    end
end

function Run:SpellDamage(c, t, base, coef, school, name)
    local amount = base + self:SpellPower(c) * (coef or 0)
    local crit = random() * 100 < (c.stats.spellCrit or 5)
    if crit then amount = amount * 1.5 end
    return self:Damage(c, t, amount, { school = school, crit = crit, name = name })
end

function Run:AddHealThreat(c, amount)
    local engaged = {}
    for _, e in ipairs(self:Alive("enemy")) do
        if next(e.threat) then engaged[#engaged + 1] = e end
    end
    for _, e in ipairs(engaged) do
        e.threat[c.id] = (e.threat[c.id] or 0) + amount / #engaged
    end
end

function Run:Heal(c, t, base, coef, name)
    if t.dead then return 0 end
    local amount = base + self:HealPower(c) * (coef or 0)
    local crit = random() * 100 < (c.stats.spellCrit or 5)
    if crit then amount = amount * 1.5 end
    local eff = min(amount, t.maxHP - t.hp)
    t.hp = t.hp + eff
    c.healDone = c.healDone + eff
    self:Emit("heal", t, floor(eff + 0.5), crit)
    self:AddHealThreat(c, eff * 0.5)
    return eff
end

function Run:ApplyAura(t, a)
    if t.dead then return end
    for i = #t.auras, 1, -1 do
        local o = t.auras[i]
        if o.key == a.key and (o.source == a.source or not a.periodic) then table.remove(t.auras, i) end
    end
    a.remaining = a.duration
    t.auras[#t.auras + 1] = a
    return a
end

function Run:ApplyDot(c, t, d)
    local ticks = d.duration / d.interval
    local total = d.total + self:SpellPower(c) * (d.coef or 0) + self:AP(c) * (d.apCoef or 0)
    return self:ApplyAura(t, { key = d.key, source = c, name = d.name, icon = d.icon, duration = d.duration,
        interval = d.interval, tickTimer = d.interval, periodic = { dmg = total / ticks, school = d.school } })
end

function Run:ApplyHot(c, t, d)
    local ticks = d.duration / d.interval
    local total = d.total + self:HealPower(c) * (d.coef or 0)
    return self:ApplyAura(t, { key = d.key, source = c, name = d.name, icon = d.icon, duration = d.duration,
        interval = d.interval, tickTimer = d.interval, periodic = { heal = total / ticks } })
end

function Run:TickAuras(u, dt)
    for i = #u.auras, 1, -1 do
        local a = u.auras[i]
        if a then
            a.remaining = a.remaining - dt
            if a.periodic then
                a.tickTimer = a.tickTimer - dt
                if a.tickTimer <= 0.001 then
                    a.tickTimer = a.tickTimer + a.interval
                    local p = a.periodic
                    if p.dmg then
                        local school = p.school == "bleed" and "bleed" or p.school
                        self:Damage(a.source, u, p.dmg, { school = school, name = a.name, periodic = true })
                    elseif p.heal and a.source then
                        local eff = min(p.heal, u.maxHP - u.hp)
                        u.hp = u.hp + eff
                        a.source.healDone = a.source.healDone + eff
                        self:Emit("heal", u, floor(eff + 0.5), false)
                        self:AddHealThreat(a.source, eff * 0.5)
                    end
                    if u.dead then return end
                end
            end
            if a.remaining <= 0 and u.auras[i] == a then table.remove(u.auras, i) end
        end
    end
end

function Run:Taunt(c, radius, duration)
    for _, e in ipairs(self:Opponents(c)) do
        if dist(c, e) <= radius then
            local top = 0
            for _, v in pairs(e.threat) do if v > top then top = v end end
            e.threat[c.id] = max(e.threat[c.id] or 0, top * 1.1 + 10)
            e.forced, e.forcedTimer = c, duration
            e.curTarget = c
        end
    end
end

---------------------------------------------------------------------------
-- Death, experience, loot
---------------------------------------------------------------------------

function Run:Kill(u, killer)
    if u.dead then return end
    u.dead, u.hp, u.casting, u.auras = true, 0, nil, {}
    if u.side == "enemy" then
        self:OnEnemyKilled(u)
    else
        for _, e in ipairs(self.units) do
            if e.side == "enemy" then
                e.threat[u.id] = nil
                if e.curTarget == u then e.curTarget = nil end
            end
        end
        if u.kind == "hero" then self.deaths = (self.deaths or 0) + 1 end
        self:Emit("log", u, u.name .. " has died.")
    end
end

function Run:GiveXP(u, amount)
    local h = u.hero
    amount = floor(amount)
    self.xp[h.id] = (self.xp[h.id] or 0) + amount
    local gained = ns.Hero.AddXP(h, amount)
    if gained > 0 then
        self:RefreshHero(u, false)
        self.levelUps[h.id] = (self.levelUps[h.id] or 0) + gained
        self:Emit("levelup", u, h.level)
        self:Emit("log", u, h.name .. " reached level " .. h.level .. "!")
    end
end

function Run:OnEnemyKilled(m)
    self.kills = self.kills + 1
    local coins = floor(m.level * (m.boss and rnd(40, 60) or rnd(4, 8)))
    self.gold = (self.gold or 0) + coins
    ns.db.gold = (ns.db.gold or 0) + coins
    local base = (m.level * 4 + 10) * (m.boss and 3 or 1)
    for _, u in ipairs(self.heroUnits) do
        local f = ns.Clamp(1 - (u.hero.level - m.level) * 0.15, 0.1, 1.3)
        self:GiveXP(u, base * f)
    end
    for _, item in ipairs(ns.Loot.ForKill(self.key, m.key, m.level, self.heroes)) do
        ns.db.bag[#ns.db.bag + 1] = item
        self.loot[#self.loot + 1] = item
        self:Emit("loot", m, item)
    end
    local spawns = m.template.onDeath
    if spawns then
        for i, key in ipairs(spawns) do
            self:SpawnMob(key, m.level, m.x + i, m.y)
        end
        self:Emit("log", m, ns.Mobs[spawns[1]].name .. " jumps out!")
    end
end
