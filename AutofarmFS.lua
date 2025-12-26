    --!optimize 2
    --[[
        Features:
        1. Complete Autofarm with Auto-Block
        2. Simple ESP System (DrawingImmediate)
        3. RightControl toggle UI
    --]]

    loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge.lua"))();

    local Load = luau.load(game:HttpGet("https://raw.githubusercontent.com/DCHARLESAKAMRGREEN/Severe-Luas/main/Libraries/Pseudosynonym.lua"))
    local Library = Load()

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local Workspace = game:GetService("Workspace")
    local RunService = game:GetService("RunService")

    -- ========= AUTOFARM STATE =========
    local FarmState = {
        Enabled = false,
        SelectedTarget = nil,
        SelectedTargetLower = "",
        AutoBlock = true,  -- Renamed from SoloGuard
        BehindDist = 8,
        YOffset = 1
    }

    local CurrentTarget = nil
    local phase = "idle"
    local cooldownEnds = 0
    local phaseStart = 0
    local targetSwitchTime = 0  -- Added for delay

    -- Constants
    local PROX_RADIUS = 50000
    local TICK_DELAY = 0.05
    local EXTRA_MARGIN = 2
    local COOLDOWN_EXTRA = 24
    local ATTACK_HOLD = 1.7
    local M1_COOLDOWN = 1.8
    local HOLD_F_COOLDOWN = true

    -- ========= ENGINE HELPERS =========
    local function severeTeleport(part, targetPos)
        pcall(function()
            local address = engine.get_instance_address(part)
            if address == 0 then return end
            local buff = buffer.create(12)
            buffer.writef32(buff, 0, targetPos.X)
            buffer.writef32(buff, 4, targetPos.Y)
            buffer.writef32(buff, 8, targetPos.Z)
            memory.writebuffer(address + 0x4C, buff) 
        end)
    end

    local function getRoot(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    end

    local function isAlive(model)
        if not model or not model:IsDescendantOf(Workspace) then return false end
        
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return false end
        
        -- Enhanced death detection - check for "dead" state
        local state = model:FindFirstChild("State")
        if state and (state.Value == "Dead" or state.Value == "Despawning" or state.Value == "dead") then
            return false
        end
        
        return true
    end

    -- ========= INPUT (VK CODES) =========
    local VK_F = 0x46

    local function m1_press() pcall(function() if mouse1press then mouse1press() end end) end
    local function m1_release() pcall(function() if mouse1release then mouse1release() end end) end

    local function f_press() 
        print("[DEBUG] F key pressed")
        pcall(function() 
            if keydown then 
                keydown(VK_F) 
            elseif keypress then 
                keypress(VK_F) 
            end 
        end) 
    end

    local function f_release() 
        print("[DEBUG] F key released")
        pcall(function() 
            if keyup then 
                keyup(VK_F) 
            elseif keyrelease then 
                keyrelease(VK_F) 
            end 
        end) 
    end

    -- ========= UI CREATION =========
    local Window = Library:CreateWindow({
        Title = "Syra | Severe Fixed",
        Tag = "Syra",  -- Fixed DisplayName error
        Keybind = "RightControl",  -- Set proper keybind for the library
        AutoShow = false
    })

    local Tab = Window:AddTab({ Name = "Autofarm" })
    local Main = Tab:AddContainer({ Name = "Main", Side = "Left", AutoSize = true })

    -- Autofarm Toggle (moved to top)
    local AutofarmToggle = Main:AddToggle({
        Name = "Enable Autofarm",
        Value = false,
        Callback = function(v)
            FarmState.Enabled = v
            if not v then
                CurrentTarget = nil
                f_release()
                m1_release()
                Status:SetValue("Status: Autofarm Disabled")
            else
                if FarmState.SelectedTarget and FarmState.SelectedTarget ~= "" then
                    Status:SetValue("Status: Autofarm Enabled")
                else
                    Status:SetValue("Status: Enter enemy name first!")
                    FarmState.Enabled = false
                    AutofarmToggle:SetValue(false)
                end
            end
        end
    })

    local Status = Main:AddLabel({ Name = "Status: Ready" })

    -- Enemy Name Input
    local EnemyInput = Main:AddInput({
        Name = "Enemy Name",
        Value = "",
        Placeholder = "Enter enemy name...",
        MaxLength = 50,
        Callback = function(value)
            -- Store both original and lowercase for case-insensitive matching
            FarmState.SelectedTarget = value
            FarmState.SelectedTargetLower = string.lower(value)
            CurrentTarget = nil -- Reset target when name changes
            Status:SetValue("Status: Target = " .. (value ~= "" and value or "None"))
        end
    })

    -- Settings Container
    local Settings = Tab:AddContainer({ Name = "Settings", Side = "Right", AutoSize = true })

    Settings:AddSlider({
        Name = "Distance",
        Min = 4,
        Max = 20,
        Default = 8,
        Callback = function(v) FarmState.BehindDist = v end
    })

    local AutoBlockToggle = Settings:AddToggle({
        Name = "Auto-Block",
        Value = true,
        Callback = function(v) FarmState.AutoBlock = v end
    })

    local ESPToggle = Settings:AddToggle({
        Name = "ESP",
        Value = false,
        Callback = function(v) 
            _G.esp_enabled = v
            if v then
                print("[Syra ESP] Enabled")
            else
                print("[Syra ESP] Disabled")
            end
        end
    })

    Settings:AddButton({
        Name = "Unlock Mouse",
        Callback = function() pcall(function() engine.set_cursor_state(true) end) end
    })

    -- Menu Settings Tab
    local SettingsTab = Window:AddTab({ Name = "Settings" })
    local Menu = SettingsTab:AddContainer({ Name = "Menu", Side = "Left", AutoSize = true })
    Menu:AddMenuBind({})
    Menu:AddKeybindList({})
    Menu:AddButton({ Name = "Unload", Unsafe = true, Callback = function() Library:Unload() end })

    -- ========= MAIN AUTOFARM LOOP =========
    task.spawn(function()
        while true do
            -- SAFETY: Auto-Block check (renamed from SoloGuard)
            if FarmState.AutoBlock and #Players:GetChildren() > 1 then
                LocalPlayer:Kick("Security Trip: Player Detected")
                break
            end

            local char = LocalPlayer.Character
            local root = getRoot(char)
            
            -- Stop autofarm if UI is visible
            local shouldFarm = FarmState.Enabled and FarmState.SelectedTarget and FarmState.SelectedTarget ~= "" and not Library.Visible
            
            if root and shouldFarm then
                -- Find Target
                if not CurrentTarget or not isAlive(CurrentTarget) then
                    -- Set target switch time if target just died
                    if CurrentTarget and not isAlive(CurrentTarget) then
                        targetSwitchTime = os.clock() + 0.8 -- 0.8 second delay
                    end
                    
                    -- Wait for delay before finding new target
                    if os.clock() >= targetSwitchTime then
                        local folder = Workspace:FindFirstChild("Enemies") or Workspace:FindFirstChild("Mobs")
                        if folder then
                            for _, m in ipairs(folder:GetChildren()) do
                                if isAlive(m) and string.find(string.lower(m.Name), FarmState.SelectedTargetLower) then
                                    CurrentTarget = m
                                    break
                                end
                            end
                        end
                    end
                end

                -- Combat State Machine
                if CurrentTarget then
                    local troot = getRoot(CurrentTarget)
                    if troot then
                        local now = os.clock()
                        
                        if phase == "idle" then
                            f_release()
                            if now >= cooldownEnds then
                                phase = "attack"
                                phaseStart = now
                                m1_press()
                            end
                        elseif phase == "attack" then
                            Status:SetValue("Status: Attacking")
                            if (now - phaseStart) >= ATTACK_HOLD then
                                m1_release()
                                phase = "cooldown"
                                cooldownEnds = now + M1_COOLDOWN
                                
                                -- BLOCK START (with micro-delay for engine registration)
                                if FarmState.AutoBlock then
                                    task.delay(0.01, f_press)
                                end
                            end
                        elseif phase == "cooldown" then
                            Status:SetValue("Status: Blocking...")
                            if now >= cooldownEnds then
                                f_release() -- RELEASE BLOCK
                                phase = "attack"
                                phaseStart = now
                                m1_press()
                            end
                        end

                        -- Movement Calculation
                        local dist = FarmState.BehindDist + EXTRA_MARGIN
                        if phase == "cooldown" then dist = dist + COOLDOWN_EXTRA end
                        
                        local goalPos = troot.Position + (-troot.CFrame.LookVector * dist) + Vector3.new(0, FarmState.YOffset, 0)
                        
                        severeTeleport(root, goalPos)
                        pcall(function()
                            root.CFrame = CFrame.lookAt(goalPos, troot.Position)
                            root.AssemblyLinearVelocity = Vector3.new(0,0,0)
                        end)
                    end
                else
                    Status:SetValue("Status: Searching...")
                end
            else
                if not FarmState.Enabled then
                    Status:SetValue("Status: Disabled")
                elseif not FarmState.SelectedTarget or FarmState.SelectedTarget == "" then
                    Status:SetValue("Status: No target selected")
                elseif Library.Visible then
                    Status:SetValue("Status: Paused (UI Open)")
                else
                    Status:SetValue("Status: Waiting...")
                end
            end
            task.wait(TICK_DELAY)
        end
    end)

    -- ========= CURSOR MANAGEMENT =========
    task.spawn(function()
        while true do
            if Library.Visible then
                pcall(function() 
                    engine.set_cursor_state(true)
                    game:GetService("UserInputService").MouseIconEnabled = true
                    game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
                end)
            else
                pcall(function()
                    game:GetService("UserInputService").MouseIconEnabled = true
                end)
            end
            task.wait(0.05)
        end
    end)

    -- ========= MANUAL KEYBIND =========
    -- Use Severe's input system instead of UserInputService
    task.spawn(function()
        while true do
            -- Check for RightControl key press using Severe's input
            if keydown and keydown(0xA3) then -- 0xA3 is RightControl VK code
                Library.Visible = not Library.Visible
                if Library.Visible then
                    pcall(function() 
                        engine.set_cursor_state(true)
                        game:GetService("UserInputService").MouseIconEnabled = true
                        game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
                    end)
                else
                    pcall(function()
                        game:GetService("UserInputService").MouseIconEnabled = true
                    end)
                end
                task.wait(0.5) -- Prevent rapid toggling
            end
            task.wait(0.1)
        end
    end)

    print("[Syra Autofarm] Complete UI loaded!")
    print("[Syra Autofarm] Press RightControl to toggle menu")
    print("[Syra Autofarm] Features: Autofarm, NPC detection, Auto-Block, Toggleable ESP")

    -- ========= WORKING ESP SYSTEM =========
    local Client = Players.LocalPlayer
    local CurrentCamera = Workspace.CurrentCamera

    -- Configuration
    local ESP_TEXT_COLOR = Color3.fromRGB(125, 165, 255)
    local NPC_TEXT_COLOR = Color3.fromRGB(255, 50, 50)
    local TEXT_SIZE = 12
    local TEXT_OPACITY = 1
    local FONT_NAME = "Tamzen"
    local VERTICAL_OFFSET = 20
    local MAX_NPC_ESP_DISTANCE = 150

    -- Helper function using Luau String Interpolation
    local function getLevelText(Player: Player): string
        local leaderstats = Player:FindFirstChild("leaderstats")
        local level = if leaderstats then leaderstats:FindFirstChild("Level") else nil
        return if level then `Lv. {level.Value}` else "Lv. ???" 
    end

    -- Main Render Loop
    if RunService and RunService.Render then
        RunService.Render:Connect(function()
            -- Check if ESP is enabled via UI toggle
            if not _G.esp_enabled then return end
            
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
                        local Distance = vector.magnitude(diff)
                        
                        if Distance <= MAX_NPC_ESP_DISTANCE then
                            local ScreenPos, Visible = CurrentCamera:WorldToScreenPoint(Head.Position)
                            if Visible then
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

            -- 2. PLAYER LEVEL ESP
            for _, Player in Players:GetChildren() do
                if Player == Client then continue end
                
                local Character = Player.Character
                local Head = if Character then Character:FindFirstChild("Head") else nil
                
                if Head then
                    local ScreenPos, Visible = CurrentCamera:WorldToScreenPoint(Head.Position)
                    if Visible then
                        local displayString = getLevelText(Player)
                        
                        DrawingImmediate.OutlinedText(
                            Vector2.new(ScreenPos.X, ScreenPos.Y - VERTICAL_OFFSET), 
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
        end)
    end

    print("[Syra ESP] Working ESP system initialized!")
    print("[Syra ESP] Features: Player levels, Enemy health - Use UI toggle to enable")
