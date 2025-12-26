--!optimize 2
-- FSR AUTOFARM - Optimized Version

-- Load libraries safely
pcall(function() loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge.lua"))() end)
task.wait(0.5)

local Library = nil
if luau and luau.load then
    Library = luau.load(game:HttpGet("https://raw.githubusercontent.com/DCHARLESAKAMRGREEN/Severe-Luas/main/Libraries/Pseudosynonym.lua"))()
end

-- Services
local Players, Workspace, RunService = game:GetService("Players"), game:GetService("Workspace"), game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- State
local FarmState = {Enabled = false, Target = "", TargetLower = "", AutoBlock = true, Distance = 8, YOffset = 1}
local CurrentTarget, phase, cooldownEnds, phaseStart, targetSwitchTime = nil, "idle", 0, 0, 0

-- Whitelist for your accounts
local WhitelistedUsers = {LocalPlayer.UserId}
local WhitelistedNames = {} -- Store names for display

-- Constants
local TICK_DELAY, ATTACK_HOLD, M1_COOLDOWN, SWITCH_DELAY = 0.05, 1.7, 1.8, 0.8
local VK_F = 0x46

-- Helper functions
local function getRoot(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) end
local function isAlive(m)
    if not m or not m:IsDescendantOf(Workspace) then return false end
    local h = m:FindFirstChildOfClass("Humanoid")
    if h and h.Health <= 0 then return false end
    local s = m:FindFirstChild("State")
    return not (s and (s.Value == "Dead" or s.Value == "Despawning" or s.Value == "dead"))
end

local function severeTeleport(part, pos)
    pcall(function()
        local addr = engine.get_instance_address(part)
        if addr ~= 0 then
            local buff = buffer.create(12)
            buffer.writef32(buff, 0, pos.X)
            buffer.writef32(buff, 4, pos.Y)
            buffer.writef32(buff, 8, pos.Z)
            memory.writebuffer(addr + 0x4C, buff)
        end
    end)
end

-- Input functions
local function press(key) pcall(function() if keydown then keydown(key) elseif keypress then keypress(key) end end) end
local function release(key) pcall(function() if keyup then keyup(key) elseif keyrelease then keyrelease(key) end end) end
local function m1() press(0x01) end
local function m1r() release(0x01) end
local function f() press(VK_F) end
local function fr() release(VK_F) end

-- UI Creation
local Window, Status
if Library then
    Window = Library:CreateWindow({Title = "FSR | Optimized", Tag = "FSR", Keybind = "RightControl", AutoShow = false})
    local Tab = Window:AddTab({Name = "Main"})
    local Main = Tab:AddContainer({Name = "Controls", Side = "Left"})
    
    local AutofarmToggle = Main:AddToggle({
        Name = "Autofarm", Value = false, Callback = function(v)
            FarmState.Enabled = v
            if not v then CurrentTarget = nil; fr(); m1r(); Status:SetValue("Status: Disabled")
            else Status:SetValue(FarmState.Target ~= "" and "Enabled" or "No target!") end
        end
    })
    
    Status = Main:AddLabel({Name = "Status: Ready"})
    
    Main:AddInput({Name = "Enemy", Value = "", Placeholder = "Enemy name...", Callback = function(v)
        FarmState.Target, FarmState.TargetLower = v, string.lower(v)
        CurrentTarget = nil
        Status:SetValue("Target: " .. (v ~= "" and v or "None"))
    end})
    
    local Settings = Tab:AddContainer({Name = "Settings", Side = "Right"})
    Settings:AddSlider({Name = "Distance", Min = 4, Max = 20, Default = 8, Callback = function(v) FarmState.Distance = v end})
    Settings:AddToggle({Name = "Auto-Block", Value = true, Callback = function(v) FarmState.AutoBlock = v end})
    Settings:AddToggle({Name = "ESP", Value = false, Callback = function(v) _G.esp_enabled = v end})
    Settings:AddButton({Name = "Unlock Mouse", Callback = function() pcall(function() engine.set_cursor_state(true) end) end})
    
    -- Player Detection Whitelist Section
    local WhitelistTab = Window:AddTab({Name = "Whitelist"})
    local WhitelistContainer = WhitelistTab:AddContainer({Name = "Player-Detection Whitelist", Side = "Left"})
    
    -- Get current players for dropdown
    local function getPlayerList()
        local players = {}
        for _, player in Players:GetChildren() do
            if player ~= LocalPlayer and not table.find(WhitelistedUsers, player.UserId) then
                table.insert(players, player.Name)
            end
        end
        return players
    end
    
    local WhitelistDropdown = WhitelistContainer:AddDropdown({
        Name = "Select Player",
        Options = getPlayerList(),
        Callback = function(selectedPlayer)
            -- Add selected player to whitelist
            local player = Players:FindFirstChild(selectedPlayer)
            if player then
                table.insert(WhitelistedUsers, player.UserId)
                WhitelistedNames[player.UserId] = player.Name
                print("[Whitelist] Added: " .. player.Name .. " (ID: " .. player.UserId .. ")")
                
                -- Update dropdown to remove selected player
                WhitelistDropdown:SetOptions(getPlayerList())
                
                -- Update whitelist display
                updateWhitelistDisplay()
            end
        end
    })
    
    -- Whitelist display
    local WhitelistDisplay = WhitelistContainer:AddLabel({Name = "Whitelisted Players:"})
    
    local function updateWhitelistDisplay()
        local whitelistedText = "Whitelisted Players:\n"
        whitelistedText = whitelistedText .. "- You (ID: " .. LocalPlayer.UserId .. ")"
        for userId, name in pairs(WhitelistedNames) do
            whitelistedText = whitelistedText .. "\n- " .. name .. " (ID: " .. userId .. ")"
        end
        if #WhitelistedUsers == 1 then
            whitelistedText = whitelistedText .. "\n\nNo additional players whitelisted"
        end
        WhitelistDisplay:SetValue(whitelistedText)
    end
    
    -- Clear whitelist button
    WhitelistContainer:AddButton({
        Name = "Clear Additional Whitelist",
        Callback = function()
            WhitelistedUsers = {LocalPlayer.UserId}
            WhitelistedNames = {}
            WhitelistDropdown:SetOptions(getPlayerList())
            updateWhitelistDisplay()
            print("[Whitelist] Cleared all additional players")
        end
    })
    
    -- Initial display update
    updateWhitelistDisplay()
else
    Status = {SetValue = function(text) print("[Status]", text) end}
end

-- Main autofarm loop
task.spawn(function()
    while true do
        -- Safety check with whitelist
        if FarmState.AutoBlock then
            local nonWhitelistedCount = 0
            for _, player in Players:GetChildren() do
                if not table.find(WhitelistedUsers, player.UserId) then
                    nonWhitelistedCount = nonWhitelistedCount + 1
                end
            end
            if nonWhitelistedCount > 0 then
                LocalPlayer:Kick("Security Trip: Non-whitelisted Player Detected")
                break
            end
        end
        
        local char, root = LocalPlayer.Character, getRoot(LocalPlayer.Character)
        local shouldFarm = FarmState.Enabled and FarmState.Target ~= "" and not (Library and Library.Visible)
        
        if root and shouldFarm then
            -- Target finding with delay
            if not CurrentTarget or not isAlive(CurrentTarget) then
                if CurrentTarget and not isAlive(CurrentTarget) then targetSwitchTime = os.clock() + SWITCH_DELAY end
                if os.clock() >= targetSwitchTime then
                    local folder = Workspace:FindFirstChild("Enemies") or Workspace:FindFirstChild("Mobs")
                    if folder then
                        for _, m in folder:GetChildren() do
                            if isAlive(m) and string.find(string.lower(m.Name), FarmState.TargetLower) then
                                CurrentTarget = m; break
                            end
                        end
                    end
                end
            end
            
            -- Combat
            if CurrentTarget then
                local troot = getRoot(CurrentTarget)
                if troot then
                    local now = os.clock()
                    
                    if phase == "idle" then
                        fr()
                        if now >= cooldownEnds then phase = "attack"; phaseStart = now; m1() end
                    elseif phase == "attack" then
                        Status:SetValue("Attacking")
                        if now - phaseStart >= ATTACK_HOLD then
                            m1r(); phase = "cooldown"; cooldownEnds = now + M1_COOLDOWN
                            if FarmState.AutoBlock then task.delay(0.01, f) end
                        end
                    elseif phase == "cooldown" then
                        Status:SetValue("Blocking")
                        if now >= cooldownEnds then fr(); phase = "attack"; phaseStart = now; m1() end
                    end
                    
                    -- Movement
                    local dist = FarmState.Distance + (phase == "cooldown" and 26 or 2)
                    local goal = troot.Position + (-troot.CFrame.LookVector * dist) + Vector3.new(0, FarmState.YOffset, 0)
                    severeTeleport(root, goal)
                end
            else
                Status:SetValue("Searching...")
            end
        else
            Status:SetValue(FarmState.Enabled and (Library and Library.Visible and "Paused" or "Waiting...") or "Disabled")
        end
        
        task.wait(TICK_DELAY)
    end
end)

-- Keybind handler
task.spawn(function()
    while true do
        if keydown and keydown(0xA3) then
            if Library then
                Library.Visible = not Library.Visible
                if Library.Visible then
                    pcall(function()
                        engine.set_cursor_state(true)
                        game:GetService("UserInputService").MouseIconEnabled = true
                        game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
                    end)
                else
                    pcall(function() game:GetService("UserInputService").MouseIconEnabled = true end)
                end
            end
            task.wait(0.5)
        end
        task.wait(0.1)
    end
end)

-- ESP System
local Client, Camera = LocalPlayer, Workspace.CurrentCamera
local ESP_COLOR, NPC_COLOR = Color3.fromRGB(125, 165, 255), Color3.fromRGB(255, 50, 50)
local function getLevel(p)
    local l = p:FindFirstChild("leaderstats") and p:FindFirstChild("leaderstats"):FindFirstChild("Level")
    return l and "Lv. " .. l.Value or "Lv. ???"
end

if RunService.Render then
    RunService.Render:Connect(function()
        if not _G.esp_enabled or not Camera then return end
        
        -- Enemy health
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, e in enemies:GetChildren() do
                local head, hum = e:FindFirstChild("Head"), e:FindFirstChildOfClass("Humanoid")
                if head and hum then
                    local diff = Camera.CFrame.Position - head.Position
                    if vector.magnitude(diff) <= 150 then
                        local pos, vis = Camera:WorldToScreenPoint(head.Position)
                        if vis then
                            DrawingImmediate.OutlinedText(
                                Vector2.new(pos.X, pos.Y + 15), 12, NPC_COLOR, 1,
                                "HP: " .. math.floor(hum.Health), true, "Tamzen"
                            )
                        end
                    end
                end
            end
        end
        
        -- Player levels
        for _, p in Players:GetChildren() do
            if p == Client then continue end
            local head = p.Character and p.Character:FindFirstChild("Head")
            if head then
                local pos, vis = Camera:WorldToScreenPoint(head.Position)
                if vis then
                    DrawingImmediate.OutlinedText(
                        Vector2.new(pos.X, pos.Y - 20), 12, ESP_COLOR, 1,
                        getLevel(p), true, "Tamzen"
                    )
                end
            end
        end
    end)
end

print("FSR Autofarm - Optimized Version Loaded!")
print("Press RightControl to toggle menu")
