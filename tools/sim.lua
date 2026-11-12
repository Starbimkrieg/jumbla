-- Headless balance simulator. Runs the real engine outside of WoW.
--   lua5.1 tools/sim.lua [runs] [seed]
-- Simulates fresh drafts progressing RFC -> DM -> WC with auto-equip,
-- and prints win rates, run times and levels.

local root = (arg[0]:match("^(.*)/tools/") or ".") .. "/"
local ns = {}
for _, f in ipairs({ "Core.lua", "Data/Classes.lua", "Data/Abilities.lua", "Data/Items.lua", "Data/Mobs.lua",
    "Data/Dungeons.lua", "Engine/Hero.lua", "Engine/Loot.lua", "Engine/Combat.lua" }) do
    assert(loadfile(root .. f))("Jumbla", ns)
end

local RUNS = tonumber(arg[1]) or 30
math.randomseed(tonumber(arg[2]) or os.time())
local VERBOSE = os.getenv("VERBOSE")

local function NewParty()
    local d = ns.Draft.New()
    while not ns.Draft.IsDone(d) do ns.Draft.Pick(d, math.random(2)) end
    return ns.Draft.Finish(d)
end

local function AvgLevel(heroes)
    local s = 0
    for _, h in ipairs(heroes) do s = s + h.level end
    return s / #heroes
end

local function Simulate(key, heroes)
    local run = ns.Run.New(key, heroes)
    while not run.finished and run.time < 1200 do run:Step(0.1) end
    ns.Loot.AutoEquip(heroes, ns.db.bag)
    return run
end

local stats = {}
local function Rec(key, run)
    local s = stats[key] or { n = 0, win = 0, time = 0, waves = 0, deaths = {} }
    stats[key] = s
    s.n = s.n + 1
    if run.result == "victory" then s.win = s.win + 1 end
    s.time = s.time + run.time
    s.waves = s.waves + run.waveIndex
    s.dead = (s.dead or 0) + (run.deaths or 0)
end

local specStats = {}
local function RecSpecs(heroes, run)
    for _, h in ipairs(heroes) do
        local t = specStats[h.spec] or { n = 0, win = 0, dmg = 0, heal = 0 }
        specStats[h.spec] = t
        t.n = t.n + 1
        if run.result == "victory" then t.win = t.win + 1 end
    end
    for _, u in ipairs(run.heroUnits) do
        local t = specStats[u.hero.spec]
        t.dmg = t.dmg + u.dmgDone / run.time
        t.heal = t.heal + u.healDone / run.time
    end
end

local runsToLevel = { DM = {}, WC = {} }
for i = 1, RUNS do
    ns.InitDB({})
    local heroes = NewParty()
    local count = 0
    for _, key in ipairs(ns.DUNGEON_ORDER) do
        local d = ns.Dungeons[key]
        local next = ns.DUNGEON_ORDER[_ + 1]
        local need = next and ns.Dungeons[next].reqLevel or (d.reqLevel + 5)
        local n = 0
        while AvgLevel(heroes) < need and n < 30 do
            local run = Simulate(key, heroes)
            Rec(key, run)
            RecSpecs(heroes, run)
            if n == 0 then
                stats[key].first = (stats[key].first or 0) + 1
                if run.result == "victory" then stats[key].firstWin = (stats[key].firstWin or 0) + 1 end
            end
            n = n + 1
            count = count + 1
            if VERBOSE then
                local comp = {}
                for _, h in ipairs(heroes) do comp[#comp + 1] = ns.SpecLabel(h.spec) .. " " .. h.level end
                print(key, run.result, run.waveIndex, string.format("%.0fs", run.time), table.concat(comp, ", "))
            end
        end
        if next then table.insert(runsToLevel[next], n) end
    end
end

for _, key in ipairs(ns.DUNGEON_ORDER) do
    local s = stats[key]
    if s then
        print(string.format("%-4s runs=%4d  win=%5.1f%%  first-try win=%5.1f%%  avg time=%5.0fs  waves=%.1f/%d  deaths/run=%.1f",
            key, s.n, s.win / s.n * 100, (s.firstWin or 0) / (s.first or 1) * 100, s.time / s.n, s.waves / s.n,
            #ns.Dungeons[key].waves, s.dead / s.n))
    end
end
for _, key in ipairs({ "DM", "WC" }) do
    local t, n = 0, 0
    for _, v in ipairs(runsToLevel[key]) do t, n = t + v, n + 1 end
    if n > 0 then print(string.format("runs of previous dungeon needed to unlock %s: %.1f", key, t / n)) end
end

print("\nper spec (all dungeons):")
local keys = {}
for k in pairs(specStats) do keys[#keys + 1] = k end
table.sort(keys, function(a, b) return specStats[a].dmg / specStats[a].n > specStats[b].dmg / specStats[b].n end)
for _, k in ipairs(keys) do
    local t = specStats[k]
    print(string.format("  %-26s runs=%4d win=%5.1f%%  dps=%5.1f  hps=%5.1f", ns.SpecLabel(k), t.n, t.win / t.n * 100,
        t.dmg / t.n, t.heal / t.n))
end
