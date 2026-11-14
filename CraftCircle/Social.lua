local _, ns = ...

ns.friends, ns.guild, ns.bnet = {}, {}, {}
local guildGUIDs = {}
local guildOnline = {}
local bnetDirty = true
local battleNetFriends = {}
local rosterReady, rosterRequested, rosterDirty, refreshTimer
local guildCount, friendCount = 0, 0
local ambiguousGuildNames = {}

function ns.GuildContact(key)
    local address = IsInGuild() and ns.guild[key]
    if address and not C_FriendList.IsIgnored(address) then return address end
end

function ns.Contact(key)
    if ambiguousGuildNames[key] then return end
    local battleNet = ns.KnownBattleNetContact(key)
    return battleNet and battleNet.address or ns.GuildContact(key) or ns.friends[key]
end

function ns.KnownBattleNetContact(key)
    local live = ns.BattleNetContact(key)
    if live then return live end
    local peer = ns.bnetPeers[key]
    local contact = peer and peer.contact
    if contact and battleNetFriends[contact.tag] and not C_FriendList.IsIgnored(contact.address) then
        return contact
    end
end

function ns.BattleNetContact(key)
    local contact = ns.bnet[key]
    if contact and not bnetDirty and BNConnected() and not C_FriendList.IsIgnored(contact.address) then
        return contact
    end
end

function ns.SharedGuildKey(key)
    local contact = ns.KnownBattleNetContact(key)
    if contact and contact.guid and guildGUIDs[contact.character] == contact.guid
        and ns.GuildContact(contact.character) then return contact.character end
end

function ns.SyncContact(key)
    return ns.GuildContact(key) or ns.BattleNetContact(key)
end

function ns.ContactKind(key)
    if ns.KnownBattleNetContact(key) then return "Battle.net friend" end
    if ns.friends[key] then return "WoW friend" end
    return "Guild member"
end

function ns.ContactOffline(key)
    if ns.KnownBattleNetContact(key) then return not ns.BattleNetContact(key) end
    return guildOnline[key] == false
end

local function ReadBattleNet()
    if not bnetDirty or C_ChatInfo.InChatMessagingLockdown() then return end
    local contacts, previous, friends = {}, ns.bnet, {}
    if BNConnected and BNConnected() and BNGetNumFriends and C_BattleNet and C_BattleNet.SendGameData then
        local total = BNGetNumFriends()
        local selfGUID = UnitGUID("player")
        local complete = total ~= nil
        for index = 1, total or 0 do
            local accountInfo = C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(index)
            local tag = accountInfo and accountInfo.battleTag
            if tag and tag ~= "" then friends[tag] = true else complete = false end
            for account = 1, C_BattleNet.GetFriendNumGameAccounts(index) or 0 do
                local info = C_BattleNet.GetFriendGameAccountInfo(index, account)
                if info and info.isOnline and info.clientProgram == "WoW" and type(info.gameAccountID) == "number" then
                    local character, address = ns.Character(info.characterName)
                    if character and info.playerGuid ~= selfGUID then
                        contacts["bn:" .. info.gameAccountID] = {
                            id = info.gameAccountID, character = character, address = address,
                            guid = info.playerGuid, realm = info.realmID, tag = tag ~= "" and tag or nil,
                        }
                    end
                end
            end
        end
        if complete then battleNetFriends = friends end
        for key, peer in pairs(ns.bnetPeers) do
            local saved = peer.contact
            local current = contacts[key]
            if not saved or (not current and not saved.tag) or (complete and not friends[saved.tag])
                or peer.seen <= GetServerTime() - ns.CACHE_AGE
                or (current and (current.tag ~= saved.tag or current.character ~= saved.character
                    or current.guid ~= saved.guid or current.realm ~= saved.realm)) then
                ns.bnetPeers[key] = nil
                ns.ForgetGear(key)
            end
        end
    end
    ns.bnet, bnetDirty = contacts, false
    for key, old in pairs(previous) do
        local current = contacts[key]
        if not current or old.character ~= current.character or old.guid ~= current.guid or old.realm ~= current.realm then
            ns.ForgetSync(key)
            previous[key] = nil
        end
    end
    for key in pairs(contacts) do
        if not previous[key] then ns.SyncBattleNet(key) end
    end
end

function ns.ContactCounts()
    if IsInGuild() and not rosterReady then return friendCount end
    return friendCount, guildCount
end

local function RefreshViews()
    local now = GetServerTime()
    for key, peer in pairs(ns.db.peers) do
        local wrongGuild = peer.guild and (not IsInGuild() or (ns.guildID and peer.guild ~= ns.guildID))
        local outsideRoster = rosterReady and not ns.GuildContact(key)
        if wrongGuild or outsideRoster or now - peer.seen >= ns.CACHE_AGE then
            ns.db.peers[key] = nil
        end
    end
    ns.Reindex()
    ns.Changed()
end

local function ReadFriends()
    local friends, ambiguous, count = {}, {}, 0
    local size = C_FriendList.GetNumFriends()
    if not size then return end
    for index = 1, size do
        local info = C_FriendList.GetFriendInfoByIndex(index)
        if info then
            local key, address = ns.Character(info.name)
            if key and friends[key] then
                ambiguous[key] = true
            elseif key and key ~= ns.selfKey and not C_FriendList.IsIgnored(address) then
                friends[key] = address
                count = count + 1
            end
        end
    end
    for key in pairs(ambiguous) do friends[key], count = nil, count - 1 end
    ns.friends, friendCount = friends, count
end

local function ReadClub(guildID, add)
    local ids = C_Club.GetClubMembers(guildID)
    if not ids or #ids == 0 then return false end
    for _, id in ipairs(ids) do
        local member = C_Club.GetMemberInfo(guildID, id)
        if not member or not ns.Character(member.name) then return false end
        local presence = Enum.ClubMemberPresence
        local connected
        if member.presence == presence.Offline or member.presence == presence.OnlineMobile then
            connected = false
        elseif member.presence == presence.Online or member.presence == presence.Away or member.presence == presence.Busy then
            connected = true
        end
        add(member.name, member.isSelf, member.guid, connected)
    end
    return true
end

local function RequestRoster()
    if GetTime() - (rosterRequested or -15) < 10 then return end
    rosterRequested = GetTime()
    C_GuildInfo.GuildRoster()
end

local function ReadGuild(readRoster)
    local previous = ns.guild
    local guildID, clubID
    if IsInGuild() then
        clubID = C_Club.GetGuildClubId()
        guildID = clubID
        if not guildID then
            local guildName = GetGuildInfo("player")
            if guildName then guildID = guildName .. "-" .. GetNormalizedRealmName() end
        end
    end
    local changed = guildID ~= ns.guildID
    if changed then
        ns.guildID = guildID
        ns.guild, guildCount, rosterReady = {}, 0, false
        wipe(guildGUIDs)
        wipe(guildOnline)
        wipe(ambiguousGuildNames)
        ns.ResetGuildSync()
        if guildID then
            rosterRequested = nil
            RequestRoster()
        end
        previous = ns.guild
    end
    if not guildID or not readRoster or C_ChatInfo.InChatMessagingLockdown() then return end
    local roster, seen, ambiguous, guids, online, count = {}, {}, {}, {}, {}, 0
    local function Add(name, isSelf, guid, connected)
        local key, address = ns.Character(name)
        if not key then return false end
        if isSelf then ns.selfKey, ns.selfName = key, address end
        if seen[key] then
            if roster[key] then count = count - 1 end
            roster[key], guids[key], ambiguous[key] = nil, nil, true
        elseif key ~= ns.selfKey and not isSelf then
            roster[key], count = address, count + 1
            guids[key] = guid
            online[key] = connected
        end
        seen[key] = true
        return true
    end

    if not clubID or not ReadClub(clubID, Add) then
        if changed then return end
        roster, seen, ambiguous, guids, online, count = {}, {}, {}, {}, {}, 0
        local size = GetNumGuildMembers()
        if not size or size == 0 then RequestRoster(); return end
        local selfGUID = UnitGUID("player")
        for index = 1, size do
            local name, _, _, _, _, _, _, _, connected, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
            if not Add(name, guid and guid == selfGUID, guid, connected) then return end
        end
    end
    ns.guild, ambiguousGuildNames, guildCount = roster, ambiguous, count
    guildGUIDs = guids
    guildOnline = online
    for key in pairs(previous) do
        if not roster[key] then ns.ForgetSync(key) end
    end
    if not rosterReady then
        rosterReady = true
        ns.SyncGuild()
    end
end

function ns.RefreshSocial()
    bnetDirty = true
    ReadGuild(true)
    ReadFriends()
    ReadBattleNet()
    RefreshViews()
end

local function Update()
    refreshTimer = nil
    local readRoster = rosterDirty
    rosterDirty = false
    ReadGuild(readRoster)
    ReadFriends()
    ReadBattleNet()
    RefreshViews()
end

function ns.StartSocial()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("FRIENDLIST_UPDATE")
    frame:RegisterEvent("IGNORELIST_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("CLUB_ADDED")
    frame:RegisterEvent("CLUB_REMOVED")
    frame:RegisterEvent("INITIAL_CLUBS_LOADED")
    frame:RegisterEvent("CLUB_MEMBERS_UPDATED")
    frame:RegisterEvent("CLUB_MEMBER_ADDED")
    frame:RegisterEvent("CLUB_MEMBER_REMOVED")
    frame:RegisterEvent("CLUB_MEMBER_UPDATED")
    frame:RegisterEvent("CLUB_MEMBER_PRESENCE_UPDATED")
    frame:RegisterEvent("BN_CONNECTED")
    frame:RegisterEvent("BN_DISCONNECTED")
    frame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
    frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event:sub(1, 3) == "BN_" then
            bnetDirty = true
            ReadBattleNet()
        elseif event == "PLAYER_ENTERING_WORLD" then
            bnetDirty = true
        end
        if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "INITIAL_CLUBS_LOADED"
            or (event:find("^CLUB_MEMBER") and unit == ns.guildID) then
            rosterDirty = true
        end
        if event == "PLAYER_GUILD_UPDATE" then
            if unit ~= "player" then return end
            ReadGuild()
            RefreshViews()
        end
        if not refreshTimer then refreshTimer = C_Timer.NewTimer(0.5, Update) end
    end)
    C_FriendList.ShowFriends()
    ns.RefreshSocial()
end
