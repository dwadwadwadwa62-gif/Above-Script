--[[
    ABOVE | AUTO MOB FARM V9
    - Slimes + Skeletons
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
    TargetMode = "ALL", -- ALL, SLIMES, SKELETONS
    SearchRange = 500,
    MaxVerticalDifference = 50,
    HoverHeight = 12,
    MinHoverHeight = 6,
    MaxHoverHeight = 24,
    HeightStep = 1,
    AutoRaiseOnDamage = false,
    AutoRaiseStep = 0,
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
main.Size = UDim2.fromOffset(560, 345)
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
sidebar.Size = UDim2.fromOffset(120, 345)
sidebar.Position = UDim2.fromOffset(0, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(6, 9, 19)
sidebar.BorderSizePixel = 0
sidebar.Parent = main
corner(sidebar, 14)

local sidebarMask = Instance.new("Frame")
sidebarMask.Size = UDim2.fromOffset(22, 345)
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

local function navLabel(text, y, active)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(16, y)
    label.Size = UDim2.fromOffset(88, 18)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
    label.TextSize = 14
    label.TextColor3 = active and Color3.fromRGB(244,244,248) or Color3.fromRGB(160, 164, 184)
    label.Text = text
    label.Parent = sidebar
    return label
end

navLabel("Farms", 95, true)
navLabel("Combat", 125, false)
navLabel("Session", 155, false)
navLabel("Settings", 185, false)

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromOffset(420, 345)
content.Position = UDim2.fromOffset(120, 0)
content.BackgroundTransparency = 1
content.Parent = main

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, -18, 0, 42)
topBar.Position = UDim2.fromOffset(10, 10)
topBar.BackgroundTransparency = 1
topBar.Parent = content

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Size = UDim2.fromOffset(170, 30)
searchBox.Position = UDim2.fromOffset(138, 4)
searchBox.BackgroundColor3 = Color3.fromRGB(15, 18, 32)
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.PlaceholderText = "Search..."
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
card.Name = "FarmCard"
card.Size = UDim2.new(1, -18, 0, 220)
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
cardTitle.Text = "Auto Farm"
cardTitle.Parent = card

local cardSub = Instance.new("TextLabel")
cardSub.BackgroundTransparency = 1
cardSub.Position = UDim2.fromOffset(14, 30)
cardSub.Size = UDim2.fromOffset(180, 18)
cardSub.TextXAlignment = Enum.TextXAlignment.Left
cardSub.Font = Enum.Font.Gotham
cardSub.TextSize = 11
cardSub.TextColor3 = Color3.fromRGB(136, 140, 164)
cardSub.Text = "Clean mode for slimes and skeletons."
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

local farmHolder, farmLabel, farmSub = row(56, "Auto Farm", "Start or pause the current farm.")
local targetHolder, targetLabel, targetSub = row(97, "Target Mode", "Switch between slimes, skeletons, or all.")
local heightHolder, heightLabel, heightSub = row(138, "Hover Height", "Adjust floating clearance.")
local resetHolder, resetLabel, resetSub = row(179, "10s Stall Reset", "Resets when no damage/kill is detected.")

local toggle, toggleKnob = makeSwitch(card, 333, 62, false)
toggle.Name = "FarmToggle"
local modeButton = Instance.new("TextButton")
modeButton.Name = "TargetMode"
modeButton.Size = UDim2.fromOffset(108, 28)
modeButton.Position = UDim2.fromOffset(280, 103)
modeButton.BackgroundColor3 = Color3.fromRGB(72, 75, 96)
modeButton.BorderSizePixel = 0
modeButton.Text = "ALL"
modeButton.TextColor3 = Color3.fromRGB(245,245,250)
modeButton.Font = Enum.Font.GothamBold
modeButton.TextSize = 12
modeButton.Parent = card
corner(modeButton, 10)

local minus = Instance.new("TextButton")
minus.Name = "HeightMinus"
minus.Size = UDim2.fromOffset(28, 28)
minus.Position = UDim2.fromOffset(284, 144)
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
heightValue.Position = UDim2.fromOffset(319, 144)
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
plus.Position = UDim2.fromOffset(372, 144)
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
resetBadge.Position = UDim2.fromOffset(281, 185)
resetBadge.Size = UDim2.fromOffset(105, 26)
resetBadge.Font = Enum.Font.GothamBold
resetBadge.TextSize = 11
resetBadge.TextColor3 = Color3.fromRGB(248,248,252)
resetBadge.Text = "ON • 10s"
resetBadge.Parent = card
corner(resetBadge, 10)

local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(1, -18, 0, 54)
statusPanel.Position = UDim2.fromOffset(10, 280)
statusPanel.BackgroundColor3 = Color3.fromRGB(11, 14, 25)
statusPanel.BorderSizePixel = 0
statusPanel.Parent = content
corner(statusPanel, 12)
stroke(statusPanel, Color3.fromRGB(43, 48, 72), 1, 0.25)

local status = Instance.new("TextLabel")
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
antiAfkText.Position = UDim2.fromOffset(12, 312)
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

local function cycleMode()
    if CONFIG.TargetMode == "ALL" then
        CONFIG.TargetMode = "SKELETONS"
    elseif CONFIG.TargetMode == "SKELETONS" then
        CONFIG.TargetMode = "SLIMES"
    else
        CONFIG.TargetMode = "ALL"
    end
    modeButton.Text = CONFIG.TargetMode
    targetSub.Text = "Switch between slimes, skeletons, or all. Current: " .. CONFIG.TargetMode
    currentTarget = nil
    targetSince = 0
    combatStartedAt = 0
    lastScan = 0
    status.Text = "Mode: " .. CONFIG.TargetMode
end

modeButton.MouseButton1Click:Connect(cycleMode)

-- The search field sets the target mode for common queries.
searchBox.FocusLost:Connect(function()
    local term = string.lower((searchBox.Text or ""):gsub("%s+", ""))
    local chosen = nil
    if term == "slime" or term == "slimes" then
        chosen = "SLIMES"
    elseif term == "skeleton" or term == "skeletons" then
        chosen = "SKELETONS"
    elseif term == "all" or term == "both" then
        chosen = "ALL"
    end
    if chosen then
        CONFIG.TargetMode = chosen
        modeButton.Text = chosen
        targetSub.Text = "Target mode: " .. chosen
        currentTarget = nil
        targetSince = 0
        combatStartedAt = 0
        lastScan = 0
        status.Text = "Mode: " .. chosen
    elseif term ~= "" then
        status.Text = "Search: slime, skeleton, all"
    end
    searchBox.Text = ""
end)

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
    local forbidden = {"spawn", "spawner", "marker", "template", "dummy", "statue", "display", "shop", "merchant", "trader"}
    for _, word in ipairs(forbidden) do
        if string.find(lowered, word, 1, true) then return true end
    end
    return false
end

local function getTargetKind(target)
    if not target then return nil end
    local lowered = string.lower(target.Name)

    if target:IsA("BasePart") then
        if CONFIG.MobNames[lowered] then return "SLIMES" end
        if string.find(lowered, CONFIG.SkeletonKeyword, 1, true) and not isSpawnMarkerName(lowered) then
            local parentModel = target:FindFirstAncestorOfClass("Model")
            if parentModel and string.find(string.lower(parentModel.Name), CONFIG.SkeletonKeyword, 1, true) then
                return nil
            end
            return "SKELETONS"
        end
    elseif target:IsA("Model") and string.find(lowered, CONFIG.SkeletonKeyword, 1, true) and not isSpawnMarkerName(lowered) then
        return "SKELETONS"
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
    if CONFIG.TargetMode ~= "ALL" and CONFIG.TargetMode ~= kind then return false end
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

    if enabled then
        oldCameraType = camera.CameraType
        oldCameraSubject = camera.CameraSubject
        lastAttack = 0
        setToggleVisual(true)
        pauseButton.Text = "Ⅱ"
        status.Text = "Searching: " .. CONFIG.TargetMode
        farmSub.Text = "Farm enabled; scanning for enemies."
    else
        setToggleVisual(false)
        pauseButton.Text = "▶"
        status.Text = "Status: Idle"
        farmSub.Text = "Farm paused; floating released."
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
    card.Visible = not collapsed
    statusPanel.Visible = not collapsed
    main.Size = UDim2.fromOffset(560, collapsed and 60 or 345)
    sidebar.Size = UDim2.fromOffset(120, collapsed and 60 or 345)
    sidebarMask.Size = UDim2.fromOffset(22, collapsed and 60 or 345)
    for _, child in ipairs(sidebar:GetChildren()) do
        if child:IsA("TextLabel") and child ~= brand and child ~= subtitle then
            child.Visible = not collapsed
        end
    end
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
        status.Text = "Floating - scanning " .. CONFIG.TargetMode
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

print("[ABOVE] V9 ready: cleaner GUI + 10s no-progress reset")
