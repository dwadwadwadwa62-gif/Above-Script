--[[
    ABOVE | AUTO MOB FARM V11 - INDIVIDUAL TARGET TOGGLES
    - Slimes exclusive; Skeletons + Morton can be selected together
    - Three GUI pages: Farming, Combat and Mining
    - Farming/Mining target selection UI only; gathering logic not connected
    - Cleaner GUI inspired by user reference
    - B stops farming
    - Anti-AFK
    - Continuous floating
    - Auto reset after 10 seconds attacking with no observable damage/kill
    - NOTE: ABOVE may hide enemy health; this cannot verify every actual hit
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local env = (type(getgenv) == "function" and getgenv()) or _G

if type(env.AboveMobFarmStop) == "function" then
    pcall(env.AboveMobFarmStop)
end

local CONFIG = {
    MobNames = {
        blueslime = true,
        greenslime = true,
        pinkslime = true,
        orangeslime = true,
    },
    SkeletonKeyword = "skeleton",
    BossKeyword = "morton", -- Matches Parts/Models containing Morton (case-insensitive)
    -- Separate target switches. Slimes run alone; Skeletons + Morton can run together.
    EnabledTargets = {
        SLIMES = true,
        SKELETONS = false,
        MORTON = false,
    },
    -- Saved UI selections. Mining and harvesting automation are NOT wired yet.
    FarmingTargets = {
        BERRIES = false, ONIONS = false, CARROTS = false,
        WHEAT = false, OTHER_CROPS = false,
        FLOWERS = false, SHINIES = false,
    },
    MiningTargets = {
        IRON = false, GOLD = false, COAL = false,
        SAND = false, STONE = false, COPPER = false,
        OTHER_ORES = false,
    },
    SearchRange = 100,
    MaxVerticalDifference = 50,
    HoverHeight = 12,
    MinHoverHeight = 6,
    MaxHoverHeight = 24,
    HeightStep = 1,
    AutoRaiseOnDamage = false,
    AutoRaiseStep = 2,
    AutoRaiseCooldown = 2,
    AttackDelay = 0.35,
    ScanDelay = 0.6,
    RequireMovement = true,
    MinimumObservedMovement = 0.65,
    RecentMovementSeconds = 4,
    MaxTargetSeconds = 14,
    StuckTargetCooldown = 20,
    AntiAFK = true,
    BackgroundAttack = true,
    NoHitResetSeconds = 10,
    ResetCooldown = 5,
}

local enabled = false
local alive = true
local currentTarget = nil
local lastAttack = 0
local lastScan = 0
local attacking = false
local farmConnection
local keyConnection
local idleConnection
local focusLostConnection
local focusGainedConnection
local inspectConnection
local windowFocused = true
local lastAntiAfk = 0
local oldCameraType
local oldCameraSubject
local hoverRoot
local hoverForce
local monitoredHumanoid
local healthConnection
local lastAutoRaise = 0
local targetSince = 0
local motionSamples = setmetatable({}, { __mode = "k" })
local ignoredUntil = setmetatable({}, { __mode = "k" })
local targetHealthMemory = setmetatable({}, { __mode = "k" })
local lastObservedProgress = 0
local combatStartedAt = 0
local resetInProgress = false
local resetResume = false
local lastReset = -math.huge

-- ==========================================
-- GUI
-- ==========================================

local playerGui = player:WaitForChild("PlayerGui")
local oldGUI = playerGui:FindFirstChild("AboveMobFarm")
if oldGUI then oldGUI:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AboveMobFarm"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
    return c
end

local function stroke(obj, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = obj
    return s
end

local main = Instance.new("Frame")
main.Name = "MainFrame"
main.Size = UDim2.fromOffset(560, 458)
main.Position = UDim2.fromOffset(18, 60)
main.BackgroundColor3 = Color3.fromRGB(9, 12, 22)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
corner(main, 14)
stroke(main, Color3.fromRGB(45, 52, 76), 1, 0.25)

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.fromOffset(120, 458)
sidebar.Position = UDim2.fromOffset(0, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(6, 9, 19)
sidebar.BorderSizePixel = 0
sidebar.Parent = main
corner(sidebar, 14)

local sidebarMask = Instance.new("Frame")
sidebarMask.Size = UDim2.fromOffset(22, 458)
sidebarMask.Position = UDim2.new(1, -22, 0, 0)
sidebarMask.BackgroundColor3 = main.BackgroundColor3
sidebarMask.BorderSizePixel = 0
sidebarMask.Parent = sidebar

local brand = Instance.new("TextLabel")
brand.BackgroundTransparency = 1
brand.Position = UDim2.fromOffset(16, 14)
brand.Size = UDim2.fromOffset(90, 34)
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.TextYAlignment = Enum.TextYAlignment.Top
brand.Font = Enum.Font.GothamBold
brand.TextSize = 18
brand.TextColor3 = Color3.fromRGB(245,245,250)
brand.Text = "ABOVE"
brand.Parent = sidebar

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(16, 34)
subtitle.Size = UDim2.fromOffset(100, 24)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 11
subtitle.TextColor3 = Color3.fromRGB(130, 136, 168)
subtitle.Text = "Auto Farm"
subtitle.Parent = sidebar

-- Three actual navigation tabs (previous labels were not clickable).
local navButtons = {}
local function navButton(kind, text, y)
    local button = Instance.new("TextButton")
    button.Name = kind .. "Tab"
    button.Size = UDim2.fromOffset(102, 34)
    button.Position = UDim2.fromOffset(10, y)
    button.BackgroundColor3 = Color3.fromRGB(26, 29, 48)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.TextXAlignment = Enum.TextXAlignment.Left
    button.Text = "   " .. text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 13
    button.TextColor3 = Color3.fromRGB(158, 164, 189)
    button.AutoButtonColor = true
    button.Parent = sidebar
    corner(button, 9)
    navButtons[kind] = button
end

navButton("FARMING", "Farming", 94)
navButton("COMBAT", "Combat", 136)
navButton("MINING", "Mining", 178)

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromOffset(420, 458)
content.Position = UDim2.fromOffset(120, 0)
content.BackgroundTransparency = 1
content.Parent = main

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, -18, 0, 42)
topBar.Position = UDim2.fromOffset(10, 10)
topBar.BackgroundTransparency = 1
topBar.Parent = content

local pageHeading = Instance.new("TextLabel")
pageHeading.BackgroundTransparency = 1
pageHeading.Position = UDim2.fromOffset(6, 6)
pageHeading.Size = UDim2.fromOffset(128, 28)
pageHeading.Text = "COMBAT"
pageHeading.TextXAlignment = Enum.TextXAlignment.Left
pageHeading.Font = Enum.Font.GothamBold
pageHeading.TextSize = 15
pageHeading.TextColor3 = Color3.fromRGB(233,233,247)
pageHeading.Parent = topBar

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Size = UDim2.fromOffset(170, 30)
searchBox.Position = UDim2.fromOffset(138, 4)
searchBox.BackgroundColor3 = Color3.fromRGB(15, 18, 32)
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.PlaceholderText = "Combat target..."
searchBox.Text = ""
searchBox.TextColor3 = Color3.fromRGB(225,225,230)
searchBox.PlaceholderColor3 = Color3.fromRGB(110, 116, 145)
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 12
searchBox.Parent = topBar
corner(searchBox, 9)
stroke(searchBox, Color3.fromRGB(44, 51, 74), 1, 0.35)

local function topMiniButton(text, x, color)
    local b = Instance.new("TextButton")
    b.Name = "WindowControl_" .. text
    b.Size = UDim2.fromOffset(26, 26)
    b.Position = UDim2.fromOffset(x, 6)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = topBar
    corner(b, 7)
    return b
end

local minimize = topMiniButton("–", 316, Color3.fromRGB(58, 68, 109))
local pauseButton = topMiniButton("▶", 346, Color3.fromRGB(171, 129, 39))
local close = topMiniButton("X", 376, Color3.fromRGB(169, 57, 60))
close.Name = "CloseButton"

local card = Instance.new("Frame")
card.Name = "CombatCard"
card.Size = UDim2.new(1, -18, 0, 325)
card.Position = UDim2.fromOffset(10, 58)
card.BackgroundColor3 = Color3.fromRGB(14, 17, 30)
card.BorderSizePixel = 0
card.Parent = content
corner(card, 12)
stroke(card, Color3.fromRGB(43, 48, 72), 1, 0.25)

local cardTitle = Instance.new("TextLabel")
cardTitle.BackgroundTransparency = 1
cardTitle.Position = UDim2.fromOffset(14, 10)
cardTitle.Size = UDim2.fromOffset(150, 20)
cardTitle.TextXAlignment = Enum.TextXAlignment.Left
cardTitle.Font = Enum.Font.GothamBold
cardTitle.TextSize = 17
cardTitle.TextColor3 = Color3.fromRGB(244,244,248)
cardTitle.Text = "Combat Farm"
cardTitle.Parent = card

local cardSub = Instance.new("TextLabel")
cardSub.BackgroundTransparency = 1
cardSub.Position = UDim2.fromOffset(14, 30)
cardSub.Size = UDim2.fromOffset(180, 18)
cardSub.TextXAlignment = Enum.TextXAlignment.Left
cardSub.Font = Enum.Font.Gotham
cardSub.TextSize = 11
cardSub.TextColor3 = Color3.fromRGB(136, 140, 164)
cardSub.Text = "Select which enemies to farm."
cardSub.Parent = card

local function makeSwitch(parent, x, y, initial)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(52, 28)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = initial and Color3.fromRGB(121, 87, 255) or Color3.fromRGB(72, 75, 96)
    button.BorderSizePixel = 0
    button.Text = ""
    button.Parent = parent
    corner(button, 14)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(22, 22)
    knob.Position = initial and UDim2.fromOffset(26, 3) or UDim2.fromOffset(4, 3)
    knob.BackgroundColor3 = Color3.fromRGB(248,248,251)
    knob.BorderSizePixel = 0
    knob.Parent = button
    corner(knob, 11)

    return button, knob
end

local function setSwitchVisual(button, knob, state)
    button.BackgroundColor3 = state and Color3.fromRGB(121, 87, 255) or Color3.fromRGB(72, 75, 96)
    knob.Position = state and UDim2.fromOffset(26, 3) or UDim2.fromOffset(4, 3)
end

local function row(y, labelText, subText)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -24, 0, 38)
    holder.Position = UDim2.fromOffset(12, y)
    holder.BackgroundTransparency = 1
    holder.Parent = card

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(0, 2)
    label.Size = UDim2.fromOffset(210, 16)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(232,232,238)
    label.Text = labelText
    label.Parent = holder

    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.fromOffset(0, 19)
    sub.Size = UDim2.fromOffset(240, 14)
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 10
    sub.TextColor3 = Color3.fromRGB(128, 132, 152)
    sub.Text = subText or ""
    sub.Parent = holder

    return holder, label, sub
end

-- Dedicated switches, matching the requested three-row target layout.
local farmHolder, farmLabel, farmSub = row(58, "Auto Combat", "Start or pause mob farming.")
local slimeHolder, slimeLabel, slimeSub = row(102, "Slimes", "Blue, Green, Pink and Orange")
local skeletonHolder, skeletonLabel, skeletonSub = row(145, "Skeletons", "Can run alongside Morton")
local mortonHolder, mortonLabel, mortonSub = row(188, "Morton", "Can run alongside Skeletons")
local heightHolder, heightLabel, heightSub = row(231, "Hover Height", "Adjust floating clearance.")
local resetHolder, resetLabel, resetSub = row(274, "10s Stall Reset", "Resets if no damage/kill is detected.")

local toggle, toggleKnob = makeSwitch(card, 333, 62, false)
toggle.Name = "FarmToggle"
local slimeToggle, slimeKnob = makeSwitch(card, 333, 106, CONFIG.EnabledTargets.SLIMES)
slimeToggle.Name = "SlimesToggle"
local skeletonToggle, skeletonKnob = makeSwitch(card, 333, 149, CONFIG.EnabledTargets.SKELETONS)
skeletonToggle.Name = "SkeletonsToggle"
local mortonToggle, mortonKnob = makeSwitch(card, 333, 192, CONFIG.EnabledTargets.MORTON)
mortonToggle.Name = "MortonToggle"

local minus = Instance.new("TextButton")
minus.Name = "HeightMinus"
minus.Size = UDim2.fromOffset(28, 28)
minus.Position = UDim2.fromOffset(284, 237)
minus.BackgroundColor3 = Color3.fromRGB(72, 75, 96)
minus.BorderSizePixel = 0
minus.Text = "-"
minus.TextColor3 = Color3.fromRGB(245,245,250)
minus.Font = Enum.Font.GothamBold
minus.TextSize = 16
minus.Parent = card
corner(minus, 9)

local heightValue = Instance.new("TextLabel")
heightValue.BackgroundColor3 = Color3.fromRGB(20, 23, 38)
heightValue.BorderSizePixel = 0
heightValue.Position = UDim2.fromOffset(319, 237)
heightValue.Size = UDim2.fromOffset(48, 28)
heightValue.Font = Enum.Font.GothamBold
heightValue.TextSize = 12
heightValue.TextColor3 = Color3.fromRGB(242,242,246)
heightValue.Text = tostring(CONFIG.HoverHeight)
heightValue.Parent = card
corner(heightValue, 9)
stroke(heightValue, Color3.fromRGB(45, 50, 74), 1, 0.35)

local plus = Instance.new("TextButton")
plus.Name = "HeightPlus"
plus.Size = UDim2.fromOffset(28, 28)
plus.Position = UDim2.fromOffset(372, 237)
plus.BackgroundColor3 = Color3.fromRGB(72, 75, 96)
plus.BorderSizePixel = 0
plus.Text = "+"
plus.TextColor3 = Color3.fromRGB(245,245,250)
plus.Font = Enum.Font.GothamBold
plus.TextSize = 16
plus.Parent = card
corner(plus, 9)

local resetBadge = Instance.new("TextLabel")
resetBadge.Name = "StallResetStatus"
resetBadge.BackgroundColor3 = Color3.fromRGB(121, 87, 255)
resetBadge.BorderSizePixel = 0
resetBadge.Position = UDim2.fromOffset(281, 280)
resetBadge.Size = UDim2.fromOffset(105, 26)
resetBadge.Font = Enum.Font.GothamBold
resetBadge.TextSize = 11
resetBadge.TextColor3 = Color3.fromRGB(248,248,252)
resetBadge.Text = "ON • 10s"
resetBadge.Parent = card
corner(resetBadge, 10)


-- The status label is initialized below; keep its upvalue visible to callbacks.
local status

-- ==========================================
-- Farming / Mining: selection pages
-- ==========================================
-- These switches persist during this script session. They do not mine or
-- harvest until ABOVE's world objects and normal interactions are mapped.
local function createResourcePage(pageName, heading, description, options, selections)
    local page = Instance.new("Frame")
    page.Name = pageName .. "Card"
    page.Size = card.Size
    page.Position = card.Position
    page.BackgroundColor3 = card.BackgroundColor3
    page.BorderSizePixel = 0
    page.Visible = false
    page.Parent = content
    corner(page, 12)
    stroke(page, Color3.fromRGB(43, 48, 72), 1, 0.25)

    local pageTitle = Instance.new("TextLabel")
    pageTitle.Size = UDim2.fromOffset(365, 24)
    pageTitle.Position = UDim2.fromOffset(14, 9)
    pageTitle.BackgroundTransparency = 1
    pageTitle.Font = Enum.Font.GothamBold
    pageTitle.TextSize = 17
    pageTitle.TextColor3 = Color3.fromRGB(244, 244, 248)
    pageTitle.TextXAlignment = Enum.TextXAlignment.Left
    pageTitle.Text = heading
    pageTitle.Parent = page

    local pageSubtitle = Instance.new("TextLabel")
    pageSubtitle.Size = UDim2.fromOffset(368, 19)
    pageSubtitle.Position = UDim2.fromOffset(14, 31)
    pageSubtitle.BackgroundTransparency = 1
    pageSubtitle.Font = Enum.Font.Gotham
    pageSubtitle.TextSize = 11
    pageSubtitle.TextColor3 = Color3.fromRGB(136, 140, 164)
    pageSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    pageSubtitle.Text = description
    pageSubtitle.Parent = page

    local note = Instance.new("TextLabel")
    note.Size = UDim2.new(1, -26, 0, 24)
    note.Position = UDim2.fromOffset(13, 54)
    note.BackgroundColor3 = Color3.fromRGB(29, 27, 47)
    note.BorderSizePixel = 0
    note.Text = "SELECT TARGETS  •  AUTOMATION NOT CONNECTED YET"
    note.Font = Enum.Font.GothamBold
    note.TextSize = 10
    note.TextColor3 = Color3.fromRGB(185, 172, 255)
    note.Parent = page
    corner(note, 7)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "TargetsList"
    scroll.Size = UDim2.new(1, -26, 0, 233)
    scroll.Position = UDim2.fromOffset(13, 84)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 81, 180)
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.CanvasSize = UDim2.fromOffset(0, #options * 47 + 4)
    scroll.Parent = page

    for index, option in ipairs(options) do
        local key, labelText, subText = option[1], option[2], option[3]
        local line = Instance.new("Frame")
        line.Name = key .. "Row"
        line.Size = UDim2.new(1, -10, 0, 45)
        line.Position = UDim2.fromOffset(0, (index - 1) * 47)
        line.BackgroundColor3 = Color3.fromRGB(19, 23, 39)
        line.BorderSizePixel = 0
        line.Parent = scroll
        corner(line, 8)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromOffset(275, 18)
        label.Position = UDim2.fromOffset(11, 5)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(231, 231, 241)
        label.Parent = line

        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.fromOffset(285, 13)
        sub.Position = UDim2.fromOffset(11, 24)
        sub.BackgroundTransparency = 1
        sub.Text = subText
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 10
        sub.TextColor3 = Color3.fromRGB(130, 136, 165)
        sub.Parent = line

        local button, knob = makeSwitch(line, 296, 8, selections[key])
        button.Name = key .. "Toggle"
        button.MouseButton1Click:Connect(function()
            if not alive then return end
            selections[key] = not selections[key]
            setSwitchVisual(button, knob, selections[key])
            status.Text = pageName .. " filters saved (automation pending)"
        end)
    end
    return page
end

local farmingCard = createResourcePage("FARMING", "Auto Harvest", "Choose crops and collectible types.", {
    {"BERRIES", "Berry Bushes", "Berries and harvestable berry plants"},
    {"ONIONS", "Onions", "Onion crops"},
    {"CARROTS", "Carrots", "Carrot crops"},
    {"WHEAT", "Wheat", "Wheat crops"},
    {"OTHER_CROPS", "Other Crops", "Additional crops (to be identified)"},
    {"FLOWERS", "Flowers", "World flowers and pickups"},
    {"SHINIES", "Shinies", "Collectible shiny items"},
}, CONFIG.FarmingTargets)

local miningCard = createResourcePage("MINING", "Auto Mining", "Choose which materials to target.", {
    {"IRON", "Iron", "Iron ore deposits"},
    {"GOLD", "Gold", "Gold ore deposits"},
    {"COAL", "Coal", "Coal deposits"},
    {"SAND", "Sand", "Sand resource blocks"},
    {"STONE", "Stone", "Stone resource blocks"},
    {"COPPER", "Copper", "If present in ABOVE"},
    {"OTHER_ORES", "Other Ores", "More ore types (to be identified)"},
}, CONFIG.MiningTargets)

local pageCards = {FARMING = farmingCard, COMBAT = card, MINING = miningCard}
local currentPage = "COMBAT"
local function showPage(pageName)
    if not pageCards[pageName] then return end
    currentPage = pageName
    for kind, page in pairs(pageCards) do
        page.Visible = (kind == pageName)
    end
    for kind, button in pairs(navButtons) do
        local selected = kind == pageName
        button.BackgroundTransparency = selected and 0 or 1
        button.BackgroundColor3 = Color3.fromRGB(46, 39, 82)
        button.TextColor3 = selected and Color3.fromRGB(248, 247, 255)
            or Color3.fromRGB(158, 164, 189)
    end
    pageHeading.Text = pageName
    searchBox.Visible = (pageName == "COMBAT")
    pauseButton.Visible = (pageName == "COMBAT")
end

for kind, button in pairs(navButtons) do
    button.MouseButton1Click:Connect(function()
        if alive then showPage(kind) end
    end)
end
showPage("COMBAT")

local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(1, -18, 0, 54)
statusPanel.Position = UDim2.fromOffset(10, 392)
statusPanel.BackgroundColor3 = Color3.fromRGB(11, 14, 25)
statusPanel.BorderSizePixel = 0
statusPanel.Parent = content
corner(statusPanel, 12)
stroke(statusPanel, Color3.fromRGB(43, 48, 72), 1, 0.25)

status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(12, 8)
status.Size = UDim2.fromOffset(250, 18)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Font = Enum.Font.GothamBold
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(236,236,242)
status.Text = "Status: Idle"
status.Parent = statusPanel

local info = Instance.new("TextLabel")
info.BackgroundTransparency = 1
info.Position = UDim2.fromOffset(12, 28)
info.Size = UDim2.fromOffset(280, 16)
info.TextXAlignment = Enum.TextXAlignment.Left
info.Font = Enum.Font.Gotham
info.TextSize = 11
info.TextColor3 = Color3.fromRGB(145, 149, 173)
info.Text = "B: Stop  •  P: Inspect  •  Auto-floating"
info.Parent = statusPanel

local stopButton = Instance.new("TextButton")
stopButton.Name = "StopFarm"
stopButton.Size = UDim2.fromOffset(108, 30)
stopButton.Position = UDim2.fromOffset(292, 12)
stopButton.BackgroundColor3 = Color3.fromRGB(20, 23, 38)
stopButton.BorderSizePixel = 0
stopButton.Text = "Stop Farm"
stopButton.TextColor3 = Color3.fromRGB(242,242,246)
stopButton.Font = Enum.Font.GothamBold
stopButton.TextSize = 12
stopButton.Parent = statusPanel
corner(stopButton, 10)
stroke(stopButton, Color3.fromRGB(45, 50, 74), 1, 0.35)

local antiAfkText = Instance.new("TextLabel")
antiAfkText.BackgroundTransparency = 1
antiAfkText.Position = UDim2.fromOffset(12, 427)
antiAfkText.Size = UDim2.fromOffset(106, 18)
antiAfkText.TextXAlignment = Enum.TextXAlignment.Left
antiAfkText.Font = Enum.Font.Gotham
antiAfkText.TextSize = 10
antiAfkText.TextColor3 = Color3.fromRGB(145, 149, 173)
antiAfkText.Text = "AFK: ON"
antiAfkText.Parent = sidebar

local function updateFocusText()
    antiAfkText.Text = (CONFIG.AntiAFK and "Anti-AFK ON" or "Anti-AFK OFF") .. (windowFocused and "" or " • BG")
end

local function updateHeightText()
    heightValue.Text = tostring(CONFIG.HoverHeight)
    heightLabel.Text = "Hover Height"
    heightSub.Text = "Adjust floating clearance. Current: " .. CONFIG.HoverHeight .. " studs"
end

updateHeightText()
updateFocusText()

focusLostConnection = UIS.WindowFocusReleased:Connect(function()
    windowFocused = false
    if alive then updateFocusText() end
end)
focusGainedConnection = UIS.WindowFocused:Connect(function()
    windowFocused = true
    if alive then updateFocusText() end
end)

local function setToggleVisual(state)
    setSwitchVisual(toggle, toggleKnob, state)
end

-- ==========================================
-- Helpers / hover
-- ==========================================

local function releaseHover()
    if hoverForce then
        pcall(function() hoverForce:Destroy() end)
        hoverForce = nil
    end
    hoverRoot = nil
end

local function ensureHover(root)
    if hoverRoot == root and hoverForce and hoverForce.Parent == root then
        return hoverForce
    end

    releaseHover()
    if not root then return nil end

    local startPosition = root.Position + Vector3.new(0, CONFIG.HoverHeight, 0)
    local force = Instance.new("BodyPosition")
    force.Name = "AboveMobFarmHover"
    force.MaxForce = Vector3.new(10000000, 10000000, 10000000)
    force.P = 30000
    force.D = 3000
    force.Position = startPosition
    force.Parent = root

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = root.CFrame + Vector3.new(0, CONFIG.HoverHeight, 0)

    hoverRoot = root
    hoverForce = force
    return force
end

local function changeHeight(change)
    if not alive then return end
    local oldHeight = CONFIG.HoverHeight
    CONFIG.HoverHeight = math.clamp(oldHeight + change, CONFIG.MinHoverHeight, CONFIG.MaxHoverHeight)
    local delta = CONFIG.HoverHeight - oldHeight
    if delta ~= 0 and hoverRoot and hoverRoot.Parent and hoverForce then
        local lift = Vector3.new(0, delta, 0)
        hoverForce.Position = hoverForce.Position + lift
        hoverRoot.CFrame = hoverRoot.CFrame + lift
    end
    updateHeightText()
end

plus.MouseButton1Click:Connect(function() changeHeight(CONFIG.HeightStep) end)
minus.MouseButton1Click:Connect(function() changeHeight(-CONFIG.HeightStep) end)

-- ==========================================
-- Individual target toggles: Slimes are exclusive; Skeletons + Morton combine.
-- ==========================================
local function selectedTargetNames()
    local selected = CONFIG.EnabledTargets
    if selected.SLIMES then return "SLIMES" end
    if selected.SKELETONS and selected.MORTON then return "SKELETONS + MORTON" end
    if selected.SKELETONS then return "SKELETONS" end
    if selected.MORTON then return "MORTON" end
    return "NONE"
end

local function refreshTargetSwitches()
    setSwitchVisual(slimeToggle, slimeKnob, CONFIG.EnabledTargets.SLIMES)
    setSwitchVisual(skeletonToggle, skeletonKnob, CONFIG.EnabledTargets.SKELETONS)
    setSwitchVisual(mortonToggle, mortonKnob, CONFIG.EnabledTargets.MORTON)
    cardSub.Text = "Selected: " .. selectedTargetNames()
end

local function setTargetEnabled(kind, desired)
    if not alive then return end
    local targets = CONFIG.EnabledTargets

    if desired then
        if kind == "SLIMES" then
            targets.SLIMES = true
            targets.SKELETONS = false
            targets.MORTON = false
        elseif kind == "SKELETONS" or kind == "MORTON" then
            targets.SLIMES = false
            targets[kind] = true
        end
    else
        targets[kind] = false
    end

    refreshTargetSwitches()
    currentTarget = nil
    targetSince = 0
    combatStartedAt = 0
    lastObservedProgress = 0
    lastScan = 0
    status.Text = "Targets: " .. selectedTargetNames()
end

slimeToggle.MouseButton1Click:Connect(function()
    setTargetEnabled("SLIMES", not CONFIG.EnabledTargets.SLIMES)
end)

skeletonToggle.MouseButton1Click:Connect(function()
    setTargetEnabled("SKELETONS", not CONFIG.EnabledTargets.SKELETONS)
end)

mortonToggle.MouseButton1Click:Connect(function()
    setTargetEnabled("MORTON", not CONFIG.EnabledTargets.MORTON)
end)

-- Optional search shortcut, applying the same exclusivity rules.
searchBox.FocusLost:Connect(function()
    local term = string.lower((searchBox.Text or ""):gsub("%s+", ""))
    if term == "slime" or term == "slimes" then
        setTargetEnabled("SLIMES", true)
    elseif term == "skeleton" or term == "skeletons" then
        setTargetEnabled("SKELETONS", true)
    elseif term == "morton" or term == "boss" then
        setTargetEnabled("MORTON", true)
    elseif term == "both" or term == "skeletons+morton" then
        setTargetEnabled("SKELETONS", true)
        setTargetEnabled("MORTON", true)
    elseif term ~= "" then
        status.Text = "Choose Slimes, Skeletons, or Morton"
    end
    searchBox.Text = ""
end)

refreshTargetSwitches()

-- ==========================================
-- Character + target detection
-- ==========================================

local function getCharacter()
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if root and humanoid and humanoid.Health > 0 then
        return char, root, humanoid
    end
    return nil
end

local function isPlayerPart(part)
    for _, p in ipairs(Players:GetPlayers()) do
        local character = p.Character
        if character and part:IsDescendantOf(character) then
            return true
        end
    end
    return false
end

local function isSpawnMarkerName(name)
    local lowered = string.lower(name)
    local forbidden = {"spawn", "spawner", "marker", "template", "dummy", "statue", "display", "shop", "merchant", "trader", "arena", "island", "portal", "pedestal"}
    for _, word in ipairs(forbidden) do
        if string.find(lowered, word, 1, true) then return true end
    end
    return false
end

-- The boss may be a Model or a directly named Part like ABOVE's slimes.
-- Prefer a named boss Model over one of its child parts; never target a map container.
local function isMortonName(name)
    return string.find(string.lower(name), CONFIG.BossKeyword, 1, true) ~= nil
end

local function getTargetKind(target)
    if not target then return nil end
    local lowered = string.lower(target.Name)
    if isSpawnMarkerName(lowered) then return nil end

    if target:IsA("BasePart") then
        if CONFIG.MobNames[lowered] then return "SLIMES" end
        local parentModel = target:FindFirstAncestorOfClass("Model")

        if isMortonName(lowered) then
            -- If a Morton-named Model contains this Part, target that Model.
            if parentModel and isMortonName(parentModel.Name)
                and not isSpawnMarkerName(parentModel.Name) then
                return nil
            end
            return "MORTON"
        end

        if string.find(lowered, CONFIG.SkeletonKeyword, 1, true) then
            if parentModel and string.find(string.lower(parentModel.Name),
                CONFIG.SkeletonKeyword, 1, true) then
                return nil
            end
            return "SKELETONS"
        end

    elseif target:IsA("Model") then
        if isMortonName(lowered) then
            -- Avoid selecting both an outer Morton Model and its inner model.
            local parent = target.Parent
            while parent and parent ~= workspace do
                if parent:IsA("Model") and isMortonName(parent.Name)
                    and not isSpawnMarkerName(parent.Name) then
                    return nil
                end
                parent = parent.Parent
            end
            return "MORTON"
        end

        if string.find(lowered, CONFIG.SkeletonKeyword, 1, true) then
            return "SKELETONS"
        end
    end
    return nil
end

local function getTargetRoot(target)
    if target:IsA("BasePart") then return target end
    if target:IsA("Model") then
        return target:FindFirstChild("HumanoidRootPart", true)
            or target.PrimaryPart
            or target:FindFirstChild("UpperTorso", true)
            or target:FindFirstChild("Torso", true)
            or target:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getHealth(target)
    if not target then return nil end
    if target:IsA("Model") then
        local hum = target:FindFirstChildWhichIsA("Humanoid", true)
        if hum then return hum.Health end
    end
    local attribute = target:GetAttribute("Health")
    if type(attribute) == "number" then return attribute end
    local value = target:FindFirstChild("Health", true)
    if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
        return value.Value
    end
    return nil
end

local function validMob(target)
    local kind = getTargetKind(target)
    if not kind then return false end
    if not CONFIG.EnabledTargets[kind] then return false end
    if not target:IsDescendantOf(workspace) then return false end
    if isPlayerPart(target) then return false end
    local root = getTargetRoot(target)
    if not root or not root:IsDescendantOf(workspace) then return false end
    local health = getHealth(target)
    if health ~= nil and health <= 0 then return false end
    return true, root, kind
end

local function isActiveMob(target, root, now)
    if not CONFIG.RequireMovement then return true end
    if getHealth(target) ~= nil then return true end
    -- A movable Morton body is eligible even when its client-visible health is absent.
    -- Anchored Morton-like parts must demonstrate movement like other mobs.
    if getTargetKind(target) == "MORTON" and not root.Anchored then
        return true
    end

    local sample = motionSamples[target]
    local position = root.Position
    if not sample then
        motionSamples[target] = {position = position, accumulated = 0, lastMovement = -math.huge}
        return false
    end

    local displacement = (position - sample.position).Magnitude
    sample.position = position
    if displacement >= 0.08 and displacement <= 25 then
        sample.accumulated = math.min(sample.accumulated + displacement, CONFIG.MinimumObservedMovement + 1)
        if sample.accumulated >= CONFIG.MinimumObservedMovement then
            sample.lastMovement = now
        end
    end

    return sample.accumulated >= CONFIG.MinimumObservedMovement
        and (now - sample.lastMovement) <= CONFIG.RecentMovementSeconds
end

local function withinRange(target, root)
    local valid, mobRoot = validMob(target)
    if not root or not valid then return false end
    local difference = mobRoot.Position - root.Position
    return difference.Magnitude <= CONFIG.SearchRange
        and math.abs(difference.Y) <= math.max(CONFIG.MaxVerticalDifference, CONFIG.HoverHeight + 8)
end

local function findNearestMob(root, now)
    local nearest = nil
    local shortest = CONFIG.SearchRange

    for _, obj in ipairs(workspace:GetDescendants()) do
        local valid, mobRoot = validMob(obj)
        if valid then
            local difference = mobRoot.Position - root.Position
            local distance = difference.Magnitude
            if distance < CONFIG.SearchRange
                and math.abs(difference.Y) <= math.max(CONFIG.MaxVerticalDifference, CONFIG.HoverHeight + 8) then
                local active = isActiveMob(obj, mobRoot, now)
                local ignored = (ignoredUntil[obj] or 0) > now
                if active and not ignored and distance < shortest then
                    nearest = obj
                    shortest = distance
                end
            end
        end
    end

    return nearest
end

local mouse = player:GetMouse()
inspectConnection = UIS.InputBegan:Connect(function(input, processed)
    if processed or not alive or input.KeyCode ~= Enum.KeyCode.P then return end
    local hit = mouse.Target
    if not hit then
        print("[ABOVE] Inspector: no part under cursor")
        return
    end
    print("[ABOVE] Hit:", hit:GetFullName(), "class:", hit.ClassName)
    local model = hit:FindFirstAncestorOfClass("Model")
    if model then
        print("[ABOVE] Nearest model:", model:GetFullName(), "class:", model.ClassName)
    end
    status.Text = "Inspect: " .. hit.Name .. (model and " / " .. model.Name or "")
    if isMortonName(hit.Name) or (model and isMortonName(model.Name)) then
        print("[ABOVE] Morton match found. Use target mode MORTON to farm it.")
    end
end)

-- ==========================================
-- Combat / input
-- ==========================================

local function activateTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return false end
    return pcall(function() tool:Activate() end)
end

local function virtualClick(x, y)
    local pressed = false
    local ok = pcall(function()
        VIM:SendMouseMoveEvent(x, y, game)
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        pressed = true
        task.wait(0.06)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        pressed = false
    end)
    if pressed then
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
    end
    return ok
end

local function attack()
    if not alive or not enabled then return end

    local view = camera.ViewportSize
    local x = math.floor(view.X / 2)
    local y = math.floor(view.Y / 2)

    if not windowFocused then
        if not CONFIG.BackgroundAttack then return end
        if activateTool() then return end
        virtualClick(x, y)
        return
    end

    if type(mousemoveabs) == "function" then pcall(mousemoveabs, x, y) end

    local clicked = false
    if type(mouse1click) == "function" then clicked = pcall(mouse1click) end
    if not clicked then clicked = virtualClick(x, y) end
    if not clicked then activateTool() end
end

-- ==========================================
-- Anti-idle
-- ==========================================

idleConnection = player.Idled:Connect(function()
    if not alive or not enabled or not CONFIG.AntiAFK then return end
    if os.clock() - lastAntiAfk < 10 then return end
    lastAntiAfk = os.clock()

    task.spawn(function()
        local down = false
        local ok = pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.zero, camera.CFrame)
            down = true
            task.wait(0.12)
            VirtualUser:Button2Up(Vector2.zero, camera.CFrame)
            down = false
        end)
        if down then pcall(function() VirtualUser:Button2Up(Vector2.zero, camera.CFrame) end) end
        if ok then print("[ABOVE] Anti-idle input sent") end
    end)
end)

-- ==========================================
-- State / reset / cleanup
-- ==========================================

local function restoreCamera()
    if oldCameraType then
        camera.CameraType = oldCameraType
        if oldCameraSubject and oldCameraSubject.Parent then
            camera.CameraSubject = oldCameraSubject
        else
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
        oldCameraType = nil
        oldCameraSubject = nil
    end
end

local function setEnabled(value)
    if not alive then return end
    if resetInProgress then
        -- Pressing B / Stop during a respawn cancels automatic resuming.
        if not value then
            resetResume = false
            status.Text = "Reset in progress; farm stopped"
        end
        return
    end

    enabled = value
    currentTarget = nil
    lastScan = 0
    targetSince = 0
    combatStartedAt = 0
    lastObservedProgress = 0

    if enabled and selectedTargetNames() == "NONE" then
        enabled = false
        setToggleVisual(false)
        status.Text = "Select Slimes, Skeletons or Morton"
        return
    end

    if enabled then
        oldCameraType = camera.CameraType
        oldCameraSubject = camera.CameraSubject
        lastAttack = 0
        setToggleVisual(true)
        pauseButton.Text = "Ⅱ"
        status.Text = "Searching: " .. selectedTargetNames()
        farmSub.Text = "Combat enabled; scanning for enemies."
    else
        setToggleVisual(false)
        pauseButton.Text = "▶"
        status.Text = "Status: Idle"
        farmSub.Text = "Combat paused; floating released."
        releaseHover()
        restoreCamera()
    end
end

-- A client can observe health changes or a destroyed/dead target, but it
-- cannot prove hits when the game keeps enemy health on the server.
-- This watchdog therefore measures *observable combat progress*.
local function resetCharacter(reason)
    if resetInProgress or not alive then return end
    if os.clock() - lastReset < CONFIG.ResetCooldown then return end

    lastReset = os.clock()
    local previousCharacter = player.Character
    local shouldResume = enabled
    setEnabled(false)
    resetInProgress = true
    resetResume = shouldResume
    status.Text = reason or "Combat stalled - resetting"
    resetBadge.Text = "RESETTING"

    task.spawn(function()
        local oldHumanoid = previousCharacter
            and previousCharacter:FindFirstChildOfClass("Humanoid")
        if oldHumanoid then
            pcall(function() oldHumanoid.Health = 0 end)
        end

        local newCharacter = nil
        local deadline = os.clock() + 15
        repeat
            task.wait(0.25)
            local candidate = player.Character
            if candidate and candidate ~= previousCharacter then
                local candidateHum = candidate:FindFirstChildOfClass("Humanoid")
                local candidateRoot = candidate:FindFirstChild("HumanoidRootPart")
                if candidateHum and candidateRoot and candidateHum.Health > 0 then
                    newCharacter = candidate
                    break
                end
            end
        until os.clock() >= deadline or not alive

        resetInProgress = false
        resetBadge.Text = "ON • 10s"
        local resume = resetResume
        resetResume = false
        if not alive then return end
        if newCharacter and resume then
            setEnabled(true)
            status.Text = "Respawned; farming resumed"
        elseif not newCharacter then
            status.Text = "Reset unconfirmed; farm stopped"
        else
            status.Text = "Stopped after reset"
        end
    end)
end

local lastToggle = 0
toggle.MouseButton1Click:Connect(function()
    if os.clock() - lastToggle < 0.5 then return end
    lastToggle = os.clock()
    setEnabled(not enabled)
end)

stopButton.MouseButton1Click:Connect(function()
    setEnabled(false)
    status.Text = "Stopped"
end)

pauseButton.MouseButton1Click:Connect(function()
    setEnabled(not enabled)
end)

local collapsed = false
minimize.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    for _, page in pairs(pageCards) do
        page.Visible = false
    end
    if not collapsed then showPage(currentPage) end
    statusPanel.Visible = not collapsed
    main.Size = UDim2.fromOffset(560, collapsed and 60 or 458)
    sidebar.Size = UDim2.fromOffset(120, collapsed and 60 or 458)
    sidebarMask.Size = UDim2.fromOffset(22, collapsed and 60 or 458)
    for _, button in pairs(navButtons) do
        button.Visible = not collapsed
    end
    antiAfkText.Visible = not collapsed
    minimize.Text = collapsed and "+" or "–"
end)

keyConnection = UIS.InputBegan:Connect(function(input, processed)
    if processed or not alive or UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.B then
        setEnabled(false)
        status.Text = "Stopped with B"
    end
end)

local function stop()
    if not alive then return end
    setEnabled(false)
    alive = false
    if farmConnection then farmConnection:Disconnect() end
    if keyConnection then keyConnection:Disconnect() end
    if inspectConnection then inspectConnection:Disconnect() end
    if idleConnection then idleConnection:Disconnect() end
    if focusLostConnection then focusLostConnection:Disconnect() end
    if focusGainedConnection then focusGainedConnection:Disconnect() end
    if healthConnection then healthConnection:Disconnect() end
    resetResume = false
    gui:Destroy()
    if env.AboveMobFarmStop == stop then env.AboveMobFarmStop = nil end
end

env.AboveMobFarmStop = stop
close.MouseButton1Click:Connect(stop)

-- ==========================================
-- Main loop
-- ==========================================

farmConnection = RunService.Heartbeat:Connect(function()
    if not alive or not enabled or resetInProgress then return end

    local _, root, hum = getCharacter()
    if not root then
        releaseHover()
        currentTarget = nil
        combatStartedAt = 0
        lastObservedProgress = 0
        status.Text = "Waiting for character..."
        return
    end

    if monitoredHumanoid ~= hum then
        if healthConnection then healthConnection:Disconnect() end
        monitoredHumanoid = hum
        local previousHealth = hum.Health
        healthConnection = hum.HealthChanged:Connect(function(newHealth)
            if not alive then return end
            if enabled and CONFIG.AutoRaiseOnDamage
                and newHealth < previousHealth
                and os.clock() - lastAutoRaise >= CONFIG.AutoRaiseCooldown then
                lastAutoRaise = os.clock()
                local before = CONFIG.HoverHeight
                changeHeight(CONFIG.AutoRaiseStep)
                if CONFIG.HoverHeight > before then
                    resetSub.Text = "Raised height after taking damage."
                else
                    resetSub.Text = "Max clearance reached; damage possible."
                end
            end
            previousHealth = newHealth
        end)
    end

    -- V8 hover behavior: hold the character above ground at all times
    -- while the farm is active, even between targets.
    local hold = ensureHover(root)
    if not hold then
        status.Text = "Could not enable hover"
        return
    end

    local now = os.clock()

    -- Observe health decrease on current target (if the game exposes it).
    if currentTarget then
        local previous = targetHealthMemory[currentTarget]
        local health = getHealth(currentTarget)
        if previous ~= nil and health ~= nil and health < previous then
            lastObservedProgress = now
            resetSub.Text = "Damage observed; stall timer restarted."
        end
        targetHealthMemory[currentTarget] = health
    end

    -- Only count disappearance as a likely kill if the mob was attacked.
    if currentTarget and not withinRange(currentTarget, root) then
        local deadOrGone = not currentTarget:IsDescendantOf(workspace)
        local health = getHealth(currentTarget)
        if health ~= nil and health <= 0 then deadOrGone = true end
        if deadOrGone and targetSince > 0 and now - lastAttack <= 2 then
            lastObservedProgress = now
            resetSub.Text = "Target defeated/disappeared after attack."
        end
        currentTarget = nil
        targetSince = 0
    end

    -- Preserve anti-spawn and stuck target protection from V8.
    if currentTarget and targetSince > 0
        and now - targetSince >= CONFIG.MaxTargetSeconds then
        ignoredUntil[currentTarget] = now + CONFIG.StuckTargetCooldown
        currentTarget = nil
        targetSince = 0
        status.Text = "Skipping stuck target..."
    end

    if not currentTarget and now - lastScan >= CONFIG.ScanDelay then
        lastScan = now
        currentTarget = findNearestMob(root, now)
        if currentTarget then
            targetSince = now
            targetHealthMemory[currentTarget] = getHealth(currentTarget)
            if combatStartedAt == 0 then
                combatStartedAt = now
                lastObservedProgress = now
            end
        end
    end

    if not currentTarget then
        -- Don't reset while idle with no enemies in range.
        combatStartedAt = 0
        lastObservedProgress = 0
        status.Text = "Floating - scanning " .. selectedTargetNames()
        return
    end

    local valid, mobRoot = validMob(currentTarget)
    if not valid then
        currentTarget = nil
        targetSince = 0
        return
    end

    -- Reset after a full 10s of combat with no OBSERVABLE damage/kill.
    -- Clicks alone are not treated as hits.
    if combatStartedAt > 0 and now - lastObservedProgress >= CONFIG.NoHitResetSeconds then
        resetCharacter("No damage/kill seen for 10s - reset")
        return
    end

    local targetPos = mobRoot.Position
    local topY = targetPos.Y + mobRoot.Size.Y * 0.5
    if currentTarget:IsA("Model") then
        local ok, cf, size = pcall(function()
            return currentTarget:GetBoundingBox()
        end)
        if ok and cf and size then
            topY = cf.Position.Y + size.Y * 0.5
        end
    end

    local rootToFeet = hum.HipHeight + root.Size.Y * 0.5
    local hoverPos = Vector3.new(
        targetPos.X,
        topY + rootToFeet + CONFIG.HoverHeight,
        targetPos.Z
    )

    pcall(function()
        hold.Position = hoverPos
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = CFrame.new(hoverPos)
    end)

    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.lookAt(
        hoverPos + Vector3.new(0, 4, 7), targetPos
    )

    status.Text = "Targeting: " .. currentTarget.Name

    if not attacking and now - lastAttack >= CONFIG.AttackDelay then
        lastAttack = now
        attacking = true
        task.spawn(function()
            pcall(attack)
            attacking = false
        end)
    end
end)

print("[ABOVE] V11 ready: individual Slimes / Skeletons / Morton toggles; Skeletons + Morton allowed")
