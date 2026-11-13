-- Draft view. Tank and Healer are picked one at a time from two big cards;
-- then all three DPS rows are shown together, two options per row.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.draft = View

local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "Damage" }

local function SpecInfo(specKey)
    local spec = ns.Specs[specKey]
    local cls = ns.Classes[spec.class]
    local res = spec.resource or cls.resource
    local armor = ns.ARMOR_NAMES[cls.armor] .. (cls.armorAt40 and (" (" .. ns.ARMOR_NAMES[cls.armorAt40] .. " at 40)") or "")
    local extras = {}
    if spec.pet then extras[#extras + 1] = "Pet: " .. ns.Pets[spec.pet].name end
    if cls.dualWield then extras[#extras + 1] = "Dual wield " .. (cls.dualWield <= 10 and "now" or ("at " .. cls.dualWield)) end
    if cls.weaponSkills then extras[#extras + 1] = ns.WEAPON_SKILL_NAMES[spec.mainhand[1]] end
    return armor .. "  |  " .. res:sub(1, 1) .. res:sub(2):lower(), table.concat(extras, "  |  ")
end

local function AbilityIcons(parent, n, size)
    local list = {}
    for i = 1, n do
        local a = CreateFrame("Button", nil, parent)
        a:SetSize(size, size)
        a.tex = a:CreateTexture(nil, "ARTWORK")
        a.tex:SetAllPoints()
        local hl = a:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.25)
        a.label = W.Font(a, "GameFontHighlightSmall", nil, "LEFT")
        a.label:SetPoint("LEFT", a, "RIGHT", 6, 0)
        a:SetScript("OnEnter", function(self) W.AbilityTooltip(self, self.abilityId) end)
        a:SetScript("OnLeave", W.HideTooltip)
        list[i] = a
    end
    return list
end

local function FillAbilities(list, specKey)
    local spec = ns.Specs[specKey]
    for i, a in ipairs(list) do
        local entry = spec.abilities[i]
        if entry then
            local def = ns.Abilities[entry.id]
            a.abilityId = entry.id
            a.tex:SetTexture(def.icon)
            a.label:SetText(def.name)
            a:Show()
        else
            a:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Big cards (Tank / Healer)
---------------------------------------------------------------------------

local function CreateBigCard(parent, index)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(320, 300)
    W.Backdrop(card, 0.1, 0.1, 0.12, 0.85)
    W.Highlight(card)
    card.portrait = W.CircleIcon(card, 80)
    card.portrait:SetPoint("TOP", 0, -16)
    card.portrait:EnableMouse(false)
    card.title = W.Font(card, "GameFontNormalLarge")
    card.title:SetPoint("TOP", card.portrait, "BOTTOM", 0, -10)
    card.role = W.Font(card, "GameFontHighlight")
    card.role:SetPoint("TOP", card.title, "BOTTOM", 0, -4)
    card.info = W.Font(card, "GameFontHighlightSmall")
    card.info:SetPoint("TOP", card.role, "BOTTOM", 0, -6)
    card.info:SetWidth(300)
    card.abilities = AbilityIcons(card, 3, 28)
    for i, a in ipairs(card.abilities) do a:SetPoint("TOPLEFT", card, "TOPLEFT", 80, -196 - (i - 1) * 32) end
    card.pick = W.Button(card, "Draft", 120, 24, function() View:PickBig(index) end)
    card.pick:SetPoint("BOTTOM", 0, 12)
    card:SetScript("OnClick", function() View:PickBig(index) end)
    return card
end

local function FillBigCard(card, specKey)
    local spec = ns.Specs[specKey]
    card.portrait:SetClass(spec.class)
    card.title:SetText("|c" .. W.ClassHex(spec.class) .. ns.SpecLabel(specKey) .. "|r")
    card.role:SetText(W.ROLE_TEXT[spec.role] .. "  -  " .. (spec.position == "MELEE" and "Melee" or "Ranged"))
    local a, b = SpecInfo(specKey)
    card.info:SetText(a .. (b ~= "" and ("\n" .. b) or ""))
    FillAbilities(card.abilities, specKey)
end

---------------------------------------------------------------------------
-- Compact cards (DPS rows)
---------------------------------------------------------------------------

local function CreateSmallCard(parent, row, index)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(370, 112)
    W.Backdrop(card, 0.1, 0.1, 0.12, 0.85)
    W.Highlight(card)
    card.selected = card:CreateTexture(nil, "BORDER")
    card.selected:SetPoint("TOPLEFT", -3, 3)
    card.selected:SetPoint("BOTTOMRIGHT", 3, -3)
    card.selected:SetColorTexture(1, 0.82, 0, 0.9)
    card.selected:SetDrawLayer("BACKGROUND", -1)
    card.portrait = W.CircleIcon(card, 60)
    card.portrait:SetPoint("LEFT", 14, 0)
    card.portrait:EnableMouse(false)
    card.title = W.Font(card, "GameFontNormalLarge", nil, "LEFT")
    card.title:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 14, 4)
    card.info = W.Font(card, "GameFontHighlightSmall", nil, "LEFT")
    card.info:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.info:SetWidth(270)
    card.abilities = AbilityIcons(card, 2, 24)
    card.abilities[1]:SetPoint("BOTTOMLEFT", card.portrait, "BOTTOMRIGHT", 14, -16)
    card:SetScript("OnClick", function()
        ns.Draft.Pick(ns.db.draft, index, row)
        View:Refresh()
    end)
    return card
end

local function FillSmallCard(card, specKey, selected)
    local spec = ns.Specs[specKey]
    card.portrait:SetClass(spec.class)
    card.title:SetText("|c" .. W.ClassHex(spec.class) .. ns.SpecLabel(specKey) .. "|r")
    local a, b = SpecInfo(specKey)
    card.info:SetText((spec.position == "MELEE" and "Melee" or "Ranged") .. "  |  " .. a .. (b ~= "" and ("\n" .. b) or ""))
    FillAbilities(card.abilities, specKey)
    card.selected:SetShown(selected)
end

---------------------------------------------------------------------------

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    self.frame = f

    self.header = W.Font(f, "GameFontNormalHuge", "Draft Your Party")
    self.header:SetPoint("TOP", 0, -4)
    self.sub = W.Font(f, "GameFontHighlight")
    self.sub:SetPoint("TOP", self.header, "BOTTOM", 0, -6)

    self.slots = {}
    for i, role in ipairs(ns.Draft.SLOTS) do
        local s = W.CircleIcon(f, 40)
        s:SetPoint("TOP", (i - 3) * 76, -58)
        s.label = W.Font(s, "GameFontHighlightSmall", ROLE_LABEL[role])
        s.label:SetPoint("TOP", s, "BOTTOM", 0, -4)
        self.slots[i] = s
    end

    -- Tank / healer stage
    self.big = { CreateBigCard(f, 1), CreateBigCard(f, 2) }
    self.big[1]:SetPoint("TOPRIGHT", f, "TOP", -20, -130)
    self.big[2]:SetPoint("TOPLEFT", f, "TOP", 20, -130)
    self.reroll = W.Button(f, "Reroll", 200, 24, function()
        if ns.Draft.Reroll(ns.db.draft) then self:Refresh() end
    end)
    self.reroll:SetPoint("TOP", 0, -446)

    -- DPS stage
    self.rows = {}
    for r = 1, ns.Draft.DPS_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(940, 112)
        row:SetPoint("TOP", 0, -128 - (r - 1) * 124)
        row.label = W.Font(row, "GameFontNormal", "DPS " .. r, "LEFT")
        row.label:SetPoint("LEFT", 0, 12)
        row.cards = { CreateSmallCard(row, r, 1), CreateSmallCard(row, r, 2) }
        row.cards[1]:SetPoint("LEFT", 60, 0)
        row.cards[2]:SetPoint("LEFT", row.cards[1], "RIGHT", 14, 0)
        row.reroll = W.Button(row, "Reroll", 80, 24, function()
            if ns.Draft.Reroll(ns.db.draft, r) then self:Refresh() end
        end)
        row.reroll:SetPoint("LEFT", row.cards[2], "RIGHT", 14, 0)
        self.rows[r] = row
    end
    self.rerollText = W.Font(f, "GameFontHighlight")
    self.rerollText:SetPoint("TOP", 0, -506)

    self.begin = W.Button(f, "Begin Adventure", 220, 32, function() self:Finish() end)
    self.begin:SetPoint("TOP", 0, -536)
end

function View:PickBig(i)
    local d = ns.db.draft
    if not d or ns.Draft.InDPSStage(d) then return end
    ns.Draft.Pick(d, i)
    self:Refresh()
end

function View:Finish()
    local d = ns.db.draft
    if not d or not ns.Draft.IsDone(d) then return end
    ns.db.party = { heroes = ns.Draft.Finish(d) }
    ns.db.draft = nil
    ns.db.bag = {}
    ns.db.clears = {}
    ns.UI:ShowView("party")
end

function View:Refresh()
    if not ns.db.draft and not ns.db.party then ns.db.draft = ns.Draft.New() end
    local d = ns.db.draft
    if not d then return end
    ns.Draft.Migrate(d)
    local dpsStage = ns.Draft.InDPSStage(d)

    local chosen = ns.Draft.Chosen(d)
    for i, s in ipairs(self.slots) do
        local pick = chosen[i]
        if pick then
            s:SetClass(ns.Specs[pick].class)
            s.label:SetText(ns.Specs[pick].name)
            s:SetAlpha(1)
        else
            s:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark", 0.4, 0.4, 0.4)
            s.label:SetText(ROLE_LABEL[ns.Draft.SLOTS[i]])
            local current = (i == d.slot) or (dpsStage and i > 2)
            s:SetAlpha(current and 1 or 0.4)
        end
    end

    for _, c in ipairs(self.big) do c:SetShown(not dpsStage) end
    self.reroll:SetShown(not dpsStage)
    for _, row in ipairs(self.rows) do row:SetShown(dpsStage) end
    self.rerollText:SetShown(dpsStage)

    if not dpsStage then
        local role = ns.Draft.SLOTS[d.slot]
        self.sub:SetText(string.format("Slot %d of %d  -  choose your %s", d.slot, #ns.Draft.SLOTS, ROLE_LABEL[role]))
        for i, c in ipairs(self.big) do FillBigCard(c, d.options[i]) end
        self.reroll:SetText(string.format("Reroll options (%d left)", d.rerolls))
        if d.rerolls > 0 then self.reroll:Enable() else self.reroll:Disable() end
        self.begin:Hide()
        return
    end

    self.sub:SetText("Choose one damage dealer from each row (you can change your mind until you begin)")
    for r, row in ipairs(self.rows) do
        for i, c in ipairs(row.cards) do FillSmallCard(c, d.dps[r][i], d.dpsPick[r] == i) end
        if d.rerolls > 0 then row.reroll:Enable() else row.reroll:Disable() end
    end
    self.rerollText:SetText(d.rerolls > 0
        and string.format("%d reroll%s left for the whole party - use it on any row", d.rerolls, d.rerolls == 1 and "" or "s")
        or "|cff888888No rerolls left|r")
    self.begin:Show()
    if ns.Draft.IsDone(d) then self.begin:Enable() else self.begin:Disable() end
end
