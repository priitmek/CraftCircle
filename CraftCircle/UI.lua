local _, ns = ...

local palette = {
    base = { 0.045, 0.062, 0.085 }, side = { 0.078, 0.105, 0.140 },
    surface = { 0.110, 0.144, 0.187 }, alternate = { 0.091, 0.120, 0.158 },
    hover = { 0.156, 0.223, 0.262 }, inset = { 0.054, 0.077, 0.106 },
    border = { 0.25, 0.31, 0.38 }, copper = { 0.54, 0.39, 0.25 }, text = { 0.98, 0.94, 0.87 },
    muted = { 0.69, 0.76, 0.83 }, gold = { 1.00, 0.78, 0.48 },
    mint = { 0.61, 0.88, 0.79 }, dark = { 0.13, 0.086, 0.055 },
    danger = { 1, 0.60, 0.54 },
}
local tabs = {
    { "Requests", "Request board", "Items your circle is looking for." },
    { "Crafters", "Crafter directory", "Find a profession or browse shared recipes." },
    { "My Circle", "My circle", "See your friends, guildmates, and their sync status." },
    { "BoE Gear", "BoE gear in your bags", "Select an item to see who might benefit from it." },
}
local ROWS, WIDTH, HEIGHT = 7, 900, 590
local ui, tab, page, selected, recipeView, recipeSearch = nil, 1, 1, nil, nil, nil
local Render, SelectTab
local fallbackIcon = "Interface/Icons/INV_Misc_QuestionMark"
local itemLoads = {}
local icons = { request = 133784, circle = 133452, craft = 136241, recipe = "Interface/Icons/INV_Scroll_03" }

local function Place(region, x, y, width, height)
    region:SetPoint("TOPLEFT", x, -y)
    if width and height then region:SetSize(width, height) end
    return region
end

local function Paint(texture, color)
    texture:SetColorTexture(unpack(color))
end

local function Block(parent, x, y, width, height, color)
    local texture = Place(parent:CreateTexture(nil, "BACKGROUND", nil, 1), x, y, width, height)
    Paint(texture, color)
    return texture
end

local function Label(parent, x, y, width, text, color, font, wrap)
    local label = Place(parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal"), x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(wrap == true)
    label:SetTextColor(unpack(color or palette.text))
    label:SetText(text)
    return label
end

local function Icon(parent, x, y, size, texture)
    local image = Place(parent:CreateTexture(nil, "ARTWORK"), x, y, size, size)
    image:SetTexture(texture or fallbackIcon)
    image:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return image
end

local function Gradient(texture, startColor, endColor)
    texture:SetTexture("Interface/Buttons/WHITE8X8")
    texture:SetGradient("HORIZONTAL", CreateColor(unpack(startColor)), CreateColor(unpack(endColor)))
end

local function Button(parent, x, y, width, height, title, handler, primary)
    local button = Place(CreateFrame("Button", nil, parent), x, y, width, height)
    button.fill = Block(button, 0, 0, width, height, primary and palette.gold or palette.surface)
    Block(button, 0, 0, width, 1, primary and palette.text or palette.border)
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 0.12)
    button:SetHighlightTexture(glow)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetTextColor(unpack(primary and palette.dark or palette.text))
    label:SetText(title)
    button.label = label
    button:SetScript("OnClick", handler)
    return button
end

local function Input(parent, x, y, width, maxLetters)
    local field = Place(CreateFrame("EditBox", nil, parent, "BackdropTemplate"), x, y, width, 30)
    field:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    field:SetBackdropColor(unpack(palette.base))
    field:SetBackdropBorderColor(unpack(palette.border))
    field:SetFontObject("GameFontHighlight")
    field:SetTextInsets(9, 9, 0, 0)
    field:SetAutoFocus(false)
    field:SetMaxLetters(maxLetters)
    field:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(palette.gold)) end)
    field:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(palette.border)) end)
    field:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return field
end

local function Status(message, errorState)
    if not ui then return end
    ui.status:SetText(message)
    ui.status:SetTextColor(unpack(errorState and palette.danger or palette.muted))
end

local function ItemName(id)
    return C_Item.GetItemInfo(id) or ("Item #" .. id)
end

local function RequestItem(id)
    if not itemLoads[id] and C_Item.DoesItemExistByID(id) then
        itemLoads[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

local function ItemIcon(id)
    local icon = C_Item.GetItemIconByID(id)
    if not icon or icon == 0 then icon = select(5, C_Item.GetItemInfoInstant(id)) end
    if not icon or icon == 0 then icon = select(10, C_Item.GetItemInfo(id)) end
    if icon and icon ~= 0 then return icon end
    RequestItem(id)
    return fallbackIcon
end

local function ItemTooltip(owner, id, link)
    if not id then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link or ("item:" .. id))
    GameTooltip:Show()
end

local function Age(peer)
    if not peer then return "No sync reply yet" end
    local minutes = math.max(0, math.floor((GetServerTime() - peer.seen) / 60))
    if minutes < 1 then return "Synced just now" end
    if minutes < 60 then return "Synced " .. minutes .. "m ago" end
    if minutes < 1440 then return "Synced " .. math.floor(minutes / 60) .. "h ago" end
    return "Cached " .. math.floor(minutes / 1440) .. "d ago"
end

local function RecipeName(id)
    return ns.RecipeName(id) or ("Recipe #" .. id)
end

local function RecipeEntry(id)
    return { key = id, title = RecipeName(id), detail = "Learned recipe", badge = "#" .. id,
        texture = icons.recipe, outputItem = ns.RecipeOutput(id), spell = id }
end

local function Match(text, query)
    return strlower(text):find(query, 1, true) ~= nil
end

local function BuildRows(query)
    local entries = {}
    if tab == 1 then
        local function AddRequests(key, name, requests)
            for id, request in pairs(requests) do
                local title = ItemName(id)
                if query == "" or Match(title .. " " .. name .. " " .. id .. " " .. request.note, query) then
                    entries[#entries + 1] = { key = key .. ":" .. id, owner = key, name = name, id = id,
                        title = title, detail = name, badge = "x" .. request.quantity,
                        request = request }
                end
            end
        end
        AddRequests(ns.selfKey, "You", ns.db.requests)
        for key in ns.PeerKeys() do
            local peer = ns.Peer(key)
            if peer then AddRequests(key, ns.Contact(key), peer.requests) end
        end
    elseif tab == 2 and recipeView then
        if query == "" then return recipeView.recipes or {} end
        for _, id in ipairs(recipeView.recipes or {}) do
            if Match(RecipeName(id) .. " " .. id, query) then
                entries[#entries + 1] = id
            end
        end
        return entries
    elseif tab == 2 and recipeSearch then
        for key, result in pairs(recipeSearch.matches) do
            local peer = key ~= ns.selfKey and ns.Peer(key)
            local owner = key == ns.selfKey and "You" or ns.Contact(key)
            if owner and owner == result.owner and (not result.guild or result.guild == ns.guildID)
                and (key == ns.selfKey or ns.SyncContact(key)) then
                local professions = key == ns.selfKey and ns.professions or peer and peer.professions or {}
                for _, match in ipairs(result.recipes) do
                    local profession
                    for _, info in ipairs(professions) do
                        if info.id == match.profession then profession = info; break end
                    end
                    entries[#entries + 1] = { key = key .. ":" .. match.id, owner = key, name = owner,
                        title = match.name, detail = profession and owner .. "  /  " .. profession.name or owner,
                        badge = "#" .. match.id, spell = match.id, outputItem = match.item, texture = icons.recipe }
                end
            end
        end
    elseif tab == 2 then
        local function AddProfessions(key, name, professions)
            for _, profession in ipairs(professions) do
                if query == "" or Match(profession.name .. " " .. name, query) then
                    local count = profession.count
                    if key == ns.selfKey then
                        local catalog = ns.db.recipes[profession.id]
                        count = catalog and catalog.count or 0
                    end
                    entries[#entries + 1] = { key = key .. ":" .. profession.id, owner = key, name = name,
                        title = profession.name, detail = name, badge = count > 0 and count .. " recipes" or "Skill " .. profession.rank,
                        texture = profession.icon or icons.craft, profession = profession, count = count }
                end
            end
        end
        AddProfessions(ns.selfKey, "You", ns.professions)
        for key in ns.PeerKeys() do
            local peer = ns.Peer(key)
            if peer then AddProfessions(key, ns.Contact(key), peer.professions) end
        end
    elseif tab == 4 then
        for _, item in ipairs(ns.BagBoEs(RequestItem)) do
            local names = {}
            for _, match in ipairs(item.matches) do names[#names + 1] = match.name end
            if query == "" or Match(item.name .. " " .. table.concat(names, " "), query) then
                entries[#entries + 1] = { key = item.link, id = item.id, link = item.link,
                    title = item.name, detail = #names > 0 and table.concat(names, ", ") or "No known upgrades",
                    badge = item.level .. " ilvl", matches = item.matches }
            end
        end
    else
        local function AddContact(key)
            local address = ns.Contact(key)
            if address and (query == "" or Match(address, query)) then
                local peer = ns.Peer(key)
                local shareable = ns.SyncContact(key)
                local cached = peer and ns.ContactOffline(key)
                entries[#entries + 1] = { key = key, title = address, shareable = shareable,
                    detail = ns.ContactKind(key) .. ((shareable or peer) and "  /  " .. Age(peer) or ""),
                    badge = cached and "OFFLINE · CACHED" or peer and "SYNCED" or shareable and "NOT SYNCED" or "ROSTER ONLY" }
            end
        end
        for key in pairs(ns.friends) do AddContact(key) end
        for key in pairs(ns.guild) do
            if not ns.friends[key] then AddContact(key) end
        end
        for key in pairs(ns.bnet) do
            if not ns.SharedGuildKey(key) then AddContact(key) end
        end
        for key in pairs(ns.bnetPeers) do
            if not ns.bnet[key] and ns.Peer(key) then AddContact(key) end
        end
    end
    table.sort(entries, function(a, b)
        if a.title == b.title then return a.key < b.key end
        return a.title < b.title
    end)
    return entries
end

local function OpenRecipes(entry)
    local profession = entry.profession
    recipeView = { owner = entry.owner, id = profession.id, title = profession.name, name = entry.name }
    selected, page = nil, 1
    ui.search:SetText("")
    if entry.owner == ns.selfKey then
        recipeView.recipes = ns.DecodeRecipes(ns.db.recipes[profession.id].payload)
    elseif ns.ContactOffline(entry.owner) then
        recipeView.error = "This crafter is offline. Open their catalog when they return."
    elseif not ns.RequestRecipes(entry.owner, profession.id) then
        recipeView.error = "Try loading the catalog again in a few seconds."
    end
    Render()
end

function ns.ShowRecipes(key, profession, recipes)
    if not recipeView or recipeView.owner ~= key or recipeView.id ~= profession then return end
    recipeView.recipes = recipes
    recipeView.error = nil
    Render()
end

function ns.RecipeError(key, profession, message)
    if not recipeView or recipeView.owner ~= key or recipeView.id ~= profession then return end
    recipeView.error = message
    Render()
end

local function CloseCatalog()
    if recipeView and recipeView.owner ~= ns.selfKey then ns.CancelRecipeRequest(recipeView.owner) end
    recipeView = nil
end

local function CloseRecipeSearch()
    ns.CancelRecipeSearch()
    recipeSearch = nil
end

local function StartRecipeSearch()
    local query = strlower(ns.Text(ui.search:GetText(), 48))
    if #query < 3 then Status("Enter at least three characters to search recipes.", true); return end
    CloseRecipeSearch()
    recipeSearch = { query = query, matches = {
        [ns.selfKey] = { owner = "You", recipes = ns.FindSharedRecipes(query, 12) },
    } }
    recipeSearch.waiting = ns.SearchRecipes(query)
    selected, page = nil, 1
    ui.search:ClearFocus()
    Status(recipeSearch.waiting and "Searching shared catalogs from online contacts." or "Showing matches from your shared catalogs.")
    Render()
end

function ns.ShowRecipeMatches(key, matches, guild)
    if not recipeSearch then return end
    recipeSearch.matches[key] = { recipes = matches, owner = ns.Contact(key), guild = guild }
    Render()
end

function ns.RecipeSearchFinished()
    if not recipeSearch then return end
    recipeSearch.waiting = false
    Status("Recipe search complete.")
    Render()
end

local function SetDetail(kicker, title, body)
    ui.kicker:SetText(kicker)
    ui.detailTitle:SetText(title)
    ui.detailBody:SetText(body)
end

local function DetailAction(button, title, handler)
    button.label:SetText(title)
    button:SetScript("OnClick", handler)
    button:Show()
end

local function ResetRequest()
    ui.item:SetText("")
    ui.quantity:SetText("1")
    ui.note:SetText("")
    ui.requestSave.label:SetText("Post request")
end

local function RenderDetail(entry)
    ui.form:SetShown(tab == 1)
    ui.detailAction:Hide()
    ui.altAction:Hide()
    if tab == 1 then
        if not entry then
            SetDetail("THE REQUEST BOARD", "Ask your circle", "Post an item and quantity. Guildmates and Battle.net friends can see it on their board and item tooltips.")
            return
        end
        SetDetail(entry.owner == ns.selfKey and "YOUR REQUEST" or "FRIEND REQUEST", entry.title,
            entry.name .. " needs " .. entry.request.quantity .. ".\n" .. entry.request.note)
        if entry.owner == ns.selfKey then
            DetailAction(ui.detailAction, "Edit request", function()
                ui.item:SetText(tostring(entry.id))
                ui.quantity:SetText(tostring(entry.request.quantity))
                ui.note:SetText(entry.request.note)
                ui.requestSave.label:SetText("Save changes")
                ui.quantity:SetFocus()
            end)
            DetailAction(ui.altAction, "Close request", function()
                ns.CloseRequest(entry.id)
                ResetRequest()
                Status("Request closed.")
            end)
        end
    elseif tab == 2 and recipeView then
        SetDetail("SHARED RECIPE CATALOG", entry and entry.title or recipeView.title,
            recipeView.name .. "\n" .. (entry and "Hover over the row to inspect the recipe." or
            "Select a recipe to see its crafter."))
    elseif tab == 2 and recipeSearch then
        if entry then
            SetDetail("RECIPE MATCH", entry.title, entry.detail .. "\nHover over the row to inspect the result.")
        else
            SetDetail("RECIPE SEARCH", "Who can craft it?", "Matches come from shared catalogs. Online guildmates and Battle.net friends can reply.")
        end
    elseif tab == 2 then
        if not entry then
            SetDetail("THE CRAFTER DIRECTORY", "Find a crafter", "Search for a profession or crafter. To find a specific recipe, enter its name and click Find recipes.")
        else
            local profession = entry.profession
            SetDetail("PROFESSION PROFILE", profession.name, entry.name .. "\nSkill " .. profession.rank ..
                " / " .. profession.max .. "\n" .. (entry.count > 0 and (entry.count .. " shared recipes") or "No recipe catalog shared."))
            if entry.count > 0 then
                DetailAction(ui.detailAction, "Browse recipes", function() OpenRecipes(entry) end)
            end
        end
    elseif tab == 4 then
        local lines = {}
        if entry then
            for index = 1, math.min(3, #entry.matches) do
                local match = entry.matches[index]
                lines[#lines + 1] = match.name .. "  +" .. match.delta .. " ilvl" .. (match.cached and " (cached)" or "")
            end
            if #entry.matches > 3 then lines[#lines + 1] = "+" .. (#entry.matches - 3) .. " more on hover" end
        end
        SetDetail("POTENTIAL UPGRADES", entry and entry.title or "Choose an item",
            #lines > 0 and table.concat(lines, "\n") or entry and "No upgrades found in synced gear."
            or "Unbound BoE gear in your bags appears here.")
    else
        local friends, guild = ns.ContactCounts()
        local battleNet = 0
        for key in pairs(ns.bnet) do
            if ns.BattleNetContact(key) then battleNet = battleNet + 1 end
        end
        local guildStatus = guild and guild .. " guildmates" or "Guild roster is loading"
        local body = guildStatus .. "\n" .. battleNet .. " Battle.net friends in WoW\n" ..
            friends .. " WoW character friends\n\nLists sync through guild and Battle.net addon data."
        SetDetail("AUTOMATIC SHARING", entry and entry.title or "Friends & guild",
            entry and (entry.detail .. "\n\n" .. (ns.Peer(entry.key) and "Lists are available on the board." or
                entry.shareable and "A reply will confirm that they have CraftCircle running." or
                "Sharing uses your guild and existing Battle.net friendships.")) or body)
    end
end

Render = function()
    if not ui or not ui:IsShown() then return end
    local entries = BuildRows(strlower(ns.Text(ui.search:GetText(), 64)))
    local pages = math.max(1, math.ceil(#entries / ROWS))
    page = math.min(page, pages)
    local current
    for _, entry in ipairs(entries) do
        if recipeView and entry == selected then current = RecipeEntry(entry); break end
        if not recipeView and entry.key == selected then current = entry; break end
    end
    for index, row in ipairs(ui.rows) do
        local entry = entries[(page - 1) * ROWS + index]
        if entry and recipeView then entry = RecipeEntry(entry) end
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            Paint(row.fill, entry.key == selected and palette.hover or index % 2 == 0 and palette.alternate or palette.surface)
            row.title:SetText(entry.title)
            row.detail:SetText(entry.detail)
            row.badge:SetText(entry.badge)
            local withIcon = tab ~= 3
            row.icon:SetShown(withIcon)
            row.iconFrame:SetShown(withIcon)
            row.contactDot:SetShown(not withIcon)
            Paint(row.contactDot, entry.badge == "SYNCED" and palette.mint or palette.border)
            row.title:ClearAllPoints()
            row.detail:ClearAllPoints()
            Place(row.title, withIcon and 46 or 26, 4)
            Place(row.detail, withIcon and 46 or 26, 20)
            if withIcon then
                local item = entry.id or entry.outputItem
                local texture = item and ItemIcon(item)
                row.icon:SetTexture(texture and texture ~= fallbackIcon and texture or entry.texture or fallbackIcon)
            end
            local activeBadge = tab ~= 3 or entry.badge == "SYNCED"
            row.badge:SetTextColor(unpack(activeBadge and palette.gold or palette.muted))
            Paint(row.badgeFill, activeBadge and palette.hover or palette.inset)
            row.marker:SetShown(entry.key == selected)
        end
    end
    local empty
    if #entries == 0 then
        if recipeSearch then
            empty = recipeSearch.waiting and "Searching shared recipes..." or "No shared recipes matched. Try another name."
        elseif recipeView and ui.search:GetText() == "" then
            empty = recipeView.error or (recipeView.recipes and "This catalog is empty." or
                "Waiting for the crafter's catalog.\nThey must be online.")
        elseif ui.search:GetText() ~= "" then
            empty = "No matches. Try another search."
        elseif tab == 1 then
            empty = "No active requests yet.\nPost an item or sync with your friends."
        elseif tab == 2 then
            empty = "No professions to display yet.\nLearn a profession or sync with a friend."
        elseif tab == 4 then
            empty = "No unbound BoE gear found in your bags."
        else
            empty = "No contacts found.\nClick Sync to refresh the game rosters."
        end
    end
    ui.empty:SetText(empty or "")
    ui.emptyPlate:SetShown(empty ~= nil)
    ui.emptyIcon:SetTexture(tab == 1 and icons.request or tab == 2 and icons.craft or icons.circle)
    local canFind = tab == 2 and not recipeView
    ui.find:SetShown(canFind)
    ui.listCount:SetShown(not canFind)
    ui.searchHint:SetText(canFind and "Search crafters or type a recipe name" or "Search this view")
    ui.listCount:SetText(#entries .. (recipeView and " RECIPES" or tab == 1 and " REQUESTS" or
        tab == 2 and " PROFESSIONS" or tab == 4 and " ITEMS" or " CONTACTS"))
    ui.page:SetText(page .. " / " .. pages)
    ui.prev:SetEnabled(page > 1)
    ui.next:SetEnabled(page < pages)
    ui.prev:SetAlpha(page > 1 and 1 or 0.45)
    ui.next:SetAlpha(page < pages and 1 or 0.45)
    ui.back:SetShown(recipeView ~= nil or recipeSearch ~= nil)
    ui.share:SetShown(canFind and not recipeSearch)
    ui.share.label:SetText(ns.db.autoRecipes and "Recipe sharing: On" or "Share learned recipes")
    ui.clearCatalogs:SetShown(tab == 3 and (ns.db.autoRecipes or next(ns.db.recipes) ~= nil))
    ui.heading:SetText(recipeView and recipeView.title or recipeSearch and "Recipe results" or tabs[tab][2])
    ui.subtitle:SetText(recipeView and ("Recipes shared by " .. recipeView.name)
        or recipeSearch and (#entries .. " matches for " .. recipeSearch.query) or tabs[tab][3])
    local contacts = 0
    for key in ns.PeerKeys() do
        if ns.Peer(key) then contacts = contacts + 1 end
    end
    ui.members:SetText(contacts .. " SYNCED")
    RenderDetail(current)
end

SelectTab = function(index)
    CloseCatalog()
    CloseRecipeSearch()
    tab, page, selected = index, 1, nil
    ui.search:SetText("")
    ui.search:ClearFocus()
    for i, button in ipairs(ui.tabs) do
        Paint(button.fill, i == tab and palette.hover or palette.surface)
        button.label:SetTextColor(unpack(i == tab and palette.gold or palette.text))
        button.indicator:SetShown(i == tab)
    end
    Render()
end

local function CreateUI()
    ui = CreateFrame("Frame", "CraftCircleWindow", UIParent, "BackdropTemplate")
    ui:SetSize(WIDTH, HEIGHT)
    ui:SetPoint("CENTER")
    ui:SetFrameStrata("DIALOG")
    ui:SetClampedToScreen(true)
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    ui:SetBackdropColor(unpack(palette.base))
    ui:SetBackdropBorderColor(unpack(palette.border))
    ui:Hide()
    table.insert(UISpecialFrames, "CraftCircleWindow")

    local drag = Place(CreateFrame("Frame", nil, ui), 0, 0, 570, 73)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() ui:StartMoving() end)
    drag:SetScript("OnDragStop", function() ui:StopMovingOrSizing() end)
    local hero = Block(ui, 1, 1, WIDTH - 2, 73, palette.surface)
    Gradient(hero, { 0.172, 0.211, 0.272, 1 }, { 0.063, 0.087, 0.120, 1 })
    Block(ui, 1, 1, WIDTH - 2, 2, palette.copper)
    Block(ui, 20, 13, 49, 49, palette.copper)
    Block(ui, 22, 15, 45, 45, palette.inset)
    Icon(ui, 26, 19, 37, icons.craft)
    local brand = Label(ui, 84, 14, 360, "CraftCircle", palette.text, "GameFontHighlightLarge")
    if GameFontHighlightLarge then brand:SetFont(GameFontHighlightLarge:GetFont(), 25, "") end
    Label(ui, 86, 48, 320, "F O R E V E R   /   T H E   W O R K S H O P", palette.gold, "GameFontNormalSmall")
    Block(ui, 600, 22, 134, 32, palette.inset)
    Block(ui, 612, 34, 5, 5, palette.mint)
    ui.members = Label(ui, 625, 32, 103, "", palette.mint, "GameFontNormalSmall")
    Button(ui, 747, 21, 92, 34, "Sync", function() Status(ns.RefreshContacts()) end, true)
    Button(ui, 849, 21, 30, 34, "X", function() ui:Hide() end)
    Block(ui, 1, 74, WIDTH - 2, 1, palette.border)

    ui.tabs = {}
    for index, definition in ipairs(tabs) do
        local button = Button(ui, 20 + (index - 1) * 128, 87, 118, 34, definition[1],
            function() SelectTab(index) end)
        button.indicator = Block(button, 0, 32, 118, 2, palette.gold)
        ui.tabs[index] = button
    end
    ui.back = Button(ui, 716, 87, 164, 34, "Back to professions", function() SelectTab(2) end)
    ui.back:Hide()

    Block(ui, 20, 135, 548, 422, palette.side)
    Block(ui, 20, 135, 548, 1, palette.border)
    ui.heading = Label(ui, 36, 151, 514, "", palette.text, "GameFontHighlightLarge")
    ui.subtitle = Label(ui, 36, 177, 514, "", palette.muted)
    ui.search = Input(ui, 36, 199, 336, 64)
    ui.searchHint = Label(ui.search, 10, 9, 312, "Search this view", palette.muted)
    ui.search:SetScript("OnTextChanged", function(self)
        ui.searchHint:SetShown(self:GetText() == "")
        page = 1
        Render()
    end)
    ui.search:SetScript("OnEnterPressed", function(self)
        if tab == 2 and not recipeView then StartRecipeSearch() else self:ClearFocus() end
    end)
    ui.find = Button(ui, 389, 199, 163, 30, "Find recipes", StartRecipeSearch, true)
    ui.listCount = Label(ui, 393, 209, 159, "", palette.gold, "GameFontNormalSmall")
    ui.listCount:SetJustifyH("RIGHT")
    ui.emptyPlate = Place(CreateFrame("Frame", nil, ui), 36, 241, 516, 276)
    Block(ui.emptyPlate, 0, 0, 516, 276, palette.inset)
    Block(ui.emptyPlate, 0, 0, 516, 1, palette.border)
    Block(ui.emptyPlate, 233, 63, 50, 50, palette.copper)
    Block(ui.emptyPlate, 234, 64, 48, 48, palette.side)
    ui.emptyIcon = Icon(ui.emptyPlate, 240, 70, 36, icons.request)
    ui.empty = Label(ui.emptyPlate, 24, 135, 468, "", palette.muted, "GameFontHighlight", true)
    ui.empty:SetJustifyH("CENTER")

    ui.rows = {}
    for index = 1, ROWS do
        local row = Place(CreateFrame("Button", nil, ui), 36, 241 + (index - 1) * 40, 516, 36)
        row.fill = Block(row, 0, 0, 516, 36, palette.surface)
        row.marker = Block(row, 0, 0, 2, 36, palette.gold)
        row.marker:Hide()
        row.iconFrame = Block(row, 8, 4, 28, 28, palette.border)
        row.icon = Icon(row, 9, 5, 26)
        row.contactDot = Block(row, 10, 15, 6, 6, palette.border)
        row.title = Label(row, 46, 4, 329, "", palette.text, "GameFontHighlight")
        row.detail = Label(row, 46, 20, 329, "", palette.muted, "GameFontNormalSmall")
        row.badgeFill = Block(row, 390, 7, 116, 22, palette.inset)
        row.badge = Label(row, 391, 12, 114, "", palette.mint, "GameFontNormalSmall")
        row.badge:SetJustifyH("CENTER")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        row:SetHighlightTexture(highlight)
        row:SetScript("OnClick", function(self)
            selected = self.entry.key
            Render()
        end)
        row:SetScript("OnEnter", function(self)
            if self.entry.id or self.entry.outputItem then
                ItemTooltip(self, self.entry.id or self.entry.outputItem, self.entry.link)
            elseif self.entry.spell then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.entry.spell)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        ui.rows[index] = row
    end
    ui.prev = Button(ui, 36, 525, 68, 25, "Previous", function() page = math.max(1, page - 1); Render() end)
    ui.page = Label(ui, 109, 533, 62, "", palette.muted, "GameFontNormalSmall")
    ui.page:SetJustifyH("CENTER")
    ui.next = Button(ui, 176, 525, 55, 25, "Next", function() page = page + 1; Render() end)
    ui.share = Button(ui, 370, 525, 182, 25, "Share learned recipes", function()
        if ns.db.autoRecipes then
            ns.UnshareRecipes()
            Status("Automatic sharing is off. Your shared catalogs were cleared.")
        else
            ns.EnableRecipeSharing()
            Status("Automatic sharing is on. CraftCircle will refresh your learned recipes.")
        end
    end, true)
    ui.clearCatalogs = Button(ui, 392, 525, 160, 25, "Unshare all recipes", function()
        ns.UnshareRecipes()
        Status("Shared recipe catalogs cleared.")
    end)

    Block(ui, 588, 135, 292, 422, palette.side)
    Block(ui, 588, 135, 292, 2, palette.copper)
    ui.kicker = Label(ui, 608, 153, 252, "", palette.gold, "GameFontNormalSmall")
    ui.detailTitle = Label(ui, 608, 177, 252, "", palette.text, "GameFontHighlightLarge", true)
    ui.detailTitle:SetHeight(36)
    ui.detailBody = Label(ui, 608, 220, 252, "", palette.muted, "GameFontHighlight", true)
    ui.detailBody:SetHeight(68)
    ui.detailAction = Button(ui, 608, 291, 122, 27, "", nil)
    ui.altAction = Button(ui, 738, 291, 122, 27, "", nil)

    ui.form = Place(CreateFrame("Frame", nil, ui), 608, 331, 252, 215)
    Block(ui.form, 0, 0, 250, 1, palette.border)
    Label(ui.form, 0, 12, 250, "POST OR UPDATE A REQUEST", palette.gold, "GameFontNormalSmall")
    Label(ui.form, 0, 33, 170, "Item link or ID", palette.text)
    Label(ui.form, 177, 33, 70, "Quantity", palette.text)
    ui.item = Input(ui.form, 0, 50, 168, 1024)
    ui.quantity = Input(ui.form, 177, 50, 73, 5)
    ui.quantity:SetNumeric(true)
    local preview = Icon(ui.form, 0, 83, 19)
    local itemHint = Label(ui.form, 26, 88, 226, "", palette.muted, "GameFontNormalSmall")
    ui.UpdateItemPreview = function()
        local id = ns.ItemID(ui.item:GetText())
        local name = id and C_Item.GetItemInfo(id)
        preview:SetTexture(id and ItemIcon(id) or icons.request)
        itemHint:SetText(name or "Drop, paste, or link an item here.")
    end
    ui.item:SetScript("OnTextChanged", ui.UpdateItemPreview)
    Label(ui.form, 0, 109, 250, "Note (optional)", palette.text)
    ui.note = Input(ui.form, 0, 126, 250, 80)
    ui.requestSave = Button(ui.form, 0, 171, 250, 34, "Post request", function()
        local id, message = ns.SaveRequest(ui.item:GetText(), ui.quantity:GetText(), ui.note:GetText())
        if id then
            ResetRequest()
            selected = ns.selfKey .. ":" .. id
            ui.search:SetText("")
            Render()
        end
        Status(message, not id)
    end, true)
    local function DropItem(self)
        local kind, id = GetCursorInfo()
        if issecretvalue and (issecretvalue(kind) or issecretvalue(id)) then return end
        if kind == "item" and ns.Integer(id, 1, 99999999) then
            self:SetText(tostring(id))
            ClearCursor()
        end
    end
    ui.item:SetScript("OnReceiveDrag", DropItem)
    ui.item:SetScript("OnMouseDown", DropItem)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
            if not ui.item:IsVisible() or not ui.item:HasFocus() then return end
            local id = ns.ItemID(link)
            if id then ui.item:SetText(tostring(id)) end
        end)
    end
    ResetRequest()

    Block(ui, 1, 566, WIDTH - 2, 1, palette.border)
    ui.status = Label(ui, 20, 574, 860, "", palette.muted, "GameFontNormalSmall")
    ui:SetScript("OnHide", function()
        GameTooltip:Hide()
        CloseCatalog()
        CloseRecipeSearch()
        wipe(itemLoads)
        for _, row in ipairs(ui.rows) do row.entry = nil end
        ui.detailAction:SetScript("OnClick", nil)
        ui.altAction:SetScript("OnClick", nil)
    end)
    ui:EnableMouseWheel(true)
    ui:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 and ui.prev:IsEnabled() then page = page - 1
        elseif delta < 0 and ui.next:IsEnabled() then page = page + 1
        else return end
        Render()
    end)
end

function ns.Changed()
    Render()
end

local function Fit()
    local scale = math.min(1, (UIParent:GetWidth() - 20) / WIDTH, (UIParent:GetHeight() - 20) / HEIGHT)
    if scale > 0 then ui:SetScale(scale) end
end

function ns.Toggle()
    if ui and ui:IsShown() then ui:Hide(); return end
    if not ui then CreateUI() end
    Fit()
    ns.RefreshProfessions()
    ui:Show()
    SelectTab(tab)
    Status(ns.RefreshContacts())
end

function ns.CreateLauncher()
    local draggedAt
    local launcher = Button(UIParent, 0, 0, 133, 36, "CraftCircle", function()
        if not draggedAt or GetTime() - draggedAt > 0.2 then ns.Toggle() end
    end)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:ClearAllPoints()
    local saved = ns.db.launcher
    local x = type(saved) == "table" and tonumber(saved.x)
    local y = type(saved) == "table" and tonumber(saved.y)
    launcher:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x or -236, y or -155)
    Block(launcher, 0, 0, 133, 1, palette.gold)
    Block(launcher, 6, 6, 24, 24, palette.gold)
    Icon(launcher, 7, 7, 22, icons.craft)
    launcher.label:ClearAllPoints()
    launcher.label:SetPoint("LEFT", 38, 0)
    launcher.label:SetTextColor(unpack(palette.gold))
    launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:StartMoving()
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        draggedAt = GetTime()
        local offsetX = self:GetRight() - UIParent:GetRight()
        local offsetY = self:GetTop() - UIParent:GetTop()
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", offsetX, offsetY)
        ns.db.launcher = { x = offsetX, y = offsetY }
    end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("CraftCircle", unpack(palette.gold))
        GameTooltip:AddLine("Click to open. Drag to move.", unpack(palette.text))
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local refresh = CreateFrame("Frame")
refresh:RegisterEvent("GET_ITEM_INFO_RECEIVED")
refresh:RegisterEvent("ITEM_DATA_LOAD_RESULT")
refresh:RegisterEvent("SPELL_DATA_LOAD_RESULT")
refresh:RegisterEvent("UI_SCALE_CHANGED")
refresh:RegisterEvent("BAG_UPDATE_DELAYED")
local redraw
refresh:SetScript("OnEvent", function(_, event, id, succeeded)
    if not ui or not ui:IsShown() then return end
    if event == "UI_SCALE_CHANGED" then Fit(); return end
    if event == "BAG_UPDATE_DELAYED" then
        if tab ~= 4 then return end
    else
        if not succeeded then return end
        if event ~= "SPELL_DATA_LOAD_RESULT" and ns.ItemID(ui.item:GetText()) == id then ui.UpdateItemPreview() end
    end
    if redraw then return end
    redraw = C_Timer.NewTimer(0.1, function() redraw = nil; Render() end)
end)
