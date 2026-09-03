--[[
	EloHub — мобильная панель способностей
	LocalScript → StarterPlayer → StarterPlayerScripts

	ESP (бокс/обводка + хп) · Скорость · Полёт · Жёсткое наведение · Телепорт к игроку
	Размер панели настраивается ползунком внизу.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")

local player  = Players.LocalPlayer
local camera  = Workspace.CurrentCamera

--==============================================================
-- ПАЛИТРА
--==============================================================
local PALETTE = {
	deep   = Color3.fromRGB(10, 16, 34),
	navy   = Color3.fromRGB(24, 40, 78),
	steel  = Color3.fromRGB(96, 118, 154),
	haze   = Color3.fromRGB(150, 166, 191),
	white  = Color3.fromRGB(255, 255, 255),
	accent = Color3.fromRGB(126, 168, 235),
	danger = Color3.fromRGB(235, 96, 96),
	good   = Color3.fromRGB(104, 214, 138),
}

--==============================================================
-- СОСТОЯНИЕ
--==============================================================
local state = {
	esp   = false,
	speed = false,
	fly   = false,
	aim   = false,

	espMode    = "box",   -- "box" | "outline"
	speedValue = 32,
	flySpeed   = 60,

	noclip     = false,   -- проход сквозь стены
	wall       = false,   -- полупрозрачная геометрия
	wallAlpha  = 0.75,

	aimFov     = 150,     -- радиус поля захвата в пикселях
	aimPart    = "Head",
	aimWall    = true,
	aimNpc     = true,

	silent     = false,   -- направление стрельбы в цель без поворота камеры
	trigger    = false,   -- авто-срабатывание при захвате
	arrows     = false,   -- стрелки к целям вне экрана
	tapTp      = false,   -- телепорт по тапу в точку

	tpTarget   = nil,     -- выбранный игрок
}

local DEFAULT_WALKSPEED = 16

--[[ Подключение к боевой системе твоей игры.
     Триггербот и silent aim не могут «стрелять» сами — они лишь сообщают,
     куда целиться. Пропиши сюда свой RemoteEvent, и оба начнут работать. ]]
local CONFIG = {
	fireRemote    = nil,   -- пример: game.ReplicatedStorage:WaitForChild("Fire")
	triggerRadius = 45,    -- цель должна быть в этом радиусе от центра, px
	triggerDelay  = 0.12,  -- пауза между авто-срабатываниями, сек
}

--==============================================================
-- ХЕЛПЕРЫ
--==============================================================
local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then inst[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(radius, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function stroke(thickness, color, transparency, parent)
	return new("UIStroke", {
		Thickness = thickness,
		Color = color,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

--==============================================================
-- ФОН
--==============================================================
local function buildBackdrop(parent)
	local bg = new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PALETTE.navy,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 0,
		Parent = parent,
	})
	corner(16, bg)

	new("UIGradient", {
		Rotation = 205,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, PALETTE.deep),
			ColorSequenceKeypoint.new(0.35, PALETTE.navy),
			ColorSequenceKeypoint.new(0.75, PALETTE.steel),
			ColorSequenceKeypoint.new(1.00, PALETTE.haze),
		}),
		Parent = bg,
	})

	local crest = new("Frame", {
		Size = UDim2.fromScale(1.6, 1.3),
		Position = UDim2.fromScale(0.45, -0.45),
		BackgroundColor3 = PALETTE.haze,
		BorderSizePixel = 0,
		Rotation = 14,
		ZIndex = 1,
		Parent = bg,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = crest })
	new("UIGradient", {
		Rotation = 120,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.78),
			NumberSequenceKeypoint.new(1.0, 1.00),
		}),
		Parent = crest,
	})

	local wave = new("Frame", {
		Size = UDim2.fromScale(1.9, 1.5),
		Position = UDim2.fromScale(-0.55, 0.30),
		BackgroundColor3 = PALETTE.deep,
		BorderSizePixel = 0,
		Rotation = -13,
		ZIndex = 2,
		Parent = bg,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = wave })
	new("UIGradient", {
		Rotation = 300,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.10),
			NumberSequenceKeypoint.new(0.6, 0.55),
			NumberSequenceKeypoint.new(1.0, 1.00),
		}),
		Parent = wave,
	})

	local vignette = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = bg,
	})
	corner(16, vignette)
	new("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.30),
			NumberSequenceKeypoint.new(0.45, 0.85),
			NumberSequenceKeypoint.new(1.0, 1.00),
		}),
		Parent = vignette,
	})

	return bg
end

--==============================================================
-- КАРКАС ИНТЕРФЕЙСА
--==============================================================
local gui = new("ScreenGui", {
	Name = "EloHub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local espLayer = new("Frame", {
	Name = "EspLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = gui,
})

local launcher = new("TextButton", {
	Name = "Launcher",
	Size = UDim2.fromOffset(58, 58),
	Position = UDim2.new(0, 16, 0, 90),
	BackgroundColor3 = PALETTE.navy,
	Text = "E",
	TextColor3 = PALETTE.white,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = launcher })
stroke(2, PALETTE.white, 0.15, launcher)

-- CanvasGroup: даёт GroupTransparency, поэтому панель гаснет целиком одним твином
local panel = new("CanvasGroup", {
	Name = "Panel",
	Position = UDim2.new(0, 16, 0, 90),
	Size = UDim2.new(0.86, 0, 0, 448),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	Visible = false,
	Active = true,
	ZIndex = 10,
	Parent = gui,
})
new("UISizeConstraint", { MaxSize = Vector2.new(336, 448), MinSize = Vector2.new(252, 380), Parent = panel })

local uiScale = new("UIScale", { Scale = 0.7, Parent = panel })
local panelHome = panel.Position   -- куда панель возвращается после анимации

buildBackdrop(panel)

local shell = new("Frame", {
	Name = "Shell",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 11,
	Parent = panel,
})
corner(16, shell)
stroke(2, PALETTE.white, 0.1, shell)
new("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = shell,
})

-- шапка (за неё таскаем)
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 12,
	Parent = shell,
})

new("TextLabel", {
	Size = UDim2.new(1, -44, 1, 0),
	BackgroundTransparency = 1,
	Text = "EloHub",
	TextColor3 = PALETTE.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	ZIndex = 12,
	Parent = header,
})

local hideBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(34, 34),
	BackgroundColor3 = PALETTE.white,
	BackgroundTransparency = 0.85,
	Text = "—",
	TextColor3 = PALETTE.white,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	AutoButtonColor = false,
	ZIndex = 12,
	Parent = header,
})
corner(10, hideBtn)
stroke(1, PALETTE.white, 0.5, hideBtn)

local body = new("ScrollingFrame", {
	Name = "Body",
	Position = UDim2.new(0, 0, 0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = true,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = PALETTE.white,
	ScrollBarImageTransparency = 0.5,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
	Parent = shell,
})
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = body,
})
new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = body })

--==============================================================
-- КОНСТРУКТОРЫ ЭЛЕМЕНТОВ
--==============================================================
local function makeCard(order, height)
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = PALETTE.white,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Active = true,
		LayoutOrder = order,
		ZIndex = 12,
		Parent = body,
	})
	corner(12, card)
	stroke(1, PALETTE.white, 0.6, card)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = card })
	return card
end

local function makeToggle(card, titleText, subtitleText, onChanged)
	new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, -72, 0, 20),
		BackgroundTransparency = 1,
		Text = titleText,
		TextColor3 = PALETTE.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 17,
		ZIndex = 13,
		Parent = card,
	})

	new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, -72, 0, 16),
		BackgroundTransparency = 1,
		Text = subtitleText,
		TextColor3 = PALETTE.haze,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		ZIndex = 13,
		Parent = card,
	})

	local track = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 13),
		Size = UDim2.fromOffset(58, 32),
		BackgroundColor3 = PALETTE.deep,
		BackgroundTransparency = 0.35,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 13,
		Parent = card,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	stroke(1.5, PALETTE.white, 0.35, track)

	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = PALETTE.white,
		BorderSizePixel = 0,
		ZIndex = 14,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

	local on = false
	track.Activated:Connect(function()
		on = not on
		TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
			Position = on and UDim2.new(1, -29, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = on and PALETTE.accent or PALETTE.white,
		}):Play()
		TweenService:Create(track, TweenInfo.new(0.16), {
			BackgroundTransparency = on and 0.05 or 0.35,
		}):Play()
		onChanged(on)
	end)
end

-- общий обработчик перетаскивания ползунков
local activeSlider = nil

local function makeSlider(card, yOffset, labelFmt, minVal, maxVal, startVal, onChanged)
	local label = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, yOffset),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = PALETTE.haze,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		ZIndex = 13,
		Parent = card,
	})

	local track = new("Frame", {
		Position = UDim2.new(0, 0, 0, yOffset + 22),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = PALETTE.deep,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 13,
		Parent = card,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	stroke(1, PALETTE.white, 0.55, track)

	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = PALETTE.accent,
		BorderSizePixel = 0,
		ZIndex = 14,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	local handle = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = PALETTE.white,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 15,
		Parent = track,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })

	local function apply(alpha)
		alpha = math.clamp(alpha, 0, 1)
		local value = math.floor(minVal + (maxVal - minVal) * alpha + 0.5)
		fill.Size = UDim2.fromScale(alpha, 1)
		handle.Position = UDim2.new(alpha, 0, 0.5, 0)
		label.Text = string.format(labelFmt, value)
		onChanged(value)
	end

	local function fromX(x)
		apply((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
	end

	local function grab(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSlider = fromX
			fromX(input.Position.X)
		end
	end

	track.InputBegan:Connect(grab)
	handle.InputBegan:Connect(grab)

	apply((startVal - minVal) / (maxVal - minVal))
	return apply
end

--==============================================================
-- ESP: бокс или обводка + полоса здоровья
--==============================================================
local espTracked = {}

local function clearEspFor(model)
	local data = espTracked[model]
	if not data then return end
	if data.box then data.box:Destroy() end
	if data.highlight then data.highlight:Destroy() end
	if data.arrow then data.arrow:Destroy() end
	espTracked[model] = nil
end

local function clearAllEsp()
	for model in pairs(espTracked) do clearEspFor(model) end
end

local function buildBox(color)
	local box = new("Frame", {
		Name = "EloBox",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = espLayer,
	})
	corner(4, box)
	stroke(1.5, color, 0, box)

	local name = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(180, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = PALETTE.white,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ZIndex = 3,
		Parent = box,
	})
	new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.35, Parent = name })

	local hpTrack = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -5, 0, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = PALETTE.deep,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = box,
	})
	corner(2, hpTrack)

	local hpFill = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PALETTE.good,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hpTrack,
	})
	corner(2, hpFill)

	local hpText = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -12, 0, 0),
		Size = UDim2.fromOffset(34, 14),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = PALETTE.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		ZIndex = 3,
		Parent = box,
	})
	new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = hpText })

	return box, name, hpFill, hpText
end

local function buildArrow(color)
	local arrow = new("TextLabel", {
		Name = "EloArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Text = "\u{25B2}",
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = 26,
		Visible = false,
		ZIndex = 4,
		Parent = espLayer,
	})
	new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = arrow })
	return arrow
end

local function addEsp(model, labelText, color)
	if espTracked[model] then return end
	local data = { name = labelText, color = color }

	if state.arrows then
		data.arrow = buildArrow(color)
	end

	if not state.esp then
		espTracked[model] = data
		return
	end

	if state.espMode == "box" then
		data.box, data.nameLabel, data.hpFill, data.hpText = buildBox(color)
	else
		data.highlight = new("Highlight", {
			Name = "EloEsp",
			FillColor = color,
			FillTransparency = 0.62,
			OutlineColor = PALETTE.white,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = model,
			Parent = model,
		})
		local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
		if head then
			local tag = new("BillboardGui", {
				Name = "EloTag",
				Adornee = head,
				Size = UDim2.fromOffset(190, 34),
				StudsOffset = Vector3.new(0, 2.6, 0),
				AlwaysOnTop = true,
				MaxDistance = 1000,
				Parent = model,
			})
			data.nameLabel = new("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = labelText,
				TextColor3 = PALETTE.white,
				Font = Enum.Font.GothamMedium,
				TextSize = 14,
				Parent = tag,
			})
			new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.35, Parent = data.nameLabel })
		end
	end

	espTracked[model] = data
end

local function scanEsp()
	if not (state.esp or state.arrows) then return end
	local seen = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			seen[other.Character] = true
			addEsp(other.Character, other.DisplayName, PALETTE.accent)
		end
	end

	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Humanoid") then
			local model = obj.Parent
			if model and model ~= player.Character and not Players:GetPlayerFromCharacter(model) then
				seen[model] = true
				addEsp(model, model.Name, PALETTE.danger)
			end
		end
	end

	for model in pairs(espTracked) do
		if not seen[model] or not model.Parent then clearEspFor(model) end
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		if state.esp or state.arrows then pcall(scanEsp) end
	end
end)

-- проекция модели в прямоугольник на экране
local function projectBounds(model)
	local cf, size = model:GetBoundingBox()
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local anyFront = false

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local world = (cf * CFrame.new(size.X / 2 * x, size.Y / 2 * y, size.Z / 2 * z)).Position
				local sp = camera:WorldToViewportPoint(world)
				if sp.Z > 0 then
					anyFront = true
					if sp.X < minX then minX = sp.X end
					if sp.Y < minY then minY = sp.Y end
					if sp.X > maxX then maxX = sp.X end
					if sp.Y > maxY then maxY = sp.Y end
				end
			end
		end
	end

	if not anyFront then return nil end
	return minX, minY, maxX - minX, maxY - minY
end

RunService.RenderStepped:Connect(function()
	if not state.esp or state.espMode ~= "box" then return end
	local root = getRoot()

	for model, data in pairs(espTracked) do
		local box = data.box
		if box then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local ok, x, y, w, h = pcall(projectBounds, model)
			if ok and x and hum and hum.Health > 0 then
				box.Visible = true
				box.Position = UDim2.fromOffset(x, y)
				box.Size = UDim2.fromOffset(w, h)

				local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				data.hpFill.Size = UDim2.fromScale(1, frac)
				data.hpFill.BackgroundColor3 = PALETTE.danger:Lerp(PALETTE.good, frac)
				data.hpText.Text = tostring(math.floor(hum.Health))

				if root then
					local target = model:FindFirstChild("HumanoidRootPart")
					local dist = target and math.floor((target.Position - root.Position).Magnitude) or 0
					data.nameLabel.Text = string.format("%s  ·  %dm", data.name, dist)
				else
					data.nameLabel.Text = data.name
				end
			else
				box.Visible = false
			end
		end
	end
end)

-- стрелки к целям, которых не видно в кадре
RunService.RenderStepped:Connect(function()
	if not state.arrows then return end

	local vp = camera.ViewportSize
	local center = Vector2.new(vp.X / 2, vp.Y / 2)
	local radius = math.min(vp.X, vp.Y) / 2 - 56

	for model, data in pairs(espTracked) do
		local arrow = data.arrow
		if arrow then
			local part = model:FindFirstChild("HumanoidRootPart")
			local hum = model:FindFirstChildOfClass("Humanoid")

			if part and hum and hum.Health > 0 then
				local sp = camera:WorldToViewportPoint(part.Position)
				local onScreen = sp.Z > 0
					and sp.X >= 0 and sp.X <= vp.X
					and sp.Y >= 0 and sp.Y <= vp.Y

				if onScreen then
					arrow.Visible = false
				else
					local offset = Vector2.new(sp.X, sp.Y) - center
					-- за спиной координаты зеркалятся, разворачиваем обратно
					if sp.Z <= 0 then offset = -offset end
					if offset.Magnitude < 1 then offset = Vector2.new(0, -1) end

					local dir = offset.Unit
					local point = center + dir * radius
					arrow.Position = UDim2.fromOffset(point.X, point.Y)
					arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
					arrow.Visible = true
				end
			else
				arrow.Visible = false
			end
		end
	end
end)

--==============================================================
-- СКОРОСТЬ
--==============================================================
RunService.Heartbeat:Connect(function()
	if not state.speed then return end
	local hum = getHumanoid()
	if hum and hum.WalkSpeed ~= state.speedValue then
		hum.WalkSpeed = state.speedValue
	end
end)

--==============================================================
-- ПОЛЁТ
--==============================================================
local flyBody, flyGyro
local verticalInput = 0
local controls

task.spawn(function()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and module then controls = module:GetControls() end
end)

local function stopFly()
	if flyBody then flyBody:Destroy(); flyBody = nil end
	if flyGyro then flyGyro:Destroy(); flyGyro = nil end
	local hum = getHumanoid()
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function startFly()
	local root, hum = getRoot(), getHumanoid()
	if not root or not hum then return end

	stopFly()
	hum.PlatformStand = true

	flyBody = new("BodyVelocity", {
		Name = "EloFly",
		MaxForce = Vector3.new(1, 1, 1) * 1e5,
		Velocity = Vector3.zero,
		P = 4000,
		Parent = root,
	})
	flyGyro = new("BodyGyro", {
		Name = "EloFlyGyro",
		MaxTorque = Vector3.new(1, 1, 1) * 4e5,
		P = 9000,
		D = 500,
		CFrame = root.CFrame,
		Parent = root,
	})
end

RunService.RenderStepped:Connect(function()
	if not state.fly or not flyBody then return end
	local root = getRoot()
	if not root then return end

	local move = Vector3.zero
	if controls then
		local ok, mv = pcall(function() return controls:GetMoveVector() end)
		if ok and mv then move = mv end
	end

	local cf = camera.CFrame
	local dir = (cf.RightVector * move.X) + (cf.LookVector * -move.Z) + Vector3.new(0, verticalInput, 0)
	if dir.Magnitude > 0 then dir = dir.Unit * state.flySpeed end

	flyBody.Velocity = dir
	if flyGyro then
		flyGyro.CFrame = CFrame.new(root.Position, root.Position + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z))
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space then verticalInput = 1
	elseif input.KeyCode == Enum.KeyCode.LeftControl then verticalInput = -1 end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftControl then
		verticalInput = 0
	end
end)

local altPad = new("Frame", {
	Name = "AltPad",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -110),
	Size = UDim2.fromOffset(72, 156),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 15,
	Parent = gui,
})
new("UIListLayout", { Padding = UDim.new(0, 12), Parent = altPad })

local function makeAltButton(symbol, value)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = PALETTE.navy,
		BackgroundTransparency = 0.15,
		Text = symbol,
		TextColor3 = PALETTE.white,
		Font = Enum.Font.GothamBold,
		TextSize = 28,
		AutoButtonColor = false,
		ZIndex = 15,
		Parent = altPad,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = btn })
	stroke(2, PALETTE.white, 0.2, btn)

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			verticalInput = value
			btn.BackgroundTransparency = 0
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if verticalInput == value then verticalInput = 0 end
			btn.BackgroundTransparency = 0.15
		end
	end)
end

makeAltButton("↑", 1)
makeAltButton("↓", -1)

--==============================================================
-- НАВЕДЕНИЕ: жёсткая фиксация
--==============================================================
local aimCircle = new("Frame", {
	Name = "AimFov",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(state.aimFov * 2, state.aimFov * 2),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = aimCircle })
local aimStroke = stroke(2, PALETTE.white, 0.55, aimCircle)

local aimDot = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6),
	BackgroundColor3 = PALETTE.white,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = aimCircle,
})
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = aimDot })

local aimTarget = nil

local function isAlive(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function aimPartOf(model)
	return model:FindFirstChild(state.aimPart)
		or model:FindFirstChild("Head")
		or model:FindFirstChild("HumanoidRootPart")
end

local function seesPart(part)
	if not state.aimWall then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local origin = camera.CFrame.Position
	local hit = Workspace:Raycast(origin, part.Position - origin, params)
	return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

local function screenOffset(part)
	local sp = camera:WorldToViewportPoint(part.Position)
	if sp.Z <= 0 then return nil end
	local center = camera.ViewportSize / 2
	return (Vector2.new(sp.X, sp.Y) - Vector2.new(center.X, center.Y)).Magnitude
end

local function pickTarget()
	local best, bestDist = nil, state.aimFov

	local function consider(model)
		if model == player.Character or not isAlive(model) then return end
		local part = aimPartOf(model)
		if not part then return end
		local off = screenOffset(part)
		if off and off < bestDist and seesPart(part) then
			best, bestDist = part, off
		end
	end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then consider(other.Character) end
	end

	if state.aimNpc then
		for _, obj in ipairs(Workspace:GetDescendants()) do
			if obj:IsA("Humanoid") and obj.Parent and not Players:GetPlayerFromCharacter(obj.Parent) then
				consider(obj.Parent)
			end
		end
	end

	return best
end

-- пока игрок ведёт камеру, фиксация отпускается: иначе увести взгляд невозможно
local lastLookInput = 0

UserInputService.InputChanged:Connect(function(input, processed)
	if processed then return end   -- ввод по панели и джойстику не считается

	local isLook =
		input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
		or (input.UserInputType == Enum.UserInputType.Gamepad1
			and input.KeyCode == Enum.KeyCode.Thumbstick2)

	if isLook and input.Delta.Magnitude > 1 then
		lastLookInput = os.clock()
	end
end)

local function cameraIsBeingMoved()
	return (os.clock() - lastLookInput) < 0.12
end

-- цель держится, пока жива, видна и не вышла за поле захвата
task.spawn(function()
	while true do
		task.wait(0.06)
		if not (state.aim or state.silent or state.trigger) then
			aimTarget = nil
		else
			local keep = false
			if aimTarget and aimTarget.Parent and isAlive(aimTarget.Parent) then
				local off = screenOffset(aimTarget)
				keep = off ~= nil and off < state.aimFov and seesPart(aimTarget)
			end
			if not keep then
				local ok, result = pcall(pickTarget)
				aimTarget = ok and result or nil
			end
		end
	end
end)

-- после камерного скрипта, иначе доворот будет перебиваться
RunService:BindToRenderStep("EloAimLock", Enum.RenderPriority.Camera.Value + 1, function()
	if not state.aim then return end

	local locked = aimTarget and aimTarget.Parent and isAlive(aimTarget.Parent)

	-- жёсткая фиксация, но только пока камеру не ведут вручную
	if locked and not cameraIsBeingMoved() then
		camera.CFrame = CFrame.new(camera.CFrame.Position, aimTarget.Position)
	end

	if not locked then aimTarget = nil end
	aimDot.BackgroundColor3 = locked and PALETTE.accent or PALETTE.white
	aimStroke.Transparency = locked and 0.25 or 0.55
end)

--==============================================================
-- SILENT AIM: направление в цель без поворота камеры
--==============================================================
--[[ Камеру не трогаем — вместо этого отдаём точку цели наружу.
     В своём оружейном скрипте вместо направления камеры возьми:

         local elo = _G.EloHub
         local dir = (elo and elo.aimDirection(muzzle.Position)) or camera.CFrame.LookVector

     Если silent aim выключен или цели нет, функция вернёт nil и сработает
     твоя обычная логика. ]]
local api = {}

function api.target()
	if not (state.silent or state.trigger) then return nil end
	if aimTarget and aimTarget.Parent and isAlive(aimTarget.Parent) then
		return aimTarget
	end
	return nil
end

function api.aimPosition()
	local part = api.target()
	return part and part.Position or nil
end

function api.aimDirection(origin)
	local pos = api.aimPosition()
	if not pos or not origin then return nil end
	local delta = pos - origin
	return delta.Magnitude > 0 and delta.Unit or nil
end

function api.isSilent() return state.silent end

_G.EloHub = api

--==============================================================
-- ТРИГГЕРБОТ
--==============================================================
local lastFire = 0

local function pullTrigger(part)
	if CONFIG.fireRemote then
		pcall(function()
			CONFIG.fireRemote:FireServer(part.Parent, part.Position)
		end)
	end
end

task.spawn(function()
	while true do
		task.wait(0.03)
		if state.trigger and aimTarget and aimTarget.Parent and isAlive(aimTarget.Parent) then
			local off = screenOffset(aimTarget)
			if off and off <= CONFIG.triggerRadius
				and seesPart(aimTarget)
				and (os.clock() - lastFire) >= CONFIG.triggerDelay then
				lastFire = os.clock()
				pullTrigger(aimTarget)
			end
		end
	end
end)

--==============================================================
-- ТЕЛЕПОРТ ПО ТАПУ В ТОЧКУ
--==============================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if not state.tapTp or processed then return end
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local root = getRoot()
	if not root then return end

	local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if hit then
		root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3.5, 0)) * (root.CFrame - root.CFrame.Position)
	end
end)

--==============================================================
-- WALLHACK: проход сквозь стены
--==============================================================
local collideMemory = {}

-- Stepped идёт до расчёта физики — снимать коллизию нужно именно здесь
RunService.Stepped:Connect(function()
	if not state.noclip then return end
	local char = player.Character
	if not char then return end

	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			if collideMemory[part] == nil then collideMemory[part] = true end
			part.CanCollide = false
		end
	end
end)

local function restoreCollision()
	for part, wasColliding in pairs(collideMemory) do
		if part.Parent and wasColliding then part.CanCollide = true end
	end
	table.clear(collideMemory)
end

--==============================================================
-- ПРОЗРАЧНЫЕ СТЕНЫ: геометрия просвечивает (только у тебя)
--==============================================================
local wallCache = {}
local wallConn

-- LocalTransparencyModifier виден только на клиенте и не трогает сервер,
-- поэтому исходную прозрачность деталей сохранять не нужно.
local function isWorldPart(part)
	if not part:IsA("BasePart") then return false end
	if part.Transparency >= 0.95 then return false end

	local ancestor = part:FindFirstAncestorOfClass("Model")
	while ancestor do
		if ancestor:FindFirstChildOfClass("Humanoid") then return false end
		ancestor = ancestor:FindFirstAncestorOfClass("Model")
	end

	if part:FindFirstAncestorOfClass("Accessory") or part:FindFirstAncestorOfClass("Tool") then
		return false
	end

	return true
end

local function applyWall(part)
	if not isWorldPart(part) then return end
	wallCache[part] = true
	part.LocalTransparencyModifier = state.wallAlpha
end

local function enableWall()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		applyWall(obj)
	end

	wallConn = Workspace.DescendantAdded:Connect(function(obj)
		if state.wall then task.defer(applyWall, obj) end
	end)
end

local function disableWall()
	if wallConn then
		wallConn:Disconnect()
		wallConn = nil
	end
	for part in pairs(wallCache) do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	table.clear(wallCache)
end

local function refreshWallAlpha()
	for part in pairs(wallCache) do
		if part.Parent then
			part.LocalTransparencyModifier = state.wallAlpha
		else
			wallCache[part] = nil
		end
	end
end

-- движок иногда сбрасывает модификатор (стриминг, смена персонажа) — подправляем
task.spawn(function()
	while true do
		task.wait(3)
		if state.wall then pcall(refreshWallAlpha) end
	end
end)

--==============================================================
-- СТРОКИ ПАНЕЛИ
--==============================================================

-- 1. ESP + выбор режима
local espCard = makeCard(1, 106)
makeToggle(espCard, "ESP", "Игроки и NPC, хп в реальном времени", function(on)
	state.esp = on
	clearAllEsp()
	scanEsp()
end)

local modeRow = new("Frame", {
	Position = UDim2.new(0, 0, 0, 58),
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	ZIndex = 13,
	Parent = espCard,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	Parent = modeRow,
})

local modeButtons = {}
local function selectEspMode(mode)
	state.espMode = mode
	for key, btn in pairs(modeButtons) do
		local active = (key == mode)
		btn.BackgroundTransparency = active and 0.05 or 0.8
		btn.BackgroundColor3 = active and PALETTE.accent or PALETTE.white
	end
	if state.esp then
		clearAllEsp()
		scanEsp()
	end
end

for _, entry in ipairs({ { "box", "Бокс" }, { "outline", "Обводка" } }) do
	local key, text = entry[1], entry[2]
	local btn = new("TextButton", {
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = PALETTE.white,
		BackgroundTransparency = 0.8,
		Text = text,
		TextColor3 = PALETTE.white,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		AutoButtonColor = false,
		ZIndex = 13,
		Parent = modeRow,
	})
	corner(9, btn)
	stroke(1, PALETTE.white, 0.5, btn)
	modeButtons[key] = btn
	btn.Activated:Connect(function() selectEspMode(key) end)
end
selectEspMode("box")

-- 2. Стрелки к целям вне экрана
local arrowCard = makeCard(2, 58)
makeToggle(arrowCard, "Стрелки к целям", "Указатели по краям экрана", function(on)
	state.arrows = on
	clearAllEsp()
	scanEsp()
end)

-- 3. Wallhack
local noclipCard = makeCard(3, 58)
makeToggle(noclipCard, "Wallhack", "Проход сквозь стены и объекты", function(on)
	state.noclip = on
	if not on then restoreCollision() end
end)

-- 4. Прозрачные стены
local wallCard = makeCard(4, 110)
makeToggle(wallCard, "Прозрачные стены", "Геометрия просвечивает", function(on)
	state.wall = on
	if on then enableWall() else disableWall() end
end)
makeSlider(wallCard, 58, "Прозрачность: %d%%", 30, 95, 75, function(value)
	state.wallAlpha = value / 100
	if state.wall then refreshWallAlpha() end
end)

-- 5. Скорость + ползунок
local speedCard = makeCard(5, 110)
makeToggle(speedCard, "Скорость", "Ускоренное передвижение", function(on)
	state.speed = on
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = on and state.speedValue or DEFAULT_WALKSPEED end
end)
makeSlider(speedCard, 58, "Значение: %d", 16, 150, 32, function(value)
	state.speedValue = value
	if state.speed then
		local hum = getHumanoid()
		if hum then hum.WalkSpeed = value end
	end
end)

-- 6. Полёт
local flyCard = makeCard(6, 58)
makeToggle(flyCard, "Полёт", "Джойстик — курс, ↑↓ — высота", function(on)
	state.fly = on
	if on then
		startFly()
		altPad.Visible = true
	else
		stopFly()
		altPad.Visible = false
		verticalInput = 0
	end
end)

-- 7. Наведение + поле захвата
local aimCard = makeCard(7, 110)
makeToggle(aimCard, "Наведение", "Жёсткая фиксация на цели", function(on)
	state.aim = on
	aimCircle.Visible = on
	if not on then aimTarget = nil end
end)
makeSlider(aimCard, 58, "Поле захвата: %d px", 40, 500, state.aimFov, function(value)
	state.aimFov = value
	aimCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end)

-- 8. Silent aim
local silentCard = makeCard(8, 58)
makeToggle(silentCard, "Silent aim", "Стрельба в цель без поворота камеры", function(on)
	state.silent = on
	if not on then aimTarget = nil end
end)

-- 9. Триггербот
local triggerCard = makeCard(9, 58)
makeToggle(triggerCard, "Триггербот", "Авто-срабатывание при захвате цели", function(on)
	state.trigger = on
	if not on then aimTarget = nil end
end)

-- 10. Телепорт к игроку
local tpCard = makeCard(10, 126)
new("TextLabel", {
	Position = UDim2.new(0, 0, 0, 10),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Text = "Телепорт",
	TextColor3 = PALETTE.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamMedium,
	TextSize = 17,
	ZIndex = 13,
	Parent = tpCard,
})

local pickButton = new("TextButton", {
	Position = UDim2.new(0, 0, 0, 34),
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = PALETTE.deep,
	BackgroundTransparency = 0.3,
	Text = "Выбрать игрока",
	TextColor3 = PALETTE.white,
	Font = Enum.Font.Gotham,
	TextSize = 15,
	AutoButtonColor = false,
	ZIndex = 13,
	Parent = tpCard,
})
corner(10, pickButton)
stroke(1, PALETTE.white, 0.5, pickButton)

local tpButton = new("TextButton", {
	Position = UDim2.new(0, 0, 0, 78),
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = PALETTE.accent,
	BackgroundTransparency = 0.15,
	Text = "Телепортироваться",
	TextColor3 = PALETTE.white,
	Font = Enum.Font.GothamMedium,
	TextSize = 15,
	AutoButtonColor = false,
	ZIndex = 13,
	Parent = tpCard,
})
corner(10, tpButton)
stroke(1, PALETTE.white, 0.35, tpButton)

local listFrame = new("ScrollingFrame", {
	Position = UDim2.new(0, 0, 0, 78),
	Size = UDim2.new(1, 0, 0, 140),
	BackgroundColor3 = PALETTE.deep,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = PALETTE.white,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Visible = false,
	Active = true,
	ZIndex = 16,
	Parent = tpCard,
})
corner(10, listFrame)
stroke(1, PALETTE.white, 0.4, listFrame)
new("UIListLayout", { Padding = UDim.new(0, 4), Parent = listFrame })
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = listFrame })

local function closeList()
	listFrame.Visible = false
	tpCard.Size = UDim2.new(1, 0, 0, 126)
end

local function rebuildList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	local others = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then table.insert(others, other) end
	end

	if #others == 0 then
		new("TextButton", {
			Size = UDim2.new(1, -8, 0, 34),
			Position = UDim2.fromOffset(4, 0),
			BackgroundTransparency = 1,
			Text = "На сервере больше никого",
			TextColor3 = PALETTE.haze,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			AutoButtonColor = false,
			ZIndex = 17,
			Parent = listFrame,
		})
		return
	end

	for _, other in ipairs(others) do
		local entry = new("TextButton", {
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundColor3 = PALETTE.white,
			BackgroundTransparency = 0.88,
			Text = string.format("  %s  (@%s)", other.DisplayName, other.Name),
			TextColor3 = PALETTE.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			AutoButtonColor = false,
			ZIndex = 17,
			Parent = listFrame,
		})
		corner(8, entry)

		entry.Activated:Connect(function()
			state.tpTarget = other
			pickButton.Text = other.DisplayName
			closeList()
		end)
	end
end

pickButton.Activated:Connect(function()
	if listFrame.Visible then
		closeList()
	else
		rebuildList()
		listFrame.Visible = true
		tpCard.Size = UDim2.new(1, 0, 0, 228)
	end
end)

Players.PlayerAdded:Connect(function()
	if listFrame.Visible then rebuildList() end
end)

Players.PlayerRemoving:Connect(function(leaving)
	if state.tpTarget == leaving then
		state.tpTarget = nil
		pickButton.Text = "Выбрать игрока"
	end
	if listFrame.Visible then task.defer(rebuildList) end
end)

local function flashButton(text)
	local original = tpButton.Text
	tpButton.Text = text
	task.delay(1.2, function()
		if tpButton.Text == text then tpButton.Text = original end
	end)
end

tpButton.Activated:Connect(function()
	local target = state.tpTarget
	if not target then
		flashButton("Сначала выбери игрока")
		return
	end

	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local myRoot = getRoot()

	if not targetRoot then
		flashButton("Игрок не заспавнен")
		return
	end
	if not myRoot then
		flashButton("Нет персонажа")
		return
	end

	myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 4)
	flashButton("Готово")
end)

-- 11. Телепорт по тапу
local tapCard = makeCard(11, 58)
makeToggle(tapCard, "Телепорт по тапу", "Тап по миру — прыжок в точку", function(on)
	state.tapTp = on
end)

-- 12. Размер интерфейса
local sizeCard = makeCard(12, 92)
new("TextLabel", {
	Position = UDim2.new(0, 0, 0, 10),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Text = "Размер панели",
	TextColor3 = PALETTE.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamMedium,
	TextSize = 17,
	ZIndex = 13,
	Parent = sizeCard,
})
makeSlider(sizeCard, 36, "Масштаб: %d%%", 70, 160, 70, function(value)
	uiScale.Scale = value / 100
end)

--==============================================================
-- ПЕРЕТАСКИВАНИЕ ПАНЕЛИ
--==============================================================
local dragging, dragStart, startPos = false, nil, nil

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	local moving = input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseMovement

	if not moving then return end

	if activeSlider then
		activeSlider(input.Position.X)
	elseif dragging then
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		if dragging then panelHome = panel.Position end
		dragging = false
		activeSlider = nil
	end
end)

--==============================================================
-- ПЛАВНОЕ ОТКРЫТИЕ И СКРЫТИЕ
--==============================================================
local FADE = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RISE = UDim2.fromOffset(0, 14)

panelHome = panel.Position
local launcherStroke = launcher:FindFirstChildOfClass("UIStroke")
local panelOpen = false

local function showLauncher(show)
	if show then launcher.Visible = true end
	TweenService:Create(launcher, FADE, {
		BackgroundTransparency = show and 0 or 1,
		TextTransparency = show and 0 or 1,
	}):Play()
	TweenService:Create(launcherStroke, FADE, { Transparency = show and 0.15 or 1 }):Play()
	if not show then
		task.delay(0.24, function()
			if panelOpen then launcher.Visible = false end
		end)
	end
end

local function openPanel()
	panelOpen = true
	panel.Position = panelHome + RISE
	panel.GroupTransparency = 1
	panel.Visible = true
	TweenService:Create(panel, FADE, { GroupTransparency = 0, Position = panelHome }):Play()
	showLauncher(false)
end

local function closePanel()
	panelOpen = false
	panelHome = panel.Position
	local tween = TweenService:Create(panel, FADE, {
		GroupTransparency = 1,
		Position = panelHome + RISE,
	})
	tween.Completed:Connect(function()
		if not panelOpen then
			panel.Visible = false
			panel.Position = panelHome
		end
	end)
	tween:Play()
	showLauncher(true)
end

hideBtn.Activated:Connect(closePanel)
launcher.Activated:Connect(openPanel)

launcher.BackgroundTransparency = 1
launcher.TextTransparency = 1
launcherStroke.Transparency = 1
openPanel()

--==============================================================
-- РЕСПАВН
--==============================================================
player.CharacterAdded:Connect(function(char)
	char:WaitForChild("Humanoid")
	task.wait(0.5)
	if state.speed then
		local hum = getHumanoid()
		if hum then hum.WalkSpeed = state.speedValue end
	end
	if state.fly then startFly() end
	if state.esp then scanEsp() end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then camera = Workspace.CurrentCamera end
end)
