--[[
    ABOVE | AUTO MOB FARM V7 - ANTI IDLE + BACKGROUND ATTACK
    Updated from the supplied V2 script.

    - Automatically targets BlueSlime, GreenSlime, PinkSlime, OrangeSlime Parts
    - + / - GUI buttons adjust clearance ABOVE the slime (6 to 24 studs)
    - B immediately switches farming OFF (the GUI stays open)
    - GUI toggle can start farming again; X closes everything
    - Holds position in the air even when no slime is found
    - Releases hover force when B, OFF, or X is used
    - Automatically raises hover clearance when health drops (optional)
    - Ignores stationary spawn markers by requiring observed movement or health
    - Skips targets that cannot be defeated after a configurable timeout
    - Anti-idle uses Roblox VirtualUser when the client becomes idle
    - Background attack prefers equipped Tool:Activate(), then simulated client clicks
    - Avoids moving the desktop mouse while the game is unfocused

    Equip your primary weapon before starting.
    Other slime names have been inferred from BlueSlime; they are not game-verified.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local env = (type(getgenv) == "function" and getgenv()) or _G

-- Shut down earlier copies before creating the replacement GUI.
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
    SearchRange = 300,           -- Maximum targeting/teleport range, in studs
    MaxVerticalDifference = 50,  -- Room for raised hover above larger slimes
    HoverHeight = 12,           -- CLEARANCE above slime top, not center
    MinHoverHeight = 6,
    MaxHoverHeight = 24,
    HeightStep = 2,
    AutoRaiseOnDamage = true,   -- Increase clearance if slime still hits you
    AutoRaiseStep = 2,
    AutoRaiseCooldown = 2,
    AttackDelay = 0.35,
    ScanDelay = 0.6,
    -- Anti-spawn-point filtering. A slime without an exposed Health value
    -- must actually move before it can be selected as a target.
    RequireMovement = true,
    MinimumObservedMovement = 0.65,
    RecentMovementSeconds = 4,
    MaxTargetSeconds = 14,
    StuckTargetCooldown = 20,
    AntiAFK = true,         -- Attempts to prevent Roblox idle disconnects
    BackgroundAttack = true, -- Attempts attacks without the Roblox window focused
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

-- ==========================================
-- GUI (same simple style as the working V2)
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

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.fromOffset(280, 302)
-- Keep away from centre-screen simulated attack clicks.
frame.Position = UDim2.fromOffset(20, 80)
frame.BackgroundColor3 = Color3.fromRGB(32, 34, 39)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Visible = true
frame.ZIndex = 1
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local function makeText(name, content, y, height, size)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = UDim2.new(1, -24, 0, height)
    label.Position = UDim2.fromOffset(12, y)
    label.BackgroundTransparency = 1
    label.Text = content
    label.TextColor3 = Color3.fromRGB(235, 235, 235)
    label.Font = Enum.Font.Gotham
    label.TextSize = size
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 2
    label.Parent = frame
    return label
end

local function makeButton(name, content, x, y, w, h, color)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.fromOffset(w, h)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = color
    button.Text = content
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 16
    button.ZIndex = 3
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    return button
end

local title = makeText("Title", "ABOVE | MOB FARM", 8, 35, 17)
title.Font = Enum.Font.GothamBold
title.Size = UDim2.new(1, -58, 0, 35)

local close = makeButton(
    "CloseButton", "X", 240, 10, 30, 30, Color3.fromRGB(155, 50, 50)
)

local toggle = makeButton(
    "FarmToggle", "AUTO FARM: OFF", 12, 55, 256, 45,
    Color3.fromRGB(150, 50, 50)
)

local status = makeText("Status", "Status: Idle", 110, 26, 13)
local instructions = makeText(
    "Instructions", "Auto-targets Blue / Green / Pink / Orange", 139, 24, 11
)
local heightText = makeText("HoverHeight", "Clearance: 12 studs", 173, 30, 13)
heightText.Size = UDim2.fromOffset(177, 30)

local minus = makeButton(
    "HeightMinus", "-", 195, 170, 32, 32, Color3.fromRGB(85, 85, 90)
)
local plus = makeButton(
    "HeightPlus", "+", 236, 170, 32, 32, Color3.fromRGB(85, 85, 90)
)
local footer = makeText(
    "Help", "B = STOP (in game)  |  + / - = clearance", 211, 25, 11
)
footer.TextColor3 = Color3.fromRGB(185, 185, 185)
local safetyText = makeText(
    "Safety", "Protection: raises height if damaged", 236, 25, 11
)
safetyText.TextColor3 = Color3.fromRGB(185, 185, 185)
local focusText = makeText(
    "Focus", "Anti-AFK: ON | Window: FOCUSED", 265, 25, 11
)
focusText.TextColor3 = Color3.fromRGB(185, 185, 185)

local function updateFocusText()
    focusText.Text = "Anti-AFK: " .. (CONFIG.AntiAFK and "ON" or "OFF")
        .. " | Window: " .. (windowFocused and "FOCUSED" or "BACKGROUND")
end

-- These events report whether Roblox has keyboard/mouse focus.
-- The farming loop itself is intentionally NOT stopped on focus loss.
focusLostConnection = UIS.WindowFocusReleased:Connect(function()
    windowFocused = false
    if alive then updateFocusText() end
end)
focusGainedConnection = UIS.WindowFocused:Connect(function()
    windowFocused = true
    if alive then updateFocusText() end
end)

-- Hover force is declared here and created only while Auto Farm is ON.
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

    -- Raise the character once at startup, then maintain height against gravity.
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

local function updateHeightText()
    heightText.Text = "Clearance: " .. CONFIG.HoverHeight .. " studs"
end

local function changeHeight(change)
    if not alive then return end
    local oldHeight = CONFIG.HoverHeight
    CONFIG.HoverHeight = math.clamp(
        oldHeight + change, CONFIG.MinHoverHeight, CONFIG.MaxHoverHeight
    )
    local delta = CONFIG.HoverHeight - oldHeight

    -- Apply +/- instantly even when waiting between slime targets.
    if delta ~= 0 and hoverRoot and hoverRoot.Parent and hoverForce then
        local lift = Vector3.new(0, delta, 0)
        hoverForce.Position = hoverForce.Position + lift
        hoverRoot.CFrame = hoverRoot.CFrame + lift
    end
    updateHeightText()
end

minus.MouseButton1Click:Connect(function()
    changeHeight(-CONFIG.HeightStep)
end)

plus.MouseButton1Click:Connect(function()
    changeHeight(CONFIG.HeightStep)
end)

print("[ABOVE] GUI loaded!")

-- ==========================================
-- TARGET DETECTION
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

local function getHealth(target)
    local attribute = target:GetAttribute("Health")
    if type(attribute) == "number" then return attribute end

    local value = target:FindFirstChild("Health")
    if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
        return value.Value
    end
    return nil
end

local function validMob(target)
    if not target or not target:IsA("BasePart") then return false end
    if not CONFIG.MobNames[string.lower(target.Name)] then return false end
    if not target:IsDescendantOf(workspace) then return false end
    if isPlayerPart(target) then return false end

    local health = getHealth(target)
    if health ~= nil and health <= 0 then return false end
    return true
end

-- Track a part across multiple scans. A stationary marker named BlueSlime
-- will not become a target just because its name matches the allowlist.
-- Health-bearing enemies are accepted even while idle.
local function isActiveSlime(target, now)
    if not CONFIG.RequireMovement then return true end
    if getHealth(target) ~= nil then return true end

    local sample = motionSamples[target]
    local position = target.Position
    if not sample then
        motionSamples[target] = {
            position = position,
            accumulated = 0,
            lastMovement = -math.huge,
        }
        return false
    end

    local displacement = (position - sample.position).Magnitude
    sample.position = position

    -- Count normal movement/bobbing, but not massive respawn jumps.
    if displacement >= 0.08 and displacement <= 25 then
        sample.accumulated = math.min(
            sample.accumulated + displacement,
            CONFIG.MinimumObservedMovement + 1
        )
        if sample.accumulated >= CONFIG.MinimumObservedMovement then
            sample.lastMovement = now
        end
    end

    return sample.accumulated >= CONFIG.MinimumObservedMovement
        and (now - sample.lastMovement) <= CONFIG.RecentMovementSeconds
end

local function withinRange(target, root)
    if not root or not validMob(target) then return false end
    local difference = target.Position - root.Position
    return difference.Magnitude <= CONFIG.SearchRange
        and math.abs(difference.Y) <= math.max(
            CONFIG.MaxVerticalDifference, CONFIG.HoverHeight + 8
        )
end

local function findNearestMob(root, now)
    local nearest = nil
    local shortest = CONFIG.SearchRange

    -- Scanned only once per CONFIG.ScanDelay, not every Heartbeat.
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and validMob(obj) then
            local difference = obj.Position - root.Position
            local distance = difference.Magnitude
            if distance < CONFIG.SearchRange
                and math.abs(difference.Y) <= math.max(
                    CONFIG.MaxVerticalDifference, CONFIG.HoverHeight + 8
                ) then
                -- Observe all matching slimes, not only the nearest marker.
                local active = isActiveSlime(obj, now)
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

-- ==========================================
-- PRIMARY WEAPON ATTACK (supports background attempts)
-- ==========================================

-- Many Roblox weapons are Tools. Activating the tool does not need a
-- physical mouse click, so this is the preferred unfocused-window action.
local function activateTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return false end
    return pcall(function() tool:Activate() end)
end

-- Sends mouse events to the Roblox client, without moving the OS cursor.
-- Executor and game behavior varies when the window is in the background.
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
    -- Never leave an attack button held if an error occurs during the click.
    if pressed then
        pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end
    return ok
end

local function attack()
    if not alive or not enabled then return end

    local view = camera.ViewportSize
    local x = math.floor(view.X / 2)
    local y = math.floor(view.Y / 2)

    -- When tabbed out, never call mousemoveabs/mouse1click: those may
    -- move or click the cursor in the user's OTHER application.
    if not windowFocused then
        if not CONFIG.BackgroundAttack then return end
        if activateTool() then return end
        virtualClick(x, y)
        return
    end

    -- Preserve the existing foreground attack behavior from V6.
    if type(mousemoveabs) == "function" then
        pcall(mousemoveabs, x, y)
    end

    local clicked = false
    if type(mouse1click) == "function" then
        clicked = pcall(mouse1click)
    end
    if not clicked then clicked = virtualClick(x, y) end
    if not clicked then activateTool() end
end

-- ==========================================
-- ANTI-IDLE
-- ==========================================

-- Player.Idled is fired by Roblox before its normal idle disconnect.
-- This is intentionally inactive whenever Auto Farm is OFF.
idleConnection = player.Idled:Connect(function()
    if not alive or not enabled or not CONFIG.AntiAFK then return end
    if os.clock() - lastAntiAfk < 10 then return end
    lastAntiAfk = os.clock()

    task.spawn(function()
        local down = false
        local ok, err = pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.zero, camera.CFrame)
            down = true
            task.wait(0.12)
            VirtualUser:Button2Up(Vector2.zero, camera.CFrame)
            down = false
        end)
        if down then
            pcall(function()
                VirtualUser:Button2Up(Vector2.zero, camera.CFrame)
            end)
        end
        if ok then
            print("[ABOVE] Anti-idle input sent")
        else
            warn("[ABOVE] Anti-idle input failed:", err)
        end
    end)
end)

-- ==========================================
-- ON/OFF, B KEYBIND, AND CLEANUP
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
    enabled = value
    currentTarget = nil
    lastScan = 0
    targetSince = 0

    if enabled then
        oldCameraType = camera.CameraType
        oldCameraSubject = camera.CameraSubject
        lastAttack = 0
        toggle.Text = "AUTO FARM: ON"
        toggle.BackgroundColor3 = Color3.fromRGB(45, 140, 75)
        status.Text = "Searching for slimes..."
    else
        toggle.Text = "AUTO FARM: OFF"
        toggle.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        status.Text = "Status: Idle"
        releaseHover()
        restoreCamera()
    end
end

-- Preserve the click debounce that stopped attack clicks from re-toggling.
local lastToggle = 0
toggle.MouseButton1Click:Connect(function()
    if os.clock() - lastToggle < 0.5 then return end
    lastToggle = os.clock()
    setEnabled(not enabled)
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
    if idleConnection then idleConnection:Disconnect() end
    if focusLostConnection then focusLostConnection:Disconnect() end
    if focusGainedConnection then focusGainedConnection:Disconnect() end
    if healthConnection then healthConnection:Disconnect() end
    gui:Destroy()
    if env.AboveMobFarmStop == stop then
        env.AboveMobFarmStop = nil
    end
end

env.AboveMobFarmStop = stop
close.MouseButton1Click:Connect(stop)

-- ==========================================
-- MAIN LOOP
-- ==========================================

farmConnection = RunService.Heartbeat:Connect(function()
    if not alive or not enabled then return end

    local _, root, hum = getCharacter()
    if not root then
        releaseHover()
        status.Text = "Waiting for character..."
        return
    end

    -- Monitor actual damage and increase clearance if slimes still reach us.
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
                    safetyText.Text = "Damage detected - raised to "
                        .. CONFIG.HoverHeight .. " studs"
                else
                    safetyText.Text = "Max clearance reached; damage possible"
                end
            end
            previousHealth = newHealth
        end)
    end

    -- Keep the character suspended while the farm runs, even without targets.
    local hold = ensureHover(root)
    if not hold then
        status.Text = "Could not enable hover"
        return
    end

    local now = os.clock()
    if currentTarget and not withinRange(currentTarget, root) then
        currentTarget = nil
        targetSince = 0
    end

    -- Never attack indefinitely at the same object: it may be a spawn point.
    if currentTarget and targetSince > 0
        and now - targetSince >= CONFIG.MaxTargetSeconds then
        ignoredUntil[currentTarget] = now + CONFIG.StuckTargetCooldown
        currentTarget = nil
        targetSince = 0
        status.Text = "Skipping stuck slime target..."
    end

    if not currentTarget and now - lastScan >= CONFIG.ScanDelay then
        lastScan = now
        currentTarget = findNearestMob(root, now)
        if currentTarget then targetSince = now end
    end

    if not currentTarget then
        -- No target: BodyPosition keeps the last safe airborne location.
        status.Text = "Floating - waiting for moving slimes"
        return
    end

    local targetPos = currentTarget.Position

    -- HoverHeight is vertical SPACE from the slime's top to the player's feet.
    -- Previously the root was only 6 studs above the slime's CENTER, which
    -- can leave feet inside its hitbox, especially for larger slimes.
    local slimeHalfHeight = currentTarget.Size.Y * 0.5
    local rootToFeet = hum.HipHeight + root.Size.Y * 0.5
    local hoverPos = targetPos + Vector3.new(
        0, slimeHalfHeight + rootToFeet + CONFIG.HoverHeight, 0
    )

    -- Follow the slime in midair. The hover force continues holding this
    -- height between targets, instead of dropping the player onto the ground.
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

    if not attacking and os.clock() - lastAttack >= CONFIG.AttackDelay then
        lastAttack = os.clock()
        attacking = true
        task.spawn(function()
            pcall(attack)
            attacking = false
        end)
    end
end)

print("[ABOVE] V7 ready: movement-verified slimes, background attack attempts, anti-idle, B stops.")
