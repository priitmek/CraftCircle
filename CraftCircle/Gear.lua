local _, ns = ...

local slots = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
    INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16, 17}, INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_2HWEAPON = {16}, INVTYPE_SHIELD = {17},
    INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18},
    INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}
local slotOrder = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}
local MAX_AGE = 7 * 86400
local guildGear, battleNetGear = {}, {}
local equipped, refresh
local TWO_HAND = 128

local function Plain(value)
    if not issecretvalue or not issecretvalue(value) then return value end
end

local function ItemKind(class, subclass, equip)
    return class * 32 + subclass + (equip == "INVTYPE_2HWEAPON" and TWO_HAND or 0)
end

local function ReadEquipment()
    local level = ns.Integer(Plain(UnitLevel("player")), 1, 999)
    if not level then return end
    local rows = { tostring(level) }
    for _, slot in ipairs(slotOrder) do
        local link = Plain(GetInventoryItemLink("player", slot))
        if link then
            local itemLevel = ns.Integer(Plain(C_Item.GetDetailedItemLevelInfo(link)), 1, 9999)
            local _, _, _, equip, _, class, subclass = C_Item.GetItemInfoInstant(link)
            class, subclass, equip = Plain(class), Plain(subclass), Plain(equip)
            if itemLevel and class and subclass and equip then
                local kind = ItemKind(class, subclass, equip)
                rows[#rows + 1] = itemLevel .. "." .. kind
            else
                rows[#rows + 1] = "-"
            end
        else
            local id = GetInventoryItemID("player", slot)
            local empty = (not issecretvalue or not issecretvalue(id)) and id == nil
            rows[#rows + 1] = empty and "0.0" or "-"
        end
    end
    return table.concat(rows, ",")
end

function ns.GearPayload()
    return equipped
end

function ns.ReceiveGear(key, payload, battleNet)
    local level, gear = payload:match("^(%d+),(.+)$")
    level = ns.Integer(level, 1, 999)
    if not level then return end
    local profile, index = { level = level, seen = GetServerTime(), guild = not battleNet and ns.guildID,
        contact = battleNet and ns.BattleNetContact(key) and ns.BattleNetContact(key).tag }, 0
    for entry in (gear .. ","):gmatch("(.-),") do
        index = index + 1
        local slot = slotOrder[index]
        if not slot then return end
        if entry ~= "-" then
            local itemLevel, kind = entry:match("^(%d+)%.(%d+)$")
            itemLevel, kind = ns.Integer(itemLevel, 0, 9999), ns.Integer(kind, 0, 255)
            if not itemLevel or not kind then return end
            profile[slot] = { level = itemLevel, kind = kind }
        end
    end
    if index ~= #slotOrder then return end
    local cache = battleNet and battleNetGear or guildGear
    if not cache[key] then
        local count, oldestKey, oldest = 0, nil, math.huge
        for peer, data in pairs(cache) do
            count = count + 1
            if data.seen < oldest then oldestKey, oldest = peer, data.seen end
        end
        if count >= ns.MAX_PEERS then cache[oldestKey] = nil end
    end
    cache[key] = profile
    ns.QueuePeerRefresh()
end

function ns.ForgetGear(key)
    guildGear[key], battleNetGear[key] = nil, nil
end

function ns.ResetGuildGear()
    if not ns.guildID then return end
    for key, profile in pairs(guildGear) do
        if profile.guild ~= ns.guildID then guildGear[key] = nil end
    end
end

function ns.StartGear()
    ns.db.guildGear = type(ns.db.guildGear) == "table" and ns.db.guildGear or {}
    ns.db.battleNetGear = type(ns.db.battleNetGear) == "table" and ns.db.battleNetGear or {}
    guildGear, battleNetGear = ns.db.guildGear, ns.db.battleNetGear
    local cutoff = GetServerTime() - MAX_AGE
    for _, cache in ipairs({ guildGear, battleNetGear }) do
        for key, profile in pairs(cache) do
            if profile.seen <= cutoff then cache[key] = nil end
        end
    end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, id, success)
        if event == "GET_ITEM_INFO_RECEIVED" then
            if not success then return end
            local worn
            for _, slot in ipairs(slotOrder) do
                if Plain(GetInventoryItemID("player", slot)) == id then worn = true; break end
            end
            if not worn then return end
        end
        if refresh then return end
        refresh = C_Timer.NewTimer(0.5, function()
            refresh = nil
            local payload = ReadEquipment()
            if payload and payload ~= equipped then
                equipped = payload
                ns.PublishGear()
            end
        end)
    end)
    equipped = ReadEquipment()
end

local function Upgrade(profile, targets, equip, kind, itemLevel)
    local best = 0
    for _, slot in ipairs(targets) do
        local worn = profile[slot]
        if worn then
            local sameType = worn.kind == kind
            local accessory = slot == 2 or (slot >= 11 and slot <= 15)
            if accessory or sameType then
                -- A two-hander also replaces a separate off-hand item.
                local offhand = profile[17]
                if equip ~= "INVTYPE_2HWEAPON" or (offhand and offhand.level == 0) then
                    best = math.max(best, itemLevel - worn.level)
                end
            end
        end
    end
    return best
end

local function ReadBoE(item)
    local name, _, _, _, minLevel, _, _, _, equip, _, _, class, subclass, bind = C_Item.GetItemInfo(item)
    equip, class, subclass, bind, minLevel = Plain(equip), Plain(class), Plain(subclass), Plain(bind), Plain(minLevel)
    local targets = slots[equip]
    if not targets or bind ~= Enum.ItemBind.OnEquip or not class or not subclass or not minLevel then return end
    local itemLevel = ns.Integer(Plain(C_Item.GetDetailedItemLevelInfo(item)), 1, 9999)
    if not itemLevel then return end
    return { name = Plain(name), targets = targets, equip = equip, kind = ItemKind(class, subclass, equip),
        level = itemLevel, minLevel = minLevel }
end

local function FindUpgrades(item)
    local now, matches, included = GetServerTime(), {}, {}
    local function Collect(cache, battleNet)
        for key, profile in pairs(cache) do
            if now - profile.seen < MAX_AGE and (battleNet or profile.guild == ns.guildID) then
                local contact = battleNet and ns.KnownBattleNetContact(key)
                if contact and contact.tag ~= profile.contact then contact = nil end
                local address = contact and contact.address or not battleNet and ns.GuildContact(key)
                local identity = battleNet and ns.SharedGuildKey(key) or key
                if address and profile.level >= item.minLevel and not included[identity] then
                    local delta = Upgrade(profile, item.targets, item.equip, item.kind, item.level)
                    if delta > 0 then
                        included[identity] = true
                        matches[#matches + 1] = { name = address, delta = delta,
                            cached = ns.ContactOffline(key) or now - profile.seen >= 1800 }
                    end
                end
            end
        end
    end
    Collect(guildGear, false)
    Collect(battleNetGear, true)
    table.sort(matches, function(a, b)
        if a.delta == b.delta then return a.name < b.name end
        return a.delta > b.delta
    end)
    return matches
end

function ns.BagBoEs(requestItem)
    local items, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = Plain(C_Container.GetContainerItemInfo(bag, slot))
            if info and Plain(info.isBound) == false then
                local link, id = Plain(info.hyperlink), Plain(info.itemID)
                if link and id and not seen[link] then
                    seen[link] = true
                    local item = ReadBoE(link)
                    if item and item.name then
                        items[#items + 1] = { link = link, id = id, name = item.name, level = item.level,
                            matches = FindUpgrades(item) }
                    elseif not Plain(C_Item.GetItemInfo(link)) then
                        requestItem(id)
                    end
                end
            end
        end
    end
    return items
end

function ns.AddGearUpgrades(tooltip, data)
    if not next(guildGear) and not next(battleNetGear) then return end
    data = Plain(data)
    if not data then return end
    local id, guid, link = Plain(data.id), Plain(data.guid), Plain(data.hyperlink)
    if not id or (issecretvalue and (issecretvalue(data.guid) or issecretvalue(data.hyperlink))) then return end
    if guid then
        local location = Plain(C_Item.GetItemLocation(guid))
        if location and Plain(C_Item.IsBound(location)) ~= false then return end
        link = Plain(C_Item.GetItemLinkByGUID(guid)) or link
    end
    local item = ReadBoE(link or id)
    if not item then return end
    local matches = FindUpgrades(item)
    if #matches == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("CraftCircle  |  Potential item-level upgrades", 0.94, 0.77, 0.44)
    for index = 1, math.min(4, #matches) do
        local match = matches[index]
        tooltip:AddDoubleLine(match.name .. (match.cached and " (cached)" or ""), "+" .. match.delta .. " ilvl",
            0.84, 0.91, 0.86, 0.76, 0.94, 0.79)
    end
    if #matches > 4 then tooltip:AddLine("+" .. (#matches - 4) .. " more", 0.65, 0.74, 0.68) end
end
