local addonName, ns = ...

ns.MAX_PEERS = 96
ns.MAX_REQUESTS = 20
ns.MAX_RECIPES = 1600
ns.MAX_PROFESSIONS = 7
ns.CACHE_AGE = 14 * 86400
ns.bnetPeers = {}
local needsByItem = {}
local peerRefresh
local events = CreateFrame("Frame")

function ns.Integer(value, min, max)
    local number = tonumber(value)
    if number and number >= min and number <= max and number == math.floor(number) then
        return number
    end
end

function ns.Text(value, limit)
    if type(value) ~= "string" then return "" end
    value = value:gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    if #value <= limit then return value end
    local endByte = limit + 1
    while endByte > 1 and value:byte(endByte) >= 128 and value:byte(endByte) < 192 do
        endByte = endByte - 1
    end
    return value:sub(1, endByte - 1)
end

function ns.Character(value)
    if (issecretvalue and issecretvalue(value)) or type(value) ~= "string" or #value > 100 then return end
    local name = value:match("^([^%-]+)")
    if not name or name:find("[%c%d|]") then return end
    name = name:match("^ *(.-) *$"):gsub(" +", " ")
    if #name == 0 or #name > 48 then return end
    return strlower(name), name
end

function ns.Peer(key)
    local battleNet = ns.bnetPeers[key]
    if battleNet and ns.BattleNetContact(key) then
        local guildKey = ns.SharedGuildKey(key)
        if not guildKey or not ns.Peer(guildKey) then return battleNet end
    end
    local peer = ns.db.peers[key]
    if peer and peer.guild == ns.guildID and peer.seen > GetServerTime() - ns.CACHE_AGE
        and ns.GuildContact(key) then return peer end
end

function ns.PeerKeys()
    local cache, key = ns.db.peers
    return function()
        key = next(cache, key)
        if not key and cache == ns.db.peers then
            cache = ns.bnetPeers
            key = next(cache)
        end
        return key
    end
end

function ns.Reindex()
    wipe(needsByItem)
    for key in ns.PeerKeys() do
        local peer = ns.Peer(key)
        if peer then
            local address = ns.Contact(key)
            for id, request in pairs(peer.requests) do
                local needs = needsByItem[id] or {}
                needsByItem[id] = needs
                needs[#needs + 1] = { key = key, name = address, quantity = request.quantity, seen = peer.seen }
            end
        end
    end
    for _, needs in pairs(needsByItem) do
        table.sort(needs, function(a, b) return a.name < b.name end)
    end
end

function ns.StorePeer(key, snapshot)
    local cache = snapshot.guild and ns.db.peers or ns.bnetPeers
    if not cache[key] then
        local count, oldestKey, oldest = 0, nil, math.huge
        for peerKey, peer in pairs(cache) do
            count = count + 1
            if peer.seen < oldest then oldestKey, oldest = peerKey, peer.seen end
        end
        if count >= ns.MAX_PEERS then cache[oldestKey] = nil end
    end
    snapshot.seen = GetServerTime()
    cache[key] = snapshot
    if peerRefresh then return end
    peerRefresh = C_Timer.NewTimer(0.35, function()
        peerRefresh = nil
        ns.Reindex()
        ns.Changed()
    end)
end

function ns.ItemID(input)
    return ns.Integer(input:match("|Hitem:(%d+)[:|]") or input:match("^%s*(%d+)%s*$"), 1, 99999999)
end

function ns.SaveRequest(input, quantity, note)
    local id = ns.ItemID(input)
    quantity = ns.Integer(quantity, 1, 99999)
    if not id or not C_Item.DoesItemExistByID(id) then
        return nil, "Drop an item here or enter a valid item link or ID."
    end
    if not quantity then return nil, "Enter a whole quantity from 1 to 99,999." end
    if not ns.db.requests[id] then
        local count = 0
        for _ in pairs(ns.db.requests) do count = count + 1 end
        if count >= ns.MAX_REQUESTS then return nil, "Close a request before adding more." end
    end
    ns.db.requests[id] = { quantity = quantity, note = ns.Text(note, 80) }
    ns.LocalChanged()
    return id, "Request saved."
end

function ns.CloseRequest(id)
    ns.db.requests[id] = nil
    ns.LocalChanged()
end

function ns.LocalChanged()
    ns.Changed()
    ns.Publish()
end

local function AddItemNeeds(tooltip, data)
    if (issecretvalue and issecretvalue(data)) or not data then return end
    local id = data.id
    if (issecretvalue and issecretvalue(id)) or not id then return end
    local needs = needsByItem[id]
    if not needs then return end
    local now, shown, remaining = GetServerTime(), 0, 0
    for _, need in ipairs(needs) do
        if now - need.seen < ns.CACHE_AGE and ns.SyncContact(need.key) then
            if shown < 4 then
                if shown == 0 then
                    tooltip:AddLine(" ")
                    tooltip:AddLine("CraftCircle  |  Requested by", 0.94, 0.77, 0.44)
                end
                local cached = now - need.seen >= 86400 and "  (cached)" or ""
                tooltip:AddDoubleLine(need.name .. cached, "x" .. need.quantity, 0.84, 0.91, 0.86, 0.76, 0.94, 0.79)
                shown = shown + 1
            else
                remaining = remaining + 1
            end
        end
    end
    if remaining > 0 then
        tooltip:AddLine("+" .. remaining .. " more on the board", 0.65, 0.74, 0.68)
    end
end

local function Init()
    CraftCircleDB = CraftCircleDB or {}
    ns.db = CraftCircleDB
    for _, key in ipairs({ "requests", "peers", "recipes" }) do
        if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
    end
    ns.selfKey, ns.selfName = ns.Character(UnitFullName("player"))
    if ns.db.identityVersion ~= 2 then
        ns.db.identityVersion = 2
        ns.db.friends = nil
        wipe(ns.db.peers)
    end
    ns.StartSync()
    ns.StartGear()
    ns.StartProfessions()
    ns.StartSocial()
    ns.CreateLauncher()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddItemNeeds)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.AddGearUpgrades)
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, loaded)
    if event == "ADDON_LOADED" then
        if loaded ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not IsLoggedIn() then
            self:RegisterEvent("PLAYER_LOGIN")
            return
        end
    else
        self:UnregisterEvent("PLAYER_LOGIN")
    end
    Init()
end)

SLASH_CRAFTCIRCLE1 = "/craftcircle"
SLASH_CRAFTCIRCLE2 = "/ccircle"
SlashCmdList.CRAFTCIRCLE = function(command)
    if not ns.db then return end
    if strlower(ns.Text(command, 20)) == "scan" then
        local _, message = ns.CaptureRecipes()
        print("|cfff0c470CraftCircle|r  " .. message)
    else
        ns.Toggle()
    end
end
