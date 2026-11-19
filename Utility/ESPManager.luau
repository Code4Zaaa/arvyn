local getgenv = getgenv or getfenv
local cloneref = cloneref or function(...) return ... end

local ESPManager = {
	Services = nil,
	Maid = nil,
	Signal = nil,
	Settings = {
		Enabled = true,
		UpdateInterval = 0.08,
		DefaultMaxDistance = 15000,
		DefaultFont = Enum.Font.GothamBold,
	},
	_Categories = {},
	_Entries = {},
	_Maid = nil,
	Container = nil,
	Signals = nil,
}

local function GetService(name)
	local S = ESPManager.Services or getgenv().Services
	if S and type(S.Get) == "function" then
		return S:Get(name)
	end
	return game:GetService(name)
end

local function CreateMaid()
	local M = ESPManager.Maid or getgenv().MaidClass or getgenv().Maid
	if type(M) == "table" then
		if type(M.new) == "function" then
			return M.new()
		end
		local mt = getmetatable(M)
		if mt and type(mt.new) == "function" then
			return mt.new()
		end
	end

	local tasks = {}
	return {
		_tasks = tasks,
		AddTask = function(self, task)
			table.insert(tasks, task)
			return task
		end,
		Add = function(self, task)
			table.insert(tasks, task)
			return task
		end,
		Cleanup = function(self)
			for _, t in ipairs(tasks) do
				if typeof(t) == "RBXScriptConnection" then
					pcall(function() t:Disconnect() end)
				elseif type(t) == "function" then
					pcall(t)
				elseif typeof(t) == "Instance" then
					pcall(function() t:Destroy() end)
				elseif type(t) == "table" and type(t.Destroy) == "function" then
					pcall(function() t:Destroy() end)
				end
			end
			table.clear(tasks)
		end,
		Destroy = function(self) self:Cleanup() end
	}
end

local function CreateSignal()
	local S = ESPManager.Signal or getgenv().Signal
	if type(S) == "table" and type(S.new) == "function" then
		return S.new()
	end

	local bindable = Instance.new("BindableEvent")
	return {
		Fire = function(self, ...) bindable:Fire(...) end,
		Connect = function(self, fn) return bindable.Event:Connect(fn) end,
		Destroy = function(self) bindable:Destroy() end,
	}
end

local function GetSafeGuiParent()
	local CoreGui = GetService("CoreGui")
	local Players = GetService("Players")
	local LocalPlayer = Players and Players.LocalPlayer
	local PlayerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then
			local renders = false
			pcall(function()
				renders = (CoreGui ~= nil and (h == CoreGui or h:IsDescendantOf(CoreGui)))
					or (PlayerGui ~= nil and h:IsDescendantOf(PlayerGui))
			end)
			if renders then return h end
		end
	end
	if CoreGui and pcall(function() return CoreGui.Name end) then
		return CoreGui
	end
	return PlayerGui or CoreGui
end

local function ToVector2(val, default)
	if typeof(val) == "Vector2" then return val end
	if type(val) == "string" then
		local x, y = val:match("^(%-?%d+%.?%d*)%s*,%s*(%-?%d+%.?%d*)$")
		if x and y then
			return Vector2.new(tonumber(x), tonumber(y))
		end
	end
	if type(val) == "table" then
		local x = tonumber(val[1] or val.X or val.x) or 0
		local y = tonumber(val[2] or val.Y or val.y) or 0
		return Vector2.new(x, y)
	end
	return default or Vector2.zero
end

local ESPEntry = {}
ESPEntry.__index = ESPEntry

function ESPEntry.new(manager, adornee, config)
	local self = setmetatable({}, ESPEntry)

	self.Manager = manager
	self.Adornee = adornee
	self.Config = config or {}
	self.Category = self.Config.Category or "General"
	self.Maid = CreateMaid()

	self.TargetPart = (adornee:IsA("Model") and (adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart")))
		or (adornee:IsA("BasePart") and adornee)

	self.MaxDistance = self.Config.MaxDistance or manager.Settings.DefaultMaxDistance
	self.HasBars = self.Config.Bars ~= nil
	self.HasWeapons = self.Config.Weapons ~= nil
	self.Visible = false

	self.Billboard = nil
	self.IconContainer = nil
	self.IconImage = nil
	self.InfoContainer = nil
	self.NameLabel = nil
	self.SubLabel = nil
	self.HealthBar = nil
	self.HealthFill = nil
	self.HealthText = nil
	self.EnergyBar = nil
	self.EnergyFill = nil
	self.EnergyText = nil
	self.WeaponsContainer = nil
	self.WeaponSlots = nil
	self.Highlight = nil

	self:_BuildUI()
	self:_SetupAutoCleanup()

	return self
end

local function EscapeRich(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function FormatNumber(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local HP_RED = Color3.fromRGB(255, 70, 70)
local HP_YELLOW = Color3.fromRGB(255, 200, 60)
local HP_GREEN = Color3.fromRGB(70, 235, 120)

local function HealthColor(ratio)
	if ratio >= 0.5 then
		return HP_YELLOW:Lerp(HP_GREEN, (ratio - 0.5) * 2)
	end
	return HP_RED:Lerp(HP_YELLOW, ratio * 2)
end

function ESPEntry:_UpdateWeapons()
	local cfg = self.Config
	if not (self.HasWeapons and type(cfg.Weapons) == "function" and self.WeaponSlots) then return end

	local weapons = cfg.Weapons()
	if type(weapons) == "table" and #weapons > 0 then
		self.WeaponsContainer.Visible = true
		for i, slot in ipairs(self.WeaponSlots) do
			local wData = weapons[i]
			if wData and wData.Sprite then
				local img = tostring(wData.Sprite.Image or "")
				if slot.Icon.Image ~= img then
					slot.Icon.Image = img
				end
				slot.Icon.ImageRectOffset = ToVector2(wData.Sprite.ImageRectOffset, Vector2.zero)
				slot.Icon.ImageRectSize = ToVector2(wData.Sprite.ImageRectSize, Vector2.new(150, 150))

				if wData.Equipped then
					slot.Stroke.Color = Color3.fromRGB(0, 255, 150)
					slot.Stroke.Thickness = 1.2
					slot.Stroke.Transparency = 0
					slot.Frame.BackgroundTransparency = 0.1
				else
					slot.Stroke.Color = Color3.fromRGB(65, 65, 80)
					slot.Stroke.Thickness = 0.8
					slot.Stroke.Transparency = 0.3
					slot.Frame.BackgroundTransparency = 0.3
				end
				slot.Frame.Visible = true
			else
				slot.Frame.Visible = false
			end
		end
	else
		self.WeaponsContainer.Visible = false
	end
end

function ESPEntry:_BuildCard()
	local cfg = self.Config
	local accent = (type(cfg.Color) == "function" and cfg.Color()) or cfg.Color or Color3.fromRGB(255, 255, 255)
	local font = self.Manager.Settings.DefaultFont

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESP_" .. tostring(self.Category) .. "_" .. (self.Adornee and self.Adornee.Name or "Target")
	bb.Adornee = self.TargetPart
	bb.Size = UDim2.new(0, 170, 0, 120)
	bb.StudsOffset = cfg.Offset or Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = self.MaxDistance
	bb.ClipsDescendants = false
	bb.Enabled = false
	bb.Parent = self.Manager.Container
	self.Billboard = self.Maid:AddTask(bb)

	local card = Instance.new("Frame", bb)
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 150, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0

	local list = Instance.new("UIListLayout", card)
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 3)

	local header = Instance.new("Frame", card)
	header.Name = "Header"
	header.LayoutOrder = 1
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 18)

	local avatar = Instance.new("ImageLabel", header)
	avatar.Name = "Avatar"
	avatar.Size = UDim2.new(0, 18, 0, 18)
	avatar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	avatar.BorderSizePixel = 0
	avatar.Image = ""
	avatar.ScaleType = Enum.ScaleType.Crop
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
	local avatarStroke = Instance.new("UIStroke", avatar)
	avatarStroke.Color = accent
	avatarStroke.Thickness = 1.2

	local nameLabel = Instance.new("TextLabel", header)
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 23, 0, 0)
	nameLabel.Size = UDim2.new(1, -23 - 38, 1, 0)
	nameLabel.Font = font
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.RichText = true
	nameLabel.TextStrokeTransparency = 0.35

	local distLabel = Instance.new("TextLabel", header)
	distLabel.Name = "DistLabel"
	distLabel.BackgroundTransparency = 1
	distLabel.AnchorPoint = Vector2.new(1, 0)
	distLabel.Position = UDim2.new(1, 0, 0, 0)
	distLabel.Size = UDim2.new(0, 38, 1, 0)
	distLabel.Font = font
	distLabel.TextSize = 10
	distLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	distLabel.TextXAlignment = Enum.TextXAlignment.Right
	distLabel.TextStrokeTransparency = 0.45

	local function makeBar(name, order, height, color)
		local track = Instance.new("Frame", card)
		track.Name = name
		track.LayoutOrder = order
		track.Size = UDim2.new(1, 0, 0, height)
		track.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		track.BackgroundTransparency = 0.55
		track.BorderSizePixel = 0
		track.ClipsDescendants = true
		Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

		local fill = Instance.new("Frame", track)
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
		return track, fill
	end

	local hpTrack, hpFill = makeBar("HealthBar", 2, 4, HP_GREEN)
	local enTrack, enFill = makeBar("EnergyBar", 3, 4, Color3.fromRGB(60, 170, 255))
	enTrack.Visible = false

	if self.HasWeapons then
		local weaponsFrame = Instance.new("Frame", card)
		weaponsFrame.Name = "WeaponsContainer"
		weaponsFrame.LayoutOrder = 5
		weaponsFrame.BackgroundTransparency = 1
		weaponsFrame.Size = UDim2.new(1, 0, 0, 18)
		weaponsFrame.Visible = false

		local wl = Instance.new("UIListLayout", weaponsFrame)
		wl.FillDirection = Enum.FillDirection.Horizontal
		wl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		wl.VerticalAlignment = Enum.VerticalAlignment.Center
		wl.SortOrder = Enum.SortOrder.LayoutOrder
		wl.Padding = UDim.new(0, 3)

		local weaponSlots = {}
		for i = 1, 6 do
			local slot = Instance.new("Frame", weaponsFrame)
			slot.Name = "Slot_" .. i
			slot.Size = UDim2.new(0, 18, 0, 18)
			slot.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			slot.BackgroundTransparency = 0.5
			slot.BorderSizePixel = 0
			slot.LayoutOrder = i
			slot.Visible = false
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 4)

			local slotStroke = Instance.new("UIStroke", slot)
			slotStroke.Color = Color3.fromRGB(65, 65, 80)
			slotStroke.Thickness = 0.8

			local icon = Instance.new("ImageLabel", slot)
			icon.Name = "Icon"
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.new(1, -4, 1, -4)
			icon.Position = UDim2.new(0, 2, 0, 2)
			icon.Image = ""

			table.insert(weaponSlots, { Frame = slot, Stroke = slotStroke, Icon = icon })
		end

		self.WeaponsContainer = weaponsFrame
		self.WeaponSlots = weaponSlots
	end

	if cfg.Highlight or cfg.ShowHighlight then
		if self.Adornee and (self.Adornee:IsA("Model") or self.Adornee:IsA("BasePart")) then
			local hl = Instance.new("Highlight")
			hl.Name = "ESP_Highlight_" .. tostring(self.Category)
			hl.Adornee = self.Adornee
			hl.FillColor = accent
			hl.OutlineColor = Color3.fromRGB(255, 255, 255)
			hl.FillTransparency = 0.7
			hl.OutlineTransparency = 0.2
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Enabled = false
			hl.Parent = self.Manager.Container
			self.Highlight = self.Maid:AddTask(hl)
		end
	end

	self.AvatarImage = avatar
	self.AvatarStroke = avatarStroke
	self.NameLabel = nameLabel
	self.DistLabel = distLabel
	self.HealthBar = hpTrack
	self.HealthFill = hpFill
	self.EnergyBar = enTrack
	self.EnergyFill = enFill
end

function ESPEntry:_UpdateCard(dist, accent)
	local cfg = self.Config
	local d = type(cfg.Card) == "function" and cfg.Card(dist) or {}

	local name = EscapeRich(d.Name or self.Adornee.Name)
	local text = "<b>" .. name .. "</b>"
	if d.Level then
		text = text .. string.format(" <font color='rgb(255,215,0)'>Lv.%s</font>", EscapeRich(d.Level))
	end
	if self.NameLabel.Text ~= text then self.NameLabel.Text = text end

	local distText = string.format("%dm", math.floor(dist or 0))
	if self.DistLabel.Text ~= distText then self.DistLabel.Text = distText end

	if self.AvatarStroke.Color ~= accent then
		self.AvatarStroke.Color = accent
	end

	local icon = type(cfg.Icon) == "function" and cfg.Icon() or cfg.Icon
	if type(icon) == "string" and icon ~= "" and self.AvatarImage.Image ~= icon then
		self.AvatarImage.Image = icon
	end

	local hp, maxHp = tonumber(d.Hp) or 0, math.max(tonumber(d.MaxHp) or 1, 1)
	local ratio = math.clamp(hp / maxHp, 0, 1)
	self.HealthFill.Size = UDim2.new(ratio, 0, 1, 0)
	self.HealthFill.BackgroundColor3 = HealthColor(ratio)

	if d.En ~= nil and d.MaxEn then
		local maxEn = math.max(tonumber(d.MaxEn) or 1, 1)
		self.EnergyBar.Visible = true
		self.EnergyFill.Size = UDim2.new(math.clamp(d.En / maxEn, 0, 1), 0, 1, 0)
	else
		self.EnergyBar.Visible = false
	end

	self:_UpdateWeapons()

	if self.Highlight then
		self.Highlight.FillColor = accent
	end
end

function ESPEntry:_BuildUI()
	local cfg = self.Config
	if cfg.Layout == "Card" then
		return self:_BuildCard()
	end
	local height = (self.HasBars and (self.HasWeapons and 58 or 44)) or (self.HasWeapons and 44 or 26)
	local offset = cfg.Offset or Vector3.new(0, 2.4, 0)
	local initialColor = (type(cfg.Color) == "function" and cfg.Color()) or cfg.Color or Color3.fromRGB(255, 255, 255)

	local bb = Instance.new("BillboardGui")
	bb.Name = "ESP_" .. tostring(self.Category) .. "_" .. (self.Adornee and self.Adornee.Name or "Target")
	bb.Adornee = self.TargetPart
	bb.Size = UDim2.new(0, 260, 0, height)
	bb.StudsOffset = offset
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = self.MaxDistance
	bb.ClipsDescendants = false
	bb.Enabled = false
	bb.Parent = self.Manager.Container
	self.Billboard = self.Maid:AddTask(bb)

	local iconFrame = Instance.new("Frame", bb)
	iconFrame.Name = "IconContainer"
	iconFrame.Size = UDim2.new(0, 28, 0, 28)
	iconFrame.Position = UDim2.new(0, 0, 0.5, -14)
	iconFrame.BackgroundTransparency = 1
	iconFrame.BorderSizePixel = 0
	iconFrame.Visible = false

	local tileBg = Instance.new("ImageLabel", iconFrame)
	tileBg.Name = "TileBackground"
	tileBg.BackgroundTransparency = 1
	tileBg.Size = UDim2.new(1, 0, 1, 0)
	tileBg.Position = UDim2.new(0, 0, 0, 0)
	tileBg.Image = "rbxassetid://0"
	tileBg.Visible = false

	local defaultBg = Instance.new("Frame", iconFrame)
	defaultBg.Name = "DefaultBackground"
	defaultBg.Size = UDim2.new(1, 0, 1, 0)
	defaultBg.Position = UDim2.new(0, 0, 0, 0)
	defaultBg.BackgroundTransparency = 0.25
	defaultBg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	defaultBg.BorderSizePixel = 0
	Instance.new("UICorner", defaultBg).CornerRadius = UDim.new(0, 6)

	local iconStroke = Instance.new("UIStroke", defaultBg)
	iconStroke.Color = initialColor
	iconStroke.Thickness = 1.2

	local iconImg = Instance.new("ImageLabel", iconFrame)
	iconImg.Name = "Icon"
	iconImg.BackgroundTransparency = 1
	iconImg.Size = UDim2.new(0.85, 0, 0.85, 0)
	iconImg.Position = UDim2.new(0.5, 0, 0.5, 0)
	iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImg.Image = "rbxassetid://0"
	iconImg.ImageColor3 = Color3.fromRGB(255, 255, 255)
	iconImg.ZIndex = 2

	self.IconContainer = iconFrame
	self.TileBackground = tileBg
	self.DefaultBackground = defaultBg
	self.IconImage = iconImg
	self.IconStroke = iconStroke

	local info = Instance.new("Frame", bb)
	info.Name = "InfoContainer"
	info.BackgroundTransparency = 1
	info.Position = UDim2.new(0, 0, 0, 0)
	info.Size = UDim2.new(1, 0, 1, 0)
	info.ClipsDescendants = false
	self.InfoContainer = info

	local nameLabel = Instance.new("TextLabel", info)
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = self.Manager.Settings.DefaultFont
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = initialColor
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.RichText = true
	nameLabel.Text = ""

	if self.HasBars then
		nameLabel.Size = UDim2.new(1, 0, 0, 16)
		nameLabel.Position = UDim2.new(0, 0, 0, 1)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center

		local barsFrame = Instance.new("Frame", info)
		barsFrame.Name = "BarsContainer"
		barsFrame.BackgroundTransparency = 1
		barsFrame.Size = UDim2.new(0, 160, 0, 13)
		barsFrame.Position = UDim2.new(0, 0, 0, 19)

		local hp = Instance.new("Frame", barsFrame)
		hp.Name = "HealthBar"
		hp.Size = UDim2.new(0, 156, 0, 12)
		hp.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		hp.BackgroundTransparency = 0.3
		hp.BorderSizePixel = 0
		hp.ClipsDescendants = true
		Instance.new("UICorner", hp).CornerRadius = UDim.new(0, 3)

		local hpStroke = Instance.new("UIStroke", hp)
		hpStroke.Color = Color3.fromRGB(50, 255, 100)
		hpStroke.Thickness = 0.8
		hpStroke.Transparency = 0.4

		local hpFill = Instance.new("Frame", hp)
		hpFill.Name = "Fill"
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		hpFill.BackgroundColor3 = Color3.fromRGB(50, 255, 100)
		hpFill.BackgroundTransparency = 0.35
		hpFill.BorderSizePixel = 0
		Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

		local hpText = Instance.new("TextLabel", hp)
		hpText.Name = "HPText"
		hpText.BackgroundTransparency = 1
		hpText.Size = UDim2.new(1, 0, 1, 0)
		hpText.Font = self.Manager.Settings.DefaultFont
		hpText.TextSize = 9
		hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
		hpText.TextStrokeTransparency = 0.2
		hpText.RichText = true

		self.HealthBar = hp
		self.HealthFill = hpFill
		self.HealthText = hpText
		self.HealthStroke = hpStroke

		local en = Instance.new("Frame", barsFrame)
		en.Name = "EnergyBar"
		en.Size = UDim2.new(0, 76, 0, 12)
		en.Position = UDim2.new(0, 80, 0, 0)
		en.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		en.BackgroundTransparency = 0.3
		en.BorderSizePixel = 0
		en.ClipsDescendants = true
		en.Visible = false
		Instance.new("UICorner", en).CornerRadius = UDim.new(0, 3)

		local enStroke = Instance.new("UIStroke", en)
		enStroke.Color = Color3.fromRGB(70, 180, 255)
		enStroke.Thickness = 0.8
		enStroke.Transparency = 0.4

		local enFill = Instance.new("Frame", en)
		enFill.Name = "Fill"
		enFill.Size = UDim2.new(1, 0, 1, 0)
		enFill.BackgroundColor3 = Color3.fromRGB(70, 180, 255)
		enFill.BackgroundTransparency = 0.35
		enFill.BorderSizePixel = 0
		Instance.new("UICorner", enFill).CornerRadius = UDim.new(0, 3)

		local enText = Instance.new("TextLabel", en)
		enText.Name = "ENText"
		enText.BackgroundTransparency = 1
		enText.Size = UDim2.new(1, 0, 1, 0)
		enText.Font = self.Manager.Settings.DefaultFont
		enText.TextSize = 9
		enText.TextColor3 = Color3.fromRGB(255, 255, 255)
		enText.TextStrokeTransparency = 0.2
		enText.RichText = true

		self.EnergyBar = en
		self.EnergyFill = enFill
		self.EnergyText = enText
		self.EnergyStroke = enStroke
	else
		nameLabel.Size = UDim2.new(1, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	end
	self.NameLabel = nameLabel

	if self.HasWeapons then
		local weaponsFrame = Instance.new("Frame", info)
		weaponsFrame.Name = "WeaponsContainer"
		weaponsFrame.BackgroundTransparency = 1
		weaponsFrame.Size = UDim2.new(0, 160, 0, 18)
		weaponsFrame.Position = UDim2.new(0, 0, 0, self.HasBars and 34 or 18)
		weaponsFrame.Visible = false

		local list = Instance.new("UIListLayout", weaponsFrame)
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, 3)
		list.SortOrder = Enum.SortOrder.LayoutOrder

		local weaponSlots = {}
		for i = 1, 6 do
			local slot = Instance.new("Frame", weaponsFrame)
			slot.Name = "Slot_" .. i
			slot.Size = UDim2.new(0, 18, 0, 18)
			slot.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
			slot.BackgroundTransparency = 0.25
			slot.BorderSizePixel = 0
			slot.LayoutOrder = i
			slot.Visible = false
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 4)

			local stroke = Instance.new("UIStroke", slot)
			stroke.Color = Color3.fromRGB(60, 60, 75)
			stroke.Thickness = 0.9

			local icon = Instance.new("ImageLabel", slot)
			icon.Name = "Icon"
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.new(1, -2, 1, -2)
			icon.Position = UDim2.new(0, 1, 0, 1)
			icon.Image = "rbxassetid://0"
			icon.ImageColor3 = Color3.fromRGB(255, 255, 255)

			table.insert(weaponSlots, {
				Frame = slot,
				Stroke = stroke,
				Icon = icon,
			})
		end

		self.WeaponsContainer = weaponsFrame
		self.WeaponSlots = weaponSlots
	end

	if cfg.Highlight or cfg.ShowHighlight then
		local canHighlight = self.Adornee and (self.Adornee:IsA("Model") or self.Adornee:IsA("BasePart"))
		if canHighlight then
			local hl = Instance.new("Highlight")
			hl.Name = "ESP_Highlight_" .. tostring(self.Category)
			hl.Adornee = self.Adornee
			hl.FillColor = initialColor
			hl.OutlineColor = Color3.fromRGB(255, 255, 255)
			hl.FillTransparency = 0.65
			hl.OutlineTransparency = 0.1
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Enabled = false
			hl.Parent = self.Manager.Container
			self.Highlight = self.Maid:AddTask(hl)
		end
	end
end

function ESPEntry:_SetupAutoCleanup()
	if not self.Adornee then return end

	if self.Adornee:IsA("Instance") then
		self.Maid:AddTask(self.Adornee.Destroying:Connect(function()
			self:Destroy()
		end))
		self.Maid:AddTask(self.Adornee.AncestryChanged:Connect(function(_, parent)
			if not parent or not self.Adornee:IsDescendantOf(workspace) then
				self:Destroy()
			end
		end))
	end
end

function ESPEntry:SetVisible(state)
	if self.Visible == state then return end
	self.Visible = state
	if self.Billboard then self.Billboard.Enabled = state end
	if self.Highlight then self.Highlight.Enabled = state end
end

function ESPEntry:Update(cameraPos, dist)
	if not (self.Adornee and self.Adornee.Parent and self.TargetPart) or not self.Adornee:IsDescendantOf(workspace) then
		self:Destroy()
		return
	end

	if not dist then
		local cam = workspace.CurrentCamera
		if cam and self.TargetPart then
			dist = (cam.CFrame.Position - self.TargetPart.Position).Magnitude
		else
			dist = 0
		end
	end

	local cfg = self.Config
	local category = self.Manager._Categories[self.Category]
	if category and category.Enabled == false then
		self:SetVisible(false)
		return
	end

	local accentColor = (type(cfg.Color) == "function" and cfg.Color())
		or cfg.Color
		or (category and category.Color)
		or Color3.fromRGB(255, 255, 255)

	if cfg.Layout == "Card" then
		self:_UpdateCard(dist, accentColor)
		self:SetVisible(true)
		return
	end

	local rawText = ""
	if type(cfg.Text) == "function" then
		rawText = tostring(cfg.Text(dist) or "")
	elseif cfg.Text then
		rawText = tostring(cfg.Text)
	else
		rawText = string.format("<b>%s</b> <font color='rgb(200,200,200)'>[%dm]</font>", self.Adornee.Name, math.floor(dist))
	end

	if self.NameLabel.Text ~= rawText then
		self.NameLabel.Text = rawText
	end
	if self.NameLabel.TextColor3 ~= accentColor then
		self.NameLabel.TextColor3 = accentColor
	end

	local iconAsset = ""
	local iconOffset = Vector2.zero
	local iconSize = Vector2.zero

	if type(cfg.Icon) == "function" then
		local res = cfg.Icon()
		if type(res) == "table" then
			iconAsset = tostring(res.Image or "")
			iconOffset = res.ImageRectOffset or res.RectOffset or Vector2.zero
			iconSize = res.ImageRectSize or res.RectSize or Vector2.zero
		elseif res then
			iconAsset = tostring(res)
		end
	elseif type(cfg.Icon) == "table" then
		iconAsset = tostring(cfg.Icon.Image or "")
		iconOffset = cfg.Icon.ImageRectOffset or cfg.Icon.RectOffset or Vector2.zero
		iconSize = cfg.Icon.ImageRectSize or cfg.Icon.RectSize or Vector2.zero
	elseif cfg.Icon then
		iconAsset = tostring(cfg.Icon)
		iconOffset = cfg.IconRectOffset or Vector2.zero
		iconSize = cfg.IconRectSize or Vector2.zero
	end

	if iconAsset ~= "" and iconAsset ~= "rbxassetid://0" then
		if self.IconImage.Image ~= iconAsset then
			self.IconImage.Image = iconAsset
		end
		self.IconImage.ImageRectOffset = ToVector2(iconOffset, Vector2.zero)
		self.IconImage.ImageRectSize = ToVector2(iconSize, Vector2.new(150, 150))

		if cfg.Tile then
			self.TileBackground.Image = tostring(cfg.Tile.Image or "")
			self.TileBackground.ImageRectOffset = ToVector2(cfg.Tile.ImageRectOffset, Vector2.zero)
			self.TileBackground.ImageRectSize = ToVector2(cfg.Tile.ImageRectSize, Vector2.new(165, 165))
			self.TileBackground.Visible = true
			if self.DefaultBackground then self.DefaultBackground.Visible = false end
			self.IconImage.Size = UDim2.new(0.82, 0, 0.82, 0)
			self.IconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
			self.IconImage.AnchorPoint = Vector2.new(0.5, 0.5)
		else
			self.TileBackground.Visible = false
			if self.DefaultBackground then
				self.DefaultBackground.Visible = true
				self.IconStroke.Color = accentColor
			end
			self.IconImage.Size = UDim2.new(1, -2, 1, -2)
			self.IconImage.Position = UDim2.new(0, 1, 0, 1)
			self.IconImage.AnchorPoint = Vector2.new(0, 0)
		end

		self.IconContainer.Visible = true
		self.InfoContainer.Position = UDim2.new(0, 34, 0, 0)
		self.InfoContainer.Size = UDim2.new(1, -34, 1, 0)
		self.NameLabel.TextXAlignment = Enum.TextXAlignment.Left
	else
		self.IconContainer.Visible = false
		self.InfoContainer.Position = UDim2.new(0, 0, 0, 0)
		self.InfoContainer.Size = UDim2.new(1, 0, 1, 0)
		if not self.HasBars then
			self.NameLabel.TextXAlignment = Enum.TextXAlignment.Center
		end
	end

	if self.HasBars and type(cfg.Bars) == "function" then
		local hpRatio, hpColor, hpText, enRatio, enColor, enText = cfg.Bars()
		local hasEnergy = (enRatio ~= nil and enRatio ~= false and enRatio > 0) or (enText ~= nil and enText ~= "")

		if hpRatio and self.HealthBar then
			self.HealthBar.Visible = true
			if hasEnergy then
				self.HealthBar.Size = UDim2.new(0, 76, 0, 12)
			else
				self.HealthBar.Size = UDim2.new(0, 156, 0, 12)
			end

			self.HealthFill.Size = UDim2.new(math.clamp(hpRatio, 0, 1), 0, 1, 0)
			if hpColor then
				self.HealthFill.BackgroundColor3 = hpColor
				self.HealthStroke.Color = hpColor
			end
			self.HealthText.Text = hpText or ""
		elseif self.HealthBar then
			self.HealthBar.Visible = false
		end

		if hasEnergy and self.EnergyBar then
			self.EnergyBar.Visible = true
			self.EnergyBar.Size = UDim2.new(0, 76, 0, 12)
			self.EnergyBar.Position = UDim2.new(0, 80, 0, 0)
			self.EnergyFill.Size = UDim2.new(math.clamp(enRatio or 0, 0, 1), 0, 1, 0)
			if enColor then
				self.EnergyFill.BackgroundColor3 = enColor
				self.EnergyStroke.Color = enColor
			end
			self.EnergyText.Text = enText or ""
		elseif self.EnergyBar then
			self.EnergyBar.Visible = false
		end
	end

	self:_UpdateWeapons()

	if self.Highlight then
		self.Highlight.FillColor = accentColor
	end

	self:SetVisible(true)
end

function ESPEntry:Destroy()
	self:SetVisible(false)
	self.Manager._Entries[self.Adornee] = nil
	self.Maid:Destroy()
end

function ESPManager:Init(options)
	if self._Destroyed or self.Settings.Enabled == false then return self end
	if self.Container and self.Container.Parent then return self end

	if options then
		for k, v in pairs(options) do
			self.Settings[k] = v
		end
	end

	self._Maid = self._Maid or CreateMaid()

	if not self.Signals then
		self.Signals = {
			OnEntryAdded = CreateSignal(),
			OnEntryRemoved = CreateSignal(),
			OnCategoryToggled = CreateSignal(),
		}
	end

	local container = Instance.new("Folder")
	container.Name = "ESPManager_Storage"
	container.Parent = GetSafeGuiParent()
	self.Container = self._Maid:AddTask(container)

	local RunService = GetService("RunService")
	local Workspace = GetService("Workspace")
	local lastUpdate = 0
	self._Maid:AddTask(RunService.Heartbeat:Connect(function()
		if not self.Settings.Enabled or self._Destroyed then return end

		local now = os.clock()
		if now - lastUpdate < self.Settings.UpdateInterval then return end
		lastUpdate = now

		local cam = Workspace.CurrentCamera
		if not cam then return end
		local camPos = cam.CFrame.Position

		for adornee, entry in pairs(self._Entries) do
			if not (adornee and adornee.Parent and entry.TargetPart) then
				entry:Destroy()
			else
				local targetPos = entry.TargetPart.Position
				local dist = (camPos - targetPos).Magnitude
				if dist > entry.MaxDistance then
					entry:SetVisible(false)
				else
					entry:Update(camPos, dist)
				end
			end
		end
	end))

	return self
end

function ESPManager:RegisterCategory(name, options)
	options = options or {}
	self._Categories[name] = {
		Enabled = options.Enabled ~= false,
		Color = options.Color or Color3.fromRGB(255, 255, 255),
		MaxDistance = options.MaxDistance or self.Settings.DefaultMaxDistance,
		ShowHighlight = options.ShowHighlight or false,
	}
	return self._Categories[name]
end

function ESPManager:ToggleCategory(name, state)
	if not self._Categories[name] then
		self:RegisterCategory(name, { Enabled = state })
	else
		self._Categories[name].Enabled = state
	end

	for _, entry in pairs(self._Entries) do
		if entry.Category == name and not state then
			entry:SetVisible(false)
		end
	end

	self.Signals.OnCategoryToggled:Fire(name, state)
end

function ESPManager:IsCategoryEnabled(name)
	local cat = self._Categories[name]
	return cat and cat.Enabled or false
end

function ESPManager:SetCategoryColor(name, color)
	if not self._Categories[name] then
		self:RegisterCategory(name, { Color = color })
	else
		self._Categories[name].Color = color
	end
end

function ESPManager:Add(adornee, config)
	if self._Destroyed or self.Settings.Enabled == false then return nil end
	if not adornee then return nil end
	self:Init()

	if self._Entries[adornee] then
		self._Entries[adornee]:Destroy()
	end

	config = config or {}
	local category = config.Category or "General"
	if not self._Categories[category] then
		self:RegisterCategory(category, { Enabled = true, Color = config.Color })
	end

	local entry = ESPEntry.new(self, adornee, config)
	self._Entries[adornee] = entry

	if self.Signals and self.Signals.OnEntryAdded then
		self.Signals.OnEntryAdded:Fire(adornee, entry)
	end
	return entry
end

function ESPManager:Get(adornee)
	return self._Entries[adornee]
end

function ESPManager:Remove(adornee)
	local entry = self._Entries[adornee]
	if entry then
		entry:Destroy()
		if self.Signals and self.Signals.OnEntryRemoved then
			self.Signals.OnEntryRemoved:Fire(adornee)
		end
	end
end

function ESPManager:ClearCategory(category)
	for adornee, entry in pairs(self._Entries) do
		if not category or entry.Category == category then
			entry:Destroy()
		end
	end
end

function ESPManager:ClearAll()
	for adornee, entry in pairs(self._Entries) do
		entry:Destroy()
	end
	table.clear(self._Entries)
end

function ESPManager:Destroy()
	self.Settings.Enabled = false
	self._Destroyed = true
	self:ClearAll()

	if self.Container then
		pcall(function() self.Container:Destroy() end)
		self.Container = nil
	end
	if self._Maid then
		pcall(function() self._Maid:Destroy() end)
		self._Maid = nil
	end
	if self.Signals then
		for _, sig in pairs(self.Signals) do
			pcall(function() sig:Destroy() end)
		end
		self.Signals = nil
	end
	table.clear(self._Entries)
	table.clear(self._Categories)

	pcall(function()
		local function scan(parent)
			if not parent then return end
			for _, c in ipairs(parent:GetChildren()) do
				if c.Name == "ESPManager_Storage" then
					pcall(function() c:Destroy() end)
				end
			end
		end
		if gethui then scan(gethui()) end
		scan(GetService("CoreGui"))
		local lp = GetService("Players") and GetService("Players").LocalPlayer
		if lp then scan(lp:FindFirstChild("PlayerGui")) end
	end)
end

local FruitMeshMap = {
	["15057683975"] = { name = "Spin Fruit", rarity = 0, realName = "Spin-Spin" },
	["15060012861"] = { name = "Rocket Fruit", rarity = 0, realName = "Rocket-Rocket" },
	["15104782377"] = { name = "Blade Fruit", rarity = 0, realName = "Blade-Blade" },
	["15105281957"] = { name = "Spring Fruit", rarity = 0, realName = "Spring-Spring" },
	["15107569005"] = { name = "Bomb Fruit", rarity = 0, realName = "Bomb-Bomb" },
	["15116740364"] = { name = "Bomb Fruit", rarity = 0, realName = "Bomb-Bomb" },
	["15116696973"] = { name = "Smoke Fruit", rarity = 0, realName = "Smoke-Smoke" },
	["15107005807"] = { name = "Spike Fruit", rarity = 0, realName = "Spike-Spike" },

	["112461342251051"] = { name = "Flame Fruit", rarity = 1, realName = "Flame-Flame" },
	["15111584216"] = { name = "Flame Fruit", rarity = 1, realName = "Flame-Flame" },
	["15100433167"] = { name = "Ice Fruit", rarity = 1, realName = "Ice-Ice" },
	["15111517558"] = { name = "Sand Fruit", rarity = 1, realName = "Sand-Sand" },
	["15111517529"] = { name = "Sand Fruit", rarity = 1, realName = "Sand-Sand" },
	["15111553409"] = { name = "Dark Fruit", rarity = 1, realName = "Dark-Dark" },
	["97865119140018"] = { name = "Eagle Fruit", rarity = 1, realName = "Eagle-Eagle" },
	["15112469964"] = { name = "Falcon Fruit", rarity = 1, realName = "Falcon-Falcon" },
	["15112600534"] = { name = "Diamond Fruit", rarity = 1, realName = "Diamond-Diamond" },

	["15100283508"] = { name = "Light Fruit", rarity = 2, realName = "Light-Light" },
	["15100283484"] = { name = "Light Fruit", rarity = 2, realName = "Light-Light" },
	["15104817760"] = { name = "Rubber Fruit", rarity = 2, realName = "Rubber-Rubber" },
	["15112333210"] = { name = "Ghost Fruit", rarity = 2, realName = "Ghost-Ghost" },
	["15112333093"] = { name = "Ghost Fruit", rarity = 2, realName = "Ghost-Ghost" },
	["15105350415"] = { name = "Magma Fruit", rarity = 2, realName = "Magma-Magma" },
	["15100485671"] = { name = "Barrier Fruit", rarity = 2, realName = "Barrier-Barrier" },

	["15057718441"] = { name = "Quake Fruit", rarity = 3, realName = "Quake-Quake" },
	["85809853722407"] = { name = "Creation Fruit", rarity = 3, realName = "Creation-Creation" },
	["15116730102"] = { name = "Love Fruit", rarity = 3, realName = "Love-Love" },
	["15100313696"] = { name = "Buddha Fruit", rarity = 3, realName = "Buddha-Buddha" },
	["15116747420"] = { name = "Rumble Fruit", rarity = 3, realName = "Lightning-Lightning" },
	["15116967784"] = { name = "Spider Fruit", rarity = 3, realName = "Spider-Spider" },
	["14661873358"] = { name = "Sound Fruit", rarity = 3, realName = "Sound-Sound" },
	["15100246632"] = { name = "Phoenix Fruit", rarity = 3, realName = "Phoenix-Phoenix" },
	["15116721173"] = { name = "Pain Fruit", rarity = 3, realName = "Pain-Pain" },
	["15100384816"] = { name = "Blizzard Fruit", rarity = 3, realName = "Blizzard-Blizzard" },

	["15100299740"] = { name = "Gravity Fruit", rarity = 4, realName = "Gravity-Gravity" },
	["14661837634"] = { name = "Mammoth Fruit", rarity = 4, realName = "Mammoth-Mammoth" },
	["15708895165"] = { name = "T-Rex Fruit", rarity = 4, realName = "T-Rex-T-Rex" },
	["15100273645"] = { name = "Dough Fruit", rarity = 4, realName = "Dough-Dough" },
	["15112263502"] = { name = "Shadow Fruit", rarity = 4, realName = "Shadow-Shadow" },
	["10395893751"] = { name = "Venom Fruit", rarity = 4, realName = "Venom-Venom" },
	["15100184583"] = { name = "Control Fruit", rarity = 4, realName = "Control-Control" },
	["86024571204851"] = { name = "Gas Fruit", rarity = 4, realName = "Gas-Gas" },
	["11908375285"] = { name = "Spirit Fruit", rarity = 4, realName = "Spirit-Spirit" },
	["101378450824208"] = { name = "Yeti Fruit", rarity = 4, realName = "Yeti-Yeti" },
	["15106768588"] = { name = "Leopard Fruit", rarity = 4, realName = "Leopard-Leopard" },
	["15482881956"] = { name = "Kitsune Fruit", rarity = 4, realName = "Kitsune-Kitsune" },
	["19001642259"] = { name = "Dragon (East) Fruit", rarity = 4, realName = "Dragon (East)-Dragon (East)" },
	["18955022385"] = { name = "Dragon (West) Fruit", rarity = 4, realName = "Dragon (West)-Dragon (West)" },
}

local FruitRarityMeta = {
	[0] = { Rarity = 0, Color = Color3.fromRGB(179, 179, 179), Tag = "Common", Hex = "#b3b3b3" },
	[1] = { Rarity = 1, Color = Color3.fromRGB(92, 140, 211),  Tag = "Uncommon", Hex = "#5c8cd3" },
	[2] = { Rarity = 2, Color = Color3.fromRGB(140, 82, 255),  Tag = "Rare", Hex = "#8c52ff" },
	[3] = { Rarity = 3, Color = Color3.fromRGB(213, 43, 228),  Tag = "Legendary", Hex = "#d52be4" },
	[4] = { Rarity = 4, Color = Color3.fromRGB(238, 47, 50),   Tag = "Mythical", Hex = "#ee2f32" },
}

local InventoryRarityTiles = {
	[0] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(1, 168), ImageRectSize = Vector2.new(165, 165) },
	[1] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(669, 1), ImageRectSize = Vector2.new(165, 165) },
	[2] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(335, 335), ImageRectSize = Vector2.new(165, 165) },
	[3] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(1, 335), ImageRectSize = Vector2.new(165, 165) },
	[4] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(669, 168), ImageRectSize = Vector2.new(165, 165) },
	["Clawed"] = { Image = "rbxassetid://125725522103833", ImageRectOffset = Vector2.new(335, 1), ImageRectSize = Vector2.new(165, 165) },
}

local FruitCache = {}
local FruitCacheBuilt = false

local function BuildFruitCache()
	if FruitCacheBuilt then return end
	local ok, itemConfig = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig", 5))
	end)
	if not (ok and itemConfig and type(itemConfig.dumpItems) == "function") then return end

	for _, item in pairs(itemConfig.dumpItems()) do
		if type(item) == "table" and item.Index and item.Index.IdType == "PhysicalMoveset" and item.Display and item.Display.Sprite then
			local displayName = item.Display.Name or ""
			local storageKey = item.Index.StorageKey or displayName
			local rVal = item.Quality and item.Quality.RarityValue or 0
			local meta = FruitRarityMeta[rVal] or FruitRarityMeta[0]

			local offV2 = ToVector2(item.Display.Sprite.ImageRectOffset, Vector2.zero)
			local szV2 = ToVector2(item.Display.Sprite.ImageRectSize, Vector2.new(150, 150))

			local fruitFullName = displayName ~= "" and (displayName .. " Fruit") or (storageKey .. " Fruit")
			local data = {
				Name = fruitFullName,
				ShortName = displayName,
				StorageKey = storageKey,
				Rarity = rVal,
				Meta = meta,
				Sprite = {
					Image = item.Display.Sprite.Image,
					ImageRectOffset = offV2,
					ImageRectSize = szV2,
				}
			}

			local function registerKey(k)
				if not k or k == "" then return end
				local lk = k:lower()
				FruitCache[lk] = data
				local stripped = lk:gsub("%-.*", ""):gsub("%s*%(.*%)", ""):gsub("%s*fruit", ""):gsub("%s+", "")
				if stripped ~= "" then
					FruitCache[stripped] = data
				end
			end

			registerKey(storageKey)
			registerKey(displayName)
			registerKey(fruitFullName)
		end
	end
	FruitCacheBuilt = true
end

local function GetFruitSprite(realName)
	if not realName then return nil end
	BuildFruitCache()

	local lk = realName:lower()
	if FruitCache[lk] and FruitCache[lk].Sprite then
		return FruitCache[lk].Sprite
	end

	local clean = lk:gsub("%-.*", ""):gsub("%s*fruit", ""):gsub("%s+", "")
	if FruitCache[clean] and FruitCache[clean].Sprite then
		return FruitCache[clean].Sprite
	end

	for k, v in pairs(FruitCache) do
		if lk:find(k, 1, true) or k:find(clean, 1, true) then
			if v.Sprite then return v.Sprite end
		end
	end

	return nil
end

local function ResolveFruitInfo(fruitInstance)
	BuildFruitCache()
	if not fruitInstance then return "Devil Fruit", FruitRarityMeta[0], nil, nil end

	for _, descendant in ipairs(fruitInstance:GetDescendants()) do
		local meshId = ""
		if descendant:IsA("MeshPart") or descendant:IsA("SpecialMesh") then
			meshId = descendant.MeshId
		end
		if meshId ~= "" then
			local idOnly = meshId:match("%d+")
			if idOnly and FruitMeshMap[idOnly] then
				local entry = FruitMeshMap[idOnly]
				local realKey = entry.realName:lower()
				local cached = FruitCache[realKey] or FruitCache[entry.name:lower()]
				if cached then
					return cached.Name, cached.Meta, cached.StorageKey, cached.Sprite
				end
				local meta = FruitRarityMeta[entry.rarity] or FruitRarityMeta[0]
				return entry.name, meta, entry.realName, GetFruitSprite(entry.realName)
			end
		end
	end

	local rawName = fruitInstance.Name
	if rawName and rawName ~= "Fruit " and rawName ~= "Fruit" and rawName ~= "Devil Fruit" and rawName ~= "" then
		local clean = rawName:lower():gsub("%s*%(tool%)", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		local cached = FruitCache[clean]
		if not cached then
			local stripped = clean:gsub("%s*fruit", ""):gsub("%-.*", ""):gsub("%s*%(.*%)", ""):gsub("%s+", "")
			cached = FruitCache[stripped]
		end
		if not cached then
			for k, v in pairs(FruitCache) do
				if clean:find(k, 1, true) or k:find(clean, 1, true) then
					cached = v
					break
				end
			end
		end
		if cached then
			return cached.Name, cached.Meta, cached.StorageKey, cached.Sprite
		end
	end

	local fruitFolder = fruitInstance:FindFirstChild("Fruit")
	if fruitFolder then
		if fruitFolder:FindFirstChild("Retopo_Cube.001") then
			local c = FruitCache["spirit-spirit"]
			if c then return c.Name, c.Meta, c.StorageKey, c.Sprite end
			return "Spirit Fruit", FruitRarityMeta[4], "Spirit-Spirit", GetFruitSprite("Spirit-Spirit")
		elseif fruitFolder:FindFirstChild("Gravity cube.026") then
			if fruitFolder:FindFirstChild("Gravity cube.001") then
				local c = FruitCache["blizzard-blizzard"]
				if c then return c.Name, c.Meta, c.StorageKey, c.Sprite end
				return "Blizzard Fruit", FruitRarityMeta[3], "Blizzard-Blizzard", GetFruitSprite("Blizzard-Blizzard")
			else
				local c = FruitCache["portal-portal"]
				if c then return c.Name, c.Meta, c.StorageKey, c.Sprite end
				return "Portal Fruit", FruitRarityMeta[3], "Portal-Portal", GetFruitSprite("Portal-Portal")
			end
		elseif fruitFolder:FindFirstChild("Cube.011") then
			local c = FruitCache["rubber-rubber"]
			if c then return c.Name, c.Meta, c.StorageKey, c.Sprite end
			return "Rubber Fruit", FruitRarityMeta[2], "Rubber-Rubber", GetFruitSprite("Rubber-Rubber")
		end
	end

	return "Devil Fruit", FruitRarityMeta[0], nil, nil
end

local WeaponCache = {}
local WeaponCacheBuilt = false

local function BuildWeaponCache()
	if WeaponCacheBuilt then return end
	local ok, itemConfig = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig", 5))
	end)
	if not (ok and itemConfig and type(itemConfig.dumpItems) == "function") then return end

	for _, item in pairs(itemConfig.dumpItems()) do
		if type(item) == "table" and item.Display and item.Display.Sprite then
			local cat = item.Display.Category
			local idType = item.Index and item.Index.IdType

			local isAllowed = (cat == "Sword" or cat == "Gun" or cat == "Fighting Style")
				or (cat == "Blox Fruit" and idType == "Moveset")

			if isAllowed then
				local offV2 = ToVector2(item.Display.Sprite.ImageRectOffset, Vector2.zero)
				local szV2 = ToVector2(item.Display.Sprite.ImageRectSize, Vector2.new(150, 150))

				local data = {
					Name = item.Display.Name or (item.Index and item.Index.StorageKey),
					Category = cat,
					Sprite = {
						Image = item.Display.Sprite.Image,
						ImageRectOffset = offV2,
						ImageRectSize = szV2,
					}
				}

				local function addKey(k)
					if not k or k == "" then return end
					local lk = k:lower()
					WeaponCache[lk] = data
				end

				if item.Index and item.Index.StorageKey then
					addKey(item.Index.StorageKey)
				end
				if item.Display.Name then
					addKey(item.Display.Name)
					if cat == "Blox Fruit" then
						addKey(item.Display.Name .. " Fruit")
						addKey(item.Display.Name .. "-Fruit")
					end
				end

				if cat == "Blox Fruit" then
					local sKey = item.Index and item.Index.StorageKey and item.Index.StorageKey:lower()
					local dName = item.Display.Name and item.Display.Name:lower()
					if (sKey and sKey:find("gas")) or (dName and (dName:find("gas") or dName:find("hellfire"))) then
						addKey("hellfire (gas)-hellfire (gas)")
						addKey("hellfire (gas)")
						addKey("hellfire")
						addKey("gas")
						addKey("gas-gas")
					end
				end
			end
		end
	end
	WeaponCacheBuilt = true
end

local function IsPhysicalFruitTool(tool)
	if not (tool and tool:IsA("Tool")) then return false end
	if tool:FindFirstChild("EatRemote") or tool:FindFirstChild("ClientEatScript") or tool:FindFirstChild("Fruit") then
		return true
	end
	if tool:GetAttribute("OriginalName") ~= nil then
		return true
	end
	local itemId = tool:GetAttribute("ItemId")
	if itemId and itemId > 1300 then
		return true
	end
	if tool:FindFirstChild("Handle") and not tool:FindFirstChild("Level") and not tool:FindFirstChild("HiddenAbilities") and not tool:FindFirstChild("LeftClickRemote") then
		local lower = tool.Name:lower()
		if lower:find("fruit") or lower:find("-") then
			return true
		end
	end
	return false
end

local function GetPlayerWeapons(player)
	if not player then return {} end
	BuildWeaponCache()

	local weapons = {}
	local seen = {}

	local function addTool(tool, equipped)
		if not (tool and tool:IsA("Tool")) then return end
		local rawName = tool.Name
		local lower = rawName:lower()

		if IsPhysicalFruitTool(tool) then
			BuildFruitCache()
			local orig = tool:GetAttribute("OriginalName")
			local info = (orig and FruitCache[orig:lower()]) or FruitCache[lower]
			if not info then
				local clean = lower:gsub("%s*%(tool%)", ""):gsub("%s*fruit", "")
				info = FruitCache[clean]
			end
			if not info then
				for k, v in pairs(FruitCache) do
					if lower:find(k, 1, true) or k:find(lower, 1, true) then
						info = v
						break
					end
				end
			end
			if info and info.Sprite then
				local key = info.Name or rawName
				if not seen[key] then
					seen[key] = true
					table.insert(weapons, {
						Name = key,
						Category = "Physical Fruit",
						Sprite = info.Sprite,
						Equipped = equipped,
					})
				end
			end
		else
			local isFruitMoveset = tool:GetAttribute("WeaponType") == "Demon Fruit"
				or tool:FindFirstChild("HiddenAbilities") ~= nil
				or tool:FindFirstChild("LeftClickRemote") ~= nil
			local isWeapon = tool:GetAttribute("WeaponType") ~= nil
				or tool:FindFirstChild("ServerEquippedWeaponPointer") ~= nil
				or tool:FindFirstChild("LocalEquippedWeaponPointer") ~= nil
				or isFruitMoveset

			local info = WeaponCache[lower]
			if not info then
				local clean = lower:gsub("%s*%(tool%)", ""):gsub("%s*fruit", "")
				info = WeaponCache[clean]
			end
			if not info and isWeapon then
				for k, v in pairs(WeaponCache) do
					if lower:find(k, 1, true) or k:find(lower, 1, true) then
						info = v
						break
					end
				end
			end

			if info and (info.Category ~= "Blox Fruit" or isFruitMoveset) then
				local key = info.Name or rawName
				if not seen[key] then
					seen[key] = true
					table.insert(weapons, {
						Name = key,
						Category = info.Category,
						Sprite = info.Sprite,
						Equipped = equipped,
					})
				end
			elseif tool.TextureId and tool.TextureId ~= "" and isWeapon then
				if not seen[rawName] then
					seen[rawName] = true
					table.insert(weapons, {
						Name = rawName,
						Category = "Weapon",
						Sprite = { Image = tool.TextureId },
						Equipped = equipped,
					})
				end
			end
		end
	end

	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				addTool(child, true)
			end
		end
	end

	local bp = player:FindFirstChild("Backpack")
	if bp then
		for _, child in ipairs(bp:GetChildren()) do
			if child:IsA("Tool") then
				addTool(child, false)
			end
		end
	end

	local categoryPriority = {
		["Fighting Style"] = 1,
		["Blox Fruit"] = 2,
		["Physical Fruit"] = 3,
		["Sword"] = 4,
		["Gun"] = 5,
	}

	table.sort(weapons, function(a, b)
		if a.Equipped ~= b.Equipped then
			return a.Equipped == true
		end
		local prioA = categoryPriority[a.Category] or 6
		local prioB = categoryPriority[b.Category] or 6
		return prioA < prioB
	end)

	return weapons
end

function ESPManager:AddPlayer(player, options)
	local Players = GetService("Players")
	local LocalPlayer = Players and Players.LocalPlayer
	if not player or (LocalPlayer and player == LocalPlayer) then return end
	options = options or {}

	local function hookCharacter(char)
		if not char then return end
		local head = char:WaitForChild("Head", 5) or char:WaitForChild("HumanoidRootPart", 5)
		local hum = char:WaitForChild("Humanoid", 5)
		if not (head and hum) then return end

		local isTeammate = (LocalPlayer and LocalPlayer.Team and player.Team and LocalPlayer.Team == player.Team) or false
		local defaultColor = isTeammate and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(255, 65, 65)

		self:Add(head, {
			Category = "Player",
			Color = options.Color or defaultColor,
			Layout = "Card",
			Offset = Vector3.new(0, 2.2, 0),
			MaxDistance = options.MaxDistance or 10000,
			ShowHighlight = options.ShowHighlight ~= false,
			Icon = function()
				return string.format(
					"https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
					player.UserId
				)
			end,
			Card = function()
				local data = player:FindFirstChild("Data")
				local level = data and data:FindFirstChild("Level") and tostring(data.Level.Value) or "?"
				local liveChar = player.Character or char
				local en = liveChar and liveChar:FindFirstChild("Energy")
				return {
					Name = player.DisplayName or player.Name,
					Level = level,
					Hp = hum and hum.Health or 0,
					MaxHp = hum and hum.MaxHealth or 1,
					En = en and tonumber(en.Value) or nil,
					MaxEn = en and tonumber(en.MaxValue) or nil,
				}
			end,
			Weapons = function()
				return GetPlayerWeapons(player)
			end,
		})
	end

	self._Maid:AddTask(player.CharacterAdded:Connect(hookCharacter))
	if player.Character then
		hookCharacter(player.Character)
	end
end

function ESPManager:AddChest(chestInstance, options)
	options = options or {}
	local root = chestInstance:IsA("BasePart") and chestInstance or (chestInstance:FindFirstChild("RootPart") or chestInstance.PrimaryPart)
	if not root then return end

	local name = chestInstance.Name:lower()
	local color = Color3.fromRGB(255, 255, 255)
	local icon = "rbxassetid://0"
	local tierName = "Chest"

	if name:find("diamond") then
		color = Color3.fromRGB(0, 230, 255)
		icon = "rbxassetid://103232045481498"
		tierName = "Diamond Chest"
	elseif name:find("gold") then
		color = Color3.fromRGB(255, 215, 0)
		icon = "rbxassetid://103232045481498"
		tierName = "Gold Chest"
	elseif name:find("silver") then
		color = Color3.fromRGB(210, 210, 220)
		icon = "rbxassetid://97335861533611"
		tierName = "Silver Chest"
	end

	self:Add(root, {
		Category = "Chest",
		Color = color,
		Icon = icon,
		Offset = Vector3.new(0, 2.0, 0),
		MaxDistance = options.MaxDistance or 6000,
		Text = function(dist)
			return string.format("<b>%s</b>\n<font color='rgb(200,200,200)'>%d studs</font>", tierName, math.floor(dist))
		end
	})
end

function ESPManager:AddFruit(fruitInstance, options)
	if self._Destroyed or self.Settings.Enabled == false then return nil end
	if not fruitInstance then return nil end
	options = options or {}

	local handle = fruitInstance:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return nil end

	if fruitInstance:FindFirstChild("statue") or fruitInstance:FindFirstChild("podium") or fruitInstance:FindFirstChild("AnimationController") then
		return nil
	end

	if fruitInstance.ClassName == "Model" and not fruitInstance.Name:match("^Fruit%s*$") then
		return nil
	end

	local isSpawned = options.IsSpawned
	if isSpawned == nil then
		isSpawned = (fruitInstance.ClassName == "Model") and (fruitInstance.Name:match("^Fruit%s*$") ~= nil)
	end

	local fruitName, meta, realName, fruitSprite = ResolveFruitInfo(fruitInstance)
	local color = options.Color or meta.Color

	local tileSprite = InventoryRarityTiles[meta.Rarity] or InventoryRarityTiles[0]
	if realName and (realName:lower():find("gas") or realName:lower():find("hellfire")) then
		tileSprite = InventoryRarityTiles["Clawed"] or tileSprite
	end

	return self:Add(handle, {
		Category = "Fruit",
		Color = color,
		Icon = fruitSprite,
		Tile = tileSprite,
		Offset = Vector3.new(0, 2.2, 0),
		ShowHighlight = true,
		HighlightAdornee = fruitInstance,
		MaxDistance = options.MaxDistance or 600000,
		Text = function(dist)
			if isSpawned then
				return string.format(
					"<font color='%s'><b>%s</b> [Spawned]</font>\n<font color='rgb(220,220,220)'>%d studs away</font>",
					meta.Hex,
					fruitName,
					math.floor(dist or 0)
				)
			else
				return string.format(
					"<font color='%s'><b>%s</b> [Dropped]</font>\n<font color='rgb(220,220,220)'>%d studs away</font>",
					meta.Hex,
					fruitName,
					math.floor(dist or 0)
				)
			end
		end
	})
end

function ESPManager:AddLocation(locationPart, displayName, options)
	options = options or {}
	if not locationPart or not locationPart:IsA("BasePart") then return end

	local color = options.Color or Color3.fromRGB(100, 200, 255)

	self:Add(locationPart, {
		Category = "Island",
		Color = color,
		Offset = Vector3.new(0, 5, 0),
		MaxDistance = options.MaxDistance or 50000,
		Text = function(dist)
			return string.format("<b><font color='rgb(100,200,255)'>%s</font></b>\n<font color='rgb(200,200,200)'>%d studs</font>", displayName or locationPart.Name, math.floor(dist or 0))
		end
	})
end

function ESPManager:AddFlower(flowerInstance, options)
	options = options or {}
	local root = flowerInstance:IsA("BasePart") and flowerInstance or (flowerInstance.PrimaryPart or flowerInstance:FindFirstChildWhichIsA("BasePart"))
	if not root then return end
	local name = flowerInstance.Name
	local color = Color3.fromRGB(255, 75, 75)
	if name:find("1") or name:lower():find("blue") then
		color = Color3.fromRGB(65, 145, 255)
	elseif name:find("2") or name:lower():find("red") then
		color = Color3.fromRGB(255, 60, 60)
	elseif name:find("3") or name:lower():find("yellow") then
		color = Color3.fromRGB(255, 220, 50)
	end
	return self:Add(root, {
		Category = "Flower",
		Color = options.Color or color,
		Offset = Vector3.new(0, 2.5, 0),
		MaxDistance = options.MaxDistance or 25000,
		Text = function(dist)
			return string.format("🌸 <b>%s</b>\n<font color='rgb(200,200,200)'>%d studs</font>", name, math.floor(dist or 0))
		end,
	})
end

ESPManager.BerryColors = {
	["Yellow Star Berry"] = Color3.fromRGB(255, 220, 50),
	["Red Cherry Berry"] = Color3.fromRGB(255, 65, 65),
	["Purple Jelly Berry"] = Color3.fromRGB(190, 80, 255),
	["Pink Pig Berry"] = Color3.fromRGB(255, 130, 180),
	["Blue Icicle Berry"] = Color3.fromRGB(80, 210, 255),
	["Green Toad Berry"] = Color3.fromRGB(65, 235, 95),
	["Orange Berry"] = Color3.fromRGB(255, 145, 35),
	["White Cloud Berry"] = Color3.fromRGB(240, 240, 255),
}

function ESPManager:AddBerry(adornee, berryName, options)
	options = options or {}
	if not adornee then return end
	local color = options.Color or self.BerryColors[berryName] or Color3.fromRGB(255, 105, 180)
	local label = options.Dropped and "Dropped Berry" or "Berry"
	return self:Add(adornee, {
		Category = "Berry",
		Color = color,
		Offset = Vector3.new(0, 1.5, 0),
		MaxDistance = options.MaxDistance or 60000,
		Text = function(dist)
			return string.format("🍒 <b><font color='rgb(%d,%d,%d)'>%s</font></b>\n<font color='rgb(200,200,200)'>%s · %d studs</font>",
				color.R * 255, color.G * 255, color.B * 255, berryName, label, math.floor(dist or 0))
		end,
	})
end

function ESPManager:AddSwordDealer(adornee, options)
	options = options or {}
	if not adornee then return end
	local color = options.Color or Color3.fromRGB(255, 200, 60)
	local name = options.Name or "Legendary Sword Dealer"
	return self:Add(adornee, {
		Category = "Sword Dealer",
		Color = color,
		Offset = Vector3.new(0, 3, 0),
		MaxDistance = options.MaxDistance or 60000,
		Text = function(dist)
			local sword = options.GetSword and options.GetSword()
			local info = sword and string.format("<font color='rgb(255,235,150)'>%s</font> · %d studs", sword, math.floor(dist or 0))
				or string.format("%d studs", math.floor(dist or 0))
			return string.format("⚔️ <b><font color='rgb(%d,%d,%d)'>%s</font></b>\n<font color='rgb(200,200,200)'>%s</font>",
				color.R * 255, color.G * 255, color.B * 255, name, info)
		end,
	})
end

function ESPManager:AddSeaBeast(mobModel, options)
	options = options or {}
	local root = (mobModel:IsA("Model") and (mobModel:FindFirstChild("HumanoidRootPart") or mobModel.PrimaryPart or mobModel:FindFirstChildWhichIsA("BasePart")))
		or (mobModel:IsA("BasePart") and mobModel)
	local hum = mobModel:IsA("Model") and mobModel:FindFirstChildOfClass("Humanoid")
	if not root then return end
	local defaultColor = Color3.fromRGB(0, 240, 180)
	return self:Add(mobModel, {
		Category = "Sea Beast",
		Color = options.Color or defaultColor,
		Offset = Vector3.new(0, 6, 0),
		ShowHighlight = options.ShowHighlight ~= false,
		MaxDistance = options.MaxDistance or 35000,
		Text = function(dist)
			return string.format("🌊 <b>%s</b>\n<font color='rgb(200,200,200)'>%d studs</font>", mobModel.Name, math.floor(dist or 0))
		end,
		Bars = function()
			if not (hum and hum.Parent) then return 0, defaultColor, "", nil, nil, nil end
			local hp = math.floor(hum.Health)
			local maxHp = math.max(math.floor(hum.MaxHealth), 1)
			return math.clamp(hp / maxHp, 0, 1), defaultColor, string.format("%d/%d HP", hp, maxHp), nil, nil, nil
		end,
	})
end

function ESPManager:AddPumpkin(pumpkinInstance, isRare, options)
	options = options or {}
	local root = pumpkinInstance:IsA("BasePart") and pumpkinInstance
		or (pumpkinInstance:FindFirstChild("RootPart") or pumpkinInstance.PrimaryPart or pumpkinInstance:FindFirstChildWhichIsA("BasePart"))
	if not root then return end

	local rare = (isRare == true) or (pumpkinInstance:GetAttribute("PumpkinRare") == true)
	local category = rare and "Rare Pumpkin" or "Pumpkin"
	local defaultColor = rare and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 140, 20)
	local label = rare and "Rare Pumpkin" or "Pumpkin"

	return self:Add(pumpkinInstance, {
		Category = category,
		Color = options.Color or defaultColor,
		Offset = Vector3.new(0, 2.2, 0),
		ShowHighlight = (options.ShowHighlight ~= nil and options.ShowHighlight) or rare,
		MaxDistance = options.MaxDistance or (rare and 30000 or 10000),
		Text = function(dist)
			local state = pumpkinInstance:GetAttribute("PumpkinState")
			local stateTag = ""
			if state and state ~= "Idle" and state ~= "Whole" then
				stateTag = string.format(" <font color='rgb(255,100,100)'>[%s]</font>", state)
			end

			if rare then
				return string.format(
					"<b><font color='rgb(255,215,0)'>★ %s</font></b>%s\n<font color='rgb(200,200,200)'>%d studs</font>",
					label,
					stateTag,
					math.floor(dist or 0)
				)
			else
				return string.format(
					"<b>%s</b>%s\n<font color='rgb(200,200,200)'>%d studs</font>",
					label,
					stateTag,
					math.floor(dist or 0)
				)
			end
		end
	})
end

function ESPManager:AddPumpkinSnowman(mobModel, options)
	options = options or {}
	local root = mobModel:FindFirstChild("HumanoidRootPart") or mobModel.PrimaryPart or mobModel:FindFirstChildWhichIsA("BasePart")
	local hum = mobModel:FindFirstChild("Humanoid")
	if not root then return end

	local defaultColor = Color3.fromRGB(80, 220, 255)

	return self:Add(mobModel, {
		Category = "Pumpkin Snowman",
		Color = options.Color or defaultColor,
		Offset = Vector3.new(0, 3.2, 0),
		ShowHighlight = options.ShowHighlight ~= false,
		MaxDistance = options.MaxDistance or 15000,
		Text = function(dist)
			local owner = mobModel:GetAttribute("Owner")
			local ownerTag = owner and string.format(" <font color='rgb(200,200,200)'>(%s)</font>", owner) or ""
			return string.format(
				"<b>Pumpkin Snowman</b>%s\n<font color='rgb(200,200,200)'>%d studs</font>",
				ownerTag,
				math.floor(dist or 0)
			)
		end,
		Bars = function()
			if not (hum and hum.Parent) then return 0, defaultColor, "", nil, nil, nil end
			local hp = math.floor(hum.Health)
			local maxHp = math.max(math.floor(hum.MaxHealth), 1)
			local hpRatio = math.clamp(hp / maxHp, 0, 1)
			local hpText = string.format("%d/%d HP", hp, maxHp)
			return hpRatio, defaultColor, hpText, nil, nil, nil
		end
	})
end

function ESPManager:AddJackOLantern(mobModel, options)
	options = options or {}
	local root = mobModel:FindFirstChild("HumanoidRootPart") or mobModel.PrimaryPart or mobModel:FindFirstChildWhichIsA("BasePart")
	local hum = mobModel:FindFirstChild("Humanoid")
	if not root then return end

	local defaultColor = Color3.fromRGB(255, 120, 0)

	return self:Add(mobModel, {
		Category = "Jack o' Lantern",
		Color = options.Color or defaultColor,
		Offset = Vector3.new(0, 3.2, 0),
		ShowHighlight = options.ShowHighlight ~= false,
		MaxDistance = options.MaxDistance or 15000,
		Text = function(dist)
			local owner = mobModel:GetAttribute("Owner")
			local ownerTag = owner and string.format(" <font color='rgb(200,200,200)'>(%s)</font>", owner) or ""
			return string.format(
				"<b>Jack o' Lantern</b>%s\n<font color='rgb(200,200,200)'>%d studs</font>",
				ownerTag,
				math.floor(dist or 0)
			)
		end,
		Bars = function()
			if not (hum and hum.Parent) then return 0, defaultColor, "", nil, nil, nil end
			local hp = math.floor(hum.Health)
			local maxHp = math.max(math.floor(hum.MaxHealth), 1)
			local hpRatio = math.clamp(hp / maxHp, 0, 1)
			local hpText = string.format("%d/%d HP", hp, maxHp)
			return hpRatio, defaultColor, hpText, nil, nil, nil
		end
	})
end

function ESPManager:AddDoorPortal(doorOrPortal, stateText, options)
	options = options or {}
	local root = (doorOrPortal:IsA("Model") and (doorOrPortal:FindFirstChild("Part") or doorOrPortal:FindFirstChild("Proximity") or doorOrPortal.PrimaryPart or doorOrPortal:FindFirstChildWhichIsA("BasePart")))
		or (doorOrPortal:IsA("BasePart") and doorOrPortal)
	if not root then return end

	local isHalloweenDoor = doorOrPortal.Name == "HalloweenDoor"
	local defaultColor = Color3.fromRGB(255, 60, 40)

	return self:Add(doorOrPortal, {
		Category = "Boss Portal",
		Color = options.Color or defaultColor,
		Offset = Vector3.new(0, 3.2, 0),
		ShowHighlight = options.ShowHighlight ~= false,
		MaxDistance = options.MaxDistance or 25000,
		Text = function(dist)
			return string.format(
				"🔥 <b><font color='rgb(255,60,40)'>Hellfire Boss Door</font></b> • <font color='rgb(255,220,50)'>[ACTIVE]</font>\n<font color='rgb(200,200,200)'>%d studs</font>",
				math.floor(dist or 0)
			)
		end
	})
end

ESPManager.FruitMeshMap = FruitMeshMap
ESPManager.ResolveFruitInfo = ResolveFruitInfo

getgenv().ESPManager = ESPManager
return ESPManager
