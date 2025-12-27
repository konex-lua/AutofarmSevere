--!optimize 2
--[[
    SYRA AUTOFARM | v3.0
    - Clean: Removed unnecessary code and optimized
    - Fix: Streamlined enemy detection and targeting
    - ESP: Optimized rendering and performance
]]

loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge.lua"))();
local Library = luau.load(game:HttpGet("https://raw.githubusercontent.com/DCHARLESAKAMRGREEN/Severe-Luas/main/Libraries/Pseudosynonym.lua"))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ========= CONFIGURATION =========
local FarmState = {
    Enabled = false,
    SelectedTargetLower = "",
    AutoBlock = true,
    AutoKick = false,
    ProximityRange = 500,
    AttackDistance = 8,
    ESP_Enabled = false,
    ESP_Names = false,
    ESP_Level = false,
    ESP_Health = false,
    BossAlert = false,
    HealthCheck = false,
    HealthThreshold = 20
}

local WhitelistedPlayers = {}
local CurrentTarget = nil
local TELE_BUFF = buffer.create(12)

-- ========= HELPERS =========
local function updateStatus(txt)
    pcall(function() Status:SetValue("Status: " .. txt) end)
end

local function severeTeleport(part, pos)
    if not part or not part.Parent then return end
    pcall(function()
        local addr = engine.get_instance_address(part)
        if addr and addr ~= 0 then 
            buffer.writef32(TELE_BUFF, 0, pos.X); buffer.writef32(TELE_BUFF, 4, pos.Y); buffer.writef32(TELE_BUFF, 8, pos.Z)
            memory.writebuffer(addr + 0x4C, TELE_BUFF) 
        end
    end)
end

local function getRoot(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) end

local function isDead(m)
    if not m or not m.Parent then return true end
    local hum = m:FindFirstChildOfClass("Humanoid")
    return (hum and hum.Health <= 0) or false
end

local function getPlayerNames()
    local n = {}
    for _, p in ipairs(Players:GetChildren()) do
        if p:IsA("Player") and p ~= LocalPlayer then table.insert(n, p.Name) end
    end
    return #n > 0 and n or {"No Players Found"}
end

-- ========= HEALTH PROTECTION =========
local function getHealthPercentage()
    local character = LocalPlayer.Character
    if not character then return 100 end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return 100 end
    return math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
end

local function emergencyHeal()
    local root = getRoot(LocalPlayer.Character)
    if not root then return end
    
    updateStatus("LOW HEALTH! Teleporting to safety...")
    
    -- Find a safe position far away
    local safePos = root.Position + Vector3.new(1000, 100, 1000)
    severeTeleport(root, safePos)
    
    -- Hold X to charge until health is max
    task.delay(0.5, function()
        if keypress then keypress(0x58) end -- X key
        updateStatus("Charging health to max...")
        
        -- Monitor health until max
        task.spawn(function()
            while true do
                local healthPercent = getHealthPercentage()
                if healthPercent >= 99 then -- 99% to account for rounding
                    if keyup then keyup(0x58) end
                    updateStatus("Health fully restored!")
                    break
                end
                task.wait(0.1)
            end
        end)
    end)
end

-- ========= ESP LOGIC =========
local function applyESP(enemy)
    if not enemy or not enemy.Parent then return end
    if enemy:FindFirstChild("SyraESP") then return end
    
    pcall(function()
        local bgui = Instance.new("BillboardGui", enemy)
        bgui.Name = "SyraESP"
        bgui.Adornee = getRoot(enemy)
        bgui.Size = UDim2.new(0, 200, 0, 50)
        bgui.AlwaysOnTop = true
        bgui.ExtentsOffset = Vector3.new(0, 3, 0)
        
        local label = Instance.new("TextLabel", bgui)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0
        label.TextSize = 14
        
        task.spawn(function()
            while enemy and enemy.Parent and not isDead(enemy) do
                if FarmState.ESP_Enabled then
                    local displayStr = ""
                    if FarmState.ESP_Names then displayStr = displayStr .. enemy.Name .. "\n" end
                    if FarmState.ESP_Level then 
                        local lv = enemy:FindFirstChild("Level")
                        displayStr = displayStr .. "Lv: " .. (lv and tostring(lv.Value) or "??") .. "\n"
                    end
                    if FarmState.ESP_Health then
                        local hum = enemy:FindFirstChildOfClass("Humanoid")
                        displayStr = displayStr .. "HP: " .. (hum and math.floor(hum.Health) or "0")
                    end
                    
                    label.Text = displayStr
                    label.Visible = true
                    
                    if FarmState.BossAlert and enemy:FindFirstChild("Boss") then
                        label.TextColor3 = Color3.new(1, 0, 0)
                        label.TextSize = 18
                    else
                        label.TextColor3 = Color3.new(1, 1, 1)
                        label.TextSize = 14
                    end
                else
                    label.Visible = false
                end
                task.wait(0.1)
            end
            pcall(function() bgui:Destroy() end)
        end)
    end)
end

-- ========= DRAWING IMMEDIATE ESP SYSTEM =========
local Client = Players.LocalPlayer
local CurrentCamera = Workspace.CurrentCamera

-- Drawing ESP Configuration
local ESP_TEXT_COLOR = Color3.fromRGB(125, 165, 255)
local NPC_TEXT_COLOR = Color3.fromRGB(255, 50, 50)
local TEXT_SIZE = 12
local TEXT_OPACITY = 1
local FONT_NAME = "Tamzen"
local VERTICAL_OFFSET = 20
local MAX_NPC_ESP_DISTANCE = 150

-- Helper function for player level text
local function getLevelText(Player: Player): string
    local liveFolder = Workspace:FindFirstChild("Live")
    if liveFolder then
        local playerFolder = liveFolder:FindFirstChild(Player.Name)
        if playerFolder then
            local levelValue = playerFolder:FindFirstChild("Level")
            if levelValue and levelValue:IsA("IntValue") then
                return `Lv. {levelValue.Value}`
            end
        end
    end
    return "Lv. ???"
end

-- DrawingImmediate ESP Render Loop
if RunService and RunService.Render then
    RunService.Render:Connect(function()
        -- Check if ESP is enabled via UI toggle
        if not FarmState.ESP_Enabled then return end
        
        if not CurrentCamera then return end

        -- 1. NPC HEALTH ESP
        local EnemiesFolder = Workspace:FindFirstChild("Enemies")
        if EnemiesFolder then
            for _, NPC in EnemiesFolder:GetChildren() do
                local Head = NPC:FindFirstChild("Head")
                local Humanoid = NPC:FindFirstChildOfClass("Humanoid")
                
                if Head and Humanoid then
                    -- Use the vector library function for distance
                    local diff = CurrentCamera.CFrame.Position - Head.Position
                    local Distance = (diff.X^2 + diff.Y^2 + diff.Z^2)^0.5
                    
                    if Distance <= MAX_NPC_ESP_DISTANCE then
                        local ScreenPos, Visible = CurrentCamera:WorldToScreenPoint(Head.Position)
                        if Visible and FarmState.ESP_Health then
                            local healthText = `HP: {math.floor(Humanoid.Health)}` 
                            
                            DrawingImmediate.OutlinedText(
                                Vector2.new(ScreenPos.X, ScreenPos.Y + 15), 
                                TEXT_SIZE, 
                                NPC_TEXT_COLOR, 
                                TEXT_OPACITY, 
                                healthText, 
                                true, 
                                FONT_NAME
                            )
                        end
                    end
                end
            end
        end

        -- 2. PLAYER ESP (Names and Levels)
        for _, Player in Players:GetChildren() do
            if Player == Client then continue end
            
            local Character = Player.Character
            local Head = if Character then Character:FindFirstChild("Head") else nil
            
            if Head then
                local ScreenPos, Visible = CurrentCamera:WorldToScreenPoint(Head.Position)
                if Visible then
                    local yOffset = VERTICAL_OFFSET
                    
                    -- Player Name ESP
                    if FarmState.ESP_Names then
                        DrawingImmediate.OutlinedText(
                            Vector2.new(ScreenPos.X, ScreenPos.Y - yOffset), 
                            TEXT_SIZE, 
                            ESP_TEXT_COLOR, 
                            TEXT_OPACITY, 
                            Player.Name, 
                            true, 
                            FONT_NAME
                        )
                        yOffset = yOffset + 15 -- Offset for next line
                    end
                    
                    -- Player Level ESP
                    if FarmState.ESP_Level then
                        local displayString = getLevelText(Player)
                        DrawingImmediate.OutlinedText(
                            Vector2.new(ScreenPos.X, ScreenPos.Y - yOffset), 
                            TEXT_SIZE, 
                            ESP_TEXT_COLOR, 
                            TEXT_OPACITY, 
                            displayString, 
                            true, 
                            FONT_NAME
                        )
                    end
                end
            end
        end
    end)
end

-- ========= UI SETUP =========
local Window = Library:CreateWindow({
    Title = "Syra | v2.9", 
    Tag = "Stable", 
    Keybind = "RightControl", 
    AutoShow = true
}) -- [cite: 3, 4, 6]

local Tab = Window:AddTab({ Name = "Main" }) -- [cite: 12]
local EspTab = Window:AddTab({ Name = "Visuals" }) -- [cite: 12]

-- Main Farm Container
local Main = Tab:AddContainer({ Name = "Autofarm", Side = "Left", AutoSize = true }) -- [cite: 14, 15]
Status = Main:AddLabel({ Name = "Status: Ready" }) -- [cite: 42]

Main:AddToggle({
    Name = "Enable Autofarm", 
    Value = false, 
    Callback = function(v) FarmState.Enabled = v end
}) -- [cite: 22]

Main:AddInput({
    Name = "Enemy Name", 
    Placeholder = "Enemy...", 
    Callback = function(v) 
        FarmState.SelectedTargetLower = string.lower(v)
        CurrentTarget = nil 
    end
}) -- [cite: 37, 38, 41]

-- Settings & Security Container
local Settings = Tab:AddContainer({ Name = "Settings", Side = "Right", AutoSize = true }) -- [cite: 14, 15]

Settings:AddSlider({
    Name = "Proximity Range",
    Min = 50,
    Max = 10000,
    Default = 500,
    Callback = function(v) FarmState.ProximityRange = v end
})

Settings:AddSlider({
    Name = "Attack Distance",
    Min = 2,
    Max = 20,
    Default = 8,
    Callback = function(v) FarmState.AttackDistance = v end
})

Settings:AddToggle({
    Name = "Auto-Block (F)", 
    Value = true, 
    Callback = function(v) FarmState.AutoBlock = v end
}) -- [cite: 22]

Settings:AddToggle({
    Name = "Auto-Kick (Security)", 
    Value = false, 
    Callback = function(v) FarmState.AutoKick = v end
}) -- [cite: 22]

-- Health Protection Section
Settings:AddToggle({
    Name = "Health Protection", 
    Value = false, 
    Callback = function(v) FarmState.HealthCheck = v end
}) -- [cite: 22]

Settings:AddSlider({
    Name = "Health Threshold (%)",
    Min = 10,
    Max = 50,
    Default = 20,
    Callback = function(v) FarmState.HealthThreshold = v end
})

local PlayerList = Settings:AddDropdown({
    Name = "Whitelist",
    Values = getPlayerNames(),
    Default = {},
    Multi = true,
    Callback = function(v) WhitelistedPlayers = v or {} end
}) -- [cite: 32, 33, 35]

Settings:AddButton({
    Name = "Refresh Player List", 
    Callback = function()
        if PlayerList.SetValues then 
            PlayerList:SetValues(getPlayerNames()) 
        end 
    end
}) -- [cite: 25]

-- ESP Visuals Container
local EspCont = EspTab:AddContainer({ Name = "ESP Settings", Side = "Left", AutoSize = true }) -- [cite: 14, 15]

EspCont:AddToggle({Name = "ESP On", Value = false, Callback = function(v) FarmState.ESP_Enabled = v end}) -- [cite: 22]
EspCont:AddToggle({Name = "Name", Value = false, Callback = function(v) FarmState.ESP_Names = v end}) -- [cite: 22]
EspCont:AddToggle({Name = "Level", Value = false, Callback = function(v) FarmState.ESP_Level = v end}) -- [cite: 22]
EspCont:AddToggle({Name = "NPC Health", Value = false, Callback = function(v) FarmState.ESP_Health = v end}) -- [cite: 22]
EspCont:AddToggle({Name = "Boss Alert", Value = false, Callback = function(v) FarmState.BossAlert = v end}) -- [cite: 22]

-- ========= CORE LOOPS =========
task.spawn(function()
    while true do
        if FarmState.ESP_Enabled then
            local enemies = Workspace:FindFirstChild("Enemies")
            if enemies then
                for _, enemy in ipairs(enemies:GetChildren()) do
                    if not isDead(enemy) then applyESP(enemy) end
                end
            end
        end
        task.wait(2)
    end
end)

task.spawn(function()
    local phase, cooldownEnds, phaseStart = "idle", 0, 0
    local isHealing = false
    
    while true do
        local root = getRoot(LocalPlayer.Character)
        
        -- Health Check System
        if FarmState.HealthCheck and not isHealing then
            local healthPercent = getHealthPercentage()
            if healthPercent <= FarmState.HealthThreshold then
                isHealing = true
                emergencyHeal()
                -- Wait for healing to complete (variable time until max health)
                task.delay(10, function() -- Max 10 second timeout
                    isHealing = false
                end)
            end
        end
        
        if root and FarmState.Enabled and FarmState.SelectedTargetLower ~= "" and not Library.Visible and not isHealing then
            -- Find target if needed
            if not CurrentTarget or isDead(CurrentTarget) then
                CurrentTarget = nil
                local folder = Workspace:FindFirstChild("Enemies")
                if folder then
                    local closestTarget = nil
                    local closestDistance = FarmState.ProximityRange
                    
                    for _, m in ipairs(folder:GetChildren()) do
                        if not isDead(m) and string.find(string.lower(m.Name), FarmState.SelectedTargetLower) then
                            local enemyRoot = getRoot(m)
                            if enemyRoot and enemyRoot.Position and root.Position then
                                local diff = root.Position - enemyRoot.Position
                                local distance = (diff.X^2 + diff.Y^2 + diff.Z^2)^0.5
                                if distance <= closestDistance then
                                    closestDistance = distance
                                    closestTarget = m
                                end
                            end
                        end
                    end
                    
                    CurrentTarget = closestTarget
                    updateStatus(CurrentTarget and "Target: " .. CurrentTarget.Name or "No target found")
                end
            end

            -- Attack target
            if CurrentTarget then
                local troot = getRoot(CurrentTarget)
                if troot then
                    local now = os.clock()
                    if phase == "idle" then
                        (keyup or keyrelease)(0x46)
                        if now >= cooldownEnds then 
                            phase, phaseStart = "attack", now
                            mouse1press() 
                        end
                    elseif phase == "attack" and (now - phaseStart) >= 1.7 then
                        mouse1release()
                        phase, cooldownEnds = "cooldown", now + 1.8
                        if FarmState.AutoBlock then task.delay(0.01, function() (keydown or keypress)(0x46) end) end
                    elseif phase == "cooldown" and now >= cooldownEnds then
                        (keyup or keyrelease)(0x46)
                        phase, phaseStart = "attack", now
                        mouse1press()
                    end

                    local dist = FarmState.AttackDistance + (phase == "cooldown" and 26 or 2)
                    local goal = troot.Position + (-troot.CFrame.LookVector * dist) + Vector3.new(0, 1, 0)
                    severeTeleport(root, goal)
                    pcall(function() 
                        root.CFrame = CFrame.lookAt(goal, troot.Position)
                        root.AssemblyLinearVelocity = Vector3.zero 
                    end)
                end
            end
        end
        task.wait(0.05)
    end
end)

task.spawn(function()
    while true do
        if keydown and keydown(0xA3) and not Library.Visible then 
            Library.Visible = not Library.Visible
        end
        task.wait(0.1)
    end
end)

print("[Syra Autofarm] Loaded successfully!")
print("[Syra Autofarm] Features: ESP, Auto-farm, Protection")
