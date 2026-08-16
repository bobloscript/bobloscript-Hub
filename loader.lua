--[[
    BobloScript Hub UI (single-file)
    Uses only the API documented by the user:
      /health
      /search
      /scripts
      /scripts/home/:kind
      /scripts/:idOrSlug
      /scripts/:idOrSlug/code
      /scripts/:idOrSlug/execute
      /hub/install
      /places
      /places/:slug/scripts

    Notes:
    - The public BobloScript API does not require an API key.
    - Remote code execution is performed only after the user presses Execute.
    - highRisk scripts require a 15-second warning countdown.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local APP_NAME = "BobloScript Hub"
local APP_SHORT_NAME = "BobloScript Hub"
local APP_VERSION = "2.1.2"
local API_BASE = "https://bobloscript.com/v1"
local CONFIG_FILE = "bobloscript_hub_config.json"
local IMAGE_CACHE_PREFIX = "bobloscript_hub_img_"
local WINDOW_WIDTH = 1040
local WINDOW_HEIGHT = 620
local MOBILE_MAX_SCALE = 1
local TOPBAR_HEIGHT = 62
local SIDEBAR_WIDTH = 186
local API_CACHE_TTL = 30
local SEARCH_DEBOUNCE = 0.38
local MAX_RECENT_SCRIPTS = 16
local MAX_RECENT_SEARCHES = 6

-- Builder Sans is the same modern type family used across current Roblox UI.
-- Keeping every weight in one family removes the "mixed font" feeling that
-- Gotham Black introduced in large headings.
local FontRegular = Enum.Font.BuilderSans
local FontMedium = Enum.Font.BuilderSansMedium
local FontBold = Enum.Font.BuilderSansBold
local FontHeavy = FontBold

local ThemePalettes = {
    dark = {
        Background = Color3.fromRGB(8, 10, 14),
        Window = Color3.fromRGB(13, 15, 20),
        Sidebar = Color3.fromRGB(11, 13, 18),
        Surface = Color3.fromRGB(18, 21, 28),
        Surface2 = Color3.fromRGB(23, 27, 35),
        Surface3 = Color3.fromRGB(29, 34, 44),
        Elevated = Color3.fromRGB(36, 42, 53),
        Border = Color3.fromRGB(48, 55, 68),
        BorderSoft = Color3.fromRGB(35, 41, 51),
        Text = Color3.fromRGB(242, 245, 249),
        Muted = Color3.fromRGB(157, 166, 181),
        Muted2 = Color3.fromRGB(103, 113, 130),
        Accent = Color3.fromRGB(47, 215, 190),
        AccentHover = Color3.fromRGB(70, 231, 207),
        AccentDark = Color3.fromRGB(18, 139, 120),
        AccentSoft = Color3.fromRGB(18, 58, 53),
        AccentFaint = Color3.fromRGB(14, 40, 39),
        AccentText = Color3.fromRGB(6, 26, 23),
        ImageText = Color3.fromRGB(246, 248, 250),
        Purple = Color3.fromRGB(172, 145, 255),
        PurpleSoft = Color3.fromRGB(54, 43, 82),
        Warning = Color3.fromRGB(239, 193, 101),
        WarningSoft = Color3.fromRGB(65, 50, 25),
        Danger = Color3.fromRGB(246, 119, 119),
        DangerSoft = Color3.fromRGB(69, 31, 34),
        Success = Color3.fromRGB(78, 218, 146),
        Black = Color3.fromRGB(0, 0, 0),
    },
    light = {
        Background = Color3.fromRGB(228, 232, 238),
        Window = Color3.fromRGB(244, 246, 249),
        Sidebar = Color3.fromRGB(238, 241, 245),
        Surface = Color3.fromRGB(251, 252, 253),
        Surface2 = Color3.fromRGB(237, 241, 245),
        Surface3 = Color3.fromRGB(226, 231, 237),
        Elevated = Color3.fromRGB(216, 223, 231),
        Border = Color3.fromRGB(190, 199, 210),
        BorderSoft = Color3.fromRGB(211, 218, 227),
        Text = Color3.fromRGB(25, 30, 39),
        Muted = Color3.fromRGB(82, 92, 108),
        Muted2 = Color3.fromRGB(124, 135, 151),
        Accent = Color3.fromRGB(23, 184, 159),
        AccentHover = Color3.fromRGB(18, 200, 171),
        AccentDark = Color3.fromRGB(13, 126, 108),
        AccentSoft = Color3.fromRGB(203, 241, 234),
        AccentFaint = Color3.fromRGB(220, 246, 241),
        AccentText = Color3.fromRGB(5, 35, 30),
        ImageText = Color3.fromRGB(246, 248, 250),
        Purple = Color3.fromRGB(121, 91, 212),
        PurpleSoft = Color3.fromRGB(231, 224, 251),
        Warning = Color3.fromRGB(170, 112, 22),
        WarningSoft = Color3.fromRGB(250, 236, 207),
        Danger = Color3.fromRGB(205, 65, 75),
        DangerSoft = Color3.fromRGB(250, 221, 224),
        Success = Color3.fromRGB(28, 156, 92),
        Black = Color3.fromRGB(0, 0, 0),
    },
}

local Theme = {}

local function applyTheme(mode)
    local palette = ThemePalettes[mode] or ThemePalettes.dark
    for key in pairs(Theme) do
        Theme[key] = nil
    end
    for key, value in pairs(palette) do
        Theme[key] = value
    end
end

applyTheme("dark")

local State = {
    screen = "home",
    themeMode = "dark",
    homeKind = "trending",
    showHighRisk = true,
    confirmBeforeExecute = true,
    autoCloseAfterExecute = false,
    compactMode = false,
    reduceMotion = false,
    installReported = false,
    loading = false,
    apiOnline = nil,
    requestGeneration = 0,
    selectedPlace = nil,
    selectedScript = nil,
    savedScripts = {},
    recentScripts = {},
    recentSearches = {},
    lastScreen = "home",
    placePage = 1,
    placeTotalPages = 1,
    scriptPage = 1,
    scriptTotalPages = 1,
    currentPlaceFilter = "all",
}

local Connections = {}
local ScreenGui
local MainWindow
local Content
local SidebarButtons = {}
local SidebarBadges = {}
local ToastHolder
local ModalLayer
local StatusDot
local StatusLabel
local GlobalSearchLayer
local GlobalSearchBox
local GlobalSearchPanel
local GlobalSearchResults
local GlobalSearchClear
local SearchShortcutLabel
local WindowShadowOuter
local WindowShadowInner
local FloatingToggle
local FloatingToggleShadow
local WindowScale
local setHubVisible
local toast
local closeGlobalSearch
local updateSidebarBadges
local transitionBusy = false
local windowFitScale = 1
local ApiCache = {}
local ScriptCodeCache = {}
local globalSearchSerial = 0

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function getGlobal(name)
    local env = safeCall(function()
        if getgenv then
            return getgenv()
        end
        return _G
    end)
    if env then
        return env[name]
    end
    return nil
end

local function getRequestFunction()
    local synApi = getGlobal("syn")
    local fluxusApi = getGlobal("fluxus")
    local httpApi = getGlobal("http")
    local requestFn = getGlobal("request")
        or getGlobal("http_request")
        or (type(synApi) == "table" and synApi.request)
        or (type(fluxusApi) == "table" and fluxusApi.request)
        or (type(httpApi) == "table" and httpApi.request)

    return requestFn
end

local function getAssetFunction()
    local synApi = getGlobal("syn")
    return getGlobal("getcustomasset")
        or getGlobal("getsynasset")
        or (type(synApi) == "table" and synApi.asset)
        or getGlobal("getasset")
end

local function getClipboardFunction()
    local clipboardApi = getGlobal("Clipboard")
    return getGlobal("setclipboard")
        or getGlobal("toclipboard")
        or (type(clipboardApi) == "table" and clipboardApi.set)
end

local function hasFileSystem()
    return type(getGlobal("isfile")) == "function"
        and type(getGlobal("readfile")) == "function"
        and type(getGlobal("writefile")) == "function"
end

local function writeConfig()
    if not hasFileSystem() then
        return false
    end

    local data = {
        themeMode = State.themeMode,
        showHighRisk = State.showHighRisk,
        confirmBeforeExecute = State.confirmBeforeExecute,
        autoCloseAfterExecute = State.autoCloseAfterExecute,
        compactMode = State.compactMode,
        reduceMotion = State.reduceMotion,
        savedScripts = State.savedScripts,
        recentScripts = State.recentScripts,
        recentSearches = State.recentSearches,
        lastScreen = State.lastScreen,
    }

    local encoded = HttpService:JSONEncode(data)
    local writefileFn = getGlobal("writefile")
    local ok = pcall(writefileFn, CONFIG_FILE, encoded)
    return ok
end

local function loadConfig()
    if not hasFileSystem() then
        return
    end

    local isfileFn = getGlobal("isfile")
    local readfileFn = getGlobal("readfile")

    local exists = safeCall(isfileFn, CONFIG_FILE)
    if not exists then
        return
    end

    local raw = safeCall(readfileFn, CONFIG_FILE)
    if type(raw) ~= "string" or raw == "" then
        return
    end

    local decoded = safeCall(HttpService.JSONDecode, HttpService, raw)
    if type(decoded) ~= "table" then
        return
    end

    State.themeMode = decoded.themeMode == "light" and "light" or "dark"
    State.showHighRisk = decoded.showHighRisk ~= false
    State.confirmBeforeExecute = decoded.confirmBeforeExecute ~= false
    State.autoCloseAfterExecute = decoded.autoCloseAfterExecute == true
    State.compactMode = decoded.compactMode == true
    State.reduceMotion = decoded.reduceMotion == true
    State.savedScripts = type(decoded.savedScripts) == "table" and decoded.savedScripts or {}
    State.recentScripts = type(decoded.recentScripts) == "table" and decoded.recentScripts or {}
    State.recentSearches = type(decoded.recentSearches) == "table" and decoded.recentSearches or {}
    State.lastScreen = type(decoded.lastScreen) == "string" and decoded.lastScreen or "home"
end

local function new(className, props, children)
    local instance = Instance.new(className)

    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                instance[key] = value
            end
        end
    end

    if children then
        for _, child in ipairs(children) do
            child.Parent = instance
        end
    end

    if props and props.Parent then
        instance.Parent = props.Parent
    end

    return instance
end

local function addCorner(parent, radius)
    return new("UICorner", {
        CornerRadius = UDim.new(0, radius or 12),
        Parent = parent,
    })
end

local function addStroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Theme.Border,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function addPadding(parent, left, right, top, bottom)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or left or 0),
        PaddingBottom = UDim.new(0, bottom or top or left or 0),
        Parent = parent,
    })
end

local function addList(parent, direction, padding, horizontalAlignment, verticalAlignment)
    return new("UIListLayout", {
        FillDirection = direction or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, padding or 0),
        HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left,
        VerticalAlignment = verticalAlignment or Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

local function clear(container)
    for _, child in ipairs(container:GetChildren()) do
        if not child:IsA("UIListLayout")
            and not child:IsA("UIGridLayout")
            and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function isGuiAlive(instance)
    return instance ~= nil
        and instance.Parent ~= nil
        and ScreenGui ~= nil
        and ScreenGui.Parent ~= nil
end

local function trackConnection(connection)
    if connection then
        table.insert(Connections, connection)
    end
    return connection
end

local function disconnectTrackedConnections()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    Connections = {}
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return tostring(math.floor(value))
end

local function formatDate(iso)
    if type(iso) ~= "string" or iso == "" then
        return "Unknown"
    end

    local year, month, day = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if year and month and day then
        return string.format("%s.%s.%s", day, month, year)
    end

    return iso
end

local function formatRelativeTime(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp then
        return nil
    end

    local elapsed = math.max(0, os.time() - timestamp)
    if elapsed < 60 then
        return "just now"
    elseif elapsed < 3600 then
        return tostring(math.floor(elapsed / 60)) .. "m ago"
    elseif elapsed < 86400 then
        return tostring(math.floor(elapsed / 3600)) .. "h ago"
    elseif elapsed < 604800 then
        return tostring(math.floor(elapsed / 86400)) .. "d ago"
    end

    return tostring(math.floor(elapsed / 604800)) .. "w ago"
end

local function urlEncode(value)
    return HttpService:UrlEncode(tostring(value or ""))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalizeQuery(value)
    local query = trim(value):gsub("[%c]", " ")
    return trim(query):sub(1, 100)
end

local function snapshotScript(scriptData)
    if type(scriptData) ~= "table" then
        return nil
    end

    return {
        id = scriptData.id,
        slug = scriptData.slug,
        title = scriptData.title,
        game = scriptData.game,
        imageUrl = scriptData.imageUrl,
        accessType = scriptData.accessType,
        highRisk = scriptData.highRisk,
        authorName = scriptData.authorName,
        authorProfileSlug = scriptData.authorProfileSlug,
        summary = scriptData.summary,
        tags = scriptData.tags,
        createdAt = scriptData.createdAt,
        updatedAt = scriptData.updatedAt,
        stats = scriptData.stats,
        robloxPlaceId = scriptData.robloxPlaceId,
        functions = scriptData.functions,
        developer = scriptData.developer,
        scope = scriptData.scope,
    }
end

local function rememberSearch(query)
    query = normalizeQuery(query)
    if query == "" then
        return
    end

    local nextSearches = { query }
    local queryLower = query:lower()
    for _, existing in ipairs(State.recentSearches) do
        if tostring(existing):lower() ~= queryLower and #nextSearches < MAX_RECENT_SEARCHES then
            table.insert(nextSearches, existing)
        end
    end
    State.recentSearches = nextSearches
    writeConfig()
end

updateSidebarBadges = function()
    local savedCount = 0
    for _ in pairs(State.savedScripts) do
        savedCount = savedCount + 1
    end

    local counts = {
        saved = savedCount,
        recent = #State.recentScripts,
    }

    for key, badge in pairs(SidebarBadges) do
        local count = counts[key] or 0
        badge.Visible = count > 0
        badge.Text = count > 99 and "99+" or tostring(count)
    end
end

local function recordRecentScript(scriptData)
    local snapshot = snapshotScript(scriptData)
    if not snapshot then
        return
    end

    local key = snapshot.id or snapshot.slug
    if not key then
        return
    end

    snapshot.lastRunAt = os.time()
    local nextRecent = { snapshot }

    for _, existing in ipairs(State.recentScripts) do
        local existingKey = existing.id or existing.slug
        if existingKey ~= key and #nextRecent < MAX_RECENT_SCRIPTS then
            table.insert(nextRecent, existing)
        end
    end

    State.recentScripts = nextRecent
    writeConfig()
    updateSidebarBadges()
end

local function getSavedScriptsSorted()
    local scripts = {}
    for _, scriptData in pairs(State.savedScripts) do
        table.insert(scripts, scriptData)
    end

    table.sort(scripts, function(a, b)
        return tostring(a.updatedAt or a.createdAt or "") > tostring(b.updatedAt or b.createdAt or "")
    end)

    return scripts
end

local function isSaved(scriptData)
    if not scriptData then
        return false
    end
    local key = scriptData.id or scriptData.slug
    return key and State.savedScripts[key] ~= nil
end

local function saveScript(scriptData)
    if not scriptData then
        return
    end

    local key = scriptData.id or scriptData.slug
    if not key then
        return
    end

    if State.savedScripts[key] then
        State.savedScripts[key] = nil
    else
        State.savedScripts[key] = snapshotScript(scriptData)
    end

    writeConfig()
    updateSidebarBadges()
end

local ImageAssetCache = {}

local function sanitizeFileName(value)
    value = tostring(value or "")
    value = value:gsub("^https?://", "")
    value = value:gsub("[^%w]", "_")
    if #value > 96 then
        value = value:sub(1, 96)
    end
    return value
end

local function extractImageExtension(url, headers)
    local headerType = nil
    if type(headers) == "table" then
        headerType = headers["Content-Type"] or headers["content-type"]
    end

    if type(headerType) == "string" then
        local lower = headerType:lower()
        if lower:find("png", 1, true) then
            return "png"
        elseif lower:find("jpeg", 1, true) or lower:find("jpg", 1, true) then
            return "jpg"
        elseif lower:find("webp", 1, true) then
            return "webp"
        end
    end

    local ext = tostring(url or ""):match("%.([%a%d]+)(%?.*)?$")
    ext = ext and ext:lower() or nil
    if ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" then
        return ext == "jpeg" and "jpg" or ext
    end

    return "png"
end

local function resolveImageSource(url)
    if type(url) ~= "string" or url == "" then
        return nil
    end

    if url:match("^rbxassetid://") or url:match("^rbxthumb://") or url:match("^rbxgameasset://") then
        return url
    end

    if ImageAssetCache[url] then
        return ImageAssetCache[url]
    end

    local assetFn = getAssetFunction()
    if not (assetFn and hasFileSystem()) then
        return nil
    end

    local fileBase = IMAGE_CACHE_PREFIX .. sanitizeFileName(url)
    local requestFn = getRequestFunction()
    if not requestFn then
        return nil
    end

    local body = nil
    local headers = nil
    local ok, response = pcall(requestFn, {
        Url = url,
        Method = "GET",
        Headers = {
            ["Accept"] = "image/*",
        },
    })

    if ok and type(response) == "table" then
        local statusCode = tonumber(response.StatusCode or response.Status or response.status_code) or 0
        if statusCode >= 200 and statusCode < 300 then
            body = response.Body or response.body
            headers = response.Headers or response.headers
        end
    end

    if type(body) ~= "string" or body == "" then
        return nil
    end

    local ext = extractImageExtension(url, headers)
    local fileName = fileBase .. "." .. ext
    local isfileFn = getGlobal("isfile")
    local writefileFn = getGlobal("writefile")

    if type(isfileFn) == "function" and safeCall(isfileFn, fileName) ~= true then
        local success = pcall(writefileFn, fileName, body)
        if not success then
            return nil
        end
    elseif type(isfileFn) ~= "function" then
        local success = pcall(writefileFn, fileName, body)
        if not success then
            return nil
        end
    end

    local asset = safeCall(assetFn, fileName)
    if asset then
        ImageAssetCache[url] = asset
    end

    return asset
end

local function refreshConnectionStatus()
    if not StatusDot or not StatusLabel then
        return
    end

    if State.apiOnline == true then
        StatusDot.BackgroundColor3 = Theme.Success
        StatusLabel.Text = "API online"
        StatusLabel.TextColor3 = Theme.Muted
    elseif State.apiOnline == false then
        StatusDot.BackgroundColor3 = Theme.Danger
        StatusLabel.Text = "API unavailable"
        StatusLabel.TextColor3 = Theme.Danger
    else
        StatusDot.BackgroundColor3 = Theme.Warning
        StatusLabel.Text = "Checking API"
        StatusLabel.TextColor3 = Theme.Muted
    end
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

local function syncWindowShadows()
    if not MainWindow then
        return
    end

    local scaledWidth = WINDOW_WIDTH * windowFitScale
    local scaledHeight = WINDOW_HEIGHT * windowFitScale

    if WindowShadowOuter then
        WindowShadowOuter.Position = UDim2.new(
            MainWindow.Position.X.Scale,
            MainWindow.Position.X.Offset,
            MainWindow.Position.Y.Scale,
            MainWindow.Position.Y.Offset + 10
        )
        WindowShadowOuter.Size = UDim2.fromOffset(scaledWidth + 26, scaledHeight + 30)
        WindowShadowOuter.Visible = MainWindow.Visible
    end

    if WindowShadowInner then
        WindowShadowInner.Position = UDim2.new(
            MainWindow.Position.X.Scale,
            MainWindow.Position.X.Offset,
            MainWindow.Position.Y.Scale,
            MainWindow.Position.Y.Offset + 18
        )
        WindowShadowInner.Size = UDim2.fromOffset(scaledWidth + 56, scaledHeight + 58)
        WindowShadowInner.Visible = MainWindow.Visible
    end
end

local function syncFloatingToggleShadow()
    if not FloatingToggle or not FloatingToggleShadow then
        return
    end

    FloatingToggleShadow.Position = UDim2.new(
        FloatingToggle.Position.X.Scale,
        FloatingToggle.Position.X.Offset,
        FloatingToggle.Position.Y.Scale,
        FloatingToggle.Position.Y.Offset + 7
    )
end

local function updateWindowFit(recenter)
    if not MainWindow or not WindowScale then
        return
    end

    local viewport = getViewportSize()
    local isMobile = UserInputService.TouchEnabled or viewport.X < 760 or viewport.Y < 500
    local horizontalMargin = isMobile and 10 or 20
    local verticalMargin = isMobile and 10 or 20
    local availableWidth = math.max(1, viewport.X - horizontalMargin)
    local availableHeight = math.max(1, viewport.Y - verticalMargin)
    local maxScale = isMobile and MOBILE_MAX_SCALE or 1

    -- Never force a minimum scale: the old 0.68 floor produced a
    -- 694x422 window that overflowed smaller phone viewports.
    windowFitScale = math.min(
        maxScale,
        availableWidth / WINDOW_WIDTH,
        availableHeight / WINDOW_HEIGHT
    )

    WindowScale.Scale = windowFitScale

    if recenter then
        MainWindow.Position = UDim2.fromScale(0.5, 0.5)
    end

    syncWindowShadows()
end

setHubVisible = function(visible)
    visible = visible == true

    if not visible and closeGlobalSearch then
        closeGlobalSearch(false)
    end

    if not visible and FloatingToggle then
        FloatingToggle.Position = UDim2.fromScale(0.5, 0.5)
        syncFloatingToggleShadow()
    end

    if MainWindow then
        MainWindow.Visible = visible
    end

    if WindowShadowOuter then
        WindowShadowOuter.Visible = visible
    end

    if WindowShadowInner then
        WindowShadowInner.Visible = visible
    end

    if FloatingToggle then
        FloatingToggle.Visible = not visible
    end

    if FloatingToggleShadow then
        FloatingToggleShadow.Visible = not visible
    end

    if visible and MainWindow and WindowScale then
        updateWindowFit(false)
        if State.reduceMotion then
            WindowScale.Scale = windowFitScale
        else
            WindowScale.Scale = windowFitScale * 0.97
            TweenService:Create(
                WindowScale,
                TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Scale = windowFitScale }
            ):Play()
        end
    end
end

local function getResponseHeader(headers, name)
    if type(headers) ~= "table" then
        return nil
    end

    local wanted = tostring(name):lower()
    for key, value in pairs(headers) do
        if tostring(key):lower() == wanted then
            return value
        end
    end

    return nil
end

local function apiRequest(method, path, body, options)
    options = options or {}
    local cacheKey = tostring(method) .. ":" .. tostring(path)

    if method == "GET" and options.noCache ~= true then
        local cached = ApiCache[cacheKey]
        if cached and cached.expiresAt > os.clock() then
            return cached.payload, nil, cached.response, true
        end
    end

    local requestFn = getRequestFunction()

    if not requestFn then
        return nil, {
            code = "REQUEST_UNAVAILABLE",
            message = "This executor does not provide an HTTP request function.",
        }
    end

    local requestData = {
        Url = API_BASE .. path,
        Method = method,
        Headers = {
            ["Accept"] = "application/json",
            ["Content-Type"] = "application/json",
        },
    }

    if body ~= nil then
        requestData.Body = HttpService:JSONEncode(body)
    end

    local ok, response = pcall(requestFn, requestData)
    if not ok then
        State.apiOnline = false
        refreshConnectionStatus()
        return nil, {
            code = "NETWORK_ERROR",
            message = tostring(response),
        }
    end

    if type(response) ~= "table" then
        State.apiOnline = false
        refreshConnectionStatus()
        return nil, {
            code = "INVALID_RESPONSE",
            message = "The executor returned an invalid HTTP response.",
        }
    end

    local statusCode = tonumber(response.StatusCode or response.Status or response.status_code) or 0
    local responseBody = response.Body or response.body or ""
    local responseHeaders = response.Headers or response.headers or {}
    local decoded = nil

    if type(responseBody) == "string" and responseBody ~= "" then
        decoded = safeCall(HttpService.JSONDecode, HttpService, responseBody)
    end

    if statusCode >= 200 and statusCode < 300 then
        State.apiOnline = true
        refreshConnectionStatus()

        local payload = decoded or {}
        if method == "GET" and options.noCache ~= true then
            ApiCache[cacheKey] = {
                payload = payload,
                response = response,
                expiresAt = os.clock() + (tonumber(options.cacheTtl) or API_CACHE_TTL),
            }
        end

        return payload, nil, response, false
    end

    local message = "Request failed with status " .. tostring(statusCode)
    local code = "HTTP_ERROR"
    local retryAfter = nil

    if type(decoded) == "table" then
        message = tostring(decoded.message or message)
        code = tostring(decoded.code or code)
        retryAfter = tonumber(decoded.retryAfter)
    end

    if statusCode == 401 then
        code = "UNAUTHORIZED"
        message = "The public API rejected this request. The service may be temporarily misconfigured."
    elseif statusCode == 429 then
        code = "RATE_LIMITED"
        retryAfter = retryAfter
            or tonumber(getResponseHeader(responseHeaders, "Retry-After"))
            or 60
        message = "Too many requests. Try again in " .. tostring(math.max(1, math.ceil(retryAfter))) .. " seconds."
    elseif statusCode == 404 then
        code = "NOT_FOUND"
        message = "The requested item was not found."
    elseif statusCode == 502 or statusCode == 503 then
        State.apiOnline = false
        refreshConnectionStatus()
    end

    return nil, {
        code = code,
        message = message,
        retryAfter = retryAfter,
        statusCode = statusCode,
        body = decoded,
        headers = responseHeaders,
    }, response
end

local function clearApiCache()
    ApiCache = {}
    ScriptCodeCache = {}
end

local function checkApiHealth(showFeedback)
    State.apiOnline = nil
    refreshConnectionStatus()

    task.spawn(function()
        local payload, err = apiRequest("GET", "/health", nil, {
            noCache = true,
        })

        State.apiOnline = err == nil and type(payload) == "table" and payload.ok == true
        refreshConnectionStatus()

        if showFeedback then
            if State.apiOnline then
                toast("BobloScript API is online.", "success", 2.5)
            else
                toast((err and err.message) or "BobloScript API is unavailable.", "error", 4)
            end
        end
    end)
end

local function getScriptIdentifier(scriptData)
    if type(scriptData) ~= "table" then
        return nil
    end
    return scriptData.id or scriptData.slug
end

local function fetchScriptCode(scriptData, forceRefresh)
    local identifier = getScriptIdentifier(scriptData)
    if not identifier then
        return nil, {
            code = "MISSING_IDENTIFIER",
            message = "This script has no usable identifier.",
        }
    end

    local cacheKey = tostring(identifier) .. ":" .. tostring(scriptData.updatedAt or "")
    local cached = ScriptCodeCache[cacheKey]
    if not forceRefresh and cached and cached.expiresAt > os.clock() then
        return cached.code, nil
    end

    local payload, err = apiRequest(
        "GET",
        "/scripts/" .. urlEncode(identifier) .. "/code",
        nil,
        { noCache = true }
    )

    if err then
        return nil, err
    end

    local code = payload and payload.code
    if type(code) ~= "string" or code == "" then
        return nil, {
            code = "EMPTY_CODE",
            message = "The API returned empty script code.",
        }
    end

    ScriptCodeCache[cacheKey] = {
        code = code,
        expiresAt = os.clock() + 60,
    }

    return code, nil
end

local function copyText(value, successMessage)
    local clipboard = getClipboardFunction()
    if type(clipboard) ~= "function" then
        toast("This executor does not provide clipboard access.", "error", 4)
        return false
    end

    local ok = pcall(clipboard, tostring(value or ""))
    if not ok then
        toast("Could not copy to the clipboard.", "error", 4)
        return false
    end

    toast(successMessage or "Copied to clipboard.", "success", 2.5)
    return true
end

local function copyScriptCode(scriptData)
    if State.loading then
        toast("Please wait for the current action to finish.", "warning", 2.5)
        return
    end

    State.loading = true
    toast("Preparing script code...", "warning", 2)

    task.spawn(function()
        local code, err = fetchScriptCode(scriptData, false)
        State.loading = false

        if err then
            toast(err.message, "error", 4)
            return
        end

        copyText(code, "Script code copied.")
    end)
end

local function makeLabel(parent, text, size, color, font, alignment)
    return new("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = text or "",
        TextColor3 = color or Theme.Text,
        TextSize = size or 15,
        Font = font or FontRegular,
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = parent,
    })
end

local function makeButton(parent, text, callback, options)
    options = options or {}

    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = options.background or Theme.Surface2,
        BorderSizePixel = 0,
        Text = text or "Button",
        TextColor3 = options.textColor or Theme.Text,
        TextSize = options.textSize or 14,
        Font = options.font or FontMedium,
        Size = options.size or UDim2.fromOffset(120, 38),
        Parent = parent,
    })
    addCorner(button, options.radius or 11)

    if options.stroke ~= false then
        addStroke(button, options.strokeColor or Theme.BorderSoft, 1, options.strokeTransparency or 0)
    end

    local normalColor = button.BackgroundColor3
    local hoverColor = options.hover or Theme.Surface3
    button:SetAttribute("RestingColor", normalColor)

    button.MouseEnter:Connect(function()
        if not button.Active then
            return
        end
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
    end)

    button.MouseLeave:Connect(function()
        local restingColor = button:GetAttribute("RestingColor") or normalColor
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = restingColor }):Play()
    end)

    button.MouseButton1Down:Connect(function()
        if button.Active then
            TweenService:Create(button, TweenInfo.new(0.06), { BackgroundColor3 = Theme.Elevated }):Play()
        end
    end)

    button.MouseButton1Up:Connect(function()
        if button.Active then
            TweenService:Create(button, TweenInfo.new(0.08), { BackgroundColor3 = hoverColor }):Play()
        end
    end)

    button.MouseButton1Click:Connect(function()
        if callback then
            callback(button)
        end
    end)

    return button
end

local function makeSearchGlyph(parent)
    local holder = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 38, 1, 0),
        Position = UDim2.fromOffset(1, 0),
        Parent = parent,
    })

    local ring = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 16, 0.5, -1),
        Size = UDim2.fromOffset(12, 12),
        Parent = holder,
    })
    addCorner(ring, 7)
    local ringStroke = addStroke(ring, Theme.Muted2, 1.4, 0)
    ringStroke.Name = "SearchIconPart"

    local handle = new("Frame", {
        Name = "SearchIconPart",
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.Muted2,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 21, 0.5, 5),
        Rotation = 45,
        Size = UDim2.fromOffset(7, 2),
        Parent = holder,
    })
    addCorner(handle, 2)

    return holder
end

local function makeIconLine(parent, x, y, width, height, rotation)
    local line = new("Frame", {
        Name = "IconPart",
        BackgroundColor3 = Theme.Muted2,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, y),
        Rotation = rotation or 0,
        Size = UDim2.fromOffset(width, height),
        Parent = parent,
    })
    addCorner(line, math.max(1, math.floor(height / 2)))
    return line
end

local function makeIconOutline(parent, x, y, width, height, radius)
    local shape = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height),
        Parent = parent,
    })
    addCorner(shape, radius or 3)
    local stroke = addStroke(shape, Theme.Muted2, 1.25, 0)
    stroke.Name = "IconPart"
    return shape
end

local function makeNavIcon(parent, kind)
    if kind == "home" then
        makeIconLine(parent, 5, 7, 10, 2, -42)
        makeIconLine(parent, 12, 7, 10, 2, 42)
        makeIconOutline(parent, 7, 10, 12, 10, 2)
        makeIconLine(parent, 12, 15, 2, 5)
    elseif kind == "scripts" then
        makeIconOutline(parent, 7, 5, 12, 16, 2)
        makeIconLine(parent, 10, 9, 6, 2)
        makeIconLine(parent, 10, 13, 6, 2)
        makeIconLine(parent, 10, 17, 4, 2)
    elseif kind == "places" then
        makeIconOutline(parent, 7, 4, 12, 12, 7)
        makeIconLine(parent, 11, 8, 4, 4)
        makeIconLine(parent, 8, 15, 8, 2, 42)
        makeIconLine(parent, 12, 15, 8, 2, -42)
    elseif kind == "saved" then
        makeIconLine(parent, 7, 5, 12, 2)
        makeIconLine(parent, 7, 5, 2, 13)
        makeIconLine(parent, 17, 5, 2, 13)
        makeIconLine(parent, 8, 16, 8, 2, 42)
        makeIconLine(parent, 12, 16, 8, 2, -42)
    elseif kind == "recent" then
        makeIconOutline(parent, 6, 6, 14, 14, 8)
        makeIconLine(parent, 12, 9, 2, 6)
        makeIconLine(parent, 13, 13, 5, 2)
    else
        makeIconLine(parent, 5, 7, 16, 2)
        makeIconLine(parent, 5, 12, 16, 2)
        makeIconLine(parent, 5, 17, 16, 2)
        makeIconLine(parent, 9, 5, 4, 6)
        makeIconLine(parent, 15, 10, 4, 6)
        makeIconLine(parent, 7, 15, 4, 6)
    end
end

local function setButtonEnabled(button, enabled)
    if not button then
        return
    end

    button.Active = enabled == true
    button.Selectable = enabled == true
    button.TextTransparency = enabled and 0 or 0.58
    button.BackgroundTransparency = enabled and 0 or 0.38
end

local function makeInput(parent, placeholder, options)
    options = options or {}

    local holder = new("Frame", {
        BackgroundColor3 = options.background or Theme.Surface,
        BorderSizePixel = 0,
        Size = options.size or UDim2.fromOffset(360, 42),
        Parent = parent,
    })
    addCorner(holder, options.radius or 12)
    local stroke = addStroke(holder, options.strokeColor or Theme.BorderSoft, 1, 0)

    local icon = nil
    if options.searchIcon then
        icon = makeSearchGlyph(holder)
    elseif options.icon then
        icon = makeLabel(holder, options.icon, 15, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
        icon.Size = UDim2.fromOffset(38, holder.Size.Y.Offset)
        icon.Position = UDim2.fromOffset(2, 0)
    end

    local leftOffset = (options.searchIcon or options.icon) and 39 or 13
    local rightOffset = options.rightPadding or 12

    local box = new("TextBox", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = Theme.Muted2,
        Text = options.text or "",
        TextColor3 = Theme.Text,
        TextSize = options.textSize or 15,
        Font = FontRegular,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -(leftOffset + rightOffset), 1, 0),
        Position = UDim2.fromOffset(leftOffset, 0),
        Parent = holder,
    })

    local function setSearchIconColor(color)
        if not options.searchIcon or not icon then
            return
        end
        for _, descendant in ipairs(icon:GetDescendants()) do
            if descendant.Name == "SearchIconPart" then
                if descendant:IsA("UIStroke") then
                    TweenService:Create(descendant, TweenInfo.new(0.12), { Color = color }):Play()
                elseif descendant:IsA("Frame") then
                    TweenService:Create(descendant, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
                end
            end
        end
    end

    box.Focused:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {
            Color = Theme.Accent,
            Transparency = 0.15,
        }):Play()
        TweenService:Create(holder, TweenInfo.new(0.12), {
            BackgroundColor3 = Theme.Surface2,
        }):Play()
        setSearchIconColor(Theme.Accent)
    end)

    box.FocusLost:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {
            Color = options.strokeColor or Theme.BorderSoft,
            Transparency = 0,
        }):Play()
        TweenService:Create(holder, TweenInfo.new(0.12), {
            BackgroundColor3 = options.background or Theme.Surface,
        }):Play()
        setSearchIconColor(Theme.Muted2)
    end)

    return holder, box, icon
end

local function makeBadge(parent, text, kind)
    local background = Theme.Surface3
    local color = Theme.Muted

    if kind == "accent" then
        background = Theme.AccentSoft
        color = Theme.Accent
    elseif kind == "purple" then
        background = Theme.PurpleSoft
        color = Theme.Purple
    elseif kind == "warning" then
        background = Theme.WarningSoft
        color = Theme.Warning
    elseif kind == "danger" then
        background = Theme.DangerSoft
        color = Theme.Danger
    end

    local badge = new("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = background,
        BorderSizePixel = 0,
        Text = "  " .. tostring(text or "") .. "  ",
        TextColor3 = color,
        TextSize = 11,
        Font = FontBold,
        Size = UDim2.fromOffset(0, 24),
        Parent = parent,
    })
    addCorner(badge, 8)

    return badge
end

toast = function(message, kind, duration)
    if not ToastHolder then
        return
    end

    local background = Theme.Surface2
    local accent = Theme.Accent

    if kind == "error" then
        background = Theme.DangerSoft
        accent = Theme.Danger
    elseif kind == "warning" then
        background = Theme.WarningSoft
        accent = Theme.Warning
    elseif kind == "success" then
        background = Theme.AccentSoft
        accent = Theme.Success
    end

    local card = new("Frame", {
        BackgroundColor3 = background,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(320, 54),
        Parent = ToastHolder,
    })
    addCorner(card, 12)
    addStroke(card, accent, 1, 0.35)

    local line = new("Frame", {
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(4, 34),
        Position = UDim2.fromOffset(10, 10),
        Parent = card,
    })
    addCorner(line, 4)

    local label = makeLabel(card, tostring(message), 13, Theme.Text, FontMedium)
    label.TextWrapped = true
    label.Size = UDim2.new(1, -34, 1, 0)
    label.Position = UDim2.fromOffset(26, 0)

    card.BackgroundTransparency = 1
    label.TextTransparency = 1
    line.BackgroundTransparency = 1

    TweenService:Create(card, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
    TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
    TweenService:Create(line, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()

    task.delay(duration or 3, function()
        if not card.Parent then
            return
        end
        TweenService:Create(card, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 1 }):Play()
        TweenService:Create(line, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
        task.wait(0.2)
        card:Destroy()
    end)
end

local function closeModal()
    if ModalLayer then
        clear(ModalLayer)
        ModalLayer.Visible = false
    end
end

local function showModal(title, bodyText, buildActions)
    ModalLayer.Visible = true
    clear(ModalLayer)

    local backdrop = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.fromScale(1, 1),
        Parent = ModalLayer,
    })

    local card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(430, 260),
        Parent = ModalLayer,
    })
    addCorner(card, 18)
    addStroke(card, Theme.Border, 1, 0)
    addPadding(card, 24, 24, 22, 20)

    local titleLabel = makeLabel(card, title or "", 20, Theme.Text, FontBold)
    titleLabel.Size = UDim2.new(1, 0, 0, 28)

    local bodyLabel = makeLabel(card, bodyText or "", 14, Theme.Muted, FontRegular)
    bodyLabel.TextWrapped = true
    bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
    bodyLabel.Size = UDim2.new(1, 0, 0, 120)
    bodyLabel.Position = UDim2.fromOffset(0, 45)

    local actions = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.new(0, 0, 1, -42),
        Parent = card,
    })
    addList(actions, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

    if buildActions then
        buildActions(actions, card, bodyLabel)
    end

    backdrop.MouseButton1Click:Connect(closeModal)
    return card, bodyLabel, actions
end

local function updateSidebarSelection(screenName)
    for name, button in pairs(SidebarButtons) do
        local selected = name == screenName
        button.BackgroundColor3 = selected and Theme.AccentFaint or Theme.Sidebar
        button:SetAttribute("RestingColor", selected and Theme.AccentFaint or Theme.Sidebar)

        local navLabel = button:FindFirstChild("NavLabel")
        if navLabel then
            navLabel.TextColor3 = selected and Theme.Accent or Theme.Muted
        end

        local iconTile = button:FindFirstChild("IconTile")
        if iconTile then
            iconTile.BackgroundColor3 = selected and Theme.AccentSoft or Theme.Surface2
            for _, descendant in ipairs(iconTile:GetDescendants()) do
                if descendant.Name == "IconPart" then
                    if descendant:IsA("UIStroke") then
                        descendant.Color = selected and Theme.Accent or Theme.Muted2
                    elseif descendant:IsA("Frame") then
                        descendant.BackgroundColor3 = selected and Theme.Accent or Theme.Muted2
                    end
                end
            end
        end

        local indicator = button:FindFirstChild("SelectedBar")
        if indicator then
            indicator.Visible = selected
        end
    end
end

local renderScreen
local openScriptDetails
local openPlaceScripts
local makeLoadingState
local makeEmptyState

closeGlobalSearch = function(clearFocus)
    globalSearchSerial = globalSearchSerial + 1
    if GlobalSearchLayer then
        GlobalSearchLayer.Visible = false
    end
    if clearFocus and GlobalSearchBox then
        GlobalSearchBox:ReleaseFocus()
    end
end

local function setGlobalSearchVisible(visible)
    if not GlobalSearchLayer then
        return
    end

    GlobalSearchLayer.Visible = visible == true
    if visible and GlobalSearchBox then
        task.defer(function()
            if GlobalSearchBox and GlobalSearchBox.Parent then
                GlobalSearchBox:CaptureFocus()
            end
        end)
    end
end

local function makeGlobalResultRow(parent, titleText, metaText, badgeText, onClick)
    local row = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.new(1, 0, 0, 58),
        Parent = parent,
    })
    addCorner(row, 11)

    local marker = new("Frame", {
        BackgroundColor3 = badgeText == "PLACE" and Theme.Purple or Theme.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 14),
        Size = UDim2.fromOffset(30, 30),
        Parent = row,
    })
    addCorner(marker, 9)

    local markerText = makeLabel(
        marker,
        badgeText == "PLACE" and "P" or "S",
        12,
        Theme.AccentText,
        FontBold,
        Enum.TextXAlignment.Center
    )
    markerText.Size = UDim2.fromScale(1, 1)

    local titleLabel = makeLabel(row, tostring(titleText or "Untitled"), 13, Theme.Text, FontBold)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Size = UDim2.new(1, -128, 0, 22)
    titleLabel.Position = UDim2.fromOffset(53, 8)

    local meta = makeLabel(row, tostring(metaText or ""), 11, Theme.Muted, FontRegular)
    meta.TextTruncate = Enum.TextTruncate.AtEnd
    meta.Size = UDim2.new(1, -128, 0, 19)
    meta.Position = UDim2.fromOffset(53, 31)

    local typeBadge = makeLabel(row, badgeText or "SCRIPT", 9, Theme.Muted2, FontBold, Enum.TextXAlignment.Right)
    typeBadge.Size = UDim2.fromOffset(58, 20)
    typeBadge.Position = UDim2.new(1, -70, 0.5, -10)

    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Theme.Surface2 }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Theme.Surface }):Play()
    end)
    row.MouseButton1Click:Connect(function()
        if onClick then
            onClick()
        end
    end)

    return row
end

local function renderGlobalSearchIdle()
    if not GlobalSearchResults then
        return
    end

    clear(GlobalSearchResults)

    local hint = makeLabel(
        GlobalSearchResults,
        #State.recentSearches > 0 and "RECENT SEARCHES" or "SEARCH THE CATALOG",
        10,
        Theme.Muted2,
        FontBold
    )
    hint.Size = UDim2.new(1, 0, 0, 24)

    if #State.recentSearches == 0 then
        makeEmptyState(
            GlobalSearchResults,
            "Find scripts and places",
            "Type a game, script, function, or access type."
        )
        return
    end

    for _, query in ipairs(State.recentSearches) do
        makeGlobalResultRow(GlobalSearchResults, query, "Run this search again", "SEARCH", function()
            if GlobalSearchBox then
                GlobalSearchBox.Text = query
                GlobalSearchBox.CursorPosition = #query + 1
            end
        end)
    end
end

local function runGlobalSearch(query)
    if not GlobalSearchResults then
        return
    end

    query = normalizeQuery(query)
    globalSearchSerial = globalSearchSerial + 1
    local serial = globalSearchSerial
    clear(GlobalSearchResults)

    if query == "" then
        renderGlobalSearchIdle()
        return
    end

    if #query < 2 then
        makeEmptyState(GlobalSearchResults, "Keep typing", "Enter at least 2 characters.")
        return
    end

    local loading = makeLoadingState(GlobalSearchResults, "Searching BobloScript")

    task.spawn(function()
        local payload, err = apiRequest(
            "GET",
            "/search?q=" .. urlEncode(query) .. "&type=all&page=1&limit=10",
            nil,
            { cacheTtl = 20 }
        )

        if serial ~= globalSearchSerial or not GlobalSearchLayer or not GlobalSearchLayer.Visible then
            return
        end

        if loading and loading.Parent then
            loading:Destroy()
        end

        if err then
            makeEmptyState(GlobalSearchResults, "Search unavailable", err.message)
            return
        end

        local result = payload and payload.result or {}
        local scripts = type(result.scripts) == "table" and result.scripts or {}
        local places = type(result.places) == "table" and result.places or {}
        local visibleCount = 0

        if #places > 0 then
            local placesHeading = makeLabel(GlobalSearchResults, "PLACES", 10, Theme.Muted2, FontBold)
            placesHeading.Size = UDim2.new(1, 0, 0, 24)

            for index, place in ipairs(places) do
                if index > 4 then
                    break
                end
                visibleCount = visibleCount + 1
                makeGlobalResultRow(
                    GlobalSearchResults,
                    place.name,
                    tostring(place.scriptCount or 0) .. " scripts  •  " .. tostring(place.creatorName or "Unknown creator"),
                    "PLACE",
                    function()
                        rememberSearch(query)
                        closeGlobalSearch(true)
                        openPlaceScripts(place, 1)
                    end
                )
            end
        end

        if #scripts > 0 then
            local scriptsHeading = makeLabel(GlobalSearchResults, "SCRIPTS", 10, Theme.Muted2, FontBold)
            scriptsHeading.Size = UDim2.new(1, 0, 0, 24)

            local visibleScripts = 0
            for _, scriptData in ipairs(scripts) do
                if State.showHighRisk or not scriptData.highRisk then
                    visibleScripts = visibleScripts + 1
                    visibleCount = visibleCount + 1
                    makeGlobalResultRow(
                        GlobalSearchResults,
                        scriptData.title,
                        tostring(scriptData.game or "Unknown game") .. "  •  " .. tostring(scriptData.accessType or "Unknown access"),
                        "SCRIPT",
                        function()
                            rememberSearch(query)
                            closeGlobalSearch(true)
                            State.selectedPlace = nil
                            openScriptDetails(scriptData)
                        end
                    )
                    if visibleScripts >= 6 then
                        break
                    end
                end
            end
        end

        if visibleCount == 0 then
            makeEmptyState(GlobalSearchResults, "Nothing found", "Try a shorter game or script name.")
        end
    end)
end

local function moveGuiChildren(source, destination, excluded)
    excluded = excluded or {}
    for _, child in ipairs(source:GetChildren()) do
        if not excluded[child]
            and not child:IsA("UIListLayout")
            and not child:IsA("UIGridLayout")
            and not child:IsA("UIPadding") then
            child.Parent = destination
        end
    end
end

local function transitionContent(buildFn)
    if not Content or not Content.Parent then
        buildFn()
        return
    end

    if transitionBusy then
        return
    end

    if State.reduceMotion then
        clear(Content)
        local ok, buildError = pcall(buildFn)
        if not ok then
            warn("[BobloScript Hub] Page render failed: " .. tostring(buildError))
        end
        return
    end

    transitionBusy = true

    local oldChildren = Content:GetChildren()
    if #oldChildren > 0 then
        local outgoing = new("CanvasGroup", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            GroupTransparency = 0,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(1, 1),
            Parent = Content,
        })

        moveGuiChildren(Content, outgoing, { [outgoing] = true })

        local fadeOut = TweenService:Create(
            outgoing,
            TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                GroupTransparency = 1,
                Position = UDim2.fromOffset(-10, 0),
            }
        )
        fadeOut:Play()
        fadeOut.Completed:Wait()
        outgoing:Destroy()
    end

    clear(Content)

    local ok, buildError = pcall(buildFn)
    if not ok then
        transitionBusy = false
        warn("[BobloScript Hub] Page render failed: " .. tostring(buildError))
        return
    end

    local incoming = new("CanvasGroup", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })

    moveGuiChildren(Content, incoming, { [incoming] = true })

    local fadeIn = TweenService:Create(
        incoming,
        TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            GroupTransparency = 0,
            Position = UDim2.fromOffset(0, 0),
        }
    )
    fadeIn:Play()
    fadeIn.Completed:Wait()

    if incoming.Parent then
        moveGuiChildren(incoming, Content)
        incoming:Destroy()
    end

    transitionBusy = false
end

local function makeSectionTitle(parent, title, subtitle)
    local wrap = new("Frame", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = parent,
    })

    local titleLabel = makeLabel(wrap, title, 18, Theme.Text, FontBold)
    titleLabel.Size = UDim2.new(1, 0, 0, 25)

    if subtitle then
        local subtitleLabel = makeLabel(wrap, subtitle, 13, Theme.Muted, FontRegular)
        subtitleLabel.TextWrapped = true
        subtitleLabel.Size = UDim2.new(1, 0, 0, 38)
        subtitleLabel.Position = UDim2.fromOffset(0, 28)
        wrap.Size = UDim2.new(1, 0, 0, 68)
    else
        wrap.Size = UDim2.new(1, 0, 0, 28)
    end

    return wrap
end

makeLoadingState = function(parent, text)
    local card = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 90),
        Parent = parent,
    })
    addCorner(card, 14)
    addStroke(card, Theme.BorderSoft, 1, 0)

    local label = makeLabel(card, text or "Loading...", 14, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
    label.Size = UDim2.fromScale(1, 1)

    task.spawn(function()
        local dots = 0
        while card.Parent do
            dots = (dots + 1) % 4
            label.Text = (text or "Loading") .. string.rep(".", dots)
            task.wait(0.35)
        end
    end)

    return card
end

makeEmptyState = function(parent, title, description)
    local card = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 120),
        Parent = parent,
    })
    addCorner(card, 14)
    addStroke(card, Theme.BorderSoft, 1, 0)

    local titleLabel = makeLabel(card, title or "Nothing found", 16, Theme.Text, FontBold, Enum.TextXAlignment.Center)
    titleLabel.Size = UDim2.new(1, -30, 0, 26)
    titleLabel.Position = UDim2.fromOffset(15, 26)

    local descriptionLabel = makeLabel(card, description or "Try another query.", 13, Theme.Muted, FontRegular, Enum.TextXAlignment.Center)
    descriptionLabel.TextWrapped = true
    descriptionLabel.Size = UDim2.new(1, -40, 0, 45)
    descriptionLabel.Position = UDim2.fromOffset(20, 55)

    return card
end

local function setImage(imageLabel, url)
    imageLabel.Image = ""
    imageLabel.ImageTransparency = 1

    if type(url) ~= "string" or url == "" then
        return
    end

    task.spawn(function()
        local source = resolveImageSource(url) or url
        if not imageLabel or not imageLabel.Parent then
            return
        end
        imageLabel.Image = source
        imageLabel.ImageTransparency = 0
    end)
end

local function makePlaceCard(parent, place, onOpen)
    local card = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.fromOffset(300, 114),
        Parent = parent,
    })
    addCorner(card, 14)
    addStroke(card, Theme.BorderSoft, 1, 0)

    local imageHolder = new("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.fromOffset(94, 94),
        Parent = card,
    })
    addCorner(imageHolder, 11)

    local image = new("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        Parent = imageHolder,
    })
    addCorner(image, 11)
    setImage(image, place.imageUrl)

    local title = makeLabel(card, tostring(place.name or "Unknown place"), 14, Theme.Text, FontBold)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Size = UDim2.new(1, -126, 0, 24)
    title.Position = UDim2.fromOffset(116, 15)

    local creator = makeLabel(card, "By " .. tostring(place.creatorName or "Unknown"), 12, Theme.Muted, FontRegular)
    creator.TextTruncate = Enum.TextTruncate.AtEnd
    creator.Size = UDim2.new(1, -126, 0, 20)
    creator.Position = UDim2.fromOffset(116, 41)

    local count = makeLabel(card, tostring(place.scriptCount or 0) .. " scripts", 12, Theme.Muted, FontMedium)
    count.Size = UDim2.new(1, -195, 0, 20)
    count.Position = UDim2.fromOffset(116, 68)

    local openButton = makeButton(card, "Open", function()
        onOpen(place)
    end, {
        size = UDim2.fromOffset(66, 30),
        background = Theme.AccentSoft,
        hover = Theme.AccentDark,
        textColor = Theme.Accent,
        textSize = 12,
        stroke = false,
        radius = 9,
    })
    openButton.Position = UDim2.new(1, -76, 1, -40)

    card.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface2 }):Play()
    end)

    card.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface }):Play()
    end)

    card.MouseButton1Click:Connect(function()
        onOpen(place)
    end)

    return card
end

local function accessKind(accessType)
    local access = tostring(accessType or ""):upper()
    if access == "NO KEY" then
        return "accent"
    elseif access == "KEY SYSTEM" then
        return "purple"
    elseif access == "PAID" then
        return "warning"
    end
    return "default"
end

local function makeScriptRow(parent, scriptData, onOpen)
    local row = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.new(1, 0, 0, State.compactMode and 72 or 88),
        Parent = parent,
    })
    addCorner(row, 12)
    addStroke(row, Theme.BorderSoft, 1, 0)

    local imageHolder = new("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.fromOffset(State.compactMode and 52 or 68, State.compactMode and 52 or 68),
        Parent = row,
    })
    addCorner(imageHolder, 10)

    local image = new("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        Parent = imageHolder,
    })
    addCorner(image, 10)
    setImage(image, scriptData.imageUrl)

    if isSaved(scriptData) then
        local savedDot = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -7, 0, 7),
            Size = UDim2.fromOffset(8, 8),
            Parent = imageHolder,
        })
        addCorner(savedDot, 4)
        addStroke(savedDot, Theme.Window, 2, 0)
    end

    local left = State.compactMode and 74 or 90

    local title = makeLabel(row, tostring(scriptData.title or "Untitled script"), 14, Theme.Text, FontBold)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Size = UDim2.new(1, -360, 0, 23)
    title.Position = UDim2.fromOffset(left, 13)

    local bylineText = tostring(scriptData.game or "Unknown game") .. "  •  By " .. tostring(scriptData.authorName or "Unknown")
    local lastRunText = formatRelativeTime(scriptData.lastRunAt)
    if lastRunText then
        bylineText = bylineText .. "  •  Ran " .. lastRunText
    end

    local byline = makeLabel(row, bylineText, 12, Theme.Muted, FontRegular)
    byline.TextTruncate = Enum.TextTruncate.AtEnd
    byline.Size = UDim2.new(1, -360, 0, 20)
    byline.Position = UDim2.fromOffset(left, 38)

    if not State.compactMode then
        local badgeHolder = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -360, 0, 24),
            Position = UDim2.fromOffset(left, 59),
            Parent = row,
        })
        addList(badgeHolder, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
        makeBadge(badgeHolder, scriptData.accessType or "UNKNOWN", accessKind(scriptData.accessType))
        if scriptData.highRisk then
            makeBadge(badgeHolder, "HIGH RISK", "warning")
        end
    end

    local stats = scriptData.stats or {}
    local views = makeLabel(row, "Views  " .. formatNumber(stats.views), 11, Theme.Muted, FontMedium, Enum.TextXAlignment.Right)
    views.Size = UDim2.fromOffset(80, 24)
    views.Position = UDim2.new(1, -270, 0.5, -12)

    local likes = makeLabel(row, "Likes  " .. formatNumber(stats.likes), 11, Theme.Muted, FontMedium, Enum.TextXAlignment.Right)
    likes.Size = UDim2.fromOffset(80, 24)
    likes.Position = UDim2.new(1, -180, 0.5, -12)

    local date = makeLabel(row, formatDate(scriptData.updatedAt), 11, Theme.Muted2, FontRegular, Enum.TextXAlignment.Right)
    date.Size = UDim2.fromOffset(88, 24)
    date.Position = UDim2.new(1, -100, 0.5, -12)

    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface2 }):Play()
    end)

    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface }):Play()
    end)

    row.MouseButton1Click:Connect(function()
        onOpen(scriptData)
    end)

    return row
end

local function makeScriptTile(parent, scriptData, onOpen)
    local card = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.fromOffset(172, 184),
        Parent = parent,
    })
    addCorner(card, 14)
    local cardStroke = addStroke(card, Theme.BorderSoft, 1, 0)

    local imageHolder = new("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 96),
        Parent = card,
    })
    addCorner(imageHolder, 14)

    local image = new("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        Parent = imageHolder,
    })
    addCorner(image, 14)
    setImage(image, scriptData.imageUrl)

    if scriptData.highRisk then
        local risk = makeLabel(imageHolder, "!", 11, Theme.Warning, FontBold, Enum.TextXAlignment.Center)
        risk.BackgroundColor3 = Theme.WarningSoft
        risk.BackgroundTransparency = 0
        risk.Position = UDim2.fromOffset(8, 8)
        risk.Size = UDim2.fromOffset(24, 24)
        addCorner(risk, 8)
        addStroke(risk, Theme.Warning, 1, 0.35)
    elseif isSaved(scriptData) then
        local saved = makeLabel(imageHolder, "SAVED", 8, Theme.Accent, FontBold, Enum.TextXAlignment.Center)
        saved.BackgroundColor3 = Theme.AccentSoft
        saved.BackgroundTransparency = 0
        saved.Position = UDim2.fromOffset(8, 8)
        saved.Size = UDim2.fromOffset(42, 24)
        addCorner(saved, 8)
    end

    local overlay = new("Frame", {
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 28),
        Position = UDim2.new(0, 0, 1, -28),
        Parent = imageHolder,
    })

    local gameLabel = makeLabel(overlay, tostring(scriptData.game or "Unknown game"), 11, Theme.ImageText, FontMedium)
    gameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    gameLabel.Size = UDim2.new(1, -14, 1, 0)
    gameLabel.Position = UDim2.fromOffset(7, 0)

    local title = makeLabel(card, tostring(scriptData.title or "Untitled script"), 13, Theme.Text, FontBold)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Size = UDim2.new(1, -16, 0, 22)
    title.Position = UDim2.fromOffset(8, 104)

    local badgeHolder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.fromOffset(8, 130),
        Parent = card,
    })
    addList(badgeHolder, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
    makeBadge(badgeHolder, scriptData.accessType or "UNKNOWN", accessKind(scriptData.accessType))

    local stats = scriptData.stats or {}
    local statLabel = makeLabel(card, formatNumber(stats.views) .. " views   " .. formatNumber(stats.likes) .. " likes", 10, Theme.Muted, FontRegular)
    statLabel.Size = UDim2.new(1, -16, 0, 20)
    statLabel.Position = UDim2.fromOffset(8, 157)

    card.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface2 }):Play()
        TweenService:Create(cardStroke, TweenInfo.new(0.12), { Color = Theme.AccentDark }):Play()
    end)

    card.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Surface }):Play()
        TweenService:Create(cardStroke, TweenInfo.new(0.12), { Color = Theme.BorderSoft }):Play()
    end)

    card.MouseButton1Click:Connect(function()
        onOpen(scriptData)
    end)

    return card
end

local function makePageHeader(parent, title, subtitle, onBack)
    local header = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 60),
        Parent = parent,
    })

    if onBack then
        local back = makeButton(header, "Back", onBack, {
            size = UDim2.fromOffset(84, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
            textSize = 13,
            radius = 10,
        })
        back.Position = UDim2.fromOffset(0, 7)
    end

    local left = onBack and 98 or 0
    local titleLabel = makeLabel(header, title or "", 20, Theme.Text, FontBold)
    titleLabel.Size = UDim2.new(1, -left, 0, 28)
    titleLabel.Position = UDim2.fromOffset(left, 2)

    if subtitle then
        local subtitleLabel = makeLabel(header, subtitle, 12, Theme.Muted, FontRegular)
        subtitleLabel.Size = UDim2.new(1, -left, 0, 22)
        subtitleLabel.Position = UDim2.fromOffset(left, 31)
    end

    return header
end

local function executeRemoteScript(scriptData)
    if State.loading then
        return
    end

    State.loading = true
    toast("Loading script code...", "warning", 2)

    task.spawn(function()
        local identifier = getScriptIdentifier(scriptData)
        local code, err = fetchScriptCode(scriptData, false)

        if err then
            State.loading = false
            toast(err.message, "error", 4)
            return
        end

        local loader = getGlobal("loadstring") or loadstring
        if type(loader) ~= "function" then
            State.loading = false
            toast("This executor does not support loadstring.", "error", 4)
            return
        end

        local compiled, compileError = loader(code)
        if not compiled then
            State.loading = false
            toast("Compilation failed: " .. tostring(compileError), "error", 5)
            return
        end

        local ok, runtimeError = pcall(compiled)
        if not ok then
            State.loading = false
            toast("Execution failed: " .. tostring(runtimeError), "error", 5)
            return
        end

        State.loading = false
        recordRecentScript(scriptData)
        toast("Script executed successfully.", "success", 4)

        task.spawn(function()
            apiRequest("POST", "/scripts/" .. urlEncode(identifier) .. "/execute")
        end)

        if State.autoCloseAfterExecute and ScreenGui then
            task.delay(0.4, function()
                if setHubVisible then
                    setHubVisible(false)
                elseif MainWindow then
                    MainWindow.Visible = false
                end
            end)
        end
    end)
end

local function requestExecution(scriptData)
    if scriptData.highRisk then
        local card, bodyLabel, actions = showModal(
            "High-risk script",
            "This script is marked as high risk. BobloScript does not guarantee that user-submitted code is safe. Review the script information before continuing.",
            function(actionsFrame)
                makeButton(actionsFrame, "Cancel", closeModal, {
                    size = UDim2.fromOffset(105, 38),
                    background = Theme.Surface2,
                    hover = Theme.Surface3,
                    textColor = Theme.Muted,
                })

                local executeButton = makeButton(actionsFrame, "Execute in 15s", nil, {
                    size = UDim2.fromOffset(150, 38),
                    background = Theme.WarningSoft,
                    hover = Theme.WarningSoft,
                    textColor = Theme.Warning,
                    strokeColor = Theme.Warning,
                    strokeTransparency = 0.4,
                })
                executeButton.Active = false

                task.spawn(function()
                    for seconds = 15, 1, -1 do
                        if not executeButton.Parent then
                            return
                        end
                        executeButton.Text = "Execute in " .. tostring(seconds) .. "s"
                        task.wait(1)
                    end

                    if not executeButton.Parent then
                        return
                    end

                    executeButton.Text = "Execute script"
                    executeButton.Active = true
                    executeButton.BackgroundColor3 = Theme.Accent
                    executeButton.TextColor3 = Theme.AccentText

                    executeButton.MouseButton1Click:Connect(function()
                        closeModal()
                        executeRemoteScript(scriptData)
                    end)
                end)
            end
        )

        if card then
            card.Size = UDim2.fromOffset(470, 270)
            bodyLabel.Size = UDim2.new(1, 0, 0, 130)
        end
    elseif not State.confirmBeforeExecute then
        executeRemoteScript(scriptData)
    else
        showModal(
            "Execute script?",
            "The selected script will be downloaded from BobloScript and executed by your current Roblox executor.",
            function(actions)
                makeButton(actions, "Cancel", closeModal, {
                    size = UDim2.fromOffset(105, 38),
                    background = Theme.Surface2,
                    hover = Theme.Surface3,
                    textColor = Theme.Muted,
                })

                makeButton(actions, "Execute script", function()
                    closeModal()
                    executeRemoteScript(scriptData)
                end, {
                    size = UDim2.fromOffset(145, 38),
                    background = Theme.Accent,
                    hover = Theme.AccentHover,
                    textColor = Theme.AccentText,
                    stroke = false,
                })
            end
        )
    end
end

openScriptDetails = function(scriptData, skipTransition)
    local function buildPage()
        local sourceScreen = State.screen
        if sourceScreen ~= "scriptDetails" then
            State.detailReturnScreen = sourceScreen
            if sourceScreen ~= "placeScripts" then
                State.selectedPlace = nil
            end
        end
        State.selectedScript = scriptData
        State.screen = "scriptDetails"
        updateSidebarSelection("")
        clear(Content)

        local scroller = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(scroller, 0, 0, 18, 24)

    local body = new("Frame", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20, 0),
        Size = UDim2.new(1, -44, 0, 0),
        Parent = scroller,
    })
    addList(body, Enum.FillDirection.Vertical, 12)

    makePageHeader(body, "Script details", "Review the information before executing.", function()
        if State.selectedPlace then
            openPlaceScripts(State.selectedPlace, State.placePage)
        else
            renderScreen(State.detailReturnScreen or "scripts")
        end
    end)

    local hero = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 184),
        Parent = body,
    })
    addCorner(hero, 16)
    addStroke(hero, Theme.BorderSoft, 1, 0)
    addPadding(hero, 16, 16, 16, 16)
    new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Surface2),
            ColorSequenceKeypoint.new(1, Theme.Surface),
        }),
        Rotation = 12,
        Parent = hero,
    })

    local imageHolder = new("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(190, 150),
        Parent = hero,
    })
    addCorner(imageHolder, 12)

    local image = new("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
        Parent = imageHolder,
    })
    addCorner(image, 12)
    setImage(image, scriptData.imageUrl)

    local title = makeLabel(hero, tostring(scriptData.title or "Untitled script"), 22, Theme.Text, FontBold)
    title.TextWrapped = true
    title.Size = UDim2.new(1, -218, 0, 55)
    title.Position = UDim2.fromOffset(208, 2)

    local author = makeLabel(
        hero,
        tostring(scriptData.game or "Unknown game") .. "  •  By " .. tostring(scriptData.authorName or "Unknown author"),
        13,
        Theme.Muted,
        FontRegular
    )
    author.Size = UDim2.new(1, -218, 0, 22)
    author.Position = UDim2.fromOffset(208, 58)

    local badgeHolder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -218, 0, 25),
        Position = UDim2.fromOffset(208, 84),
        Parent = hero,
    })
    addList(badgeHolder, Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
    makeBadge(badgeHolder, scriptData.accessType or "UNKNOWN", accessKind(scriptData.accessType))
    if scriptData.highRisk then
        makeBadge(badgeHolder, "HIGH RISK", "warning")
    end

    local stats = scriptData.stats or {}
    local statLabel = makeLabel(hero, formatNumber(stats.views) .. " views     " .. formatNumber(stats.likes) .. " likes", 12, Theme.Muted, FontMedium)
    statLabel.Size = UDim2.new(1, -218, 0, 22)
    statLabel.Position = UDim2.fromOffset(208, 116)

    local updated = makeLabel(hero, "Updated " .. formatDate(scriptData.updatedAt), 12, Theme.Muted2, FontRegular)
    updated.Size = UDim2.new(1, -218, 0, 22)
    updated.Position = UDim2.fromOffset(208, 140)

    local actionRow = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = body,
    })
    addList(actionRow, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    makeButton(actionRow, "Execute Script", function()
        requestExecution(scriptData)
    end, {
        size = UDim2.fromOffset(190, 42),
        background = Theme.Accent,
        hover = Theme.AccentHover,
        textColor = Theme.AccentText,
        stroke = false,
        textSize = 14,
    })

    makeButton(actionRow, "Copy code", function()
        copyScriptCode(scriptData)
    end, {
        size = UDim2.fromOffset(128, 42),
        background = Theme.Surface2,
        hover = Theme.Elevated,
        textColor = Theme.Text,
    })

    local saveText = isSaved(scriptData) and "Remove from saved" or "Save script"
    makeButton(actionRow, saveText, function(button)
        saveScript(scriptData)
        button.Text = isSaved(scriptData) and "Remove from saved" or "Save script"
        toast(isSaved(scriptData) and "Script saved." or "Script removed from saved.", "success", 2.5)
    end, {
        size = UDim2.fromOffset(165, 42),
        background = Theme.Surface2,
        hover = Theme.Surface3,
        textColor = Theme.Text,
    })

    if scriptData.slug then
        makeButton(actionRow, "Copy page link", function()
            copyText(
                "https://bobloscript.com/script/" .. tostring(scriptData.slug),
                "Script page link copied."
            )
        end, {
            size = UDim2.fromOffset(142, 42),
            background = Theme.Surface2,
            hover = Theme.Elevated,
            textColor = Theme.Muted,
        })
    end

    local infoGrid = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 170),
        Parent = body,
    })

    local grid = new("UIGridLayout", {
        CellPadding = UDim2.fromOffset(12, 12),
        CellSize = UDim2.new(0.5, -6, 0, 170),
        FillDirectionMaxCells = 2,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = infoGrid,
    })

    local function infoCard(titleText, content)
        local card = new("Frame", {
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = infoGrid,
        })
        addCorner(card, 14)
        addStroke(card, Theme.BorderSoft, 1, 0)
        addPadding(card, 16, 16, 15, 15)

        local heading = makeLabel(card, titleText, 14, Theme.Text, FontBold)
        heading.Size = UDim2.new(1, 0, 0, 24)

        local contentLabel = makeLabel(card, content, 13, Theme.Muted, FontRegular)
        contentLabel.TextWrapped = true
        contentLabel.TextYAlignment = Enum.TextYAlignment.Top
        contentLabel.Size = UDim2.new(1, 0, 1, -38)
        contentLabel.Position = UDim2.fromOffset(0, 34)

        return card
    end

    infoCard("Description", tostring(scriptData.summary or "No description was provided."))
    infoCard("Functions", tostring(scriptData.functions or "Open the script page to review the available functions."))

    if type(scriptData.tags) == "table" and #scriptData.tags > 0 then
        local tagsCard = new("Frame", {
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 90),
            Parent = body,
        })
        addCorner(tagsCard, 14)
        addStroke(tagsCard, Theme.BorderSoft, 1, 0)
        addPadding(tagsCard, 16, 16, 14, 14)

        local heading = makeLabel(tagsCard, "Tags", 14, Theme.Text, FontBold)
        heading.Size = UDim2.new(1, 0, 0, 22)

        local tags = new("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.fromOffset(0, 34),
            Parent = tagsCard,
        })
        addList(tags, Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

        for index, tag in ipairs(scriptData.tags) do
            if index > 7 then
                break
            end
            makeBadge(tags, tostring(tag), "default")
        end
    end

        if scriptData.functions == nil and scriptData.developer == nil then
            task.spawn(function()
                local identifier = scriptData.id or scriptData.slug
                if not identifier then
                    return
                end

                local payload, err = apiRequest("GET", "/scripts/" .. urlEncode(identifier))
                if err or type(payload) ~= "table" or type(payload.script) ~= "table" then
                    return
                end

                local fullScript = payload.script
                local activeIdentifier = State.selectedScript
                    and (State.selectedScript.id or State.selectedScript.slug)
                if activeIdentifier ~= identifier then
                    return
                end

                State.selectedScript = fullScript
                if State.screen == "scriptDetails" and isGuiAlive(Content) then
                    openScriptDetails(fullScript, true)
                end
            end)
        end
    end

    if skipTransition then
        buildPage()
    else
        transitionContent(buildPage)
    end
end

openPlaceScripts = function(place, page, skipTransition)
    local function buildPage()
        State.selectedPlace = place
        State.screen = "placeScripts"
        State.placePage = page or 1
        updateSidebarSelection("")
        clear(Content)

        local root = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(root, 20, 20, 18, 20)

    local header = makePageHeader(root, tostring(place.name or "Place"), tostring(place.scriptCount or 0) .. " scripts available", function()
        renderScreen("places")
    end)

    local controls = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.fromOffset(0, 64),
        Parent = root,
    })
    addList(controls, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    local filterButtons = {}
    local filters = {
        { key = "all", label = "All" },
        { key = "NO KEY", label = "No Key" },
        { key = "KEY SYSTEM", label = "Key System" },
        { key = "PAID", label = "Paid" },
    }

    local results = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 116),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, 0, 1, -164),
        Parent = root,
    })
    addList(results, Enum.FillDirection.Vertical, 9)

    local pagination = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 1, -40),
        Parent = root,
    })
    addList(pagination, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local cachedScripts = {}

    local function applyFilter()
        clear(results)
        local visibleCount = 0

        for _, scriptData in ipairs(cachedScripts) do
            local matchesRisk = State.showHighRisk or not scriptData.highRisk
            local matchesAccess = State.currentPlaceFilter == "all"
                or tostring(scriptData.accessType or ""):upper() == State.currentPlaceFilter

            if matchesRisk and matchesAccess then
                visibleCount = visibleCount + 1
                makeScriptRow(results, scriptData, openScriptDetails)
            end
        end

        if visibleCount == 0 then
            makeEmptyState(results, "No scripts in this filter", "Try another access filter or page.")
        end

        for key, button in pairs(filterButtons) do
            local selected = key == State.currentPlaceFilter
            button.BackgroundColor3 = selected and Theme.AccentSoft or Theme.Surface
            button.TextColor3 = selected and Theme.Accent or Theme.Muted
            button:SetAttribute("RestingColor", selected and Theme.AccentSoft or Theme.Surface)
        end
    end

    for _, filter in ipairs(filters) do
        local button = makeButton(controls, filter.label, function()
            State.currentPlaceFilter = filter.key
            applyFilter()
        end, {
            size = UDim2.fromOffset(filter.key == "KEY SYSTEM" and 104 or 76, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
            textSize = 13,
            radius = 10,
        })
        filterButtons[filter.key] = button
    end

    local searchHolder, searchBox = makeInput(controls, "Search on this page...", {
        size = UDim2.fromOffset(235, 34),
        textSize = 12,
        radius = 10,
    })
    searchHolder.LayoutOrder = 20

    local loading = makeLoadingState(results, "Loading scripts")

    local function renderPagination()
        clear(pagination)

        local previousButton = makeButton(pagination, "<", function()
            if State.placePage > 1 then
                openPlaceScripts(place, State.placePage - 1)
            end
        end, {
            size = UDim2.fromOffset(38, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
        })

        local pageLabel = makeLabel(pagination, "Page " .. tostring(State.placePage) .. " / " .. tostring(State.placeTotalPages), 12, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
        pageLabel.Size = UDim2.fromOffset(110, 34)

        local nextButton = makeButton(pagination, ">", function()
            if State.placePage < State.placeTotalPages then
                openPlaceScripts(place, State.placePage + 1)
            end
        end, {
            size = UDim2.fromOffset(38, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
        })
        setButtonEnabled(previousButton, State.placePage > 1)
        setButtonEnabled(nextButton, State.placePage < State.placeTotalPages)
    end

    local requestedPlacePage = State.placePage
    local requestedPlaceKey = place.id or place.slug or place.placeId
    task.spawn(function()
        local payload, err = apiRequest("GET", "/places/" .. urlEncode(place.slug) .. "/scripts?page=" .. tostring(requestedPlacePage) .. "&limit=12")
        local activePlaceKey = State.selectedPlace
            and (State.selectedPlace.id or State.selectedPlace.slug or State.selectedPlace.placeId)
        if State.screen ~= "placeScripts"
            or activePlaceKey ~= requestedPlaceKey
            or State.placePage ~= requestedPlacePage
            or not isGuiAlive(results) then
            return
        end
        loading:Destroy()

        if err then
            makeEmptyState(results, "Could not load scripts", err.message)
            toast(err.message, "error", 4)
            return
        end

        local result = payload and payload.result or {}
        cachedScripts = type(result.scripts) == "table" and result.scripts or {}
        State.placeTotalPages = math.max(tonumber(result.totalPages) or 1, 1)
        renderPagination()
        applyFilter()
    end)

        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local query = searchBox.Text:lower()
            clear(results)
            local count = 0

            for _, scriptData in ipairs(cachedScripts) do
                local title = tostring(scriptData.title or ""):lower()
                local gameName = tostring(scriptData.game or ""):lower()
                local matchesText = query == "" or title:find(query, 1, true) or gameName:find(query, 1, true)
                local matchesAccess = State.currentPlaceFilter == "all"
                    or tostring(scriptData.accessType or ""):upper() == State.currentPlaceFilter
                local matchesRisk = State.showHighRisk or not scriptData.highRisk

                if matchesText and matchesAccess and matchesRisk then
                    count = count + 1
                    makeScriptRow(results, scriptData, openScriptDetails)
                end
            end

            if count == 0 then
                makeEmptyState(results, "No matching scripts", "Change the search text or access filter.")
            end
        end)
    end

    if skipTransition then
        buildPage()
    else
        transitionContent(buildPage)
    end
end

local function renderHome()
    local scroller = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(scroller, 0, 0, 18, 24)

    local body = new("Frame", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -40, 0, 0),
        Parent = scroller,
    })
    addList(body, Enum.FillDirection.Vertical, 0)

    local hero = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(1, 0, 0, 180),
        Parent = body,
    })
    addCorner(hero, 18)
    addStroke(hero, Theme.BorderSoft, 1, 0)
    new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Surface),
            ColorSequenceKeypoint.new(0.58, Theme.Surface2),
            ColorSequenceKeypoint.new(1, Theme.AccentFaint),
        }),
        Rotation = 5,
        Parent = hero,
    })

    local glowLarge = new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -204, 0, -154),
        Size = UDim2.fromOffset(320, 320),
        Parent = hero,
    })
    addCorner(glowLarge, 160)

    local glowSmall = new("Frame", {
        BackgroundColor3 = Theme.Purple,
        BackgroundTransparency = 0.96,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -92, 0, 86),
        Size = UDim2.fromOffset(156, 156),
        Parent = hero,
    })
    addCorner(glowSmall, 78)

    local hour = tonumber(os.date("*t").hour) or 12
    local greeting = hour < 12 and "Good morning" or hour < 18 and "Good afternoon" or "Good evening"
    local playerName = LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name) or "there"
    if #playerName > 18 then
        playerName = playerName:sub(1, 18)
    end

    local catalogPill = new("Frame", {
        BackgroundColor3 = Theme.AccentFaint,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(24, 17),
        Size = UDim2.fromOffset(126, 23),
        Parent = hero,
    })
    addCorner(catalogPill, 8)
    addStroke(catalogPill, Theme.Accent, 1, 0.72)

    local catalogDot = new("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.fromOffset(7, 7),
        Parent = catalogPill,
    })
    addCorner(catalogDot, 4)

    local eyebrow = makeLabel(catalogPill, "PUBLIC CATALOG", 9, Theme.Accent, FontBold)
    eyebrow.Size = UDim2.new(1, -26, 1, 0)
    eyebrow.Position = UDim2.fromOffset(24, 0)

    local title = makeLabel(hero, greeting .. ", " .. playerName, 25, Theme.Text, FontHeavy)
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Size = UDim2.new(1, -48, 0, 38)
    title.Position = UDim2.fromOffset(24, 44)

    local subtitle = makeLabel(hero, "Search the catalog, check access, then run what you need.", 13, Theme.Muted, FontRegular)
    subtitle.Size = UDim2.new(1, -48, 0, 22)
    subtitle.Position = UDim2.fromOffset(24, 78)

    local searchWrap = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -48, 0, 44),
        Position = UDim2.fromOffset(24, 116),
        Parent = hero,
    })
    addList(searchWrap, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    local inputHolder, input = makeInput(searchWrap, "Search games, scripts, or functions...", {
        size = UDim2.new(1, -112, 1, 0),
        radius = 12,
        textSize = 14,
        searchIcon = true,
        background = Theme.Window,
    })
    inputHolder.Size = UDim2.new(1, -112, 1, 0)

    local function searchCatalog()
        local query = normalizeQuery(input.Text)
        if query:gsub("%s", "") == "" then
            toast("Enter a game, script, or function.", "warning", 2.5)
            return
        end

        rememberSearch(query)
        if GlobalSearchBox then
            GlobalSearchBox.Text = query
            GlobalSearchBox.CursorPosition = #query + 1
            setGlobalSearchVisible(true)
        end
    end

    makeButton(searchWrap, "Search", searchCatalog, {
        size = UDim2.fromOffset(102, 44),
        background = Theme.Accent,
        hover = Theme.AccentHover,
        textColor = Theme.AccentText,
        stroke = false,
        radius = 12,
        textSize = 14,
        font = FontBold,
    })

    input.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            searchCatalog()
        end
    end)

    local heroBottomSpacing = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 14),
        Parent = body,
    })

    local catalogBar = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = body,
    })
    addCorner(catalogBar, 15)
    addStroke(catalogBar, Theme.BorderSoft, 1, 0)

    local collectionTitle = makeLabel(catalogBar, "Trending scripts", 15, Theme.Text, FontBold)
    collectionTitle.Size = UDim2.new(1, -352, 0, 23)
    collectionTitle.Position = UDim2.fromOffset(16, 7)

    local collectionMeta = makeLabel(catalogBar, "Popular with the community right now", 11, Theme.Muted2, FontRegular)
    collectionMeta.Size = UDim2.new(1, -352, 0, 19)
    collectionMeta.Position = UDim2.fromOffset(16, 30)

    local quick = new("Frame", {
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(306, 38),
        Position = UDim2.new(1, -322, 0, 10),
        Parent = catalogBar,
    })
    addCorner(quick, 11)
    addStroke(quick, Theme.BorderSoft, 1, 0.35)
    addList(quick, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local listSpacing = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 16),
        Parent = body,
    })

    local homeListHolder = new("Frame", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = body,
    })
    addList(homeListHolder, Enum.FillDirection.Vertical, 12)

    local activeKind = State.homeKind == "nokey" and "nokey"
        or State.homeKind == "latest" and "latest"
        or "trending"
    local kindLoadSerial = 0

    local kindButtons = {}
    local kinds = {
        { key = "trending", label = "Trending" },
        { key = "nokey", label = "No Key" },
        { key = "latest", label = "Latest" },
    }

    local function loadKind(kind)
        kindLoadSerial = kindLoadSerial + 1
        local requestSerial = kindLoadSerial
        activeKind = kind
        State.homeKind = kind
        clear(homeListHolder)

        if kind == "trending" then
            collectionTitle.Text = "Trending scripts"
            collectionMeta.Text = "Popular with the community right now"
        elseif kind == "nokey" then
            collectionTitle.Text = "No Key scripts"
            collectionMeta.Text = "Open and run without a key flow"
        else
            collectionTitle.Text = "Latest scripts"
            collectionMeta.Text = "Recently added to the catalog"
        end

        local loading = makeLoadingState(homeListHolder, "Loading scripts")

        for key, button in pairs(kindButtons) do
            local selected = key == kind
            button.BackgroundColor3 = selected and Theme.AccentSoft or Theme.Surface2
            button.TextColor3 = selected and Theme.Accent or Theme.Muted
            button:SetAttribute("RestingColor", selected and Theme.AccentSoft or Theme.Surface2)
        end

        task.spawn(function()
            local payload, err = apiRequest("GET", "/scripts/home/" .. kind)
            if requestSerial ~= kindLoadSerial
                or State.screen ~= "home"
                or not isGuiAlive(homeListHolder) then
                return
            end
            loading:Destroy()

            if err then
                makeEmptyState(homeListHolder, "Could not load scripts", err.message)
                toast(err.message, "error", 4)
                return
            end

            local scripts = payload and payload.result and payload.result.scripts or {}
            if type(scripts) ~= "table" or #scripts == 0 then
                makeEmptyState(homeListHolder, "No scripts found", "This collection is currently empty.")
                return
            end

            local gridHolder = new("Frame", {
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                Parent = homeListHolder,
            })

            local grid = new("UIGridLayout", {
                CellPadding = UDim2.fromOffset(12, 12),
                CellSize = UDim2.new(0.25, -9, 0, 184),
                FillDirectionMaxCells = 4,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = gridHolder,
            })

            local visible = 0
            for _, scriptData in ipairs(scripts) do
                if State.showHighRisk or not scriptData.highRisk then
                    visible = visible + 1
                    makeScriptTile(gridHolder, scriptData, openScriptDetails)
                    if visible >= 8 then
                        break
                    end
                end
            end

            local rows = math.ceil(math.max(visible, 1) / 4)
            gridHolder.Size = UDim2.new(1, 0, 0, rows * 184 + math.max(rows - 1, 0) * 12)
        end)
    end

    for _, kind in ipairs(kinds) do
        local button = makeButton(quick, kind.label, function()
            loadKind(kind.key)
        end, {
            size = UDim2.fromOffset(98, 30),
            background = Theme.Surface2,
            hover = Theme.Surface3,
            textColor = Theme.Muted,
            textSize = 11,
            stroke = false,
            radius = 9,
            font = FontMedium,
        })
        kindButtons[kind.key] = button
    end

    loadKind(activeKind)
end

local function renderPlaces()
    local root = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(root, 20, 20, 18, 18)

    makePageHeader(root, "Places", "Search Roblox places and open their available scripts.")

    local searchRow = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.fromOffset(0, 63),
        Parent = root,
    })
    addList(searchRow, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    local searchHolder, searchBox = makeInput(searchRow, "Search places...", {
        size = UDim2.new(1, -110, 0, 42),
        textSize = 15,
    })
    searchHolder.Size = UDim2.new(1, -110, 0, 42)
    searchBox.Text = State.pendingPlaceQuery or ""
    State.pendingPlaceQuery = nil

    local searchButton = makeButton(searchRow, "Search", nil, {
        size = UDim2.fromOffset(100, 42),
        background = Theme.Accent,
        hover = Theme.AccentHover,
        textColor = Theme.AccentText,
        stroke = false,
        textSize = 15,
    })

    local results = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 119),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, 0, 1, -167),
        Parent = root,
    })

    local grid = new("UIGridLayout", {
        CellPadding = UDim2.fromOffset(12, 12),
        CellSize = UDim2.new(0.5, -6, 0, 114),
        FillDirectionMaxCells = 2,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = results,
    })

    local pagination = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 1, -40),
        Parent = root,
    })
    addList(pagination, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local currentQuery = ""
    local placeLoadSerial = 0

    local function loadPlaces(page)
        placeLoadSerial = placeLoadSerial + 1
        local requestSerial = placeLoadSerial
        State.placePage = page or 1
        currentQuery = normalizeQuery(searchBox.Text)
        local requestPage = State.placePage
        local requestQuery = currentQuery
        clear(results)
        clear(pagination)

        local loading = new("Frame", {
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 114),
            Parent = results,
        })
        addCorner(loading, 14)
        local label = makeLabel(loading, "Loading places...", 14, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
        label.Size = UDim2.fromScale(1, 1)

        task.spawn(function()
            local path = "/places?q=" .. urlEncode(requestQuery) .. "&page=" .. tostring(requestPage) .. "&limit=12"
            local payload, err = apiRequest("GET", path)
            if requestSerial ~= placeLoadSerial
                or State.screen ~= "places"
                or not isGuiAlive(results) then
                return
            end
            loading:Destroy()

            if err then
                local empty = new("Frame", {
                    BackgroundColor3 = Theme.Surface,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 114),
                    Parent = results,
                })
                addCorner(empty, 14)
                local errorLabel = makeLabel(empty, err.message, 13, Theme.Danger, FontMedium, Enum.TextXAlignment.Center)
                errorLabel.TextWrapped = true
                errorLabel.Size = UDim2.new(1, -30, 1, 0)
                errorLabel.Position = UDim2.fromOffset(15, 0)
                toast(err.message, "error", 4)
                return
            end

            local result = payload and payload.result or {}
            local places = type(result.places) == "table" and result.places or {}
            State.placeTotalPages = math.max(tonumber(result.totalPages) or 1, 1)

            if #places == 0 then
                local empty = new("Frame", {
                    BackgroundColor3 = Theme.Surface,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 114),
                    Parent = results,
                })
                addCorner(empty, 14)
                local emptyLabel = makeLabel(empty, "No places found. Try another game name.", 13, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
                emptyLabel.TextWrapped = true
                emptyLabel.Size = UDim2.new(1, -30, 1, 0)
                emptyLabel.Position = UDim2.fromOffset(15, 0)
            else
                for _, place in ipairs(places) do
                    makePlaceCard(results, place, function(selected)
                        openPlaceScripts(selected, 1)
                    end)
                end
            end

            local previousButton = makeButton(pagination, "<", function()
                if State.placePage > 1 then
                    loadPlaces(State.placePage - 1)
                end
            end, {
                size = UDim2.fromOffset(38, 34),
                background = Theme.Surface,
                hover = Theme.Surface2,
                textColor = Theme.Muted,
            })

            local pageLabel = makeLabel(pagination, "Page " .. tostring(State.placePage) .. " / " .. tostring(State.placeTotalPages), 12, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
            pageLabel.Size = UDim2.fromOffset(110, 34)

            local nextButton = makeButton(pagination, ">", function()
                if State.placePage < State.placeTotalPages then
                    loadPlaces(State.placePage + 1)
                end
            end, {
                size = UDim2.fromOffset(38, 34),
                background = Theme.Surface,
                hover = Theme.Surface2,
                textColor = Theme.Muted,
            })
            setButtonEnabled(previousButton, State.placePage > 1)
            setButtonEnabled(nextButton, State.placePage < State.placeTotalPages)
        end)
    end

    searchButton.MouseButton1Click:Connect(function()
        rememberSearch(searchBox.Text)
        loadPlaces(1)
    end)

    searchBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            rememberSearch(searchBox.Text)
            loadPlaces(1)
        end
    end)

    loadPlaces(1)
end

local function renderScripts()
    local root = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(root, 20, 20, 18, 18)

    makePageHeader(root, "Scripts", "Search the complete BobloScript catalog.")

    local searchRow = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Position = UDim2.fromOffset(0, 63),
        Parent = root,
    })
    addList(searchRow, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    local searchHolder, searchBox = makeInput(searchRow, "Search scripts...", {
        size = UDim2.new(1, -110, 0, 42),
        textSize = 15,
    })
    searchHolder.Size = UDim2.new(1, -110, 0, 42)
    searchBox.Text = State.pendingScriptQuery or ""
    State.pendingScriptQuery = nil

    local searchButton = makeButton(searchRow, "Search", nil, {
        size = UDim2.fromOffset(100, 42),
        background = Theme.Accent,
        hover = Theme.AccentHover,
        textColor = Theme.AccentText,
        stroke = false,
        textSize = 15,
    })

    local filters = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 38),
        Position = UDim2.fromOffset(0, 112),
        Parent = root,
    })
    addList(filters, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    local selectedAccess = "all"
    local selectedSort = "newest"
    local accessButtons = {}
    local scriptLoadSerial = 0

    local accessOptions = {
        { key = "all", label = "All" },
        { key = "no-key", label = "No Key" },
        { key = "key-system", label = "Key System" },
    }

    local results = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 160),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, 0, 1, -208),
        Parent = root,
    })
    addList(results, Enum.FillDirection.Vertical, 9)

    local pagination = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 1, -40),
        Parent = root,
    })
    addList(pagination, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

    local function updateFilterButtons()
        for key, button in pairs(accessButtons) do
            local selected = key == selectedAccess
            button.BackgroundColor3 = selected and Theme.AccentSoft or Theme.Surface
            button.TextColor3 = selected and Theme.Accent or Theme.Muted
            button:SetAttribute("RestingColor", selected and Theme.AccentSoft or Theme.Surface)
        end
    end

    local function loadScripts(page)
        scriptLoadSerial = scriptLoadSerial + 1
        local requestSerial = scriptLoadSerial
        State.scriptPage = page or 1
        local requestPage = State.scriptPage
        local requestQuery = normalizeQuery(searchBox.Text)
        local requestAccess = selectedAccess
        local requestSort = selectedSort
        clear(results)
        clear(pagination)
        local loading = makeLoadingState(results, "Loading scripts")

        task.spawn(function()
            local path = "/scripts?q=" .. urlEncode(requestQuery)
                .. "&access=" .. urlEncode(requestAccess)
                .. "&sort=" .. urlEncode(requestSort)
                .. "&page=" .. tostring(requestPage)
                .. "&limit=12"

            local payload, err = apiRequest("GET", path)
            if requestSerial ~= scriptLoadSerial
                or State.screen ~= "scripts"
                or not isGuiAlive(results) then
                return
            end
            loading:Destroy()

            if err then
                makeEmptyState(results, "Could not load scripts", err.message)
                toast(err.message, "error", 4)
                return
            end

            local result = payload and payload.result or {}
            local scripts = type(result.scripts) == "table" and result.scripts or {}
            State.scriptTotalPages = math.max(tonumber(result.totalPages) or 1, 1)

            local visible = 0
            for _, scriptData in ipairs(scripts) do
                if State.showHighRisk or not scriptData.highRisk then
                    visible = visible + 1
                    makeScriptRow(results, scriptData, openScriptDetails)
                end
            end

            if visible == 0 then
                makeEmptyState(results, "No scripts found", "Change the search text or filter.")
            end

            local previousButton = makeButton(pagination, "<", function()
                if State.scriptPage > 1 then
                    loadScripts(State.scriptPage - 1)
                end
            end, {
                size = UDim2.fromOffset(38, 34),
                background = Theme.Surface,
                hover = Theme.Surface2,
                textColor = Theme.Muted,
            })

            local pageLabel = makeLabel(pagination, "Page " .. tostring(State.scriptPage) .. " / " .. tostring(State.scriptTotalPages), 12, Theme.Muted, FontMedium, Enum.TextXAlignment.Center)
            pageLabel.Size = UDim2.fromOffset(110, 34)

            local nextButton = makeButton(pagination, ">", function()
                if State.scriptPage < State.scriptTotalPages then
                    loadScripts(State.scriptPage + 1)
                end
            end, {
                size = UDim2.fromOffset(38, 34),
                background = Theme.Surface,
                hover = Theme.Surface2,
                textColor = Theme.Muted,
            })
            setButtonEnabled(previousButton, State.scriptPage > 1)
            setButtonEnabled(nextButton, State.scriptPage < State.scriptTotalPages)
        end)
    end

    for _, option in ipairs(accessOptions) do
        local button = makeButton(filters, option.label, function()
            selectedAccess = option.key
            updateFilterButtons()
            loadScripts(1)
        end, {
            size = UDim2.fromOffset(option.key == "key-system" and 104 or 76, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
            textSize = 12,
            radius = 10,
        })
        accessButtons[option.key] = button
    end

    local sortButton = makeButton(filters, "Sort: Newest", nil, {
        size = UDim2.fromOffset(126, 34),
        background = Theme.Surface,
        hover = Theme.Surface2,
        textColor = Theme.Muted,
        textSize = 12,
        radius = 10,
    })
    sortButton.LayoutOrder = 10

    local sortOptions = {
        { key = "newest", label = "Newest" },
        { key = "updated", label = "Updated" },
        { key = "most-views", label = "Most views" },
        { key = "trending", label = "Trending" },
    }
    sortButton.MouseButton1Click:Connect(function()
        showModal("Sort scripts", "Choose how the catalog should be ordered.", function(actions)
            for _, option in ipairs(sortOptions) do
                makeButton(actions, option.label, function()
                    selectedSort = option.key
                    sortButton.Text = "Sort: " .. option.label
                    closeModal()
                    loadScripts(1)
                end, {
                    size = UDim2.fromOffset(option.key == "most-views" and 92 or 82, 36),
                    background = selectedSort == option.key and Theme.AccentSoft or Theme.Surface2,
                    hover = Theme.Surface3,
                    textColor = selectedSort == option.key and Theme.Accent or Theme.Muted,
                    textSize = 11,
                    radius = 9,
                })
            end
        end)
    end)

    searchButton.MouseButton1Click:Connect(function()
        rememberSearch(searchBox.Text)
        loadScripts(1)
    end)

    searchBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            rememberSearch(searchBox.Text)
            loadScripts(1)
        end
    end)

    updateFilterButtons()
    loadScripts(1)
end

local function renderSaved()
    local root = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(root, 20, 20, 18, 18)

    makePageHeader(root, "Saved scripts", "Scripts stored locally on this device.")

    local results = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 66),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, 0, 1, -66),
        Parent = root,
    })
    addList(results, Enum.FillDirection.Vertical, 9)

    local count = 0
    for _, scriptData in ipairs(getSavedScriptsSorted()) do
        count = count + 1
        makeScriptRow(results, scriptData, openScriptDetails)
    end

    if count == 0 then
        makeEmptyState(results, "No saved scripts", "Open a script and press Save script.")
    end
end

local function renderRecent()
    local root = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(root, 20, 20, 18, 18)

    makePageHeader(root, "Recently executed", "Quickly return to scripts you ran on this device.")

    if #State.recentScripts > 0 then
        local clearButton = makeButton(root, "Clear history", function()
            showModal(
                "Clear execution history?",
                "This removes the local list of recently executed scripts. It does not change your saved scripts.",
                function(actions)
                    makeButton(actions, "Cancel", closeModal, {
                        size = UDim2.fromOffset(100, 38),
                        background = Theme.Surface2,
                        hover = Theme.Surface3,
                        textColor = Theme.Muted,
                    })
                    makeButton(actions, "Clear", function()
                        State.recentScripts = {}
                        writeConfig()
                        updateSidebarBadges()
                        closeModal()
                        renderScreen("recent")
                        toast("Execution history cleared.", "success", 2.5)
                    end, {
                        size = UDim2.fromOffset(100, 38),
                        background = Theme.DangerSoft,
                        hover = Theme.Danger,
                        textColor = Theme.Danger,
                    })
                end
            )
        end, {
            size = UDim2.fromOffset(118, 34),
            background = Theme.Surface,
            hover = Theme.Surface2,
            textColor = Theme.Muted,
            textSize = 12,
        })
        clearButton.Position = UDim2.new(1, -118, 0, 7)
    end

    local results = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 66),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, 0, 1, -66),
        Parent = root,
    })
    addList(results, Enum.FillDirection.Vertical, 9)

    for _, scriptData in ipairs(State.recentScripts) do
        makeScriptRow(results, scriptData, openScriptDetails)
    end

    if #State.recentScripts == 0 then
        makeEmptyState(results, "No execution history", "Scripts appear here after a successful run.")
    end
end

local function makeToggle(parent, labelText, description, initialValue, callback)
    local row = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, description and 55 or 42),
        Parent = parent,
    })

    local label = makeLabel(row, labelText, 13, Theme.Text, FontMedium)
    label.Size = UDim2.new(1, -70, 0, 22)
    label.Position = UDim2.fromOffset(0, description and 4 or 10)

    if description then
        local desc = makeLabel(row, description, 11, Theme.Muted, FontRegular)
        desc.TextWrapped = true
        desc.Size = UDim2.new(1, -70, 0, 26)
        desc.Position = UDim2.fromOffset(0, 26)
    end

    local switch = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = initialValue and Theme.Accent or Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.fromOffset(46, 24),
        Position = UDim2.new(1, -46, 0.5, -12),
        Parent = row,
    })
    addCorner(switch, 12)

    local knob = new("Frame", {
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(18, 18),
        Position = initialValue and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3),
        Parent = switch,
    })
    addCorner(knob, 9)

    local value = initialValue
    switch.MouseButton1Click:Connect(function()
        value = not value
        TweenService:Create(switch, TweenInfo.new(0.15), {
            BackgroundColor3 = value and Theme.Accent or Theme.Surface3,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = value and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3),
        }):Play()
        callback(value)
    end)

    return row
end

local function renderPreferences()
    local scroller = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 3,
        Size = UDim2.fromScale(1, 1),
        Parent = Content,
    })
    addPadding(scroller, 0, 0, 18, 24)

    local body = new("Frame", {
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20, 0),
        Size = UDim2.new(1, -44, 0, 0),
        Parent = scroller,
    })
    addList(body, Enum.FillDirection.Vertical, 14)

    makePageHeader(body, "Preferences", "Control local Hub behavior and saved data.")

    local publicCard = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 106),
        Parent = body,
    })
    addCorner(publicCard, 15)
    addStroke(publicCard, Theme.BorderSoft, 1, 0)
    addPadding(publicCard, 16, 16, 14, 14)

    local publicTitle = makeLabel(publicCard, "Public API", 15, Theme.Text, FontBold)
    publicTitle.Size = UDim2.new(1, 0, 0, 24)

    local publicDescription = makeLabel(
        publicCard,
        "BobloScript Hub works without registration or an API key. Request limits are applied automatically by IP.",
        12,
        Theme.Muted,
        FontRegular
    )
    publicDescription.TextWrapped = true
    publicDescription.TextYAlignment = Enum.TextYAlignment.Top
    publicDescription.Size = UDim2.new(1, -150, 0, 52)
    publicDescription.Position = UDim2.fromOffset(0, 30)

    local checkButton = makeButton(publicCard, "Check status", function()
        checkApiHealth(true)
    end, {
        size = UDim2.fromOffset(128, 36),
        background = Theme.Surface2,
        hover = Theme.Elevated,
        textColor = Theme.Text,
        textSize = 12,
    })
    checkButton.Position = UDim2.new(1, -128, 0, 34)

    local preferencesCard = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 0),
        Parent = body,
    })
    addCorner(preferencesCard, 15)
    addStroke(preferencesCard, Theme.BorderSoft, 1, 0)
    addPadding(preferencesCard, 16, 16, 14, 14)
    addList(preferencesCard, Enum.FillDirection.Vertical, 2)

    local prefTitle = makeLabel(preferencesCard, "Interface", 15, Theme.Text, FontBold)
    prefTitle.Size = UDim2.new(1, 0, 0, 28)

    makeToggle(preferencesCard, "Show high-risk scripts", nil, State.showHighRisk, function(value)
        State.showHighRisk = value
        writeConfig()
    end)

    makeToggle(
        preferencesCard,
        "Confirm before execution",
        "High-risk scripts always keep the 15-second safety check.",
        State.confirmBeforeExecute,
        function(value)
            State.confirmBeforeExecute = value
            writeConfig()
        end
    )

    makeToggle(preferencesCard, "Close Hub after execute", nil, State.autoCloseAfterExecute, function(value)
        State.autoCloseAfterExecute = value
        writeConfig()
    end)

    makeToggle(preferencesCard, "Compact script rows", nil, State.compactMode, function(value)
        State.compactMode = value
        writeConfig()
    end)

    makeToggle(preferencesCard, "Reduce interface motion", nil, State.reduceMotion, function(value)
        State.reduceMotion = value
        writeConfig()
    end)

    local dataCard = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 176),
        Parent = body,
    })
    addCorner(dataCard, 15)
    addStroke(dataCard, Theme.BorderSoft, 1, 0)
    addPadding(dataCard, 16, 16, 14, 14)

    local dataTitle = makeLabel(dataCard, "Local data", 15, Theme.Text, FontBold)
    dataTitle.Size = UDim2.new(1, 0, 0, 28)

    local clearSaved = makeButton(dataCard, "Clear saved scripts", function()
        State.savedScripts = {}
        writeConfig()
        updateSidebarBadges()
        toast("Saved scripts cleared.", "success", 3)
    end, {
        size = UDim2.fromOffset(160, 38),
        background = Theme.Surface2,
        hover = Theme.Surface3,
        textColor = Theme.Text,
    })
    clearSaved.Position = UDim2.fromOffset(0, 45)

    local clearRecent = makeButton(dataCard, "Clear run history", function()
        State.recentScripts = {}
        writeConfig()
        updateSidebarBadges()
        toast("Execution history cleared.", "success", 3)
    end, {
        size = UDim2.fromOffset(160, 38),
        background = Theme.Surface2,
        hover = Theme.Surface3,
        textColor = Theme.Text,
    })
    clearRecent.Position = UDim2.fromOffset(174, 45)

    local clearCacheButton = makeButton(dataCard, "Clear session cache", function()
        clearApiCache()
        toast("Session cache cleared.", "success", 3)
    end, {
        size = UDim2.fromOffset(164, 38),
        background = Theme.Surface2,
        hover = Theme.Surface3,
        textColor = Theme.Text,
    })
    clearCacheButton.Position = UDim2.fromOffset(348, 45)

    local fileSupport = makeLabel(
        dataCard,
        hasFileSystem() and "Executor file storage: available" or "Executor file storage: unavailable",
        11,
        Theme.Muted,
        FontRegular
    )
    fileSupport.Size = UDim2.new(1, 0, 0, 22)
    fileSupport.Position = UDim2.fromOffset(0, 96)

    local capabilityText = "HTTP: " .. (getRequestFunction() and "ready" or "missing")
        .. "   •   Clipboard: " .. (getClipboardFunction() and "ready" or "missing")
        .. "   •   loadstring: " .. ((getGlobal("loadstring") or loadstring) and "ready" or "missing")
    local capabilities = makeLabel(dataCard, capabilityText, 11, Theme.Muted2, FontRegular)
    capabilities.Size = UDim2.new(1, 0, 0, 22)
    capabilities.Position = UDim2.fromOffset(0, 120)

    local shortcutsCard = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 104),
        Parent = body,
    })
    addCorner(shortcutsCard, 15)
    addStroke(shortcutsCard, Theme.BorderSoft, 1, 0)
    addPadding(shortcutsCard, 16, 16, 14, 14)

    local shortcutsTitle = makeLabel(shortcutsCard, "Keyboard shortcuts", 15, Theme.Text, FontBold)
    shortcutsTitle.Size = UDim2.new(1, 0, 0, 26)

    local shortcutsText = makeLabel(
        shortcutsCard,
        "Ctrl + K  Global search     •     Right Shift  Hide or show Hub     •     Esc  Close search or modal",
        12,
        Theme.Muted,
        FontRegular
    )
    shortcutsText.TextWrapped = true
    shortcutsText.Size = UDim2.new(1, 0, 0, 46)
    shortcutsText.Position = UDim2.fromOffset(0, 32)
end

renderScreen = function(screenName, skipTransition)
    local function buildPage()
        closeGlobalSearch(false)
        State.screen = screenName
        if screenName == "home"
            or screenName == "places"
            or screenName == "scripts"
            or screenName == "saved"
            or screenName == "recent"
            or screenName == "preferences" then
            State.lastScreen = screenName
            writeConfig()
        end
        updateSidebarSelection(screenName)
        clear(Content)

        if screenName == "home" then
            renderHome()
        elseif screenName == "places" then
            renderPlaces()
        elseif screenName == "scripts" then
            renderScripts()
        elseif screenName == "saved" then
            renderSaved()
        elseif screenName == "recent" then
            renderRecent()
        elseif screenName == "preferences" then
            renderPreferences()
        else
            renderHome()
        end
    end

    if skipTransition then
        buildPage()
    else
        transitionContent(buildPage)
    end
end

local function makeDraggable(handle, target, options)
    options = options or {}

    local deadzone = tonumber(options.deadzone) or 6
    local onClick = options.onClick

    local dragging = false
    local moved = false
    local activeTouch = nil
    local inputMode = nil
    local startPointer = nil
    local currentPointer = nil
    local startTopLeft = nil
    local renderConnection = nil

    local function getPointer(input)
        if input and input.UserInputType == Enum.UserInputType.Touch then
            return input.Position
        end
        return UserInputService:GetMouseLocation()
    end

    local function getTargetSize()
        if target == MainWindow then
            return Vector2.new(WINDOW_WIDTH * windowFitScale, WINDOW_HEIGHT * windowFitScale)
        end
        return target.AbsoluteSize
    end

    local function getTopLeft(targetSize)
        local viewport = getViewportSize()
        local position = target.Position
        local anchor = target.AnchorPoint

        return Vector2.new(
            position.X.Scale * viewport.X + position.X.Offset - targetSize.X * anchor.X,
            position.Y.Scale * viewport.Y + position.Y.Offset - targetSize.Y * anchor.Y
        )
    end

    local function applyPosition(pointer)
        if not dragging or not startPointer or not startTopLeft or not pointer then
            return
        end

        local delta = pointer - startPointer
        if not moved then
            if delta.Magnitude < deadzone then
                return
            end
            moved = true
        end

        local viewport = getViewportSize()
        local targetSize = getTargetSize()
        local anchor = target.AnchorPoint

        local left = math.clamp(
            startTopLeft.X + delta.X,
            8,
            math.max(8, viewport.X - targetSize.X - 8)
        )
        local top = math.clamp(
            startTopLeft.Y + delta.Y,
            8,
            math.max(8, viewport.Y - targetSize.Y - 8)
        )

        target.Position = UDim2.fromOffset(
            left + targetSize.X * anchor.X,
            top + targetSize.Y * anchor.Y
        )

        if target == MainWindow then
            syncWindowShadows()
        elseif target == FloatingToggle then
            syncFloatingToggleShadow()
        end
    end

    local function stopDragging()
        if not dragging then
            return
        end

        local shouldClick = not moved
        dragging = false
        activeTouch = nil
        inputMode = nil
        startPointer = nil
        currentPointer = nil
        startTopLeft = nil

        if renderConnection then
            renderConnection:Disconnect()
            renderConnection = nil
        end

        if shouldClick and type(onClick) == "function" then
            task.defer(onClick)
        end
    end

    handle.InputBegan:Connect(function(input)
        local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
        local isTouch = input.UserInputType == Enum.UserInputType.Touch

        if not isMouse and not isTouch then
            return
        end

        dragging = true
        moved = false
        inputMode = isTouch and "touch" or "mouse"
        activeTouch = isTouch and input or nil
        startPointer = getPointer(input)
        currentPointer = startPointer

        local targetSize = getTargetSize()
        startTopLeft = getTopLeft(targetSize)

        if renderConnection then
            renderConnection:Disconnect()
        end

        renderConnection = trackConnection(RunService.RenderStepped:Connect(function()
            if dragging then
                applyPosition(currentPointer)
            end
        end))

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                stopDragging()
            end
        end)
    end)

    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if inputMode == "mouse" and input.UserInputType == Enum.UserInputType.MouseMovement then
            currentPointer = UserInputService:GetMouseLocation()
        elseif inputMode == "touch" and input == activeTouch then
            currentPointer = input.Position
        end
    end))

    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end

        if inputMode == "mouse" and input.UserInputType == Enum.UserInputType.MouseButton1 then
            stopDragging()
        elseif inputMode == "touch" and input == activeTouch then
            stopDragging()
        end
    end))
end

local function buildUi()
    loadConfig()
    applyTheme(State.themeMode)

    local old = nil
    local parent = nil
    local sharedEnvironment = safeCall(function()
        return getgenv and getgenv() or _G
    end)

    if sharedEnvironment and type(sharedEnvironment.__BOBLOSCRIPT_HUB_CLEANUP) == "function" then
        pcall(sharedEnvironment.__BOBLOSCRIPT_HUB_CLEANUP)
    end
    disconnectTrackedConnections()

    if type(getGlobal("gethui")) == "function" then
        parent = safeCall(getGlobal("gethui"))
    end
    parent = parent or CoreGui

    old = parent:FindFirstChild("BobloScriptHub")
    if old then
        old:Destroy()
    end

    ScreenGui = new("ScreenGui", {
        Name = "BobloScriptHub",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = parent,
    })

    local function cleanupCurrentHub()
        disconnectTrackedConnections()
        if ScreenGui and ScreenGui.Parent then
            ScreenGui:Destroy()
        end
        if sharedEnvironment and sharedEnvironment.__BOBLOSCRIPT_HUB_CLEANUP == cleanupCurrentHub then
            sharedEnvironment.__BOBLOSCRIPT_HUB_CLEANUP = nil
        end
    end

    if sharedEnvironment then
        sharedEnvironment.__BOBLOSCRIPT_HUB_CLEANUP = cleanupCurrentHub
    end

    WindowShadowOuter = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WINDOW_WIDTH + 26, WINDOW_HEIGHT + 30),
        ZIndex = 0,
        Parent = ScreenGui,
    })
    addCorner(WindowShadowOuter, 28)

    WindowShadowInner = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.93,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 18),
        Size = UDim2.fromOffset(WINDOW_WIDTH + 56, WINDOW_HEIGHT + 58),
        ZIndex = 0,
        Parent = ScreenGui,
    })
    addCorner(WindowShadowInner, 34)

    MainWindow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Window,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
        Parent = ScreenGui,
    })
    addCorner(MainWindow, 18)
    addStroke(MainWindow, Theme.Border, 1, 0)

    WindowScale = new("UIScale", {
        Scale = 1,
        Parent = MainWindow,
    })

    local topbar = new("Frame", {
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
        Parent = MainWindow,
    })
    addCorner(topbar, 18)
    new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Sidebar),
            ColorSequenceKeypoint.new(1, Theme.Window),
        }),
        Rotation = 0,
        Parent = topbar,
    })

    local separator = new("Frame", {
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        Parent = topbar,
    })

    local brandMark = new("Frame", {
        BackgroundColor3 = Theme.AccentSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 13),
        Size = UDim2.fromOffset(36, 36),
        Parent = topbar,
    })
    addCorner(brandMark, 11)
    addStroke(brandMark, Theme.Accent, 1, 0.45)

    local brandLetter = makeLabel(brandMark, "B", 17, Theme.Accent, FontHeavy, Enum.TextXAlignment.Center)
    brandLetter.Size = UDim2.fromScale(1, 1)

    local logoRichText = State.themeMode == "light"
        and '<font color="rgb(25,30,39)">Boblo</font><font color="rgb(23,184,159)">Script</font>'
        or '<font color="rgb(242,245,249)">Boblo</font><font color="rgb(47,215,190)">Script</font>'
    local logo = new("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        RichText = true,
        Text = logoRichText,
        TextColor3 = Theme.Text,
        TextSize = 16,
        Font = FontBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.fromOffset(120, TOPBAR_HEIGHT),
        Position = UDim2.fromOffset(58, 0),
        Parent = topbar,
    })

    local brandSeparator = new("Frame", {
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(SIDEBAR_WIDTH - 1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        Parent = topbar,
    })

    local globalSearchHolder
    globalSearchHolder, GlobalSearchBox = makeInput(topbar, "Search scripts, functions, places...", {
        size = UDim2.new(1, -(SIDEBAR_WIDTH + 244), 0, 40),
        radius = 12,
        textSize = 13,
        searchIcon = true,
        rightPadding = 86,
        background = Theme.Background,
    })
    globalSearchHolder.Position = UDim2.fromOffset(SIDEBAR_WIDTH + 14, 11)

    SearchShortcutLabel = makeLabel(globalSearchHolder, "Ctrl K", 9, Theme.Muted2, FontBold, Enum.TextXAlignment.Center)
    SearchShortcutLabel.BackgroundColor3 = Theme.Surface2
    SearchShortcutLabel.BackgroundTransparency = 0
    SearchShortcutLabel.Size = UDim2.fromOffset(46, 22)
    SearchShortcutLabel.Position = UDim2.new(1, -54, 0.5, -11)
    addCorner(SearchShortcutLabel, 7)

    GlobalSearchClear = makeButton(globalSearchHolder, "×", function()
        GlobalSearchBox.Text = ""
        GlobalSearchBox:CaptureFocus()
    end, {
        size = UDim2.fromOffset(26, 26),
        background = Theme.Surface2,
        hover = Theme.Elevated,
        textColor = Theme.Muted,
        stroke = false,
        radius = 8,
        textSize = 16,
    })
    GlobalSearchClear.Position = UDim2.new(1, -84, 0.5, -13)
    GlobalSearchClear.Visible = false

    local minimize = makeButton(topbar, "—", function()
        setHubVisible(false)
    end, {
        size = UDim2.fromOffset(38, 32),
        background = Theme.Window,
        hover = Theme.Surface2,
        textColor = Theme.Muted,
        stroke = false,
        radius = 9,
    })
    minimize.Position = UDim2.new(1, -88, 0, 15)

    local close = makeButton(topbar, "×", function()
        setHubVisible(false)
    end, {
        size = UDim2.fromOffset(38, 32),
        background = Theme.Window,
        hover = Theme.DangerSoft,
        textColor = Theme.Muted,
        stroke = false,
        radius = 9,
        textSize = 20,
    })
    close.Position = UDim2.new(1, -46, 0, 15)

    local settingsTop = makeButton(topbar, "Prefs", function()
        renderScreen("preferences")
    end, {
        size = UDim2.fromOffset(58, 32),
        background = Theme.Surface,
        hover = Theme.Surface2,
        textColor = Theme.Muted,
        textSize = 11,
        radius = 10,
    })
    settingsTop.Position = UDim2.new(1, -152, 0, 15)

    local nextThemeLabel = State.themeMode == "dark" and "Light" or "Dark"
    local themeTop = makeButton(topbar, nextThemeLabel, function()
        State.themeMode = State.themeMode == "dark" and "light" or "dark"
        applyTheme(State.themeMode)
        writeConfig()
        task.defer(buildUi)
    end, {
        size = UDim2.fromOffset(58, 32),
        background = Theme.Surface,
        hover = Theme.Surface2,
        textColor = Theme.Muted,
        textSize = 11,
        radius = 10,
    })
    themeTop.Position = UDim2.new(1, -216, 0, 15)

    local sidebar = new("Frame", {
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
        Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
        Parent = MainWindow,
    })

    local sidebarSeparator = new("Frame", {
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        Parent = sidebar,
    })

    local profileCard = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 14),
        Size = UDim2.new(1, -24, 0, 52),
        Parent = sidebar,
    })
    addCorner(profileCard, 12)
    addStroke(profileCard, Theme.BorderSoft, 1, 0)

    local profileMark = new("Frame", {
        BackgroundColor3 = Theme.AccentSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(9, 9),
        Size = UDim2.fromOffset(34, 34),
        Parent = profileCard,
    })
    addCorner(profileMark, 10)
    local profileLetter = makeLabel(profileMark, "B", 15, Theme.Accent, FontHeavy, Enum.TextXAlignment.Center)
    profileLetter.Size = UDim2.fromScale(1, 1)

    local profileTitle = makeLabel(profileCard, "BobloScript", 12, Theme.Text, FontBold)
    profileTitle.Size = UDim2.new(1, -56, 0, 20)
    profileTitle.Position = UDim2.fromOffset(51, 7)
    local profileSubtitle = makeLabel(profileCard, "Community hub", 10, Theme.Muted2, FontRegular)
    profileSubtitle.Size = UDim2.new(1, -56, 0, 18)
    profileSubtitle.Position = UDim2.fromOffset(51, 27)

    local nav = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 82),
        Size = UDim2.new(1, -24, 0, 320),
        Parent = sidebar,
    })
    addList(nav, Enum.FillDirection.Vertical, 6)

    local items = {
        { key = "home", icon = "home", label = "Home" },
        { key = "scripts", icon = "scripts", label = "Scripts" },
        { key = "places", icon = "places", label = "Places" },
        { key = "saved", icon = "saved", label = "Saved" },
        { key = "recent", icon = "recent", label = "Recent" },
        { key = "preferences", icon = "preferences", label = "Preferences" },
    }

    for _, item in ipairs(items) do
        local button = makeButton(nav, "", function()
            renderScreen(item.key)
        end, {
            size = UDim2.new(1, 0, 0, 44),
            background = Theme.Sidebar,
            hover = Theme.Surface,
            textColor = Theme.Muted,
            textSize = 14,
            stroke = false,
            radius = 12,
            font = FontMedium,
        })
        local iconTile = new("Frame", {
            Name = "IconTile",
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(10, 9),
            Size = UDim2.fromOffset(26, 26),
            Parent = button,
        })
        addCorner(iconTile, 8)

        makeNavIcon(iconTile, item.icon)

        local labelRightInset = (item.key == "saved" or item.key == "recent") and 42 or 12
        local navLabel = makeLabel(button, item.label, 13, Theme.Muted, FontMedium)
        navLabel.Name = "NavLabel"
        navLabel.TextTruncate = Enum.TextTruncate.AtEnd
        navLabel.Position = UDim2.fromOffset(48, 0)
        navLabel.Size = UDim2.new(1, -(48 + labelRightInset), 1, 0)

        local indicator = new("Frame", {
            Name = "SelectedBar",
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(-12, 10),
            Size = UDim2.fromOffset(3, 24),
            Visible = false,
            Parent = button,
        })
        addCorner(indicator, 3)

        if item.key == "saved" or item.key == "recent" then
            local countBadge = makeLabel(button, "0", 9, Theme.Muted, FontBold, Enum.TextXAlignment.Center)
            countBadge.BackgroundColor3 = Theme.Surface3
            countBadge.BackgroundTransparency = 0
            countBadge.Position = UDim2.new(1, -34, 0.5, -10)
            countBadge.Size = UDim2.fromOffset(26, 20)
            countBadge.Visible = false
            addCorner(countBadge, 7)
            SidebarBadges[item.key] = countBadge
        end
        SidebarButtons[item.key] = button
    end
    updateSidebarBadges()

    local statusCard = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        Position = UDim2.new(0, 12, 1, -68),
        Size = UDim2.new(1, -24, 0, 34),
        Parent = sidebar,
    })
    addCorner(statusCard, 10)
    addStroke(statusCard, Theme.BorderSoft, 1, 0)
    statusCard.MouseButton1Click:Connect(function()
        checkApiHealth(true)
    end)

    StatusDot = new("Frame", {
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(10, 13),
        Size = UDim2.fromOffset(8, 8),
        Parent = statusCard,
    })
    addCorner(StatusDot, 4)

    StatusLabel = makeLabel(statusCard, "Public API", 11, Theme.Muted, FontBold)
    StatusLabel.Size = UDim2.new(1, -28, 1, 0)
    StatusLabel.Position = UDim2.fromOffset(24, 0)

    local versionLabel = makeLabel(sidebar, "v" .. APP_VERSION, 10, Theme.Muted2, FontRegular)
    versionLabel.Size = UDim2.new(1, -24, 0, 20)
    versionLabel.Position = UDim2.new(0, 12, 1, -30)

    Content = new("Frame", {
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(SIDEBAR_WIDTH, TOPBAR_HEIGHT),
        Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
        Parent = MainWindow,
    })

    GlobalSearchLayer = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
        Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
        Visible = false,
        ZIndex = 80,
        Parent = MainWindow,
    })

    local searchDismiss = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.48,
        BorderSizePixel = 0,
        Text = "",
        Size = UDim2.fromScale(1, 1),
        ZIndex = 80,
        Parent = GlobalSearchLayer,
    })
    searchDismiss.MouseButton1Click:Connect(function()
        closeGlobalSearch(true)
    end)

    GlobalSearchPanel = new("Frame", {
        BackgroundColor3 = Theme.Window,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(SIDEBAR_WIDTH + 14, 4),
        Size = UDim2.new(1, -(SIDEBAR_WIDTH + 244), 0, 408),
        ZIndex = 81,
        Parent = GlobalSearchLayer,
    })
    addCorner(GlobalSearchPanel, 16)
    addStroke(GlobalSearchPanel, Theme.Border, 1, 0)

    local searchPanelTitle = makeLabel(GlobalSearchPanel, "Search results", 13, Theme.Text, FontBold)
    searchPanelTitle.Size = UDim2.new(1, -180, 0, 42)
    searchPanelTitle.Position = UDim2.fromOffset(14, 0)

    local searchPanelHint = makeLabel(GlobalSearchPanel, "Enter opens all scripts", 10, Theme.Muted2, FontRegular, Enum.TextXAlignment.Right)
    searchPanelHint.Size = UDim2.fromOffset(160, 42)
    searchPanelHint.Position = UDim2.new(1, -174, 0, 0)

    local searchPanelSeparator = new("Frame", {
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 0, 1),
        Parent = GlobalSearchPanel,
    })

    GlobalSearchResults = new("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(12, 53),
        ScrollBarImageColor3 = Theme.Border,
        ScrollBarThickness = 3,
        Size = UDim2.new(1, -24, 1, -65),
        ZIndex = 82,
        Parent = GlobalSearchPanel,
    })
    addList(GlobalSearchResults, Enum.FillDirection.Vertical, 7)

    local inputDebounceSerial = 0
    GlobalSearchBox.Focused:Connect(function()
        setGlobalSearchVisible(true)
        if trim(GlobalSearchBox.Text) == "" then
            renderGlobalSearchIdle()
        else
            runGlobalSearch(GlobalSearchBox.Text)
        end
    end)

    GlobalSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        inputDebounceSerial = inputDebounceSerial + 1
        local serial = inputDebounceSerial
        GlobalSearchClear.Visible = trim(GlobalSearchBox.Text) ~= ""

        task.delay(SEARCH_DEBOUNCE, function()
            if serial ~= inputDebounceSerial or not GlobalSearchLayer.Visible then
                return
            end
            runGlobalSearch(GlobalSearchBox.Text)
        end)
    end)

    GlobalSearchBox.FocusLost:Connect(function(enterPressed)
        if not enterPressed then
            return
        end

        local query = trim(GlobalSearchBox.Text)
        if query == "" then
            return
        end

        rememberSearch(query)
        State.pendingScriptQuery = query
        closeGlobalSearch(false)
        renderScreen("scripts")
    end)

    ToastHolder = new("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.fromOffset(330, 260),
        ZIndex = 50,
        Parent = MainWindow,
    })
    addList(ToastHolder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)

    ModalLayer = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 100,
        Parent = MainWindow,
    })

    local floatingWidth = UserInputService.TouchEnabled and 190 or 224
    local floatingHeight = UserInputService.TouchEnabled and 48 or 54

    FloatingToggleShadow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Theme.Black,
        BackgroundTransparency = 0.66,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 7),
        Size = UDim2.fromOffset(floatingWidth + 8, floatingHeight + 8),
        Visible = false,
        ZIndex = 198,
        Parent = ScreenGui,
    })
    addCorner(FloatingToggleShadow, 19)

    FloatingToggle = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(floatingWidth, floatingHeight),
        Visible = false,
        ZIndex = 200,
        Parent = ScreenGui,
    })
    addCorner(FloatingToggle, 17)

    local toggleGradient = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(31, 228, 174)),
            ColorSequenceKeypoint.new(0.18, Color3.fromRGB(74, 255, 122)),
            ColorSequenceKeypoint.new(0.36, Color3.fromRGB(176, 255, 91)),
            ColorSequenceKeypoint.new(0.52, Color3.fromRGB(43, 224, 205)),
            ColorSequenceKeypoint.new(0.68, Color3.fromRGB(38, 173, 255)),
            ColorSequenceKeypoint.new(0.84, Color3.fromRGB(143, 105, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(31, 228, 174))
        }),
        Rotation = 0,
        Parent = FloatingToggle,
    })

    if not State.reduceMotion then
        TweenService:Create(
            toggleGradient,
            TweenInfo.new(4.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
            { Rotation = 360 }
        ):Play()
    end

    local floatingButton = new("TextButton", {
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Font = FontBold,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -6, 1, -6),
        Text = APP_SHORT_NAME,
        TextColor3 = Theme.Text,
        TextSize = 15,
        ZIndex = 201,
        Parent = FloatingToggle,
    })
    addCorner(floatingButton, 15)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 27),
        PaddingRight = UDim.new(0, 42),
        Parent = floatingButton,
    })

    local floatingDot = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 13, 0.5, 0),
        Size = UDim2.fromOffset(9, 9),
        ZIndex = 202,
        Parent = floatingButton,
    })
    addCorner(floatingDot, 5)

    new("Frame", {
        BackgroundColor3 = Theme.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -45, 0.5, -11),
        Size = UDim2.fromOffset(1, 22),
        ZIndex = 202,
        Parent = FloatingToggle,
    })

    local floatingClose = new("TextButton", {
        Active = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = FontMedium,
        Position = UDim2.new(1, -22, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 18,
        ZIndex = 203,
        Parent = FloatingToggle,
    })
    addCorner(floatingClose, 9)

    floatingClose.MouseEnter:Connect(function()
        TweenService:Create(floatingClose, TweenInfo.new(0.12), {
            BackgroundColor3 = Theme.DangerSoft,
            BackgroundTransparency = 0,
            TextColor3 = Theme.Danger,
        }):Play()
    end)
    floatingClose.MouseLeave:Connect(function()
        TweenService:Create(floatingClose, TweenInfo.new(0.12), {
            BackgroundColor3 = Theme.Surface,
            BackgroundTransparency = 1,
            TextColor3 = Theme.Muted,
        }):Play()
    end)
    floatingClose.MouseButton1Click:Connect(function()
        cleanupCurrentHub()
    end)

    floatingButton.MouseEnter:Connect(function()
        TweenService:Create(floatingButton, TweenInfo.new(0.12), {
            BackgroundColor3 = Theme.Surface2,
        }):Play()
    end)
    floatingButton.MouseLeave:Connect(function()
        TweenService:Create(floatingButton, TweenInfo.new(0.12), {
            BackgroundColor3 = Theme.Surface,
        }):Play()
    end)

    makeDraggable(floatingButton, FloatingToggle, {
        deadzone = 7,
        onClick = function()
            setHubVisible(true)
        end,
    })
    syncFloatingToggleShadow()

    makeDraggable(topbar, MainWindow, {
        deadzone = 3,
    })

    trackConnection(MainWindow:GetPropertyChangedSignal("Visible"):Connect(syncWindowShadows))
    updateWindowFit(true)
    syncWindowShadows()

    local camera = workspace.CurrentCamera
    if camera then
        trackConnection(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            updateWindowFit(true)
        end))
    end

    trackConnection(UserInputService.InputBegan:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.RightShift and ScreenGui and ScreenGui.Parent then
            setHubVisible(not MainWindow.Visible)
            return
        end

        if input.KeyCode == Enum.KeyCode.Escape then
            if GlobalSearchLayer and GlobalSearchLayer.Visible then
                closeGlobalSearch(true)
                return
            elseif ModalLayer and ModalLayer.Visible then
                closeModal()
                return
            end
        end

        if processed then
            return
        end

        local controlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        if input.KeyCode == Enum.KeyCode.K and controlHeld then
            setHubVisible(true)
            setGlobalSearchVisible(true)
        end
    end))

    refreshConnectionStatus()
    checkApiHealth(false)
    setHubVisible(true)
    local validLastScreens = {
        home = true,
        places = true,
        scripts = true,
        saved = true,
        recent = true,
        preferences = true,
    }
    if State.screen == "scriptDetails" and State.selectedScript then
        openScriptDetails(State.selectedScript, true)
    elseif State.screen == "placeScripts" and State.selectedPlace then
        openPlaceScripts(State.selectedPlace, State.placePage, true)
    else
        renderScreen(validLastScreens[State.lastScreen] and State.lastScreen or "home", true)
    end

    if not State.installReported then
        State.installReported = true
        task.spawn(function()
            apiRequest("POST", "/hub/install")
        end)
    end

end

buildUi()
