-- Smoke test: loads the whole addon against a stubbed WoW API and clicks
-- through draft -> party -> dungeon -> battle -> results.
--   lua5.1 tools/smoke.lua
local root = (arg[0]:match("^(.*)/tools/") or ".") .. "/"

local Mock = {}
local function new(kind)
    local o = setmetatable({ _kind = kind, _scripts = {}, _shown = true }, Mock)
    return o
end
local methods = {
    CreateTexture = function() return new("Texture") end,
    CreateFontString = function() return new("FontString") end,
    CreateMaskTexture = function() return new("MaskTexture") end,
    SetScript = function(self, k, fn) self._scripts[k] = fn end,
    GetScript = function(self, k) return self._scripts[k] end,
    GetFrameLevel = function() return 1 end,
    Show = function(self) self._shown = true end,
    Hide = function(self) self._shown = false end,
    SetShown = function(self, v) self._shown = not not v end,
    IsShown = function(self) return self._shown end,
    SetChecked = function(self, v) self._checked = v end,
    GetChecked = function(self) return self._checked end,
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    SetGradient = function() end,
}
-- Unknown Capitalized keys are treated as API methods (no-ops); plain fields are nil.
Mock.__index = function(t, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end

function CreateFrame(kind) return new(kind) end
UIParent = new("Frame")
GameTooltip = new("GameTooltip")
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }
function UnitOnTaxi() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return true end
function CreateFont() return new("Font") end
function StaticPopup_Show(name) StaticPopupDialogs[name].OnAccept() end
function CreateColor() return {} end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
YES, NO = "Yes", "No"

local ns = {}
local files = {}
for line in io.lines(root .. "Jumbla.toc") do
    if line:match("%.lua$") then files[#files + 1] = line:gsub("\\", "/") end
end
local eventFrame
local realCreate = CreateFrame
CreateFrame = function(kind, ...)
    local f = realCreate(kind, ...)
    if not eventFrame then eventFrame = f end
    return f
end
for _, f in ipairs(files) do assert(loadfile(root .. f))("Jumbla", ns) end
eventFrame._scripts.OnEvent(eventFrame, "ADDON_LOADED", "Jumbla")
assert(ns.db, "db not initialised")

math.randomseed(42)
SlashCmdList.JUMBLA("")
assert(ns.UI.current == "draft", "expected draft view, got " .. tostring(ns.UI.current))
local draft = ns.Views.draft
-- tank and healer one at a time
draft.big[1]._scripts.OnClick()
draft.big[2].pick._scripts.OnClick()
assert(ns.Draft.InDPSStage(ns.db.draft), "should be on the DPS rows")
-- all three DPS rows at once, six different classes
local seen = {}
for r = 1, 3 do
    for i = 1, 2 do
        local cls = ns.Specs[ns.db.draft.dps[r][i]].class
        assert(not seen[cls], "duplicate class across DPS rows: " .. cls)
        seen[cls] = true
    end
end
-- reroll row 2 (the only reroll), then it's gone
local before = ns.db.draft.dps[2][1]
draft.rows[2].reroll._scripts.OnClick()
assert(ns.db.draft.rerolls == 0)
assert(not ns.Draft.Reroll(ns.db.draft, 1), "second reroll should fail")
draft.begin._scripts.OnClick()
assert(ns.db.draft, "begin should do nothing until every row is picked")
for r = 1, 3 do draft.rows[r].cards[(r % 2) + 1]._scripts.OnClick() end
draft.rows[1].cards[1]._scripts.OnClick() -- change of mind
assert(ns.db.draft.dpsPick[1] == 1)
draft.begin._scripts.OnClick()
assert(ns.UI.current == "party")
for _, h in ipairs(ns.db.party.heroes) do print("hero", h.name, ns.SpecLabel(h.spec)) end

ns.UI:ShowView("dungeons")
ns.Views.dungeons.cards[1].enter._scripts.OnClick()
assert(ns.UI.current == "battle")
local battle = ns.Views.battle
ns.db.settings.speed = 4
local frames = 0
while not battle.resultsShown and frames < 20000 do
    battle.frame._scripts.OnUpdate(battle.frame, 0.05)
    frames = frames + 1
    if frames == 100 then
        -- hover a token, a party frame (ability panel) and swap the meter
        for _, t in pairs(battle.tokens) do t.circle._scripts.OnEnter(t.circle) break end
        local pf = battle.partyFrames[1]
        pf._scripts.OnEnter(pf)
        battle.meter.header._scripts.OnClick()
        assert(ns.db.settings.meter == "healing")
    end
    if frames == 400 then battle.partyFrames[1]._scripts.OnLeave() end
end
print("battle result:", battle.run.result, string.format("%.0fs", battle.run.time), "loot:", #battle.run.loot)
assert(battle.resultsShown)
battle.results.equip._scripts.OnClick()
assert(ns.UI.current == "party")

-- bag interactions
local party = ns.Views.party
table.insert(ns.db.bag, ns.Items.Generate({ ilvl = 12, quality = 3, slot = "HEAD", armorType = "CLOTH" }))
party:Refresh()
local b = party.bagButtons[1]
b._scripts.OnEnter(b)
b._scripts.OnClick(b, "LeftButton")
party.slotRows.HEAD._scripts.OnEnter(party.slotRows.HEAD)
party.slotRows.HEAD._scripts.OnClick(party.slotRows.HEAD, "RightButton")
party.rows[3]._scripts.OnClick()
local junk = ns.Items.Generate({ ilvl = 5, quality = 0, slot = "FEET", armorType = "CLOTH" })
table.insert(ns.db.bag, junk)
local goldBefore = ns.db.gold
party:ConfirmSellAll()
for _, it in ipairs(ns.db.bag) do assert(it ~= junk, "junk should have been sold") end
assert(ns.db.gold > goldBefore)

-- weapon skills: train a new type, then check it can be equipped
local h = ns.db.party.heroes[1]
ns.Views.party.selected = 1
ns.db.gold = 100000
local trainable = ns.Hero.Trainable(h)
if #trainable > 0 then
    local wtype = trainable[1]
    local axe = ns.Items.Generate({ ilvl = 10, quality = 2, wtype = wtype })
    assert(not ns.Hero.CanEquip(h, axe), "untrained weapon should be blocked")
    party.showSkills = true
    ns.db.gold = 0
    party:Refresh()
    for _, row in ipairs(party.skillRows) do
        if row.train.wtype == wtype then row.train._scripts.OnEnter(row.train) end
    end
    ns.db.gold = 100000
    party:Refresh()
    for _, row in ipairs(party.skillRows) do
        if row.train.wtype == wtype and row.train:IsShown() then row.train._scripts.OnClick(row.train) end
    end
    assert(h.weaponSkills[wtype] == 1, "training failed")
    assert(ns.Hero.CanEquip(h, axe), "trained weapon should be allowed")
    print("trained", ns.WEAPON_SKILL_NAMES[wtype], "gold left", ns.db.gold)
    party.showSkills = false
end

-- dual wield: a level 10 rogue can, a level 10 warrior can't
local rogue = ns.Hero.Create("ROGUE_COMBAT", {})
local warrior = ns.Hero.Create("WARRIOR_FURY", {})
local dagger = ns.Items.Generate({ ilvl = 9, quality = 2, wtype = "DAGGER" })
rogue.weaponSkills.DAGGER = 50
assert(ns.Hero.CanEquip(rogue, dagger, "OFFHAND"))
assert(ns.Hero.Compute(rogue).offWeapon, "rogue starter gear should dual wield")
warrior.weaponSkills.DAGGER = 50
assert(not ns.Hero.CanEquip(warrior, dagger, "OFFHAND"), "warriors dual wield at 20")
warrior.level = 20
assert(ns.Hero.CanEquip(warrior, dagger, "OFFHAND"))
-- armor: plate locked until 40, hunters in leather
local plate = ns.Items.Generate({ ilvl = 10, quality = 2, slot = "CHEST", armorType = "PLATE" })
local ok, why = ns.Hero.CanEquip(warrior, plate)
assert(not ok and why:find("40"), why)
warrior.level = 40
assert(ns.Hero.CanEquip(warrior, plate))
assert(ns.Hero.ArmorType(ns.Hero.Create("HUNTER_MM", {})) == "LEATHER")
-- agility attack power
local d = ns.Hero.Compute(rogue)
assert(d.ap == d.agi * 2 + d.str, "rogue AP should be 2*agi + str")

-- retreat path + taxi landing pause
ns.UI:StartBattle("RFC")
battle.frame._scripts.OnUpdate(battle.frame, 0.5)
ns.UI:PauseBattle(true)
assert(battle.paused)
battle.retreat._scripts.OnClick()
battle.frame._scripts.OnUpdate(battle.frame, 0.1)
assert(battle.run.result == "retreat")
battle.results.cont._scripts.OnClick()

-- reset
SlashCmdList.JUMBLA("reset")
assert(ns.UI.current == "draft" and ns.db.party == nil)
print("smoke test passed")
