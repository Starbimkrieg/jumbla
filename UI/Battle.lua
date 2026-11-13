-- Battle view: the 2D field with round unit tokens, floating combat text,
-- party frames, speed controls and the end-of-run summary.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.battle = View

local SCALE = 9                                   -- pixels per yard
local FIELD_PX_W, FIELD_PX_H = ns.FIELD_W * SCALE, ns.FIELD_H * SCALE
local MAX_FLOATERS = 40
local FLOAT_TIME = 1.1

---------------------------------------------------------------------------
-- Unit tokens
---------------------------------------------------------------------------

local function TokenSize(u)
    if u.boss then return 34 end
    if u.kind == "pet" then return 16 end
    return 22
end

function View:CreateToken()
    local t = CreateFrame("Frame", nil, self.field)
    t:SetSize(40, 40)
    t:SetFrameLevel(self.field:GetFrameLevel() + 2)
    t.circle = W.CircleIcon(t, 22)
    t.circle:SetPoint("CENTER")
    t.hp = W.Bar(t, 28, 3, 0.1, 0.9, 0.1)
    t.power = W.Bar(t, 28, 2, 0, 0.44, 1)
    t.flash = t:CreateTexture(nil, "OVERLAY")
    t.flash:SetSize(16, 16)
    t.castBar = W.Bar(t, 28, 2, 1, 0.8, 0)
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
    else
        if u.boss then t.circle:SetIcon(u.icon, 1, 0.75, 0.1) else t.circle:SetIcon(u.icon, 0.8, 0.1, 0.1) end
    end
    local barW = size + 6
    t.hp:SetWidth(barW)
    t.hp:ClearAllPoints()
    t.hp:SetPoint("TOP", t.circle, "BOTTOM", 0, -3)
    t.power:SetWidth(barW)
    t.power:ClearAllPoints()
    t.power:SetPoint("TOP", t.hp, "BOTTOM", 0, -1)
    t.power:SetShown(u.kind == "hero")
    t.castBar:SetWidth(barW)
    t.castBar:ClearAllPoints()
    t.castBar:SetPoint("BOTTOM", t.circle, "TOP", 0, 3)
    t.flash:ClearAllPoints()
    t.flash:SetPoint("BOTTOM", t.castBar, "TOP", 0, 2)
    t.flash:Hide()
    t.flashTime = 0
    t:Show()
end

function View:UpdateToken(t, elapsed)
    local u = t.unit
    t:ClearAllPoints()
    t:SetPoint("CENTER", self.field, "TOPLEFT", u.x * SCALE, -u.y * SCALE)
    t.hp:SetValue(u.maxHP > 0 and u.hp / u.maxHP or 0)
    if u.side == "enemy" then t.hp:SetStatusBarColor(0.9, 0.15, 0.1) else t.hp:SetStatusBarColor(0.1, 0.9, 0.1) end
    if u.kind == "hero" then
        local c = W.POWER_COLORS[u.resource] or W.POWER_COLORS.MANA
        t.power:SetStatusBarColor(c[1], c[2], c[3])
        t.power:SetValue(u.maxPower > 0 and u.power / u.maxPower or 0)
    end
    local cast = u.casting
    if cast and cast.total > 0 then
        t.castBar:SetValue(cast.channel and (cast.remaining / cast.total) or (1 - cast.remaining / cast.total))
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
        fl = { fs = self.overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal"), life = 0 }
        self.floaters[#self.floaters + 1] = fl
    end
    fl.fs:SetFontObject(big and "GameFontNormalLarge" or "GameFontNormalSmall")
    fl.fs:SetText(text)
    fl.fs:SetTextColor(r, g, b)
    fl.x = u.x * SCALE + math.random(-8, 8)
    fl.y = -u.y * SCALE + 10
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
                f.fs:SetPoint("CENTER", self.overlay, "TOPLEFT", f.x, f.y + p * 24)
                f.fs:SetAlpha(math.min(1, f.life / 0.4))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function CreatePartyFrame(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(148, 50)
    W.Backdrop(p, 0.1, 0.1, 0.12, 0.85)
    p.portrait = W.CircleIcon(p, 32)
    p.portrait:SetPoint("LEFT", 6, 0)
    p.name = W.Font(p, "GameFontNormalSmall", nil, "LEFT")
    p.name:SetPoint("TOPLEFT", p.portrait, "TOPRIGHT", 6, 2)
    p.name:SetWidth(100)
    p.hp = W.Bar(p, 100, 9, 0.1, 0.9, 0.1)
    p.hp:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -3)
    p.hpText = W.Font(p.hp, "NumberFontNormalSmall")
    p.hpText:SetPoint("CENTER")
    p.power = W.Bar(p, 100, 6, 0, 0.44, 1)
    p.power:SetPoint("TOPLEFT", p.hp, "BOTTOMLEFT", 0, -2)
    return p
end

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    self.frame = f
    self.tokens, self.tokenPool, self.floaters, self.logLines = {}, {}, {}, {}

    self.title = W.Font(f, "GameFontNormalLarge", nil, "LEFT")
    self.title:SetPoint("TOPLEFT", 10, -4)
    self.clock = W.Font(f, "GameFontHighlight", nil, "LEFT")
    self.clock:SetPoint("LEFT", self.title, "RIGHT", 12, 0)

    -- Controls
    self.retreat = W.Button(f, "Retreat", 70, 22, function()
        if self.run then self.run:Retreat() end
    end)
    self.retreat:SetPoint("TOPRIGHT", -10, 0)
    self.speedButtons = {}
    local anchor = self.retreat
    for _, s in ipairs({ 4, 2, 1 }) do
        local b = W.Button(f, s .. "x", 36, 22, function()
            ns.db.settings.speed = s
            self:RefreshControls()
        end)
        b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        b.speed = s
        self.speedButtons[#self.speedButtons + 1] = b
        anchor = b
    end
    self.pause = W.Button(f, "Pause", 70, 22, function() self:SetPaused(not self.paused) end)
    self.pause:SetPoint("RIGHT", anchor, "LEFT", -8, 0)

    -- Field
    local field = CreateFrame("Frame", nil, f)
    field:SetSize(FIELD_PX_W, FIELD_PX_H)
    field:SetPoint("TOP", 0, -30)
    field:SetClipsChildren(true)
    self.fieldBg = W.Backdrop(field, 0.2, 0.05, 0.03, 1)
    local shade = field:CreateTexture(nil, "BACKGROUND", nil, 1)
    shade:SetAllPoints()
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    -- SetGradient's signature differs between client generations; it's cosmetic.
    if not (CreateColor and pcall(shade.SetGradient, shade, "HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.45))) then
        shade:SetColorTexture(0, 0, 0, 0.15)
    end
    local border = field:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.4, 0.35, 0.25, 1)
    border:SetDrawLayer("BACKGROUND", -1)
    self.field = field
    self.overlay = CreateFrame("Frame", nil, field)
    self.overlay:SetAllPoints()
    self.overlay:SetFrameLevel(field:GetFrameLevel() + 10)

    self.banner = W.Font(self.overlay, "GameFontNormalHuge")
    self.banner:SetPoint("CENTER", 0, 60)
    self.bannerTime = 0

    -- Party frames
    self.partyFrames = {}
    for i = 1, 5 do
        local p = CreatePartyFrame(f)
        p:SetPoint("TOPLEFT", field, "BOTTOMLEFT", (i - 1) * 151 - 15, -8)
        self.partyFrames[i] = p
    end

    -- Log
    self.log = W.Font(f, "GameFontHighlightSmall", nil, "LEFT")
    self.log:SetPoint("TOPLEFT", field, "BOTTOMLEFT", -15, -64)
    self.log:SetWidth(740)
    self.log:SetJustifyV("TOP")
    self.log:SetSpacing(2)

    self:CreateResults(f)

    f:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
end

function View:CreateResults(f)
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(520, 380)
    r:SetPoint("TOP", 0, -20)
    r:SetFrameLevel(self.overlay:GetFrameLevel() + 10)
    W.Backdrop(r, 0.05, 0.05, 0.07, 0.96)
    r:EnableMouse(true)
    r.title = W.Font(r, "GameFontNormalHuge")
    r.title:SetPoint("TOP", 0, -14)
    r.left = W.Font(r, "GameFontHighlightSmall", nil, "LEFT")
    r.left:SetPoint("TOPLEFT", 16, -50)
    r.left:SetSpacing(3)
    r.left:SetWidth(240)
    r.left:SetJustifyV("TOP")
    r.right = W.Font(r, "GameFontHighlightSmall", nil, "LEFT")
    r.right:SetPoint("TOPLEFT", 270, -50)
    r.right:SetSpacing(3)
    r.right:SetWidth(240)
    r.right:SetJustifyV("TOP")
    r.equip = W.Button(r, "Auto-Equip & Continue", 180, 26, function()
        ns.Loot.AutoEquip(ns.db.party.heroes, ns.db.bag)
        ns.UI:EndBattle()
        ns.UI:ShowView("party")
    end)
    r.equip:SetPoint("BOTTOMRIGHT", r, "BOTTOM", -6, 14)
    r.cont = W.Button(r, "Continue", 140, 26, function()
        ns.UI:EndBattle()
        ns.UI:ShowView("party")
    end)
    r.cont:SetPoint("BOTTOMLEFT", r, "BOTTOM", 6, 14)
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
    for _, f in ipairs(self.floaters) do f.life = 0 f.fs:Hide() end
    self.logLines = {}
    self.log:SetText("")
    self.results:Hide()
    self.resultsShown = false
    local c = run.dungeon.color
    self.fieldBg:SetColorTexture(c[1], c[2], c[3], 1)
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
end

function View:Stop()
    self.run = nil
    self.results:Hide()
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
    while #self.logLines > 4 do table.remove(self.logLines, 1) end
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
            self:Float(u, e.a:sub(1, 1):upper() .. e.a:sub(2), 0.7, 0.7, 0.7)
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
            local label = e.b == "Trash" and ("Wave " .. e.a) or e.b
            self:Banner(label)
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
    self:HandleEvents()

    -- tokens
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
            p:SetAlpha(u.dead and 0.5 or 1)
        end
    end

    local wave = run.state == "rest" and (run.waveIndex == 0 and "Preparing" or "Resting")
        or ("Wave " .. run.waveIndex .. "/" .. run:WaveCount())
    self.clock:SetText(string.format("%s  -  %d:%02d%s", wave, run.time / 60, run.time % 60,
        self.paused and "  |cffff8800(paused)|r" or ""))

    if run.finished and not self.resultsShown then
        self.resultsShown = true
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
        if i > 16 then
            right[#right + 1] = "...and " .. (#run.loot - 16) .. " more"
            break
        end
        right[#right + 1] = ns.Items.ColoredName(item)
    end
    r.right:SetText(table.concat(right, "\n"))
    r:Show()
end
