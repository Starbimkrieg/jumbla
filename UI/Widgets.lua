-- Small UI helpers shared by every view.
local ADDON, ns = ...

local W = {}
ns.W = W
ns.Views = {}

local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FALLBACK_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}

function W.ClassColor(token)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    local cc = ns.Classes[token].color
    return cc[1], cc[2], cc[3]
end

function W.ClassHex(token)
    local r, g, b = W.ClassColor(token)
    return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function W.Font(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    if text then fs:SetText(text) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

function W.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 22)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Mouse-over highlight for Buttons (the HIGHLIGHT layer only shows on hover).
function W.Highlight(btn, alpha)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, alpha or 0.1)
    return hl
end

-- Named font objects at a given size (for the bigger battle text).
local fontCache = {}
function W.FontObject(size, flags)
    local key = size .. (flags or "")
    if fontCache[key] then return fontCache[key] end
    local f = CreateFont("JumblaFont" .. size .. (flags or ""):gsub(",", ""))
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
    fontCache[key] = f
    return f
end

function W.Text(parent, size, flags, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(W.FontObject(size, flags))
    if text then fs:SetText(text) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

function W.Backdrop(frame, r, g, b, a)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r or 0, g or 0, b or 0, a or 0.5)
    frame.bg = bg
    return bg
end

-- A round icon: class circle for heroes, masked icon for everything else,
-- with a colored ring behind it.
function W.CircleIcon(parent, size)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(size, size)

    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetPoint("CENTER")
    f.ring:SetSize(size + 4, size + 4)
    f.ring:SetColorTexture(1, 1, 1, 1)
    local ringMask = f:CreateMaskTexture()
    ringMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
    ringMask:SetAllPoints(f.ring)
    f.ring:AddMaskTexture(ringMask)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.mask = f:CreateMaskTexture()
    f.mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
    f.mask:SetAllPoints(f.icon)

    function f:SetClass(token)
        if self.masked then
            self.icon:RemoveMaskTexture(self.mask)
            self.masked = false
        end
        self.icon:SetTexture(CLASS_CIRCLES)
        local c = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]) or FALLBACK_TCOORDS[token]
        self.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        self.ring:SetVertexColor(W.ClassColor(token))
    end

    function f:SetIcon(path, r, g, b)
        self.icon:SetTexture(path)
        self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not self.masked then
            self.icon:AddMaskTexture(self.mask)
            self.masked = true
        end
        self.ring:SetVertexColor(r or 0.8, g or 0.1, b or 0.1)
    end

    function f:SetSizeAll(s)
        self:SetSize(s, s)
        self.ring:SetSize(s + 4, s + 4)
    end

    return f
end

function W.Bar(parent, width, height, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

W.POWER_COLORS = {
    MANA = { 0.0, 0.44, 1.0 }, RAGE = { 0.9, 0.1, 0.1 }, ENERGY = { 1.0, 0.9, 0.2 },
}

function W.ItemTooltip(owner, item, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(ns.Items.TooltipLines(item)) do
        if i == 1 then
            GameTooltip:SetText(line[1], line[2], line[3], line[4])
        else
            GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
        end
    end
    for _, line in ipairs(extra or {}) do
        GameTooltip:AddLine(line[1], line[2] or 0.6, line[3] or 0.8, line[4] or 1, true)
    end
    GameTooltip:Show()
end

function W.AbilityTooltip(owner, abilityId)
    local a = ns.Abilities[abilityId]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(a.name, 1, 1, 1)
    local cost = a.cost and a.cost > 0 and (a.cost .. " cost") or "No cost"
    local cast = a.channel and ("Channeled " .. a.channel .. " sec")
        or ((a.cast or 0) > 0 and (a.cast .. " sec cast") or "Instant")
    GameTooltip:AddDoubleLine(cost, cast, 1, 1, 1, 1, 1, 1)
    if (a.cd or 0) > 0 then GameTooltip:AddLine(a.cd .. " sec cooldown", 1, 1, 1) end
    GameTooltip:AddLine(a.desc, 1, 0.82, 0, true)
    GameTooltip:Show()
end

function W.HideTooltip() GameTooltip:Hide() end

-- Role text helper.
W.ROLE_TEXT = { TANK = "|cff66aaffTank|r", HEALER = "|cff66ff66Healer|r", DPS = "|cffff6666Damage|r" }
