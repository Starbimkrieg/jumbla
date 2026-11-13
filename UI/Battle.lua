-- Battle view: painted dungeon field with round unit tokens, floating combat
-- text, a damage/healing meter, party frames with an ability hover panel,
-- speed controls and the end-of-run summary.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.battle = View

local SCALE = 12                                  -- pixels per yard
local FIELD_PX_W, FIELD_PX_H = ns.FIELD_W * SCALE, ns.FIELD_H * SCALE
local MAX_FLOATERS = 60
local FLOAT_TIME = 1.2
local SCENE_PATH = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Scenes\\"

---------------------------------------------------------------------------
-- Unit tokens
---------------------------------------------------------------------------

local function TokenSize(u)
    if u.boss then return 48 end
    if u.kind == "pet" then return 24 end
    if u.kind == "hero" then return 36 end
    return 32
end

function View:CreateToken()
    local t = CreateFrame("Frame", nil, self.field)
    t:SetSize(60, 60)
    t.circle = W.CircleIcon(t, 34)
    t.circle:SetPoint("CENTER")
    t.hp = W.Bar(t, 40, 5, 0.1, 0.9, 0.1)
    t.power = W.Bar(t, 40, 3, 0, 0.44, 1)
    t.castBar = W.Bar(t, 40, 4, 1, 0.8, 0)
    t.flash = t:CreateTexture(nil, "OVERLAY")
    t.flash:SetSize(26, 26)
    t.circle:SetScript("OnEnter", function(c) View:UnitTooltip(c, t.unit) end)
    t.circle:SetScript("OnLeave", W.HideTooltip)
    return t
end

function View:SetupToken(t, u)
    t.unit = u
    local size = TokenSize(u)
    t.circle:SetSizeAll(size)
    if u.kind == "hero" then
        t.circle:SetClass(u.class)
    elseif u.kind == "pet" then
        t.circle:SetIcon(u.icon, 0.3, 0.8, 0.3)
    elseif u.boss then
        t.circle:SetIcon(u.icon, 1, 0.75, 0.1)
    else
        t.circle:SetIcon(u.icon, 0.85, 0.1, 0.1)
    end
    local barW = size + 12
    t.hp:SetWidth(barW)
    t.hp:ClearAllPoints()
    t.hp:SetPoint("TOP", t.circle, "BOTTOM", 0, -4)
    t.power:SetWidth(barW)
    t.power:ClearAllPoints()
    t.power:SetPoint("TOP", t.hp, "BOTTOM", 0, -1)
    t.power:SetShown(u.kind == "hero")
    t.castBar:SetWidth(barW)
    t.castBar:ClearAllPoints()
    t.castBar:SetPoint("BOTTOM", t.circle, "TOP", 0, 4)
    t.flash:ClearAllPoints()
    t.flash:SetPoint("BOTTOM", t.castBar, "TOP", 0, 3)
    t.flash:Hide()
    t.flashTime = 0
    t:Show()
end

-- Interpolated position between the last two simulation ticks, so movement
-- is smooth at any game speed.
function View:UnitPos(u)
    local a = self.alpha or 1
    local px, py = u.px or u.x, u.py or u.y
    return px + (u.x - px) * a, py + (u.y - py) * a
end

function View:UpdateToken(t, elapsed)
    local u = t.unit
    local x, y = self:UnitPos(u)
    t:ClearAllPoints()
    t:SetPoint("CENTER", self.field, "TOPLEFT", x * SCALE, -y * SCALE)
    t.hp:SetValue(u.maxHP > 0 and u.hp / u.maxHP or 0)
    if u.side == "enemy" then t.hp:SetStatusBarColor(0.9, 0.15, 0.1) else t.hp:SetStatusBarColor(0.1, 0.9, 0.1) end
    if u.kind == "hero" then
        local c = W.POWER_COLORS[u.resource] or W.POWER_COLORS.MANA
        t.power:SetStatusBarColor(c[1], c[2], c[3])
        t.power:SetValue(u.maxPower > 0 and u.power / u.maxPower or 0)
    end
    local cast = u.casting
    if cast and cast.total > 0 then
        local done = (cast.total - cast.remaining) + (self.alpha or 0) * ns.TICK
        local p = ns.Clamp(done / cast.total, 0, 1)
        t.castBar:SetValue(cast.channel and (1 - p) or p)
        t.castBar:Show()
    else
        t.castBar:Hide()
    end
    if t.flashTime > 0 then
        t.flashTime = t.flashTime - elapsed
        t.flash:SetAlpha(math.min(1, t.flashTime * 2))
        if t.flashTime <= 0 then t.flash:Hide() end
    end
    t.circle.icon:SetDesaturated(u.dead)
    t:SetAlpha(u.dead and 0.35 or 1)
    t:SetFrameLevel(self.field:GetFrameLevel() + (u.dead and 1 or (u.boss and 4 or 3)))
end

function View:UnitTooltip(owner, u)
    if not u then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if u.kind == "hero" then
        GameTooltip:SetText(u.name, W.ClassColor(u.class))
        GameTooltip:AddLine("Level " .. u.level .. " " .. ns.SpecLabel(u.hero.spec), 1, 1, 1)
    else
        GameTooltip:SetText(u.name, u.side == "enemy" and 1 or 0.3, u.side == "enemy" and 0.3 or 1, 0.3)
        GameTooltip:AddLine("Level " .. (u.level or "?") .. (u.boss and " (Boss)" or ""), 1, 1, 1)
    end
    GameTooltip:AddLine(string.format("Health: %d / %d", u.hp, u.maxHP), 0.2, 1, 0.2)
    if u.kind == "hero" then
        GameTooltip:AddLine(string.format("%s: %d / %d", u.resource:sub(1, 1) .. u.resource:sub(2):lower(),
            u.power, u.maxPower), 0.4, 0.6, 1)
    end
    if u.curTarget and not u.curTarget.dead then GameTooltip:AddLine("Target: " .. u.curTarget.name, 1, 0.82, 0) end
    for _, a in ipairs(u.auras) do
        GameTooltip:AddLine(string.format("%s (%ds)", a.name, math.max(0, a.remaining)), 0.6, 0.8, 1)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Floating combat text
---------------------------------------------------------------------------

function View:Float(u, text, r, g, b, big)
    local fl
    for _, f in ipairs(self.floaters) do
        if f.life <= 0 then fl = f break end
    end
    if not fl then
        if #self.floaters >= MAX_FLOATERS then return end
        fl = { fs = self.overlay:CreateFontString(nil, "OVERLAY"), life = 0 }
        self.floaters[#self.floaters + 1] = fl
    end
    fl.fs:SetFontObject(big and W.FontObject(26, "THICKOUTLINE") or W.FontObject(18, "OUTLINE"))
    fl.fs:SetText(text)
    fl.fs:SetTextColor(r, g, b)
    local x, y = self:UnitPos(u)
    fl.x = x * SCALE + math.random(-12, 12)
    fl.y = -y * SCALE + 20
    fl.life = FLOAT_TIME
    fl.fs:Show()
end

function View:UpdateFloaters(elapsed)
    for _, f in ipairs(self.floaters) do
        if f.life > 0 then
            f.life = f.life - elapsed
            if f.life <= 0 then
                f.fs:Hide()
            else
                local p = 1 - f.life / FLOAT_TIME
                f.fs:ClearAllPoints()
                f.fs:SetPoint("CENTER", self.overlay, "TOPLEFT", f.x, f.y + p * 36)
                f.fs:SetAlpha(math.min(1, f.life / 0.4))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Damage / healing meter
---------------------------------------------------------------------------

function View:CreateMeter()
    local m = CreateFrame("Frame", nil, self.overlay)
    m:SetSize(230, 26 + 5 * 20)
    m:SetPoint("TOPRIGHT", -6, -6)
    W.Backdrop(m, 0, 0, 0, 0.55)
    m.header = CreateFrame("Button", nil, m)
    m.header:SetPoint("TOPLEFT")
    m.header:SetPoint("TOPRIGHT")
    m.header:SetHeight(22)
    W.Backdrop(m.header, 0.15, 0.15, 0.2, 0.9)
    W.Highlight(m.header, 0.15)
    m.title = W.Text(m.header, 13, "OUTLINE", nil, "LEFT")
    m.title:SetPoint("LEFT", 6, 0)
    m.hint = W.Text(m.header, 11, "", "click to swap", "RIGHT")
    m.hint:SetPoint("RIGHT", -6, 0)
    m.hint:SetTextColor(0.6, 0.6, 0.6)
    m.header:SetScript("OnClick", function()
        ns.db.settings.meter = (ns.db.settings.meter == "healing") and "damage" or "healing"
        self:UpdateMeter()
    end)
    m.rows = {}
    for i = 1, 5 do
        local bar = W.Bar(m, 222, 18, 0.5, 0.5, 0.5)
        bar:SetPoint("TOPLEFT", 4, -24 - (i - 1) * 20)
        bar.name = W.Text(bar, 12, "OUTLINE", nil, "LEFT")
        bar.name:SetPoint("LEFT", 4, 0)
        bar.value = W.Text(bar, 12, "OUTLINE", nil, "RIGHT")
        bar.value:SetPoint("RIGHT", -4, 0)
        m.rows[i] = bar
    end
    self.meter = m
    self.meterTimer = 0
end

local function Abbrev(n)
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

function View:UpdateMeter()
    local run, m = self.run, self.meter
    if not run then return end
    local healing = ns.db.settings.meter == "healing"
    m.title:SetText(healing and "Healing Done" or "Damage Done")
    local list = {}
    for _, u in ipairs(run.heroUnits) do
        list[#list + 1] = { u = u, v = healing and u.healDone or u.dmgDone }
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    local top = math.max(1, list[1] and list[1].v or 1)
    local t = math.max(1, run.time)
    for i, bar in ipairs(m.rows) do
        local e = list[i]
        if e then
            bar:SetStatusBarColor(W.ClassColor(e.u.class))
            bar:SetValue(e.v / top)
            bar.name:SetText(i .. ". " .. e.u.name)
            bar.value:SetText(string.format("%s (%.1f)", Abbrev(e.v), e.v / t))
            bar:Show()
        else
            bar:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Party frames + ability hover panel
---------------------------------------------------------------------------

local function CreatePartyFrame(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetSize(188, 64)
    W.Backdrop(p, 0.1, 0.1, 0.12, 0.85)
    W.Highlight(p, 0.12)
    p.portrait = W.CircleIcon(p, 44)
    p.portrait:SetPoint("LEFT", 8, 0)
    p.portrait:EnableMouse(false)
    p.name = W.Text(p, 13, "OUTLINE", nil, "LEFT")
    p.name:SetPoint("TOPLEFT", p.portrait, "TOPRIGHT", 8, 2)
    p.name:SetWidth(124)
    p.hp = W.Bar(p, 124, 14, 0.1, 0.9, 0.1)
    p.hp:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -4)
    p.hpText = W.Text(p.hp, 11, "OUTLINE")
    p.hpText:SetPoint("CENTER")
    p.power = W.Bar(p, 124, 8, 0, 0.44, 1)
    p.power:SetPoint("TOPLEFT", p.hp, "BOTTOMLEFT", 0, -2)
    p:SetScript("OnEnter", function(self) View:ShowAbilityPanel(self) end)
    p:SetScript("OnLeave", function() View:HideAbilityPanel() end)
    return p
end

function View:CreateAbilityPanel(f)
    local a = CreateFrame("Frame", nil, f)
    a:SetSize(320, 150)
    a:SetFrameStrata("TOOLTIP")
    W.Backdrop(a, 0.03, 0.03, 0.05, 0.95)
    a.title = W.Text(a, 15, "OUTLINE", nil, "LEFT")
    a.title:SetPoint("TOPLEFT", 10, -8)
    a.sub = W.Text(a, 12, "", nil, "LEFT")
    a.sub:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -3)
    a.sub:SetTextColor(0.8, 0.8, 0.8)
    a.slots = {}
    for i = 1, 4 do
        local s = CreateFrame("Frame", nil, a)
        s:SetSize(52, 52)
        s:SetPoint("TOPLEFT", 10 + (i - 1) * 76, -48)
        s.border = s:CreateTexture(nil, "BACKGROUND")
        s.border:SetPoint("TOPLEFT", -2, 2)
        s.border:SetPoint("BOTTOMRIGHT", 2, -2)
        s.border:SetColorTexture(0.3, 0.3, 0.3, 1)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints()
        s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        s.shade = s:CreateTexture(nil, "OVERLAY")   -- cooldown wipe (shrinks from the top)
        s.shade:SetPoint("BOTTOMLEFT")
        s.shade:SetPoint("BOTTOMRIGHT")
        s.shade:SetColorTexture(0, 0, 0, 0.65)
        s.cd = W.Text(s, 22, "THICKOUTLINE")
        s.cd:SetPoint("CENTER")
        s.name = W.Text(s, 11, "", nil, "CENTER")
        s.name:SetPoint("TOP", s, "BOTTOM", 0, -3)
        s.name:SetWidth(74)
        s.cost = W.Text(s, 10, "", nil, "CENTER")
        s.cost:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
        a.slots[i] = s
    end
    a.auras = W.Text(a, 11, "", nil, "LEFT")
    a.auras:SetPoint("BOTTOMLEFT", 10, 8)
    a.auras:SetWidth(300)
    a.auras:SetTextColor(0.6, 0.8, 1)
    a:Hide()
    self.abilityPanel = a
end

function View:ShowAbilityPanel(pf)
    if not pf.unit then return end
    local a = self.abilityPanel
    a.unit = pf.unit
    a:ClearAllPoints()
    a:SetPoint("BOTTOM", pf, "TOP", 0, 6)
    a:Show()
    self:UpdateAbilityPanel()
end

function View:HideAbilityPanel()
    self.abilityPanel.unit = nil
    self.abilityPanel:Hide()
end

local RES_NAME = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy" }

function View:UpdateAbilityPanel()
    local a = self.abilityPanel
    local u = a.unit
    if not u then return end
    a.title:SetText("|c" .. W.ClassHex(u.class) .. u.name .. "|r")
    local cast = u.casting and (u.casting.def and u.casting.def.name)
    a.sub:SetText(string.format("Level %d %s   %s %d/%d%s", u.level, ns.SpecLabel(u.hero.spec),
        RES_NAME[u.resource] or "", u.power, u.maxPower, cast and ("   |cffffd100Casting " .. cast .. "|r") or ""))
    local n = #u.abilities
    a:SetWidth(math.max(240, 20 + n * 76))
    for i, s in ipairs(a.slots) do
        local ab = u.abilities[i]
        if ab then
            local def = ab.def
            s.icon:SetTexture(def.icon)
            s.name:SetText(def.name)
            local cost = def.cost or 0
            local affordable = (u.power or 0) >= cost
            s.cost:SetText(cost > 0 and (cost .. " " .. (RES_NAME[u.resource] or "")) or "No cost")
            s.cost:SetTextColor(affordable and 0.8 or 1, affordable and 0.8 or 0.3, affordable and 0.8 or 0.3)
            -- Out of resource: tint blue, like the default action bars.
            if affordable then s.icon:SetVertexColor(1, 1, 1) else s.icon:SetVertexColor(0.4, 0.4, 1) end
            local cdLeft = ab.cd or 0
            if cdLeft > 0 and (def.cd or 0) > 0 then
                s.shade:SetHeight(math.max(1, 52 * cdLeft / def.cd))
                s.shade:Show()
                s.cd:SetText(cdLeft >= 1 and tostring(math.ceil(cdLeft)) or string.format("%.1f", cdLeft))
            else
                s.shade:Hide()
                s.cd:SetText("")
            end
            local casting = u.casting and u.casting.ab == ab
            s.border:SetColorTexture(casting and 1 or 0.3, casting and 0.82 or 0.3, casting and 0 or 0.3, 1)
            s:Show()
        else
            s:Hide()
        end
    end
    local auras = {}
    for _, au in ipairs(u.auras) do
        if au.duration and au.duration < 1000 then
            auras[#auras + 1] = string.format("%s %ds", au.name, math.max(0, au.remaining))
        else
            auras[#auras + 1] = au.name
        end
    end
    a.auras:SetText(#auras > 0 and table.concat(auras, ",  ") or "")
    a:SetHeight(#auras > 0 and 150 or 136)
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    self.frame = f
    self.tokens, self.tokenPool, self.floaters, self.logLines = {}, {}, {}, {}

    self.title = W.Text(f, 18, "OUTLINE", nil, "LEFT")
    self.title:SetPoint("TOPLEFT", 10, -4)
    self.title:SetTextColor(1, 0.82, 0)
    self.clock = W.Text(f, 14, "", nil, "LEFT")
    self.clock:SetPoint("LEFT", self.title, "RIGHT", 14, 0)

    self.retreat = W.Button(f, "Retreat", 80, 24, function()
        if self.run then self.run:Retreat() end
    end)
    self.retreat:SetPoint("TOPRIGHT", -10, 0)
    self.speedButtons = {}
    local anchor = self.retreat
    for _, s in ipairs({ 4, 2, 1 }) do
        local b = W.Button(f, s .. "x", 40, 24, function()
            ns.db.settings.speed = s
            self:RefreshControls()
        end)
        b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        b.speed = s
        self.speedButtons[#self.speedButtons + 1] = b
        anchor = b
    end
    self.pause = W.Button(f, "Pause", 80, 24, function() self:SetPaused(not self.paused) end)
    self.pause:SetPoint("RIGHT", anchor, "LEFT", -8, 0)

    -- Field: flat dungeon color underneath, painted scene on top.
    local field = CreateFrame("Frame", nil, f)
    field:SetSize(FIELD_PX_W, FIELD_PX_H)
    field:SetPoint("TOP", 0, -30)
    field:SetClipsChildren(true)
    local border = field:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.45, 0.38, 0.25, 1)
    self.fieldBg = field:CreateTexture(nil, "BACKGROUND", nil, -7)
    self.fieldBg:SetAllPoints()
    self.scene = field:CreateTexture(nil, "BACKGROUND", nil, -6)
    self.scene:SetAllPoints()
    local dim = field:CreateTexture(nil, "BACKGROUND", nil, -5)
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.12)
    self.field = field
    self.overlay = CreateFrame("Frame", nil, field)
    self.overlay:SetAllPoints()
    self.overlay:SetFrameLevel(field:GetFrameLevel() + 10)

    self.banner = W.Text(self.overlay, 34, "THICKOUTLINE")
    self.banner:SetPoint("CENTER", 0, 80)
    self.banner:SetTextColor(1, 0.82, 0)
    self.bannerTime = 0

    self:CreateMeter()

    self.partyFrames = {}
    for i = 1, 5 do
        local p = CreatePartyFrame(f)
        p:SetPoint("TOPLEFT", field, "BOTTOMLEFT", (i - 1) * 193, -8)
        self.partyFrames[i] = p
    end
    self:CreateAbilityPanel(f)

    self.log = W.Text(f, 12, "", nil, "LEFT")
    self.log:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -78)
    self.log:SetWidth(FIELD_PX_W)
    self.log:SetJustifyV("TOP")
    self.log:SetSpacing(2)

    self:CreateResults(f)
    f:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
end

function View:CreateResults(f)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(660, 440)
    r:SetPoint("TOP", 0, -50)
    r:SetFrameLevel(self.overlay:GetFrameLevel() + 20)
    W.Backdrop(r, 0.05, 0.05, 0.07, 0.96)
    r:EnableMouse(true)
    r.title = W.Text(r, 30, "OUTLINE")
    r.title:SetPoint("TOP", 0, -16)
    r.left = W.Text(r, 13, "", nil, "LEFT")
    r.left:SetPoint("TOPLEFT", 20, -60)
    r.left:SetSpacing(4)
    r.left:SetWidth(320)
    r.left:SetJustifyV("TOP")
    r.right = W.Text(r, 13, "", nil, "LEFT")
    r.right:SetPoint("TOPLEFT", 360, -60)
    r.right:SetSpacing(4)
    r.right:SetWidth(280)
    r.right:SetJustifyV("TOP")
    r.equip = W.Button(r, "Auto-Equip & Continue", 200, 28, function()
        ns.Loot.AutoEquip(ns.db.party.heroes, ns.db.bag)
        ns.UI:EndBattle()
        ns.UI:ShowView("party")
    end)
    r.equip:SetPoint("BOTTOMRIGHT", r, "BOTTOM", -6, 16)
    r.cont = W.Button(r, "Continue", 160, 28, function()
        ns.UI:EndBattle()
        ns.UI:ShowView("party")
    end)
    r.cont:SetPoint("BOTTOMLEFT", r, "BOTTOM", 6, 16)
    r:Hide()
    self.results = r
end

---------------------------------------------------------------------------
-- Run lifecycle
---------------------------------------------------------------------------

function View:Start(run)
    self.run = run
    run.emit = true
    for _, t in pairs(self.tokens) do t:Hide() table.insert(self.tokenPool, t) end
    self.tokens = {}
    for _, fl in ipairs(self.floaters) do fl.life = 0 fl.fs:Hide() end
    self.logLines = {}
    self.log:SetText("")
    self.results:Hide()
    self:HideAbilityPanel()
    self.resultsShown = false
    local c = run.dungeon.color
    self.fieldBg:SetColorTexture(c[1], c[2], c[3], 1)
    self.scene:SetTexture(SCENE_PATH .. run.key .. ".tga")
    self.title:SetText(run.dungeon.name)
    self:SetPaused(false)
    self:Banner("Prepare!")
    for i, p in ipairs(self.partyFrames) do
        local u = run.heroUnits[i]
        p.unit = u
        if u then
            p.portrait:SetClass(u.class)
            p.name:SetText("|c" .. W.ClassHex(u.class) .. u.name .. "|r")
            p:Show()
        else
            p:Hide()
        end
    end
    self:UpdateMeter()
end

function View:Stop()
    self.run = nil
    self.results:Hide()
    self:HideAbilityPanel()
end

function View:SetPaused(p)
    self.paused = p
    self.pause:SetText(p and "Resume" or "Pause")
end

function View:RefreshControls()
    for _, b in ipairs(self.speedButtons) do
        if b.speed == ns.db.settings.speed then b:LockHighlight() else b:UnlockHighlight() end
    end
end

function View:Refresh()
    self:RefreshControls()
end

function View:Banner(text)
    self.banner:SetText(text)
    self.banner:Show()
    self.bannerTime = 2
end

function View:AddLog(text)
    table.insert(self.logLines, text)
    while #self.logLines > 3 do table.remove(self.logLines, 1) end
    self.log:SetText(table.concat(self.logLines, "\n"))
end

function View:HandleEvents()
    local run = self.run
    local evs = run.events
    run.events = {}
    for _, e in ipairs(evs) do
        local u = e.unit
        if e.kind == "damage" and u then
            if e.a > 0 then
                if u.side == "party" then
                    self:Float(u, "-" .. e.a, 1, 0.25, 0.25, e.b)
                else
                    self:Float(u, e.b and (e.a .. "!") or tostring(e.a), 1, e.b and 0.85 or 1, e.b and 0.2 or 1, e.b)
                end
            end
            if e.d and e.d > 0 then self:Float(u, "Absorb " .. e.d, 0.8, 0.8, 1) end
        elseif e.kind == "heal" and u then
            if e.a > 0 then self:Float(u, "+" .. e.a, 0.2, 1, 0.2, e.b) end
        elseif e.kind == "miss" and u then
            self:Float(u, e.a:sub(1, 1):upper() .. e.a:sub(2), 0.75, 0.75, 0.75)
        elseif e.kind == "ability" and u then
            local t = self.tokens[u.id]
            if t then
                t.flash:SetTexture(e.a)
                t.flash:Show()
                t.flashTime = 1.2
            end
        elseif e.kind == "log" then
            self:AddLog(e.a)
        elseif e.kind == "levelup" and u then
            self:Float(u, "LEVEL " .. e.a .. "!", 1, 0.82, 0, true)
        elseif e.kind == "loot" then
            self:AddLog(u.name .. " dropped " .. ns.Items.ColoredName(e.a))
        elseif e.kind == "wave" then
            self:Banner(e.b == "Trash" and ("Wave " .. e.a) or e.b)
            self:AddLog("|cffffd100Wave " .. e.a .. "/" .. run:WaveCount() .. ": " .. e.b .. "|r")
        elseif e.kind == "cleared" then
            self:Banner("Wave cleared")
        end
    end
end

function View:OnUpdate(elapsed)
    local run = self.run
    if not run then return end
    if not self.paused and not run.finished then
        run:Update(elapsed * (ns.db.settings.speed or 1))
    end
    -- Fraction of the way to the next tick (positions are drawn in between).
    self.alpha = run.finished and 1 or ns.Clamp(run.acc / ns.TICK, 0, 1)
    self:HandleEvents()

    local seen = {}
    for _, u in ipairs(run.units) do
        seen[u.id] = true
        local t = self.tokens[u.id]
        if not t then
            t = table.remove(self.tokenPool) or self:CreateToken()
            self.tokens[u.id] = t
            self:SetupToken(t, u)
        end
        self:UpdateToken(t, elapsed)
    end
    for id, t in pairs(self.tokens) do
        if not seen[id] then
            t:Hide()
            self.tokens[id] = nil
            table.insert(self.tokenPool, t)
        end
    end
    self:UpdateFloaters(elapsed)

    if self.bannerTime > 0 then
        self.bannerTime = self.bannerTime - elapsed
        self.banner:SetAlpha(math.min(1, self.bannerTime))
        if self.bannerTime <= 0 then self.banner:Hide() end
    end

    for _, p in ipairs(self.partyFrames) do
        local u = p.unit
        if u then
            p.hp:SetValue(u.hp / u.maxHP)
            p.hpText:SetText(u.dead and "Dead" or (math.floor(u.hp) .. " / " .. u.maxHP))
            local c = W.POWER_COLORS[u.resource] or W.POWER_COLORS.MANA
            p.power:SetStatusBarColor(c[1], c[2], c[3])
            p.power:SetValue(u.maxPower > 0 and u.power / u.maxPower or 0)
            p.portrait:SetAlpha(u.dead and 0.4 or 1)
        end
    end
    if self.abilityPanel.unit then self:UpdateAbilityPanel() end

    self.meterTimer = self.meterTimer - elapsed
    if self.meterTimer <= 0 then
        self.meterTimer = 0.25
        self:UpdateMeter()
    end

    local wave = run.state == "rest" and (run.waveIndex == 0 and "Preparing" or "Resting")
        or ("Wave " .. run.waveIndex .. "/" .. run:WaveCount())
    self.clock:SetText(string.format("%s  -  %d:%02d%s", wave, run.time / 60, run.time % 60,
        self.paused and "  |cffff8800(paused)|r" or ""))

    if run.finished and not self.resultsShown then
        self.resultsShown = true
        self:UpdateMeter()
        self:ShowResults()
    end
end

function View:ShowResults()
    local run, r = self.run, self.results
    local titles = { victory = "|cff33ff33Victory!|r", wipe = "|cffff3333Your party has wiped|r",
        retreat = "|cffffaa00Retreated|r" }
    r.title:SetText(titles[run.result] or run.result)

    local left = { string.format("|cffffd100%s|r  -  %d:%02d, %d kills", run.dungeon.name, run.time / 60,
        run.time % 60, run.kills), "Gold looted: " .. ns.FormatMoney(run.gold or 0), "" }
    for _, u in ipairs(run.heroUnits) do
        local h = u.hero
        local lv = run.levelUps[h.id]
        left[#left + 1] = string.format("|c%s%s|r  +%d xp%s", W.ClassHex(h.class), h.name, run.xp[h.id] or 0,
            lv and ("  |cffffd100Level " .. h.level .. "!|r") or "")
        left[#left + 1] = string.format("    dmg %d  (%.1f dps)   heal %d", u.dmgDone, u.dmgDone / math.max(1, run.time),
            u.healDone)
    end
    if run.result == "victory" then
        left[#left + 1] = ""
        left[#left + 1] = "Clear bonus: +" .. run.dungeon.bonusXP .. " xp each"
    end
    r.left:SetText(table.concat(left, "\n"))

    local right = { "|cffffd100Loot|r" }
    if #run.loot == 0 then right[#right + 1] = "|cff888888Nothing this time.|r" end
    for i, item in ipairs(run.loot) do
        if i > 18 then
            right[#right + 1] = "...and " .. (#run.loot - 18) .. " more"
            break
        end
        right[#right + 1] = ns.Items.ColoredName(item)
    end
    r.right:SetText(table.concat(right, "\n"))
    r:Show()
end
