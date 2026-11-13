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
Mock.__index = function(t, k) return methods[k] or function() end end

function CreateFrame(kind) return new(kind) end
UIParent = new("Frame")
GameTooltip = new("GameTooltip")
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }
function UnitOnTaxi() return false end
function IsShiftKeyDown() return false end
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
-- use the reroll once, then confirm it is gone
draft.reroll._scripts.OnClick()
assert(ns.db.draft.rerolls == 0)
assert(not ns.Draft.Reroll(ns.db.draft), "second reroll should fail")
for i = 1, 5 do draft.cards[(i % 2) + 1].pick._scripts.OnClick() end
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
        -- hover a token to exercise the tooltip
        for _, t in pairs(battle.tokens) do t.circle._scripts.OnEnter(t.circle) break end
    end
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
party:SellUnusable()

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
