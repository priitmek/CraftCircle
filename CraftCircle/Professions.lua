local _, ns = ...

local trade = C_TradeSkillUI
ns.professions = {}
local autoTimer, openedProfession, scanOpen

function ns.ObservedCatalogs()
    local now = GetServerTime()
    return function(records, key)
        repeat
            key = next(records, key)
            if not key then return end
            local record = records[key]
            if record.seen > now - ns.CACHE_AGE then return key, record end
        until false
    end, ns.db.observed, nil
end

local function ObserveLinkedProfession()
    if not trade.IsTradeSkillLinked or trade.IsDataSourceChanging() then return end
    local linked, owner = trade.IsTradeSkillLinked()
    if issecretvalue and (issecretvalue(linked) or issecretvalue(owner)) then return end
    if not linked then return end
    local key, name = ns.Character(owner)
    local info = trade.GetBaseProfessionInfo()
    if not key or key == ns.selfKey or C_FriendList.IsIgnored(name) or not info or not info.professionID
        or info.professionID <= 0 then return end
    local ids, seen = {}, {}
    for _, id in ipairs(trade.GetFilteredRecipeIDs() or {}) do
        local recipe = trade.GetRecipeInfo(id)
        if recipe and recipe.learned and not recipe.isDummyRecipe and not recipe.isRecraft and not seen[id] then
            ids[#ids + 1], seen[id] = id, true
            if #ids >= ns.MAX_RECIPES then break end
        end
    end
    if #ids == 0 then return end
    local records, identity = ns.db.observed, key .. ":" .. info.professionID
    local previous = records[identity]
    if previous then
        for _, id in ipairs(previous.recipes) do
            if #ids >= ns.MAX_RECIPES then break end
            if not seen[id] then ids[#ids + 1] = id end
        end
    else
        local size, oldest, oldestTime = 0, nil, math.huge
        for id, record in pairs(records) do
            size = size + 1
            if record.seen < oldestTime then oldest, oldestTime = id, record.seen end
        end
        if size >= 32 then records[oldest] = nil end
    end
    table.sort(ids)
    records[identity] = { owner = key, name = name, recipes = ids, seen = GetServerTime(),
        profession = { id = info.professionID, name = ns.Text(info.professionName, 64),
            rank = info.skillLevel or 0, max = info.maxSkillLevel or 0 } }
    ns.Changed()
end

function ns.CachedCatalog(key, profession)
    local peer = ns.Peer(key)
    local record = ns.db.catalogs[key .. ":" .. profession]
    if not peer or not record or record.seen <= GetServerTime() - ns.CACHE_AGE
        or record.guild ~= peer.guild or record.tag ~= (peer.contact and peer.contact.tag)
        or record.character ~= (peer.contact and peer.contact.character)
        or record.guid ~= (peer.contact and peer.contact.guid) then return end
    for _, info in ipairs(peer.professions) do
        if info.id == profession and info.count == record.count then return record end
    end
end

function ns.CatalogFingerprint(payload)
    local hash = 0
    for index = 1, #payload do
        hash = (hash * 131 + payload:byte(index)) % 2147483647
    end
    return ("%08x"):format(hash)
end

function ns.StoreCatalog(key, profession, payload, count)
    local peer = ns.Peer(key)
    if not peer then return end
    local catalogs, id = ns.db.catalogs, key .. ":" .. profession
    if not catalogs[id] then
        local size, oldest, oldestTime = 0, nil, math.huge
        for entry, record in pairs(catalogs) do
            size = size + 1
            if record.seen < oldestTime then oldest, oldestTime = entry, record.seen end
        end
        if size >= 32 then catalogs[oldest] = nil end
    end
    local contact = peer.contact
    catalogs[id] = { payload = payload, count = count, seen = GetServerTime(), guild = peer.guild,
        tag = contact and contact.tag, character = contact and contact.character, guid = contact and contact.guid }
end

function ns.RecipeName(id)
    local name = C_Spell.GetSpellName(id)
    if name and name ~= "" then return name end
    local info = trade.GetRecipeInfo(id)
    return info and info.name
end

function ns.RecipeOutput(id)
    local ok, output = pcall(trade.GetRecipeOutputItemData, id)
    local item = ok and output and ns.Integer(output.itemID, 1, 99999999)
    if item then return item end
    local available, schematic = pcall(trade.GetRecipeSchematic, id, false)
    if available and schematic then return ns.Integer(schematic.outputItemID, 1, 99999999) end
end

function ns.FindSharedRecipes(query, limit)
    local matches = {}
    local recipeID = tonumber(query)
    for _, profession in ipairs(ns.professions) do
        local catalog = ns.db.recipes[profession.id]
        if catalog then
            for rawID in catalog.payload:gmatch("%d+") do
                local id = tonumber(rawID)
                local name = ns.RecipeName(id)
                if id == recipeID or (name and strlower(name):find(query, 1, true)) then
                    matches[#matches + 1] = { id = id, profession = profession.id, item = ns.RecipeOutput(id),
                        name = name or ("Recipe #" .. id) }
                    if #matches == limit then return matches end
                end
            end
        end
    end
    return matches
end

function ns.RefreshProfessions()
    local professions, owned = {}, {}
    local indices = { GetProfessions() }
    for position = 1, ns.MAX_PROFESSIONS do
        local index = indices[position]
        if index then
            local name, icon, rank, maxRank, _, _, id = GetProfessionInfo(index)
            if name and id and id > 0 and not owned[id] then
                owned[id] = true
                professions[#professions + 1] = {
                    id = id, name = ns.Text(name, 64), icon = icon, rank = rank or 0, max = maxRank or 0,
                }
            end
        end
    end

    local previous = ns.professions
    local changed = #previous ~= #professions
    local ownershipChanged = changed
    for index, profession in ipairs(professions) do
        local old = previous[index]
        if not old or old.id ~= profession.id then ownershipChanged = true end
        if not old or old.id ~= profession.id or old.rank ~= profession.rank or old.max ~= profession.max then
            changed = true
        end
    end
    ns.professions = professions
    if IsLoggedIn() then
        for id in pairs(ns.db.recipes) do
            if not owned[id] then
                ns.db.recipes[id] = nil
                changed = true
            end
        end
    end
    if changed then ns.LocalChanged() end
    return ownershipChanged
end

local function Scan(id, includeOpen, keepExisting)
    local recipes, known = {}, {}
    local function Collect(spells, onlyLearned)
        for _, spellID in ipairs(spells) do
            if #recipes == ns.MAX_RECIPES then return end
            if not known[spellID] then
                local info = trade.GetRecipeInfo(spellID)
                if info and not info.isDummyRecipe and not info.isRecraft and not info.isGatheringRecipe
                    and (not onlyLearned or (info.learned and trade.IsRecipeInSkillLine(spellID, id))) then
                    recipes[#recipes + 1] = spellID
                    known[spellID] = true
                end
            end
        end
    end
    Collect(trade.GetProfessionSpells(id) or {})
    if includeOpen then Collect(trade.GetFilteredRecipeIDs() or {}, true) end
    if #recipes == 0 then return 0, false end
    local previous = ns.db.recipes[id]
    if keepExisting and previous then
        for _, spellID in ipairs(ns.DecodeRecipes(previous.payload) or {}) do
            if #recipes == ns.MAX_RECIPES then break end
            if not known[spellID] then recipes[#recipes + 1] = spellID end
        end
    end
    table.sort(recipes)
    local payload = "R," .. table.concat(recipes, ",")
    if previous and previous.payload == payload then return #recipes, false end
    ns.db.recipes[id] = { payload = payload, count = #recipes }
    return #recipes, true
end

local function OpenProfession()
    if ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame.CraftingPage:IsVisible()
        and Professions.InLocalCraftingMode() and not trade.IsRuneforging() and not trade.IsDataSourceChanging() then
        return Professions.GetEffectiveSkillLineID()
    end
end

local function ScheduleScan()
    if autoTimer or not ns.db.autoRecipes then return end
    autoTimer = C_Timer.NewTimer(0.5, function()
        autoTimer = nil
        if not ns.db.autoRecipes then return end
        local active = scanOpen and OpenProfession()
        scanOpen = nil
        local changed
        for _, profession in ipairs(ns.professions) do
            local _, updated = Scan(profession.id, profession.id == active, true)
            changed = changed or updated
        end
        if changed then ns.LocalChanged() end
    end)
end

function ns.StartProfessions()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    frame:RegisterEvent("NEW_RECIPE_LEARNED")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    frame:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_SHOW" then
            openedProfession = true
        elseif event == "TRADE_SKILL_LIST_UPDATE" then
            ObserveLinkedProfession()
            if not openedProfession or not OpenProfession() then return end
            openedProfession, scanOpen = nil, true
            ScheduleScan()
        elseif event == "NEW_RECIPE_LEARNED" then
            ScheduleScan()
        else
            local ownershipChanged = ns.RefreshProfessions()
            if event == "PLAYER_ENTERING_WORLD" or ownershipChanged then ScheduleScan() end
        end
    end)
    if IsLoggedIn() then ns.RefreshProfessions(); ScheduleScan() end
end

function ns.EnableRecipeSharing()
    ns.db.autoRecipes = true
    scanOpen = true
    ns.RefreshProfessions()
    ScheduleScan()
    ns.Changed()
end

function ns.CaptureRecipes()
    local id = OpenProfession()
    if not id then return nil, "Open one of your own crafting professions in WoW first." end
    ns.RefreshProfessions()
    local owner
    for _, profession in ipairs(ns.professions) do
        if profession.id == id then owner = profession; break end
    end
    if not owner then return nil, "This profession is unavailable for sharing." end
    local count, changed = Scan(id, true, true)
    if count == 0 then return nil, "No learned crafting recipes were available yet." end
    if changed then ns.LocalChanged() end
    local limit = count == ns.MAX_RECIPES and " (catalog limit reached)" or ""
    return true, "Shared " .. count .. " " .. owner.name .. " recipes" .. limit .. "."
end

function ns.UnshareRecipes()
    ns.db.autoRecipes = false
    if autoTimer then autoTimer:Cancel(); autoTimer = nil end
    wipe(ns.db.recipes)
    ns.LocalChanged()
end
