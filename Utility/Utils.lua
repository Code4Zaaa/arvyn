local Utils = {}

function Utils.AwaitCondition(condition, name, timeout)
    local start = tick()
    timeout = timeout or 30
    while not condition() do
        if tick() - start > timeout then
            warn("[Arvyn] Timeout waiting for: " .. (name or "Unknown"))
            return false
        end
        task.wait(0.5)
    end
    return true
end

function Utils.GetSafeModule(parent, pathString)
    local current = parent
    for part in string.gmatch(pathString, "[^%.]+") do
        if current then
            current = current:FindFirstChild(part)
        end
    end
    
    if current and current:IsA("ModuleScript") then
        local success, result = pcall(require, current)
        if success then return result end
    end
    return nil
end

function Utils.GetRemote(parent, pathString)
    local current = parent
    for _, name in ipairs(pathString:split(".")) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

function Utils.Convert_CFrame(x)
    if not x then return end
    return (typeof(x) == "Vector3" and CFrame.new(x)) or (typeof(x) == "CFrame" and x) or (typeof(x) == "Model" and x:GetPivot()) or x.CFrame
end

function Utils.GetDistance(LocalPlayer, POS_1, POS_2, NO_Y)
    if POS_1 == nil then return 0 end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return 1/0
    end
  
    if POS_2 == nil then
        POS_2 = char:FindFirstChild("HumanoidRootPart")
    end
   
    local p1 = Utils.Convert_CFrame(POS_1)
    local p2 = Utils.Convert_CFrame(POS_2)
    
    if not p1 or not p2 then return 1/0 end
    
    return (Vector3.new(p1.X, (NO_Y and 0 or p1.Y), p1.Z) 
        - Vector3.new(p2.X, (NO_Y and 0 or p2.Y), p2.Z)).Magnitude
end

local BlackScreenGui = nil
function Utils.ToggleBlackScreen(RunService, LocalPlayer, v)
    if v then
        RunService:Set3dRenderingEnabled(false)
        if not BlackScreenGui then
            local gui = Instance.new("ScreenGui")
            gui.Name = "BlackScreen"
            gui.ResetOnSpawn = false
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = -999  
            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 1, 0)
            frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            frame.BorderSizePixel = 0
            frame.ZIndex = 1
            frame.Parent = gui
            gui.Parent = LocalPlayer.PlayerGui
            BlackScreenGui = gui
        end
    else
        RunService:Set3dRenderingEnabled(true)
        if BlackScreenGui then
            BlackScreenGui:Destroy()
            BlackScreenGui = nil
        end
    end
end

function Utils.SetAutoExecute(v)
    if v and queue_on_teleport then
        local source = getgenv().ArvynSource or [[loadstring(game:HttpGet("https://api.arvynscripts.cloud/api/files/loader.lua"))()]]
        queue_on_teleport(source)
    end
end

function Utils.EnableNoClip(Maid, LocalPlayer, boolean, getState)
    if boolean then
        local function apply(char)
            if not char then return end
            
            local function handlePart(v)
                if v:IsA("BasePart") or v:IsA("Part") then
                    v.CanCollide = false
                end
            end

            for _, v in pairs(char:GetDescendants()) do
                handlePart(v)
            end

            Maid:AddTask(char.DescendantAdded:Connect(handlePart), "NoClipPartAdded")

            local head = char:WaitForChild("Head", 5)
            if head and not head:FindFirstChild("BodyVelocity") then
                local BodyVelocity = Instance.new("BodyVelocity")
                BodyVelocity.Name = "BodyVelocity"
                BodyVelocity.Parent = head
                BodyVelocity.Velocity = Vector3.new(0, 0, 0)
                BodyVelocity.P = 1500
                BodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
            end

            if not char:FindFirstChild("ARVHighlight") then
                local highlight = Instance.new("Highlight")
                highlight.Name = "ARVHighlight"
                highlight.Parent = char
                highlight.FillColor = Color3.fromRGB(0, 160, 255)
                highlight.FillTransparency = 0.5
                highlight.OutlineColor = Color3.fromRGB(0, 0, 50)
                highlight.OutlineTransparency = 0
            end
        end

        apply(LocalPlayer.Character)

        Maid:AddTask(LocalPlayer.CharacterAdded:Connect(function(char)
            task.wait(1)
            if getState and not getState() then return end
            apply(char)
        end), "NoClipRespawn")
    else
        Maid:Cleanup("NoClipPartAdded")
        Maid:Cleanup("NoClipRespawn")
        
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
            end

            local highlight = char:FindFirstChild("ARVHighlight")
            if highlight then highlight:Destroy() end

            local head = char:FindFirstChild("Head")
            if head then
                local bv = head:FindFirstChild("BodyVelocity")
                if bv then bv:Destroy() end
            end
        end
    end
end

function Utils.ToggleAntiKnockback(Maid, LocalPlayer, state, getState)
    Maid:Cleanup("AKB_ChildAdded")
    Maid:Cleanup("AKB_CharAdded")
    Maid:Cleanup("AntiKnockback")
    if not state then return end
    
    local function ApplyAntiKB(character)
        if not character then return end
        local root = character:WaitForChild("HumanoidRootPart", 10)
        if root then
            Maid:AddTask(root.ChildAdded:Connect(function(child)
                if getState and not getState() then return end
                if child:IsA("BodyVelocity") and child.MaxForce == Vector3.new(40000, 40000, 40000) then
                    child:Destroy()
                end
            end), "AKB_ChildAdded")
        end
    end

    if LocalPlayer.Character then ApplyAntiKB(LocalPlayer.Character) end
    Maid:AddTask(LocalPlayer.CharacterAdded:Connect(ApplyAntiKB), "AKB_CharAdded")
end

function Utils.ToggleAntiGameplayPaused(GuiService, state)
    pcall(function()
        GuiService:SetGameplayPausedNotificationEnabled(not state)
    end)
end

function Utils.MiniTween(TweenService, LocalPlayer, targetCFrame, activeTween, currentDest, speed)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil end
    
    local targetPos = targetCFrame.Position
    if activeTween and activeTween.PlaybackState == Enum.PlaybackState.Playing then
        if currentDest and (currentDest.Position - targetPos).Magnitude < 3 then
            return activeTween, currentDest
        end
    end

    local distance = (root.Position - targetPos).Magnitude
    speed = speed or 150
    local tweenInfo = TweenInfo.new(distance / speed, Enum.EasingStyle.Linear)
    
    if activeTween then activeTween:Cancel() end
    
    local newTween = TweenService:Create(root, tweenInfo, {CFrame = targetCFrame})
    newTween:Play()
    
    return newTween, targetCFrame
end

function Utils.GetNearestEnemy(LocalPlayer, mobsList, range, isValidTarget)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    local nearest = nil
    local minDist = range or 1/0
    
    local mobs = typeof(mobsList) == "Instance" and mobsList:GetChildren() or mobsList
    for _, npc in pairs(mobs) do
        if npc:IsA("Model") and (not isValidTarget or isValidTarget(npc)) then
            local npcPos = npc:GetPivot().Position
            local dist = (root.Position - npcPos).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = npc
            end
        end
    end
    
    return nearest
end

return Utils
