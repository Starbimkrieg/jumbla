-- Draft view: pick Tank, Healer and three DPS from two options each.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.draft = View

local ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "Damage" }

local function CreateCard(parent, index)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(300, 290)
    W.Backdrop(card, 0.1, 0.1, 0.12, 0.85)
    card.highlight = card:CreateTexture(nil, "HIGHLIGHT")
    card.highlight:SetAllPoints()
    card.highlight:SetColorTexture(1, 1, 1, 0.08)

    card.portrait = W.CircleIcon(card, 72)
    card.portrait:SetPoint("TOP", 0, -16)
    card.portrait:EnableMouse(false)

    card.title = W.Font(card, "GameFontNormalLarge")
    card.title:SetPoint("TOP", card.portrait, "BOTTOM", 0, -10)
    card.role = W.Font(card, "GameFontHighlight")
    card.role:SetPoint("TOP", card.title, "BOTTOM", 0, -4)
    card.info = W.Font(card, "GameFontHighlightSmall")
    card.info:SetPoint("TOP", card.role, "BOTTOM", 0, -6)

    card.abilities = {}
    for i = 1, 3 do
        local a = CreateFrame("Button", nil, card)
        a:SetSize(28, 28)
        a.tex = a:CreateTexture(nil, "ARTWORK")
        a.tex:SetAllPoints()
        a.label = W.Font(a, "GameFontHighlightSmall", nil, "LEFT")
        a.label:SetPoint("LEFT", a, "RIGHT", 6, 0)
        a:SetScript("OnEnter", function(self) W.AbilityTooltip(self, self.abilityId) end)
        a:SetScript("OnLeave", W.HideTooltip)
        card.abilities[i] = a
    end

    card.pick = W.Button(card, "Draft", 120, 24)
    card.pick:SetPoint("BOTTOM", 0, 12)
    card.pick:SetScript("OnClick", function() View:Pick(index) end)
    card:SetScript("OnClick", function() View:Pick(index) end)
    return card
end

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    self.frame = f

    self.header = W.Font(f, "GameFontNormalHuge", "Draft Your Party")
    self.header:SetPoint("TOP", 0, -6)
    self.sub = W.Font(f, "GameFontHighlight")
    self.sub:SetPoint("TOP", self.header, "BOTTOM", 0, -6)

    -- Picked-so-far row
    self.slots = {}
    for i, role in ipairs(ns.Draft.SLOTS) do
        local s = W.CircleIcon(f, 40)
        s:SetPoint("TOP", (i - 3) * 70, -64)
        s.label = W.Font(s, "GameFontHighlightSmall", ROLE_LABEL[role])
        s.label:SetPoint("TOP", s, "BOTTOM", 0, -4)
        self.slots[i] = s
    end

    self.cards = { CreateCard(f, 1), CreateCard(f, 2) }
    self.cards[1]:SetPoint("TOPRIGHT", f, "TOP", -20, -140)
    self.cards[2]:SetPoint("TOPLEFT", f, "TOP", 20, -140)

    self.reroll = W.Button(f, "Reroll", 160, 24, function()
        if ns.Draft.Reroll(ns.db.draft) then self:Refresh() end
    end)
    self.reroll:SetPoint("TOP", 0, -445)

    self.begin = W.Button(f, "Begin Adventure", 200, 30, function() self:Finish() end)
    self.begin:SetPoint("TOP", 0, -260)
end

function View:Pick(i)
    local d = ns.db.draft
    if not d or ns.Draft.IsDone(d) then return end
    ns.Draft.Pick(d, i)
    self:Refresh()
end

function View:Finish()
    local heroes = ns.Draft.Finish(ns.db.draft)
    ns.db.party = { heroes = heroes }
    ns.db.draft = nil
    ns.db.bag = {}
    ns.db.clears = {}
    ns.UI:ShowView("party")
end

local function FillCard(card, specKey)
    local spec = ns.Specs[specKey]
    local cls = ns.Classes[spec.class]
    card.portrait:SetClass(spec.class)
    card.title:SetText("|c" .. W.ClassHex(spec.class) .. ns.SpecLabel(specKey) .. "|r")
    card.role:SetText(W.ROLE_TEXT[spec.role] .. "  -  " .. (spec.position == "MELEE" and "Melee" or "Ranged"))
    local res = spec.resource or cls.resource
    card.info:SetText(ns.ARMOR_NAMES[cls.armor] .. " armor  |  " .. res:sub(1, 1) .. res:sub(2):lower()
        .. (spec.pet and ("  |  Pet: " .. ns.Pets[spec.pet].name) or ""))
    for i, a in ipairs(card.abilities) do
        local entry = spec.abilities[i]
        if entry then
            local def = ns.Abilities[entry.id]
            a.abilityId = entry.id
            a.tex:SetTexture(def.icon)
            a.label:SetText(def.name)
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", card, "TOPLEFT", 70, -170 - (i - 1) * 32)
            a:Show()
        else
            a:Hide()
        end
    end
end

function View:Refresh()
    if not ns.db.draft and not ns.db.party then ns.db.draft = ns.Draft.New() end
    local d = ns.db.draft
    if not d then return end
    local done = ns.Draft.IsDone(d)

    for i, s in ipairs(self.slots) do
        local pick = d.picks[i]
        if pick then
            s:SetClass(ns.Specs[pick].class)
            s.label:SetText(ns.Specs[pick].name)
            s:SetAlpha(1)
        else
            s:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark", 0.4, 0.4, 0.4)
            s.label:SetText(ROLE_LABEL[ns.Draft.SLOTS[i]])
            s:SetAlpha(i == d.slot and 1 or 0.4)
        end
    end

    if done then
        self.sub:SetText("Your party is ready.")
        for _, c in ipairs(self.cards) do c:Hide() end
        self.reroll:Hide()
        self.begin:Show()
        return
    end

    local role = ns.Draft.SLOTS[d.slot]
    self.sub:SetText(string.format("Slot %d of %d  -  choose your %s", d.slot, #ns.Draft.SLOTS, ROLE_LABEL[role]))
    for i, c in ipairs(self.cards) do
        FillCard(c, d.options[i])
        c:Show()
    end
    self.begin:Hide()
    self.reroll:Show()
    self.reroll:SetText(string.format("Reroll options (%d left)", d.rerolls))
    if d.rerolls > 0 then self.reroll:Enable() else self.reroll:Disable() end
end
