-- Party view: heroes, stats, equipment and the shared bag.
local ADDON, ns = ...
local W = ns.W

local View = {}
ns.Views.party = View

local BAG_COLS, BAG_ROWS, BAG_SIZE = 16, 3, 38

local function Heroes() return ns.db.party and ns.db.party.heroes or {} end

function View:Selected()
    local heroes = Heroes()
    self.selected = ns.Clamp(self.selected or 1, 1, math.max(1, #heroes))
    return heroes[self.selected]
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function CreateHeroRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(230, 56)
    W.Backdrop(row, 0.1, 0.1, 0.12, 0.8)
    row.sel = row:CreateTexture(nil, "BORDER")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.15)
    W.Highlight(row, 0.12)
    row.portrait = W.CircleIcon(row, 40)
    row.portrait:SetPoint("LEFT", 8, 0)
    row.portrait:EnableMouse(false)
    row.name = W.Font(row, "GameFontNormal", nil, "LEFT")
    row.name:SetPoint("TOPLEFT", row.portrait, "TOPRIGHT", 10, 0)
    row.spec = W.Font(row, "GameFontHighlightSmall", nil, "LEFT")
    row.spec:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.xp = W.Bar(row, 160, 6, 0.58, 0.0, 0.55)
    row.xp:SetPoint("TOPLEFT", row.spec, "BOTTOMLEFT", 0, -5)
    row:SetScript("OnClick", function()
        View.selected = i
        View:Refresh()
    end)
    return row
end

local function CreateSlotRow(parent, slot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(270, 30)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    W.Highlight(b, 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28)
    b.icon:SetPoint("LEFT")
    b.label = W.Font(b, "GameFontDisableSmall", ns.SLOT_NAMES[slot], "LEFT")
    b.label:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
    b.name = W.Font(b, "GameFontHighlightSmall", nil, "LEFT")
    b.name:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 0)
    b.name:SetWidth(230)
    b.slot = slot
    b:SetScript("OnEnter", function(self)
        local h = View:Selected()
        local item = h and h.gear[self.slot]
        if item then W.ItemTooltip(self, item, { { "Right-click: unequip to bag" } }) end
    end)
    b:SetScript("OnLeave", W.HideTooltip)
    b:SetScript("OnClick", function(self, button)
        local h = View:Selected()
        if button == "RightButton" and h and h.gear[self.slot] then
            table.insert(ns.db.bag, ns.Hero.Unequip(h, self.slot))
            View:Refresh()
        end
    end)
    return b
end

local function CreateBagButton(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BAG_SIZE - 4, BAG_SIZE - 4)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    b.up = W.Font(b, "NumberFontNormal", "+")
    b.up:SetPoint("TOPRIGHT", -1, -1)
    b.up:SetTextColor(0.2, 1, 0.2)
    b:SetScript("OnEnter", function(self) View:BagTooltip(self) end)
    b:SetScript("OnLeave", W.HideTooltip)
    b:SetScript("OnClick", function(self, button) View:BagClick(self, button) end)
    return b
end

function View:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(760, 600)
    f:SetPoint("TOP", 0, -10)
    self.frame = f
    self.page = 1

    self.rows = {}
    for i = 1, 5 do
        local r = CreateHeroRow(f, i)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 60)
        self.rows[i] = r
    end

    -- Stats column
    local stats = CreateFrame("Frame", nil, f)
    stats:SetPoint("TOPLEFT", 240, 0)
    stats:SetSize(220, 296)
    W.Backdrop(stats, 0.1, 0.1, 0.12, 0.8)
    self.statsTitle = W.Font(stats, "GameFontNormal", nil, "LEFT")
    self.statsTitle:SetPoint("TOPLEFT", 8, -8)
    self.statLeft = W.Font(stats, "GameFontHighlightSmall", nil, "LEFT")
    self.statLeft:SetPoint("TOPLEFT", 8, -28)
    self.statLeft:SetSpacing(3)
    self.statRight = W.Font(stats, "GameFontHighlightSmall", nil, "RIGHT")
    self.statRight:SetPoint("TOPRIGHT", -8, -28)
    self.statRight:SetSpacing(3)
    self.statLeft:SetSpacing(2)
    self.statRight:SetSpacing(2)
    self.abilityButtons = {}
    for i = 1, 3 do
        local a = CreateFrame("Button", nil, stats)
        a:SetSize(20, 20)
        a:SetPoint("TOPRIGHT", -6 - (i - 1) * 23, -4)
        a.tex = a:CreateTexture(nil, "ARTWORK")
        a.tex:SetAllPoints()
        W.Highlight(a, 0.25)
        a:SetScript("OnEnter", function(s) W.AbilityTooltip(s, s.abilityId) end)
        a:SetScript("OnLeave", W.HideTooltip)
        self.abilityButtons[i] = a
    end
    self.statsFrame = stats
    self.skillsToggle = W.Button(stats, "Weapon Skills", 110, 20, function()
        self.showSkills = not self.showSkills
        self:Refresh()
    end)
    self.skillsToggle:SetPoint("BOTTOMRIGHT", -6, 6)
    self:CreateSkills(stats)

    -- Equipment column
    self.slotRows = {}
    for i, slot in ipairs(ns.SLOTS) do
        local r = CreateSlotRow(f, slot)
        r:SetPoint("TOPLEFT", 475, -(i - 1) * 33)
        self.slotRows[slot] = r
    end

    -- Bag
    local bag = CreateFrame("Frame", nil, f)
    bag:SetPoint("TOPLEFT", 0, -304)
    bag:SetPoint("BOTTOMRIGHT")
    W.Backdrop(bag, 0.1, 0.1, 0.12, 0.8)
    self.bagTitle = W.Font(bag, "GameFontNormal", nil, "LEFT")
    self.bagTitle:SetPoint("TOPLEFT", 8, -8)
    self.bagHint = W.Font(bag, "GameFontDisableSmall",
        "Click: equip   Right-click: equip off hand   Shift+Right-click: sell", "LEFT")
    self.bagHint:SetPoint("LEFT", self.bagTitle, "RIGHT", 12, 0)

    local auto = W.Button(bag, "Auto-Equip Upgrades", 150, 22, function()
        local n = #ns.Loot.AutoEquip(Heroes(), ns.db.bag)
        ns.Print(n > 0 and (n .. " upgrade(s) equipped.") or "No upgrades found.")
        self:Refresh()
    end)
    auto:SetPoint("TOPRIGHT", -8, -4)
    local junk = W.Button(bag, "Sell All", 100, 22, function() self:ConfirmSellAll() end)
    junk:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText("Sell All", 1, 1, 1)
        GameTooltip:AddLine("Sells every item in the bag that isn't an upgrade for someone in your party. "
            .. "Upgrades (marked +) are kept for Auto-Equip.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    junk:SetScript("OnLeave", W.HideTooltip)
    junk:SetPoint("RIGHT", auto, "LEFT", -6, 0)

    self.bagButtons = {}
    for i = 1, BAG_COLS * BAG_ROWS do
        local b = CreateBagButton(bag, i)
        local col, row = (i - 1) % BAG_COLS, math.floor((i - 1) / BAG_COLS)
        b:SetPoint("TOPLEFT", 12 + col * BAG_SIZE, -36 - row * BAG_SIZE)
        self.bagButtons[i] = b
    end
    self.prev = W.Button(bag, "<", 26, 22, function() self.page = self.page - 1 self:Refresh() end)
    self.prev:SetPoint("BOTTOMRIGHT", -40, 8)
    self.next = W.Button(bag, ">", 26, 22, function() self.page = self.page + 1 self:Refresh() end)
    self.next:SetPoint("BOTTOMRIGHT", -8, 8)
    self.pageText = W.Font(bag, "GameFontHighlightSmall")
    self.pageText:SetPoint("RIGHT", self.prev, "LEFT", -8, 0)
    self.goldText = W.Font(bag, "GameFontHighlight", nil, "LEFT")
    self.goldText:SetPoint("BOTTOMLEFT", 10, 12)
end

---------------------------------------------------------------------------
-- Bag interaction
---------------------------------------------------------------------------

function View:BagTooltip(btn)
    local item = btn.item
    if not item then return end
    local h = self:Selected()
    local extra = {}
    if h then
        local ok, reason = ns.Hero.CanEquip(h, item)
        if ok then
            extra[#extra + 1] = { "Click: equip on " .. h.name }
            local cur = h.gear[item.slot]
            if cur then extra[#extra + 1] = { "Currently: " .. cur.name, 0.7, 0.7, 0.7 } end
            if item.hand == "1H" then
                local okOH, whyOH = ns.Hero.CanEquip(h, item, "OFFHAND")
                extra[#extra + 1] = okOH and { "Right-click: equip in off hand" } or { whyOH, 0.7, 0.7, 0.7 }
            end
        else
            extra[#extra + 1] = { reason, 1, 0.2, 0.2 }
        end
        local skill = item.wtype and ns.Hero.UsesWeaponSkills(h) and ns.WEAPON_SKILL_NAMES[item.wtype]
            and ns.Hero.Skill(h, item.wtype)
        if skill then
            extra[#extra + 1] = { string.format("%s skill: %d / %d", h.name, skill, ns.Hero.MaxSkill(h)), 0.7, 0.7, 0.7 }
        end
    end
    -- Who would want it?
    for _, other in ipairs(Heroes()) do
        local v = ns.Hero.UpgradeValue(other, item)
        if v and v > 0.5 then extra[#extra + 1] = { "Upgrade for " .. other.name, 0.2, 1, 0.2 } end
    end
    extra[#extra + 1] = { "Shift+Right-click: sell", 0.6, 0.6, 0.6 }
    W.ItemTooltip(btn, item, extra)
end

function View:BagClick(btn, button)
    local item = btn.item
    if not item then return end
    if button == "RightButton" and IsShiftKeyDown() then
        self:Sell(item)
        W.HideTooltip()
        self:Refresh()
        return
    end
    local slot = item.slot
    if button == "RightButton" then
        if item.hand ~= "1H" then return end   -- right-click puts a one-hander in the off hand
        slot = "OFFHAND"
    elseif button ~= "LeftButton" then
        return
    end
    local h = self:Selected()
    if not h then return end
    local ok, reason = ns.Hero.CanEquip(h, item, slot)
    if not ok then
        ns.Print(reason)
        return
    end
    for i, it in ipairs(ns.db.bag) do
        if it == item then table.remove(ns.db.bag, i) break end
    end
    for _, old in ipairs(ns.Hero.Equip(h, item, slot)) do table.insert(ns.db.bag, old) end
    W.HideTooltip()
    self:Refresh()
end

function View:Sell(item)
    for i, it in ipairs(ns.db.bag) do
        if it == item then
            table.remove(ns.db.bag, i)
            ns.db.gold = (ns.db.gold or 0) + ns.Items.SellValue(item)
            return
        end
    end
end

-- Items in the bag that are not an upgrade for anyone (what Sell All sells).
function View:SellAllCandidates()
    local sell, copper = {}, 0
    for _, item in ipairs(ns.db.bag) do
        local upgrade = false
        for _, h in ipairs(Heroes()) do
            local v = ns.Hero.UpgradeValue(h, item)
            if v and v > 0.5 then upgrade = true break end
        end
        if not upgrade then
            sell[item] = true
            copper = copper + ns.Items.SellValue(item)
        end
    end
    return sell, copper
end

function View:ConfirmSellAll()
    local sell, copper = self:SellAllCandidates()
    local n = 0
    for _ in pairs(sell) do n = n + 1 end
    if n == 0 then
        ns.Print("Nothing to sell - everything in the bag is an upgrade for someone.")
        return
    end
    StaticPopup_Show("JUMBLA_SELL_ALL", n, ns.FormatMoney(copper))
end

function View:SellAll()
    local sell, copper = self:SellAllCandidates()
    local keep, n = {}, 0
    for _, item in ipairs(ns.db.bag) do
        if sell[item] then n = n + 1 else keep[#keep + 1] = item end
    end
    ns.db.bag = keep
    ns.db.gold = (ns.db.gold or 0) + copper
    ns.Print("Sold " .. n .. " item(s) for " .. ns.FormatMoney(copper) .. ".")
    self:Refresh()
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["JUMBLA_SELL_ALL"] = {
    text = "Sell %d item(s) that aren't upgrades for %s?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function() View:SellAll() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Weapon skills panel (shares the stats frame)
---------------------------------------------------------------------------

function View:CreateSkills(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, -26)
    p:SetPoint("BOTTOMRIGHT", 0, 30)
    self.skillsPanel = p
    self.skillNote = W.Font(p, "GameFontDisableSmall", nil, "LEFT")
    self.skillNote:SetPoint("TOPLEFT", 8, -2)
    self.skillNote:SetWidth(204)
    self.skillRows = {}
    for i = 1, #ns.WEAPON_SKILL_ORDER do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(204, 20)
        row:SetPoint("TOPLEFT", 8, -16 - (i - 1) * 21)
        row.label = W.Font(row, "GameFontHighlightSmall", nil, "LEFT")
        row.label:SetPoint("LEFT")
        row.value = W.Font(row, "GameFontHighlightSmall", nil, "RIGHT")
        row.value:SetPoint("RIGHT")
        row.train = W.Button(row, "Train", 92, 18, function(b)
            local h = self:Selected()
            local ok, why = ns.Hero.Train(h, b.wtype)
            if ok then
                ns.Print(h.name .. " learned " .. ns.WEAPON_SKILL_NAMES[b.wtype] .. ".")
            else
                ns.Print(why)
            end
            self:Refresh()
        end)
        row.train:SetPoint("RIGHT")
        if row.train.SetMotionScriptsWhileDisabled then row.train:SetMotionScriptsWhileDisabled(true) end
        row.train:SetScript("OnEnter", function(b)
            local h = self:Selected()
            local cost, have = ns.Hero.TrainCost(h), ns.db.gold or 0
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText("Train " .. ns.WEAPON_SKILL_NAMES[b.wtype], 1, 1, 1)
            GameTooltip:AddLine("Cost: " .. ns.FormatMoney(cost), 1, 1, 1)
            if have < cost then
                GameTooltip:AddLine("You have " .. ns.FormatMoney(have) .. " - need " .. ns.FormatMoney(cost - have) .. " more.",
                    1, 0.3, 0.3, true)
            end
            GameTooltip:AddLine("Starts at skill 1 and rises as you fight with it. Low skill means more misses.",
                1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        row.train:SetScript("OnLeave", W.HideTooltip)
        self.skillRows[i] = row
    end
end

function View:RefreshSkills(h)
    local cls = ns.Classes[h.class]
    if not ns.Hero.UsesWeaponSkills(h) then
        self.skillNote:SetText(cls.name .. "s can use any weapon their class allows - no training needed.")
        for _, row in ipairs(self.skillRows) do row:Hide() end
        return
    end
    local m = ns.Hero.MaxSkill(h)
    local dw = cls.dualWield and (ns.Hero.CanDualWield(h) and "Dual wield: yes" or ("Dual wield at " .. cls.dualWield))
        or "No dual wield"
    self.skillNote:SetText("Max skill " .. m .. "   |   " .. dw)
    local i = 0
    for _, wtype in ipairs(ns.WEAPON_SKILL_ORDER) do
        if cls.weapons[wtype] then
            i = i + 1
            local row = self.skillRows[i]
            row.label:SetText(ns.WEAPON_SKILL_NAMES[wtype])
            local v = ns.Hero.Skill(h, wtype)
            if v then
                row.value:SetText((v >= m and "|cff33ff33" or "|cffffd100") .. v .. " / " .. m .. "|r")
                row.value:Show()
                row.train:Hide()
            else
                row.value:Hide()
                row.train.wtype = wtype
                row.train:SetText("Train " .. ns.FormatMoneyShort(ns.Hero.TrainCost(h)))
                row.train:Show()
                if (ns.db.gold or 0) >= ns.Hero.TrainCost(h) then row.train:Enable() else row.train:Disable() end
            end
            row:Show()
        end
    end
    for j = i + 1, #self.skillRows do self.skillRows[j]:Hide() end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function pct(v) return string.format("%.1f%%", v) end

function View:RefreshStats(h)
    local d = ns.Hero.Compute(h)
    local spec = ns.Specs[h.spec]
    self.statsTitle:SetText("|c" .. W.ClassHex(h.class) .. h.name .. "|r  " .. W.ROLE_TEXT[spec.role])
    local resName = d.resource:sub(1, 1) .. d.resource:sub(2):lower()
    local function wtext(x) return x and string.format("%d-%d @ %.1f", x.min, x.max, x.speed) or "-" end
    local left = { "Health", resName, "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Armor ("
        .. ns.ARMOR_NAMES[ns.Hero.ArmorType(h)] .. ")", "Defense Rating", "Attack Power", "Crit (melee / spell)",
        "Dodge", "Block", "Spell Power / Healing", "Main Hand", "Off Hand", "Ranged" }
    local right = {
        d.maxHP, d.resource == "MANA" and d.maxPower or 100, d.str, d.agi, d.sta, d.int, d.spi, d.armor, d.def,
        d.ap, pct(d.meleeCrit) .. " / " .. pct(d.spellCrit), pct(d.dodge),
        d.hasShield and (pct(d.blockChance) .. " / " .. d.blockValue) or "-",
        d.spellPower .. " / " .. d.healPower,
        wtext(d.weapon), wtext(d.offWeapon), wtext(d.rangedWeapon),
    }
    for i, v in ipairs(right) do right[i] = tostring(v) end
    self.statLeft:SetText(table.concat(left, "\n"))
    self.statRight:SetText(table.concat(right, "\n"))
    local abilities = ns.Hero.Abilities(h)
    for i, a in ipairs(self.abilityButtons) do
        if abilities[i] then
            a.abilityId = abilities[i]
            a.tex:SetTexture(ns.Abilities[abilities[i]].icon)
            a:Show()
        else
            a:Hide()
        end
    end
end

function View:Refresh()
    local heroes = Heroes()
    local sel = self:Selected()
    for i, row in ipairs(self.rows) do
        local h = heroes[i]
        if h then
            row.portrait:SetClass(h.class)
            row.name:SetText("|c" .. W.ClassHex(h.class) .. h.name .. "|r")
            row.spec:SetText("Level " .. h.level .. " " .. ns.SpecLabel(h.spec))
            row.xp:SetValue(h.level >= ns.MAX_LEVEL and 1 or h.xp / ns.Hero.XPToLevel(h.level))
            row.sel:SetShown(h == sel)
            row:Show()
        else
            row:Hide()
        end
    end
    if not sel then return end
    self:RefreshStats(sel)
    self.statLeft:SetShown(not self.showSkills)
    self.statRight:SetShown(not self.showSkills)
    self.skillsPanel:SetShown(self.showSkills and true or false)
    self.skillsToggle:SetText(self.showSkills and "Stats" or "Weapon Skills")
    if self.showSkills then self:RefreshSkills(sel) end
    self.goldText:SetText(ns.FormatMoney(ns.db.gold or 0))

    for _, slot in ipairs(ns.SLOTS) do
        local r = self.slotRows[slot]
        local item = sel.gear[slot]
        if item then
            r.icon:SetTexture("Interface\\Icons\\" .. item.icon)
            r.name:SetText(ns.Items.ColoredName(item))
        else
            r.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            r.name:SetText("|cff666666Empty|r")
        end
    end

    local bag = ns.db.bag
    local perPage = BAG_COLS * BAG_ROWS
    local pages = math.max(1, math.ceil(#bag / perPage))
    self.page = ns.Clamp(self.page, 1, pages)
    self.bagTitle:SetText("Bag (" .. #bag .. ")")
    self.pageText:SetText(self.page .. " / " .. pages)
    if self.page > 1 then self.prev:Enable() else self.prev:Disable() end
    if self.page < pages then self.next:Enable() else self.next:Disable() end
    for i, b in ipairs(self.bagButtons) do
        local item = bag[(self.page - 1) * perPage + i]
        b.item = item
        if item then
            b.icon:SetTexture("Interface\\Icons\\" .. item.icon)
            local c = ns.QUALITY_COLORS[item.quality] or ns.QUALITY_COLORS[1]
            b.border:SetColorTexture(c[1], c[2], c[3], 0.9)
            local ok = ns.Hero.CanEquip(sel, item) or (item.hand == "1H" and ns.Hero.CanEquip(sel, item, "OFFHAND"))
            b.icon:SetVertexColor(1, ok and 1 or 0.35, ok and 1 or 0.35)
            local v = ns.Hero.UpgradeValue(sel, item)
            b.up:SetShown(v ~= nil and v > 0.5)
            b:Show()
        else
            b:Hide()
        end
    end
end
