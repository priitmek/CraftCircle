local _, ns = ...

local PREFIX = "CraftCircle3"
local PART_SIZE, MAX_PARTS, TIMEOUT = 215, 80, 180
local MAX_BOARD_PARTS, MAX_GUILD_TRANSFERS = 32, 32
local results = Enum.SendAddonMessageResult
local queue, queued, boardTransfers, lastCatalogReply = {}, {}, {}, {}
local lastBattleNetQuery, lastBattleNetReply, battleNetDirty = {}, {}, {}
local lastFindReply, lastFindAt, lastSearchAt = {}, -30, -30
local MAX_MATCHES, MAX_SEARCH_REPLIES = 12, 24
local activeSearch
local guildQueryAt, boardSentAt = -30, -30
local pendingCatalog, boardTimer, boardCleanup, sendTimer, ready
local pump, SendBattleNetBoard

local function Schedule(delay)
    if sendTimer or #queue == 0 then return end
    sendTimer = C_Timer.NewTimer(delay, function()
        sendTimer = nil
        pump()
    end)
end

local function Enqueue(slot, message, payload, peer)
    local battleNet = peer and ns.BattleNetContact(peer)
    if queued[slot] or #queue >= 128 or (not battleNet and not ns.guildID) then return false end
    local total = payload and math.ceil(#payload / PART_SIZE) or 1
    if total > MAX_PARTS then return false end
    queue[#queue + 1] = { slot = slot, message = message, payload = payload, part = 1,
        total = total, expires = GetTime() + TIMEOUT, guild = not battleNet and ns.guildID,
        battleNet = battleNet and battleNet.id, peer = peer }
    queued[slot] = true
    Schedule(0)
    return true
end

local function DropJob(index)
    queued[queue[index].slot] = nil
    table.remove(queue, index)
end

pump = function()
    local job = table.remove(queue, 1)
    if not job then return end
    local delay = 0.24
    local lockdown = C_ChatInfo.InChatMessagingLockdown()
    local battleNet = job.battleNet and ns.BattleNetContact(job.peer)
    local valid = job.battleNet and (lockdown or (battleNet and battleNet.id == job.battleNet))
        or (job.guild and job.guild == ns.guildID and IsInGuild() and (not job.peer or ns.GuildContact(job.peer)))
    if valid and GetTime() < job.expires then
        local message = job.message
        if job.payload then
            local start = (job.part - 1) * PART_SIZE + 1
            message = message .. job.part .. ":" .. job.total .. ":" .. job.payload:sub(start, start + PART_SIZE - 1)
        end
        local result
        if lockdown then
            result = results.AddOnMessageLockdown
        elseif job.battleNet then
            result = C_BattleNet.SendGameData(job.battleNet, PREFIX, message)
        else
            result = C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD")
        end
        if result == results.Success then
            job.part = job.part + 1
        elseif result == results.AddonMessageThrottle or result == results.ChannelThrottle then
            delay = 1.05
        elseif result == results.AddOnMessageLockdown then
            delay = 5
        else
            job.part = job.total + 1
        end
        if job.part <= job.total then
            queue[#queue + 1] = job
            Schedule(delay)
            return
        end
    end
    queued[job.slot] = nil
    if job.battleNet and job.slot == "board:" .. job.peer and battleNetDirty[job.peer] then
        battleNetDirty[job.peer] = nil
        SendBattleNetBoard(job.peer)
    end
    Schedule(delay)
end

local function QueueGear(key)
    local payload = ns.GearPayload()
    if not payload then return end
    local slot = key and ("gear:" .. key) or "gear:guild"
    for _, job in ipairs(queue) do
        if job.slot == slot then
            job.message = "E:" .. payload
            return
        end
    end
    Enqueue(slot, "E:" .. payload, nil, key)
end

local function EncodeText(value)
    return (value:gsub("[^A-Za-z0-9 ._'-]", function(byte) return ("~%02X"):format(byte:byte()) end))
end

local function DecodeText(value, limit)
    value = value:gsub("~(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    return ns.Text(value, limit)
end

local function Snapshot()
    local rows = { "B" }
    for id, request in pairs(ns.db.requests) do
        rows[#rows + 1] = table.concat({ "N", id, request.quantity, EncodeText(request.note) }, ",")
    end
    for _, profession in ipairs(ns.professions) do
        local count = ns.db.recipes[profession.id] and ns.db.recipes[profession.id].count or 0
        rows[#rows + 1] = table.concat({ "P", profession.id, profession.rank, profession.max, count, EncodeText(profession.name) }, ",")
    end
    return table.concat(rows, ";")
end

local function DecodeBoard(payload)
    if payload:sub(1, 1) ~= "B" or (#payload > 1 and payload:sub(2, 2) ~= ";") then return end
    local snapshot = { requests = {}, professions = {} }
    local requests, professions = 0, {}
    for row in payload:sub(2):gmatch("[^;]+") do
        local id, amount, note = row:match("^N,(%d+),(%d+),(.*)$")
        if id then
            id = ns.Integer(id, 1, 99999999)
            amount = ns.Integer(amount, 1, 99999)
            if not id or not amount or snapshot.requests[id] or requests >= ns.MAX_REQUESTS then return end
            snapshot.requests[id] = { quantity = amount, note = DecodeText(note, 80) }
            requests = requests + 1
        else
            local pid, rank, maxRank, count, name = row:match("^P,(%d+),(%d+),(%d+),(%d+),(.+)$")
            pid = ns.Integer(pid, 1, 99999)
            rank, maxRank = ns.Integer(rank, 0, 9999), ns.Integer(maxRank, 0, 9999)
            count = ns.Integer(count, 0, ns.MAX_RECIPES)
            if not pid or not rank or not maxRank or not count or professions[pid]
                or #snapshot.professions >= ns.MAX_PROFESSIONS then return end
            professions[pid] = true
            snapshot.professions[#snapshot.professions + 1] = {
                id = pid, rank = rank, max = maxRank, count = count, name = DecodeText(name, 64),
            }
        end
    end
    return snapshot
end

function ns.DecodeRecipes(payload)
    if payload == "R" then return {} end
    if not payload:match("^R,%d[%d,]*%d$") and not payload:match("^R,%d$") then return end
    if payload:find(",,", 1, true) then return end
    local recipes, previous = {}, 0
    for id in payload:gmatch("%d+") do
        id = ns.Integer(id, 1, 99999999)
        if not id or id <= previous or #recipes >= ns.MAX_RECIPES then return end
        recipes[#recipes + 1], previous = id, id
    end
    return recipes
end

local function Token()
    return ("%08x%06x"):format(GetServerTime(), math.random(0, 16777215))
end

function ns.CancelRecipeSearch()
    if not activeSearch then return end
    activeSearch.timer:Cancel()
    activeSearch = nil
    for index = #queue, 1, -1 do
        if queue[index].slot:sub(1, 5) == "find:" then DropJob(index) end
    end
end

function ns.SearchRecipes(query)
    if not ready or C_ChatInfo.InChatMessagingLockdown() or GetTime() - lastSearchAt < 2 then return false end
    ns.CancelRecipeSearch()
    local token = Token()
    local message = "F:" .. token .. ":" .. EncodeText(query)
    local sent = IsInGuild() and Enqueue("find:guild", message) or false
    for key in pairs(ns.bnetPeers) do
        if ns.BattleNetContact(key) and not ns.SharedGuildKey(key)
            and Enqueue("find:" .. key, message, nil, key) then sent = true end
    end
    if not sent then return false end
    lastSearchAt = GetTime()
    activeSearch = { token = token, replies = {}, count = 0, guild = ns.guildID }
    activeSearch.timer = C_Timer.NewTimer(25, function()
        ns.CancelRecipeSearch()
        ns.RecipeSearchFinished()
    end)
    return true
end

function ns.SyncGuild()
    if not ready or not IsInGuild() or GetTime() - guildQueryAt < 20 then return false end
    if not Enqueue("query", "G") then return false end
    guildQueryAt = GetTime()
    return true
end

function ns.SyncBattleNet(key)
    local now = GetTime()
    if not ready or not ns.BattleNetContact(key) or now - (lastBattleNetQuery[key] or -30) < 20 then return false end
    if not Enqueue("hello:" .. key, "G", nil, key) then return false end
    lastBattleNetQuery[key] = now
    return true
end

function ns.RefreshContacts()
    ns.RefreshSocial()
    if not ready then return "Addon messaging is unavailable." end
    if C_ChatInfo.InChatMessagingLockdown() then return "Sync is paused here. Try again outside the encounter." end
    local sent = ns.SyncGuild()
    for key in pairs(ns.bnet) do
        if ns.SyncBattleNet(key) then sent = true end
    end
    if sent then return "Sync requested. Online guildmates and Battle.net friends with CraftCircle can reply." end
    if not IsInGuild() and not next(ns.bnet) then return "No guild or online Battle.net contacts to sync." end
    return "Waiting for replies. Try Sync again in a few seconds."
end

function ns.CancelRecipeRequest(key)
    if not pendingCatalog or (key and pendingCatalog.key ~= key) then return end
    pendingCatalog.timer:Cancel()
    pendingCatalog = nil
    for index = #queue, 1, -1 do
        if queue[index].slot == "catalog" then DropJob(index) end
    end
end

function ns.RequestRecipes(key, profession)
    if not ready or not ns.selfKey or not ns.SyncContact(key) then return false end
    ns.CancelRecipeRequest()
    local token = Token()
    local battleNet = ns.BattleNetContact(key) ~= nil
    local target = battleNet and "@" or EncodeText(key)
    if not Enqueue("catalog", "Q:" .. token .. ":" .. profession .. ":" .. target, nil, key) then return false end
    pendingCatalog = { key = key, token = token, profession = profession, parts = {}, count = 0, battleNet = battleNet }
    pendingCatalog.timer = C_Timer.NewTimer(TIMEOUT, function()
        pendingCatalog = nil
        ns.RecipeError(key, profession, "No catalog received. Check that the crafter is online and retry.")
    end)
    return true
end

local function PublishGuild()
    if not ready or not ns.guildID or boardTimer then return end
    local delay = math.max(0, boardSentAt + 8 - GetTime()) + math.random() * 2
    boardTimer = C_Timer.NewTimer(delay, function()
        boardTimer = nil
        if not ns.guildID or not IsInGuild() then return end
        boardSentAt = GetTime()
        if Enqueue("board", "S:" .. Token() .. ":", Snapshot()) then
            QueueGear()
        else
            PublishGuild()
        end
    end)
end

SendBattleNetBoard = function(key, payload)
    if not ns.BattleNetContact(key) then return end
    local slot = "board:" .. key
    if queued[slot] then
        battleNetDirty[key] = true
    else
        if Enqueue(slot, "S:" .. Token() .. ":", payload or Snapshot(), key) then QueueGear(key) end
    end
end

function ns.Publish()
    PublishGuild()
    local payload
    for key in pairs(ns.bnetPeers) do
        payload = payload or Snapshot()
        SendBattleNetBoard(key, payload)
    end
end

function ns.ForgetSync(key)
    ns.ForgetGear(key)
    ns.CancelRecipeRequest(key)
    boardTransfers[key], lastCatalogReply[key] = nil, nil
    lastBattleNetQuery[key], lastBattleNetReply[key], battleNetDirty[key] = nil, nil, nil
    lastFindReply[key] = nil
    for index = #queue, 1, -1 do
        if queue[index].peer == key then DropJob(index) end
    end
end

function ns.ResetGuildSync()
    ns.ResetGuildGear()
    if pendingCatalog and not pendingCatalog.battleNet then ns.CancelRecipeRequest() end
    if boardTimer then boardTimer:Cancel(); boardTimer = nil end
    for index = #queue, 1, -1 do
        if not queue[index].battleNet then DropJob(index) end
    end
    for key in pairs(boardTransfers) do
        if not ns.bnet[key] then boardTransfers[key] = nil end
    end
    for key in pairs(lastCatalogReply) do
        if not ns.bnet[key] then lastCatalogReply[key] = nil end
    end
    for key in pairs(lastFindReply) do
        if not ns.bnet[key] then lastFindReply[key] = nil end
    end
    guildQueryAt, boardSentAt = -30, -30
end

local function Append(transfer, part, total, data)
    if (transfer.total and transfer.total ~= total) or transfer.parts[part] then return end
    transfer.total = total
    transfer.parts[part], transfer.count = data, transfer.count + 1
    if transfer.count == total then return table.concat(transfer.parts) end
end

local function ReceiveBoard(key, token, part, total, data, battleNet)
    local transfer = boardTransfers[key]
    if not transfer or transfer.token ~= token then
        local count = 0
        for _ in pairs(boardTransfers) do count = count + 1 end
        if not transfer and count >= MAX_GUILD_TRANSFERS then return end
        transfer = { token = token, parts = {}, count = 0 }
        boardTransfers[key] = transfer
        if not boardCleanup then
            boardCleanup = C_Timer.NewTimer(60, function()
                boardCleanup = nil
                wipe(boardTransfers)
            end)
        end
    end
    local payload = Append(transfer, part, total, data)
    if not payload then return end
    boardTransfers[key] = nil
    if not next(boardTransfers) and boardCleanup then boardCleanup:Cancel(); boardCleanup = nil end
    local snapshot = DecodeBoard(payload)
    if snapshot then
        if not battleNet then snapshot.guild = ns.guildID end
        ns.StorePeer(key, snapshot)
    end
end

local function ReceiveCatalogQuery(key, message, battleNet)
    local token, profession, target = message:match("^Q:(%x+):(%d+):(.+)$")
    if not token or #token ~= 14 or #target > 144 then return end
    if battleNet then
        if target ~= "@" then return end
    elseif DecodeText(target, 48) ~= ns.selfKey or not ns.GuildContact(key) then
        return
    end
    profession = ns.Integer(profession, 1, 99999)
    local now = GetTime()
    if not profession or now - (lastCatalogReply[key] or -30) < 6 then return end
    local recipes = ns.db.recipes[profession]
    if Enqueue("reply:" .. key, "D:" .. token .. ":", recipes and recipes.payload or "R", key) then
        lastCatalogReply[key] = now
    end
end

local function ReceiveFind(key, message)
    local token, raw = message:match("^F:(%x+):(.+)$")
    if not token or #token ~= 14 or #raw > 144 or not ns.SyncContact(key) then return end
    local query = strlower(DecodeText(raw, 48))
    if #query < 3 or not next(ns.db.recipes) then return end
    local now = GetTime()
    if now - (lastFindReply[key] or -30) < 4 or now - lastFindAt < 0.4 then return end
    lastFindReply[key], lastFindAt = now, now
    local rows = {}
    for _, match in ipairs(ns.FindSharedRecipes(query, MAX_MATCHES)) do
        rows[#rows + 1] = table.concat({ match.id, match.profession, match.item or 0,
            EncodeText(ns.Text(match.name, 80)) }, ",")
    end
    if #rows > 0 then Enqueue("matches:" .. key, "M:" .. token .. ":", table.concat(rows, ";"), key) end
end

local function ReceiveMatches(key, token, part, total, data, battleNet)
    local search = activeSearch
    if not search or search.token ~= token or not ns.SyncContact(key)
        or (not battleNet and search.guild ~= ns.guildID) then return end
    local transfer = search.replies[key]
    if transfer == true then return end
    if not transfer then
        if search.count >= MAX_SEARCH_REPLIES then return end
        search.count = search.count + 1
        transfer = { parts = {}, count = 0 }
        search.replies[key] = transfer
    end
    local payload = Append(transfer, part, total, data)
    if not payload then return end
    search.replies[key] = true
    local matches, seen = {}, {}
    for row in payload:gmatch("[^;]+") do
        local id, profession, item, name = row:match("^(%d+),(%d+),(%d+),(.+)$")
        id = ns.Integer(id, 1, 99999999)
        profession = ns.Integer(profession, 1, 99999)
        item = ns.Integer(item, 0, 99999999)
        if not id or not profession or not item or seen[id] or #matches >= MAX_MATCHES then return end
        seen[id] = true
        matches[#matches + 1] = { id = id, profession = profession, item = item ~= 0 and item or nil,
            name = DecodeText(name, 80) }
    end
    ns.ShowRecipeMatches(key, matches, not battleNet and ns.guildID)
end

local function Receive(_, event, prefix, message, channel, sender)
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(channel)
        or issecretvalue(sender) or issecretvalue(message)) then return end
    if prefix ~= PREFIX or type(message) ~= "string" or #message > 245 then return end
    local battleNet = event == "BN_CHAT_MSG_ADDON"
    local key
    if battleNet then
        if type(sender) ~= "number" then return end
        key = "bn:" .. sender
        if not ns.BattleNetContact(key) then return end
    else
        if channel ~= "GUILD" or not ns.guildID or not IsInGuild() then return end
        local address
        key, address = ns.Character(sender)
        if not key or key == ns.selfKey or C_FriendList.IsIgnored(address) then return end
    end
    if message == "G" or (battleNet and message == "H") then
        if battleNet then
            local now = GetTime()
            if now - (lastBattleNetReply[key] or -30) >= 8 then
                lastBattleNetReply[key] = now
                SendBattleNetBoard(key)
                if message == "G" and not ns.bnetPeers[key] then Enqueue("return:" .. key, "H", nil, key) end
            end
        else
            PublishGuild()
        end
        return
    end
    if message:sub(1, 2) == "Q:" then ReceiveCatalogQuery(key, message, battleNet); return end
    if message:sub(1, 2) == "F:" then ReceiveFind(key, message); return end
    if message:sub(1, 2) == "E:" then
        if battleNet or ns.GuildContact(key) then ns.ReceiveGear(key, message:sub(3), battleNet) end
        return
    end

    local kind, token, part, total, data = message:match("^([SDM]):(%x+):(%d+):(%d+):(.+)$")
    if not token or #token ~= 14 or #data > PART_SIZE then return end
    local limit = kind == "S" and MAX_BOARD_PARTS or kind == "M" and 16 or MAX_PARTS
    total = ns.Integer(total, 1, limit)
    part = total and ns.Integer(part, 1, total)
    if not part then return end
    if kind == "S" then ReceiveBoard(key, token, part, total, data, battleNet); return end
    if kind == "M" then ReceiveMatches(key, token, part, total, data, battleNet); return end

    local transfer = pendingCatalog
    if not transfer or transfer.token ~= token or transfer.key ~= key or transfer.battleNet ~= battleNet
        or not ns.SyncContact(key) then return end
    local payload = Append(transfer, part, total, data)
    if not payload then return end
    ns.CancelRecipeRequest(key)
    local recipes = ns.DecodeRecipes(payload)
    if recipes then ns.ShowRecipes(key, transfer.profession, recipes) end
end

function ns.StartSync()
    local registration = Enum.RegisterAddonMessagePrefixResult
    local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    ready = result == registration.Success or result == registration.DuplicatePrefix
    if not ready then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    if C_BattleNet and C_BattleNet.SendGameData then frame:RegisterEvent("BN_CHAT_MSG_ADDON") end
    frame:SetScript("OnEvent", Receive)
end
