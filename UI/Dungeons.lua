-- Dungeon select view plus settings.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.dungeons = View

function ns.PartyLevel()
    local heroes = ns.db.party and ns.db.party.heroes or {}
    if #heroes == 0 then return 0 end
    local s = 0
    for _, h in ipairs(heroes) do s = s + h.level end
    return s / #heroes
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["JUMBLA_RESET"] = {
    text = "Start a new draft?\nYour current party and bag will be lost.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        if ns.UI then ns.UI:EndBattle() end
        ns.db.party, ns.db.draft, ns.db.bag, ns.db.clears = nil, nil, {}, {}
        if ns.UI then ns.UI:ShowView("draft") end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function CreateCard(parent, key)
    local d = ns.Dungeons[key]
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(740, 80)
    W.Backdrop(card, d.color[1], d.color[2], d.color[3], 0.9)
    card.name = W.Font(card, "GameFontNormalLarge", d.name, "LEFT")
    card.name:SetPoint("TOPLEFT", 14, -12)
    card.info = W.Font(card, "GameFontHighlight", nil, "LEFT")
    card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
    card.bosses = W.Font(card, "GameFontDisableSmall", nil, "LEFT")
    card.bosses:SetPoint("TOPLEFT", card.info, "BOTTOMLEFT", 0, -4)
    card.bosses:SetWidth(560)
    local names = {}
    for _, w in ipairs(d.waves) do if w.boss then names[#names + 1] = ns.Mobs[w.boss].name end end
    card.bosses:SetText("Bosses: " .. table.concat(names, ", "))
    card.enter = W.Button(card, "Enter", 120, 28, function() ns.UI:StartBattle(key) end)
    card.enter:SetPoint("RIGHT", -14, 0)
    card.key = key
    return card
end

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(760, 600)
    f:SetPoint("TOP", 0, -10)
    self.frame = f

    self.header = W.Font(f, "GameFontNormalHuge", "Choose a Dungeon")
    self.header:SetPoint("TOP", 0, -4)
    self.partyLine = W.Font(f, "GameFontHighlight")
    self.partyLine:SetPoint("TOP", self.header, "BOTTOM", 0, -6)

    self.cards = {}
    for i, key in ipairs(ns.DUNGEON_ORDER) do
        local c = CreateCard(f, key)
        c:SetPoint("TOP", 0, -60 - (i - 1) * 90)
        self.cards[i] = c
    end

    local y = -60 - #ns.DUNGEON_ORDER * 90 - 10
    local function Check(label, key, yOff)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 10, yOff)
        local t = W.Font(cb, "GameFontHighlight", label, "LEFT")
        t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb:SetScript("OnClick", function(s) ns.db.settings[key] = s:GetChecked() and true or false end)
        cb.key = key
        return cb
    end
    self.checks = {
        Check("Open automatically when you take a flight", "autoOpenOnTaxi", y),
        Check("Pause the battle when the flight lands", "pauseOnLanding", y - 28),
    }

    local reset = W.Button(f, "Start New Draft", 150, 24, function() StaticPopup_Show("JUMBLA_RESET") end)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
end

function View:Refresh()
    local lvl = ns.PartyLevel()
    self.partyLine:SetText(string.format("Party average level: %.1f", lvl))
    for _, c in ipairs(self.cards) do
        local d = ns.Dungeons[c.key]
        local clears = ns.db.clears[c.key] or 0
        c.info:SetText(string.format("Requires level %d   |   Enemies level %d-%d   |   %d waves   |   Cleared %d time%s",
            d.reqLevel, d.levels[1], d.bossLevel, #d.waves, clears, clears == 1 and "" or "s"))
        if lvl >= d.reqLevel then
            c.enter:Enable()
            c.enter:SetText("Enter")
            c:SetAlpha(1)
        else
            c.enter:Disable()
            c.enter:SetText("Level " .. d.reqLevel)
            c:SetAlpha(0.55)
        end
    end
    for _, cb in ipairs(self.checks) do cb:SetChecked(ns.db.settings[cb.key]) end
end
