-- Main window and view switching.
local ADDON, ns = ...
local W = ns.W

local UI = {}
ns.UI = UI

local VIEW_ORDER = { "draft", "party", "dungeons", "battle" }

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "JumblaMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(1000, 720)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- Ctrl + mouse wheel scales the whole window.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        self:SetScale((ns.db.settings.scale or f:GetScale()) + delta * 0.05)
    end)
    f:Hide()
    table.insert(UISpecialFrames, "JumblaMainFrame")
    self.frame = f

    local title = W.Font(f, "GameFontHighlight", "Jumbla: Dungeon Draft")
    title:SetPoint("TOP", 0, -5)
    local hint = W.Font(f, "GameFontDisableSmall", "Ctrl + mouse wheel to resize", "RIGHT")
    hint:SetPoint("TOPRIGHT", -34, -32)

    self.tabs = {}
    local function Tab(label, view, x)
        local b = W.Button(f, label, 100, 22, function() self:ShowView(view) end)
        b:SetPoint("TOPLEFT", x, -28)
        self.tabs[view] = b
    end
    Tab("Party", "party", 12)
    Tab("Dungeons", "dungeons", 116)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 10, -56)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    self.content = content

    for _, name in ipairs(VIEW_ORDER) do
        local v = ns.Views[name]
        v:Create(content)
        v.frame:Hide()
    end
end

function UI:SetScale(scale)
    scale = ns.Clamp(scale, 0.5, 1.5)
    ns.db.settings.scale = scale
    self.frame:SetScale(scale)
end

-- First open: shrink to fit the screen if the window would be too tall.
function UI:ApplyScale()
    local scale = ns.db.settings.scale
    if not scale then
        local avail = UIParent:GetHeight() or 768
        scale = math.min(1, (avail * 0.92) / 720)
    end
    self:SetScale(scale)
end

function UI:InBattle()
    return ns.Views.battle.run ~= nil
end

function UI:ShowView(name)
    self:Create()
    if not ns.db.party and name ~= "draft" then name = "draft" end
    if self:InBattle() then name = "battle" end
    for _, n in ipairs(VIEW_ORDER) do ns.Views[n].frame:SetShown(n == name) end
    self.current = name
    local tabsEnabled = ns.db.party ~= nil and not self:InBattle()
    for view, b in pairs(self.tabs) do
        b:SetShown(ns.db.party ~= nil)
        if tabsEnabled and view ~= name then b:Enable() else b:Disable() end
    end
    ns.Views[name]:Refresh()
end

function UI:Show()
    self:Create()
    self:ApplyScale()
    self.frame:Show()
    self:ShowView(self.current or (ns.db.party and "party" or "draft"))
end

function UI:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function UI:StartBattle(key)
    local d = ns.Dungeons[key]
    if ns.PartyLevel() < d.reqLevel then
        ns.Print(d.name .. " requires an average party level of " .. d.reqLevel .. ".")
        return
    end
    local run = ns.Run.New(key, ns.db.party.heroes)
    ns.Views.battle:Start(run)
    self:ShowView("battle")
end

function UI:EndBattle()
    if not self.frame then return end
    ns.Views.battle:Stop()
end

function UI:PauseBattle(paused)
    if self.frame and self:InBattle() then ns.Views.battle:SetPaused(paused) end
end
