-- Jumbla: Dungeon Draft
-- Core: namespace, saved variables, slash commands and flight hooks.

local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "0.1.0"

local DEFAULTS = {
    schema = 1,
    nextId = 1,
    party = nil,          -- { heroes = { hero, hero, ... } } once a draft is finished
    bag = {},             -- shared loot bag (item tables)
    gold = 0,             -- copper; earned from kills and selling, spent on weapon training
    clears = {},          -- [dungeonKey] = number of clears
    settings = {
        speed = 1,
        autoOpenOnTaxi = true,
        pauseOnLanding = true,
    },
}

local function ApplyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.InitDB(db)
    db = db or {}
    ApplyDefaults(DEFAULTS, db)
    ns.db = db
    return db
end

function ns.NewId()
    local id = ns.db.nextId
    ns.db.nextId = id + 1
    return id
end

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Jumbla|r: " .. tostring(msg))
    else
        print("Jumbla: " .. tostring(msg))
    end
end

function ns.Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function ns.Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Everything below needs the real game client (the headless simulator in
-- tools/ loads this file too, so bail out quietly when there is no UI).
if not CreateFrame then return end

local events = CreateFrame("Frame")
local wasOnTaxi = false

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        JumblaDB = ns.InitDB(JumblaDB)
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_CONTROL_LOST" then
        -- Taxi state is not always set on the same frame control is lost.
        C_Timer.After(0.5, function()
            if UnitOnTaxi("player") then
                wasOnTaxi = true
                if ns.db and ns.db.settings.autoOpenOnTaxi and ns.UI then
                    ns.UI:Show()
                end
            end
        end)
    elseif event == "PLAYER_CONTROL_GAINED" then
        if wasOnTaxi and not UnitOnTaxi("player") then
            wasOnTaxi = false
            if ns.db and ns.db.settings.pauseOnLanding and ns.UI then
                ns.UI:PauseBattle(true)
                ns.Print("You landed - battle paused.")
            end
        end
    end
end)

SLASH_JUMBLA1 = "/jumbla"
SLASH_JUMBLA2 = "/jb"
SlashCmdList.JUMBLA = function(msg)
    msg = (msg or ""):lower()
    if msg == "reset" then
        StaticPopup_Show("JUMBLA_RESET")
    elseif ns.UI then
        ns.UI:Toggle()
    end
end
