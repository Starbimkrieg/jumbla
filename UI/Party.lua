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
    f:SetAllPoints()
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
    self.abilityButtons = {}
    for i = 1, 3 do
        local a = CreateFrame("Button", nil, stats)
        a:SetSize(26, 26)
        a:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 30, 8)
        a.tex = a:CreateTexture(nil, "ARTWORK")
        a.tex:SetAllPoints()
        a:SetScript("OnEnter", function(s) W.AbilityTooltip(s, s.abilityId) end)
        a:SetScript("OnLeave", W.HideTooltip)
        self.abilityButtons[i] = a
    end

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
        "Click: equip on selected hero   Shift+Right-click: discard", "LEFT")
    self.bagHint:SetPoint("LEFT", self.bagTitle, "RIGHT", 12, 0)

    local auto = W.Button(bag, "Auto-Equip Upgrades", 150, 22, function()
        local n = #ns.Loot.AutoEquip(Heroes(), ns.db.bag)
        ns.Print(n > 0 and (n .. " upgrade(s) equipped.") or "No upgrades found.")
        self:Refresh()
    end)
    auto:SetPoint("TOPRIGHT", -8, -4)
    local junk = W.Button(bag, "Discard Unusable", 130, 22, function() self:DiscardUnusable() end)
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
        else
            extra[#extra + 1] = { reason, 1, 0.2, 0.2 }
        end
    end
    -- Who would want it?
    for _, other in ipairs(Heroes()) do
        local v = ns.Hero.UpgradeValue(other, item)
        if v and v > 0.5 then extra[#extra + 1] = { "Upgrade for " .. other.name, 0.2, 1, 0.2 } end
    end
    extra[#extra + 1] = { "Shift+Right-click: discard", 0.6, 0.6, 0.6 }
    W.ItemTooltip(btn, item, extra)
end

function View:BagClick(btn, button)
    local item = btn.item
    if not item then return end
    if button == "RightButton" and IsShiftKeyDown() then
        for i, it in ipairs(ns.db.bag) do
            if it == item then table.remove(ns.db.bag, i) break end
        end
        W.HideTooltip()
        self:Refresh()
        return
    end
    if button ~= "LeftButton" then return end
    local h = self:Selected()
    if not h then return end
    local ok, reason = ns.Hero.CanEquip(h, item)
    if not ok then
        ns.Print(reason)
        return
    end
    for i, it in ipairs(ns.db.bag) do
        if it == item then table.remove(ns.db.bag, i) break end
    end
    for _, old in ipairs(ns.Hero.Equip(h, item)) do table.insert(ns.db.bag, old) end
    W.HideTooltip()
    self:Refresh()
end

function View:DiscardUnusable()
    local keep, removed = {}, 0
    for _, item in ipairs(ns.db.bag) do
        local usable = false
        for _, h in ipairs(Heroes()) do
            local cls = ns.Classes[h.class]
            local armorOk = not item.armorType or ns.ARMOR_RANK[item.armorType] <= ns.ARMOR_RANK[cls.armor]
            local weaponOk = not item.wtype or cls.weapons[item.wtype]
            if armorOk and weaponOk then usable = true end
        end
        if usable then keep[#keep + 1] = item else removed = removed + 1 end
    end
    ns.db.bag = keep
    ns.Print("Discarded " .. removed .. " item(s) nobody can use.")
    self:Refresh()
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
    local left = { "Health", resName, "Strength", "Agility", "Stamina", "Intellect", "Spirit", "Armor",
        "Attack Power", "Melee Crit", "Dodge", "Block", "Spell Crit", "Spell Power", "Healing", "Main Hand", "Ranged" }
    local w = d.weapon
    local r = d.rangedWeapon
    local right = {
        d.maxHP, d.resource == "MANA" and d.maxPower or 100, d.str, d.agi, d.sta, d.int, d.spi, d.armor,
        d.ap, pct(d.meleeCrit), pct(d.dodge),
        d.hasShield and (pct(d.blockChance) .. " / " .. d.blockValue) or "-",
        pct(d.spellCrit), d.spellPower, d.healPower,
        string.format("%d-%d @ %.1f", w.min, w.max, w.speed),
        r and string.format("%d-%d @ %.1f", r.min, r.max, r.speed) or "-",
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
            local ok = ns.Hero.CanEquip(sel, item)
            b.icon:SetVertexColor(1, ok and 1 or 0.35, ok and 1 or 0.35)
            local v = ns.Hero.UpgradeValue(sel, item)
            b.up:SetShown(v ~= nil and v > 0.5)
            b:Show()
        else
            b:Hide()
        end
    end
end
