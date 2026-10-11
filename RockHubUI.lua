-- RockHubUI: standalone UI extracted from the original Rock Hub interface.
-- No external modules required. See RockHubUI.example.lua and RockHubUI.md.
local Library = { Version = "1.0.0" }
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

function Library:CreateWindow(options)
options = options or {}
local player = Players.LocalPlayer
assert(player, "RockHubUI requires a local client")
local window = { Destroyed = false, Controls = {} }
local connections, ownedValues, activeTweens = {}, {}, {}
local popupClosers, registry, actions, config = {}, {}, {}, {}
local keyListener, keyCaptureCancel
local keybinds = {}
local presentation = { toggles = {} }
local locale = {
    translate = function(text) return text end,
    lower = string.lower,
    onChanged = function() end,
}
local theme = options.Theme or {}
local bgColor = theme.Background or Color3.fromRGB(14, 14, 14)
local panelColor = theme.Panel or Color3.fromRGB(20, 20, 20)
local elemColor = theme.Element or Color3.fromRGB(27, 27, 27)
local hoverColor = theme.Hover or Color3.fromRGB(36, 36, 36)
local strokeColor = theme.Stroke or Color3.fromRGB(42, 42, 42)
local textColor = theme.Text or Color3.fromRGB(230, 230, 230)
local dimColor = theme.Dim or Color3.fromRGB(120, 120, 120)
local mutedColor = theme.Muted or Color3.fromRGB(85, 85, 85)
local accentColor = theme.Accent or Color3.fromRGB(255, 255, 255)

local function connect(signal, callback)
    local connection = signal:Connect(function(...)
        if not window.Destroyed then callback(...) end
    end)
    connections[connection] = true
    return connection
end
local function connectOnce(signal, callback)
    local connection
    connection = signal:Once(function(...)
        connections[connection] = nil
        if not window.Destroyed then callback(...) end
    end)
    connections[connection] = true
    return connection
end
local function spawnCallback(callback, ...)
    if not callback or window.Destroyed then return end
    local args = table.pack(...)
    task.spawn(function()
        if window.Destroyed then return end
        local ok, err = pcall(callback, table.unpack(args, 1, args.n))
        if not ok then warn("[RockHubUI callback] " .. tostring(err)) end
    end)
end
local function trackTween(tw)
    activeTweens[tw] = true
    connectOnce(tw.Completed, function() activeTweens[tw] = nil end)
end
local function create(className, props)
    assert(not window.Destroyed, "RockHubUI window is destroyed")
    local inst = Instance.new(className)
    local parent = props.Parent
    for k, v in pairs(props) do
        if k ~= "Parent" and k ~= "Localize" then inst[k] = v end
    end
    inst.Parent = parent
    return inst
end
local function configKey(sec, name)
    return (sec.configTab or sec.tab.name) .. "/" .. (sec.configName or sec.name) .. "/" .. (sec.configItemName or name)
end
local function register(key, set, get, default)
    registry[key] = { set = set, get = get, default = default }
    config[key] = default
end
local function registerAction(key, label, kind, invoke, get)
    actions[key] = { invoke = invoke, get = get, kind = kind, label = label }
end
local function setConfig(key, value) config[key] = value end
local function addCorner(inst, r)
	create("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = inst })
end

local function makeRound(inst)
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = inst })
end

local function addStroke(inst, color)
	return create("UIStroke", {
		Color = color or strokeColor,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function tween(inst, t, props, dir, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	trackTween(tw)
	tw:Play()
	return tw
end

local function ownedValue(value)
	local inst = Instance.new("NumberValue")
	inst.Value = value or 0
	table.insert(ownedValues, inst)
	return inst
end

local gradients = {}

local function addGradient(target)
	local gradient = create("UIGradient", { Parent = target })
	table.insert(gradients, gradient)
	return gradient
end

local function shimmerSeq(t)
	local kps = {}
	for i = 0, 8 do
		local x = i / 8
		local v = 0.5 + 0.5 * math.sin((x - t) * math.pi * 2)
		local c = math.floor(80 + v * 175)
		kps[#kps + 1] = ColorSequenceKeypoint.new(x, Color3.fromRGB(c, c, c))
	end
	return ColorSequence.new(kps)
end

local function line(parent, x1, y1, x2, y2, th, color)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local f = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.fromOffset(len + th * 0.6, th),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color or dimColor,
		BorderSizePixel = 0,
		Parent = parent,
	})
	makeRound(f)
	return f
end

local function dot(parent, x, y, size)
	local f = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = dimColor,
		BorderSizePixel = 0,
		Parent = parent,
	})
	makeRound(f)
	return f
end

local function createIcon(kind, parent)
	local holder = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = parent,
	})
	local scale = create("UIScale", { Parent = holder })
	local parts = {}

	local function add(inst, prop)
		table.insert(parts, { inst, prop })
	end

	if kind == "move" then
		add(dot(holder, 11.5, 2.8, 4.6), "BackgroundColor3")
		local lines = {
			{ 10, 6, 8, 11 },
			{ 9.6, 7, 12.6, 9 },
			{ 12.6, 9, 15, 7.4 },
			{ 9.6, 7, 6.6, 8.6 },
			{ 6.6, 8.6, 4.6, 7 },
			{ 8, 11, 11, 13.4 },
			{ 11, 13.4, 10.6, 17 },
			{ 8, 11, 6, 14 },
			{ 6, 14, 2.6, 15 },
		}
		for _, s in ipairs(lines) do
			add(line(holder, s[1], s[2], s[3], s[4], 2), "BackgroundColor3")
		end
	elseif kind == "eye" then
		local eye = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(16, 10),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(eye)
		add(create("UIStroke", { Color = dimColor, Thickness = 1.6, Parent = eye }), "Color")
		add(dot(holder, 9, 9, 5), "BackgroundColor3")
	elseif kind == "wing" then
		add(dot(holder, 3, 15, 3.4), "BackgroundColor3")
		local lines = { { 3, 15, 9, 3 }, { 9, 3, 16.5, 5 }, { 7.4, 6.4, 15.5, 9.6 }, { 5.6, 9.8, 13, 14.2 } }
		for _, s in ipairs(lines) do
			add(line(holder, s[1], s[2], s[3], s[4], 1.8), "BackgroundColor3")
		end
	elseif kind == "sliders" then
		local rows = { { 4, 6 }, { 9, 12 }, { 14, 8 } }
		for _, r in ipairs(rows) do
			add(line(holder, 2, r[1], 16, r[1], 1.6), "BackgroundColor3")
			add(dot(holder, r[2], r[1], 5), "BackgroundColor3")
		end
	elseif kind == "star" then
		add(line(holder, 9, 1.5, 9, 16.5, 2), "BackgroundColor3")
		add(line(holder, 1.5, 9, 16.5, 9, 2), "BackgroundColor3")
		add(line(holder, 5, 5, 13, 13, 1.4), "BackgroundColor3")
		add(line(holder, 13, 5, 5, 13, 1.4), "BackgroundColor3")
		add(dot(holder, 9, 9, 5), "BackgroundColor3")
	elseif kind == "gear" then
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(ring)
		add(create("UIStroke", { Color = dimColor, Thickness = 2.6, Parent = ring }), "Color")
		for i = 0, 7 do
			local a = math.rad(i * 45)
			add(line(holder, 9 + math.cos(a) * 5.5, 9 + math.sin(a) * 5.5, 9 + math.cos(a) * 8, 9 + math.sin(a) * 8, 3), "BackgroundColor3")
		end
	elseif kind == "target" then
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(ring)
		add(create("UIStroke", { Color = dimColor, Thickness = 1.6, Parent = ring }), "Color")
		add(line(holder, 9, 0.5, 9, 4.5, 1.6), "BackgroundColor3")
		add(line(holder, 9, 13.5, 9, 17.5, 1.6), "BackgroundColor3")
		add(line(holder, 0.5, 9, 4.5, 9, 1.6), "BackgroundColor3")
		add(line(holder, 13.5, 9, 17.5, 9, 1.6), "BackgroundColor3")
		add(dot(holder, 9, 9, 3), "BackgroundColor3")
	elseif kind == "cart" then
		local lines = {
			{ 1, 3, 4, 3 },
			{ 4, 3, 6.2, 11.5 },
			{ 4.8, 5.5, 16.5, 5.5 },
			{ 16.5, 5.5, 14.8, 11.5 },
			{ 6.2, 11.5, 14.8, 11.5 },
			{ 5.5, 8.5, 15.8, 8.5 },
		}
		for _, s in ipairs(lines) do
			add(line(holder, s[1], s[2], s[3], s[4], 1.7), "BackgroundColor3")
		end
		add(dot(holder, 7.2, 15, 3.2), "BackgroundColor3")
		add(dot(holder, 13.8, 15, 3.2), "BackgroundColor3")
	elseif kind == "pin" then
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 7),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(ring)
		add(create("UIStroke", { Color = dimColor, Thickness = 1.8, Parent = ring }), "Color")
		add(line(holder, 4.8, 9.6, 9, 16.5, 1.8), "BackgroundColor3")
		add(line(holder, 13.2, 9.6, 9, 16.5, 1.8), "BackgroundColor3")
		add(dot(holder, 9, 7, 3), "BackgroundColor3")
	elseif kind == "smile" then
		add(dot(holder, 5.5, 6, 3.4), "BackgroundColor3")
		add(dot(holder, 12.5, 6, 3.4), "BackgroundColor3")
		add(line(holder, 4, 11, 6.8, 13.8, 2), "BackgroundColor3")
		add(line(holder, 6.8, 13.8, 11.2, 13.8, 2), "BackgroundColor3")
		add(line(holder, 11.2, 13.8, 14, 11, 2), "BackgroundColor3")
	elseif kind == "bolt" then
		add(line(holder, 12, 1.5, 5.5, 10, 2.4), "BackgroundColor3")
		add(line(holder, 5.5, 10, 12.5, 8, 2.4), "BackgroundColor3")
		add(line(holder, 12.5, 8, 6, 16.5, 2.4), "BackgroundColor3")
	elseif kind == "globe" then
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(ring)
		add(create("UIStroke", { Color = dimColor, Thickness = 1.5, Parent = ring }), "Color")
		local meridian = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(7, 16),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		makeRound(meridian)
		add(create("UIStroke", { Color = dimColor, Thickness = 1.3, Parent = meridian }), "Color")
		add(line(holder, 1.5, 9, 16.5, 9, 1.3), "BackgroundColor3")
		add(line(holder, 3, 5, 15, 5, 1.1), "BackgroundColor3")
		add(line(holder, 3, 13, 15, 13, 1.1), "BackgroundColor3")
	elseif kind == "drone" then
		for _, c in ipairs({ { 4, 4 }, { 14, 4 }, { 4, 14 }, { 14, 14 } }) do
			add(line(holder, 9, 9, c[1], c[2], 1.8), "BackgroundColor3")
			local r = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(c[1], c[2]),
				Size = UDim2.fromOffset(6, 6),
				BackgroundTransparency = 1,
				Parent = holder,
			})
			makeRound(r)
			add(create("UIStroke", { Color = dimColor, Thickness = 1.4, Parent = r }), "Color")
		end
		add(dot(holder, 9, 9, 5), "BackgroundColor3")
	elseif kind == "grid" then
		for _, p in ipairs({ { 4.5, 4.5 }, { 13.5, 4.5 }, { 4.5, 13.5 }, { 13.5, 13.5 } }) do
			local sq = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(p[1], p[2]),
				Size = UDim2.fromOffset(6.5, 6.5),
				BackgroundColor3 = dimColor,
				BorderSizePixel = 0,
				Parent = holder,
			})
			addCorner(sq, 2)
			add(sq, "BackgroundColor3")
		end
	end
	local icon = {}

	icon.color = function(c, t)
		for _, p in ipairs(parts) do
			tween(p[1], t or 0.2, { [p[2]] = c })
		end
	end

	icon.pop = function()
		scale.Scale = 0.7
		tween(scale, 0.35, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
	end

	return icon
end


local gui = create("ScreenGui", {
	Name = options.Name or "RockHubUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
})
local parented = false
if options.Parent then gui.Parent = options.Parent parented = true end
if not parented and gethui then
	parented = pcall(function()
		gui.Parent = gethui()
	end)
end
if not parented then
	parented = pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end)
end
if not parented then
	gui.Parent = player:WaitForChild("PlayerGui")
end
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ClipToDeviceSafeArea = true
end)


local main = create("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(680, 470),
	BackgroundColor3 = bgColor,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})
addCorner(main, 10)
local mainStroke = create("UIStroke", { Thickness = 1, Color = accentColor, Transparency = 0.3, Parent = main })
addGradient(mainStroke)
local mainScale = create("UIScale", { Scale = 0, Parent = main })
local menuOpen = false
local responsiveScale = 1
local viewportConnection
local updateWatermarkResponsive

local function updateResponsiveScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local viewport = cam.ViewportSize
	local topLeft, bottomRight = Vector2.zero, Vector2.zero
	pcall(function()
		topLeft, bottomRight = GuiService:GetGuiInset()
	end)
	local margin = UserInputService.TouchEnabled and 16 or 24
	local availableWidth = math.max(1, viewport.X - topLeft.X - bottomRight.X - margin)
	local availableHeight = math.max(1, viewport.Y - topLeft.Y - bottomRight.Y - margin)
	responsiveScale = math.clamp(math.min(availableWidth / 680, availableHeight / 470), 0.35, 1)
	if UserInputService.TouchEnabled then
		main.Position = UDim2.fromScale(0.5, 0.5)
	end
	if menuOpen then
		mainScale.Scale = responsiveScale
	end
	if updateWatermarkResponsive then
		updateWatermarkResponsive()
	end
end

local function bindViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConnection = connect(cam:GetPropertyChangedSignal("ViewportSize"), updateResponsiveScale)
	end
	updateResponsiveScale()
end

connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindViewport)
connect(gui:GetPropertyChangedSignal("AbsoluteSize"), updateResponsiveScale)
bindViewport()
local topBar = create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Parent = main })
local logo = create("TextLabel", {
	Text = options.Title or "Rock Hub",
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = accentColor,
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(0, 205, 1, 0),
	Parent = topBar,
})
addGradient(logo)
create("TextLabel", {
	Text = options.Version or "UI",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = dimColor,
	TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(219, 1),
	Size = UDim2.new(0, 40, 1, 0),
	Parent = topBar,
})
local closeBtn = create("TextButton", {
	Text = "x",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = dimColor,
	BackgroundColor3 = elemColor,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(24, 24),
	Parent = topBar,
})
addCorner(closeBtn, 6)
connect(closeBtn.MouseEnter, function()
	tween(closeBtn, 0.15, { TextColor3 = accentColor, BackgroundTransparency = 0 })
end)
connect(closeBtn.MouseLeave, function()
	tween(closeBtn, 0.15, { TextColor3 = dimColor, BackgroundTransparency = 1 })
end)
local headerLine = create("Frame", {
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = accentColor,
	BorderSizePixel = 0,
	Parent = main,
})
addGradient(headerLine)
local tabY = 10
local layoutOrder = 0
local sidebar = create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 39),
	Size = UDim2.new(0, 170, 1, -39),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ElasticBehavior = Enum.ElasticBehavior.Never,
	ScrollingEnabled = true,
	Active = true,
	ClipsDescendants = true,
	CanvasSize = UDim2.new(),
	Parent = main,
})
local tabSelector = create("Frame", {
	Position = UDim2.fromOffset(8, 10),
	Size = UDim2.new(1, -16, 0, 32),
	BackgroundColor3 = accentColor,
	BorderSizePixel = 0,
	ZIndex = 1,
	Parent = sidebar,
})
addCorner(tabSelector, 8)
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(105, 105, 105), Color3.fromRGB(62, 62, 62)),
	Parent = tabSelector,
})
local selectorStroke = create("UIStroke", {
	Color = accentColor,
	Thickness = 1,
	Transparency = 0.75,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = tabSelector,
})
local sweepGradient = create("UIGradient", { Parent = selectorStroke })
local solidSeq = NumberSequence.new(0)
local sweepSeq = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(0.85, 0.2),
	NumberSequenceKeypoint.new(1, 0),
})
local sweepId = 0
local sweepTween

local function playSweep()
	sweepId += 1
	local id = sweepId
	if sweepTween then
		sweepTween:Cancel()
	end
	sweepGradient.Transparency = sweepSeq
	sweepGradient.Rotation = -90
	sweepTween = tween(sweepGradient, 0.5, { Rotation = 270 }, Enum.EasingDirection.InOut, Enum.EasingStyle.Sine)
	connectOnce(sweepTween.Completed, function(state)
		if id ~= sweepId or state ~= Enum.PlaybackState.Completed then
			return
		end
		sweepGradient.Transparency = solidSeq
		selectorStroke.Transparency = 0.4
		tween(selectorStroke, 0.4, { Transparency = 0.75 })
	end)
end

local tabList = create("Frame", {
	Position = UDim2.fromOffset(8, 10),
	Size = UDim2.new(1, -16, 1, -10),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = sidebar,
})
local tabLayout = create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabList })

local function updateSidebarCanvas()
	-- tabY uses unscaled layout units; AbsoluteContentSize shrinks with UIScale on phones.
	local contentHeight = math.max(0, tabY - 13)
	tabList.Size = UDim2.new(1, -16, 0, contentHeight)
	sidebar.CanvasSize = UDim2.fromOffset(0, 10 + contentHeight + 24)
end

connect(tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"), updateSidebarCanvas)
create("Frame", {
	Position = UDim2.fromOffset(170, 39),
	Size = UDim2.new(0, 1, 1, -39),
	BackgroundColor3 = strokeColor,
	BorderSizePixel = 0,
	Parent = main,
})
sidebar.ZIndex = 5
local content = create("Frame", {
	Position = UDim2.fromOffset(184, 50),
	Size = UDim2.new(1, -196, 1, -60),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 1,
	Parent = main,
})
local fadeOverlay = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = bgColor,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 50,
	Parent = content,
})
local fadeTween
local tabs = {}
local currentTab

local function selectTab(tab)
	if keyCaptureCancel then keyCaptureCancel() end
	if currentTab == tab then
		return
	end
	local old = currentTab
	currentTab = tab
	for _, t in ipairs(tabs) do
		if t ~= tab then
			t.page.Visible = false
		end
	end
	local y = tab.y
	if old then
		tween(tabSelector, 0.3, { Position = UDim2.fromOffset(8, y) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
	else
		tabSelector.Position = UDim2.fromOffset(8, y)
	end
	playSweep()
	if old then
		tween(old.label, 0.2, { TextColor3 = dimColor })
		old.label.Font = Enum.Font.GothamMedium
		old.icon.color(dimColor)
		old.chev(false)
	end
	tween(tab.label, 0.2, { TextColor3 = accentColor })
	tab.label.Font = Enum.Font.GothamBold
	tab.icon.color(accentColor)
	tab.icon.pop()
	tab.chev(true)
	tab.page.CanvasPosition = Vector2.zero
	tab.page.Position = UDim2.fromOffset(0, 14)
	tab.page.Visible = true
	tween(tab.page, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
	if fadeTween then
		fadeTween:Cancel()
	end
	fadeOverlay.BackgroundTransparency = 0
	fadeTween = tween(fadeOverlay, 0.3, { BackgroundTransparency = 1 })
end


	local searchTerms

	local function matchesSearch(item, s, tab)
		local key = item.key .. " " .. s.name:lower() .. " " .. (s.group or ""):lower() .. " " .. tab.name:lower()
		key ..= " " .. locale.translate(item.name):lower() .. " " .. locale.translate(item.desc or ""):lower()
			.. " " .. locale.translate(s.name):lower() .. " " .. locale.translate(tab.name):lower()
		key = locale.lower(key)
		for _, w in ipairs(searchTerms) do
			if not key:find(w, 1, true) then
				return false
			end
		end
		return true
	end

	local function layoutTab(tab)
		if tab.custom then
			return
		end
		local y = tab.contentY or 46
		if searchTerms then
			for _, s in ipairs(tab.sections) do
				local rowY = 30
				local any = false
				for _, item in ipairs(s.items) do
					local ok = matchesSearch(item, s, tab)
					item.row.Visible = ok
					if ok then
						item.row.Position = UDim2.fromOffset(8, rowY)
						rowY += item.h + 6
						any = true
					end
				end
				s.card.Visible = any
				if any then
					local h = rowY + 8 - 6
					s.card.Position = UDim2.fromOffset(2, y)
					s.card.Size = UDim2.new(1, -8, 0, h)
					y += h + 10
				end
			end
			tab.page.CanvasSize = UDim2.fromOffset(0, y - 10 + 2 + 4)
			return
		end
		for _, s in ipairs(tab.sections) do
			local shown = not tab.subs or s.group == tab.sub
			local expanded = not s.collapsible or s.isOpen or s.open > 0.001
			for _, item in ipairs(s.items) do
				item.row.Position = UDim2.fromOffset(8, item.y)
				item.row.Visible = expanded
			end
			local h = s.height
			if s.collapsible then
				h = math.floor(30 + (s.height - 30) * s.open + 0.5)
			end
			s.card.Visible = shown
			if shown then
				s.card.Position = UDim2.fromOffset(2, y)
				s.card.Size = UDim2.new(1, -8, 0, h)
				y += h + 10
			end
		end
		tab.page.CanvasSize = UDim2.fromOffset(0, y - 10 + 2 + 4)
	end

	local function addSeparator(label)
		layoutOrder += 1
		local height = label and 18 or 9
		local holder = create("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			LayoutOrder = layoutOrder,
			Parent = tabList,
		})
		if label then
			create("TextLabel", {
				Text = string.upper(label), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = mutedColor,
				TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
				Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), Parent = holder,
			})
		else
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 4, 0, 1),
				BackgroundColor3 = strokeColor,
				BorderSizePixel = 0,
				Parent = holder,
			})
		end
		tabY += height + 3
		updateSidebarCanvas()
	end

	local function addTab(name, iconName, desc)
		local index = #tabs + 1
		layoutOrder += 1
		local y = tabY
		tabY += 35
		updateSidebarCanvas()
		local tabBtn = create("TextButton", {
			Text = "",
			BackgroundColor3 = elemColor,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = layoutOrder,
			Parent = tabList,
		})
		addCorner(tabBtn, 7)
		local icon = createIcon(iconName, tabBtn)
			local label = create("TextLabel", {
			Text = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = dimColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -60, 1, 0),
			ZIndex = 3,
			Parent = tabBtn,
		})
		local chevron = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(6, 10),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = tabBtn,
		})
		local chevTop = line(chevron, 1, 1.5, 4.5, 5, 1.5, mutedColor)
		local chevBottom = line(chevron, 4.5, 5, 1, 8.5, 1.5, mutedColor)
		chevTop.ZIndex, chevBottom.ZIndex = 3, 3

		local function setChevron(on)
			tween(chevron, 0.3, { Rotation = on and 90 or 0 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			tween(chevTop, 0.2, { BackgroundColor3 = on and accentColor or mutedColor })
			tween(chevBottom, 0.2, { BackgroundColor3 = on and accentColor or mutedColor })
		end

		local page = create("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = dimColor,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollBarImageTransparency = 0.4,
			ClipsDescendants = true,
			Visible = false,
			ZIndex = 1,
			Parent = content,
		})
		local pageTitle = create("TextLabel", {
			Text = name,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = accentColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 22),
			Parent = page,
		})
		local pageDesc = create("TextLabel", {
			Text = desc or "",
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = dimColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, -8, 0, 16),
			Parent = page,
		})
		local tab = {
			name = name,
			index = index,
			y = y,
			btn = tabBtn,
			label = label,
			icon = icon,
			chev = setChevron,
			page = page,
			sections = {},
			title = pageTitle,
			desc = pageDesc,
		}
		table.insert(tabs, tab)
		connect(tabBtn.MouseButton1Click, function()
			selectTab(tab)
		end)
		connect(tabBtn.MouseEnter, function()
			if currentTab ~= tab then
				tween(label, 0.15, { TextColor3 = textColor })
				icon.color(textColor, 0.15)
			end
		end)
		connect(tabBtn.MouseLeave, function()
			if currentTab ~= tab then
				tween(label, 0.15, { TextColor3 = dimColor })
				icon.color(dimColor, 0.15)
			end
		end)
		return tab
	end

	local Section = {}
	Section.__index = Section

	local function addSection(tab, name, group, priority)
		local card = create("Frame", { BackgroundColor3 = panelColor, Parent = tab.page })
		addCorner(card, 10)
		local stroke = addStroke(card)
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(accentColor, Color3.fromRGB(190, 190, 190)),
			Parent = card,
		})
		local highlight = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0, 15),
			Size = UDim2.fromOffset(3, 12),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Parent = card,
		})
		makeRound(highlight)
		addGradient(highlight)
		create("TextLabel", {
			Text = string.upper(name),
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -34, 0, 30),
			Parent = card,
		})
		connect(card.MouseEnter, function()
			tween(stroke, 0.2, { Color = Color3.fromRGB(56, 56, 56) })
		end)
		connect(card.MouseLeave, function()
			tween(stroke, 0.2, { Color = strokeColor })
		end)
		local s = setmetatable({
			tab = tab,
			card = card,
			name = name,
			items = {},
			y = 30,
			height = 32,
			rows = {},
			open = 1,
			group = group or tab.subs and tab.subs[1],
			priority = priority or 100,
			creationIndex = #tab.sections + 1,
		}, Section)
		table.insert(tab.sections, s)
		table.sort(tab.sections, function(a, b)
			local ag = tab.subs and (table.find(tab.subs, a.group) or math.huge) or 1
			local bg = tab.subs and (table.find(tab.subs, b.group) or math.huge) or 1
			if ag ~= bg then return ag < bg end
			if a.priority ~= b.priority then return a.priority < b.priority end
			return a.creationIndex < b.creationIndex
		end)
		layoutTab(tab)
		return s
	end

	local function setSubTabs(tab, items)
		tab.subs = items
		tab.sub = items[1]
		local cur = 1
		local titleW = TextService:GetTextSize(tab.title.Text, 18, Enum.Font.GothamBold, Vector2.new(400, 40)).X
		tab.desc.Visible = false
		tab.title.Size = UDim2.fromOffset(titleW + 4, 40)
		local bar = create("Frame", {
			Position = UDim2.fromOffset(titleW + 16, 6),
			Size = UDim2.new(1, -(titleW + 16) - 8, 0, 28),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = tab.page,
		})
		local subButtons = {}
		local x = 0
		for i, sub in ipairs(items) do
			local tw = TextService:GetTextSize(sub, 12, Enum.Font.GothamMedium, Vector2.new(300, 40)).X
			local w = tw + 34
			local b = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromRGB(90, 90, 90),
				BackgroundTransparency = i == cur and 0.35 or 1,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(w, 28),
				ZIndex = 3,
				Parent = bar,
			})
			addCorner(b, 9)
			local pip = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 13, 0.5, 0),
				Size = UDim2.fromOffset(i == cur and 6 or 0, i == cur and 6 or 0),
				BackgroundColor3 = accentColor,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = b,
			})
			makeRound(pip)
			local lbl = create("TextLabel", {
				Text = sub,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = i == cur and accentColor or dimColor,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(i == cur and 22 or 12, 0),
				Size = UDim2.new(1, -22, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 4,
				Parent = b,
			})
			subButtons[i] = { b = b, dot = pip, lbl = lbl, w = w }
			x += w + 4
		end
		local function arrangeSubTabs()
			titleW = TextService:GetTextSize(tab.title.Text, 18, Enum.Font.GothamBold, Vector2.new(400, 40)).X
			for index, button in ipairs(subButtons) do
				button.w = TextService:GetTextSize(locale.translate(items[index]), 12, Enum.Font.GothamMedium, Vector2.new(400, 40)).X + 34
			end
			x = 0
			for _, button in ipairs(subButtons) do x += button.w + 4 end
			local width = math.max(120, main.Size.X.Offset - 204)
			local inline = titleW + 16 + x - 4 <= width
			local startX = inline and titleW + 16 or 0
			local available = width - startX
			local rowX, rowY = 0, 0
			for _, button in ipairs(subButtons) do
				local w = math.min(button.w, available)
				if rowX > 0 and rowX + w > available then rowX, rowY = 0, rowY + 34 end
				button.b.Position = UDim2.fromOffset(rowX, rowY)
				button.b.Size = UDim2.fromOffset(w, 28)
				rowX += w + 4
			end
			bar.Position = UDim2.fromOffset(startX, inline and 6 or 34)
			bar.Size = UDim2.new(1, -startX - 8, 0, rowY + 28)
			tab.title.Size = inline and UDim2.fromOffset(titleW + 4, 40) or UDim2.new(1, -8, 0, 22)
			tab.contentY = inline and 46 or 74 + rowY
			layoutTab(tab)
		end
		arrangeSubTabs()
		locale.onChanged(arrangeSubTabs)
		connect(main:GetPropertyChangedSignal("Size"), arrangeSubTabs)

		local function refresh(i, on)
			local o = subButtons[i]
			tween(o.b, 0.25, { BackgroundTransparency = on and 0.35 or 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(o.dot, 0.25, { Size = UDim2.fromOffset(on and 6 or 0, on and 6 or 0) }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			tween(o.lbl, 0.25, { TextColor3 = on and accentColor or dimColor, Position = UDim2.fromOffset(on and 22 or 12, 0) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
		end

		local function relayout(anim)
			layoutTab(tab)
			if anim then
				tab.page.CanvasPosition = Vector2.zero
				tab.page.Position = UDim2.fromOffset(0, 14)
				tween(tab.page, 0.35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
				if fadeTween then
					fadeTween:Cancel()
				end
				fadeOverlay.BackgroundTransparency = 0
				fadeTween = tween(fadeOverlay, 0.3, { BackgroundTransparency = 1 })
			end
		end

		local function set(i)
			if i == cur then
				return
			end
			if keyCaptureCancel then keyCaptureCancel() end
			refresh(cur, false)
			cur = i
			tab.sub = items[i]
			refresh(i, true)
			relayout(true)
		end

		tab.setSub = function(sub)
			local i = table.find(items, sub)
			if i then
				set(i)
			end
		end

		for i, o in ipairs(subButtons) do
			connect(o.b.MouseEnter, function()
				if i ~= cur then
					tween(o.b, 0.15, { BackgroundTransparency = 0.8 })
					tween(o.lbl, 0.15, { TextColor3 = textColor })
				end
			end)
			connect(o.b.MouseLeave, function()
				if i ~= cur then
					tween(o.b, 0.15, { BackgroundTransparency = 1 })
					tween(o.lbl, 0.15, { TextColor3 = dimColor })
				end
			end)
			connect(o.b.MouseButton1Click, function()
				set(i)
			end)
		end
		layoutTab(tab)
	end

	Section.Collapsible = function(self2, startOpen)
		self2.collapsible = true
		self2.isOpen = startOpen and true or false
		self2.open = self2.isOpen and 1 or 0
		self2.card.ClipsDescendants = true
		local stroke = self2.card:FindFirstChildOfClass("UIStroke")
		local headerBtn = create("TextButton", {
			Text = "",
			BackgroundColor3 = elemColor,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 30),
			ZIndex = 4,
			Parent = self2.card,
		})
		local hint = create("TextLabel", {
			Text = self2.isOpen and "hide" or "open",
			Font = Enum.Font.GothamMedium,
			TextSize = 10,
			TextColor3 = mutedColor,
			TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -30, 0, 15),
			Size = UDim2.fromOffset(40, 14),
			ZIndex = 5,
			Parent = self2.card,
		})
		local arrow = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -18, 0, 15),
			Size = UDim2.fromOffset(10, 6),
			BackgroundTransparency = 1,
			Rotation = self2.isOpen and 180 or 0,
			ZIndex = 5,
			Parent = self2.card,
		})
		local arrowL = line(arrow, 1, 1, 5, 5, 1.6)
		local arrowR = line(arrow, 5, 5, 9, 1, 1.6)
		arrowL.ZIndex, arrowR.ZIndex = 5, 5
		local anim = ownedValue()
		anim.Value = self2.open
		connect(anim.Changed, function(v)
			self2.open = v
			layoutTab(self2.tab)
		end)
		local openTween

		local function toggleCollapse()
			self2.isOpen = not self2.isOpen
			local on = self2.isOpen
			if on then
				for _, r in ipairs(self2.rows) do
					r.Visible = true
				end
			end
			if openTween then
				openTween:Cancel()
			end
			openTween = tween(anim, on and 0.4 or 0.3, { Value = on and 1 or 0 }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			connectOnce(openTween.Completed, function(st)
				if st == Enum.PlaybackState.Completed and not self2.isOpen then
					for _, r in ipairs(self2.rows) do
						r.Visible = false
					end
				end
			end)
			tween(arrow, 0.35, { Rotation = on and 180 or 0 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			hint.Text = on and "hide" or "open"
			if stroke then
				stroke.Color = accentColor
				tween(stroke, 0.5, { Color = strokeColor })
			end
		end

		connect(headerBtn.MouseButton1Click, toggleCollapse)

		self2.expand = function()
			if not self2.isOpen then
				toggleCollapse()
			end
		end

		connect(headerBtn.MouseEnter, function()
			tween(arrowL, 0.15, { BackgroundColor3 = accentColor })
			tween(arrowR, 0.15, { BackgroundColor3 = accentColor })
			tween(hint, 0.15, { TextColor3 = textColor })
		end)
		connect(headerBtn.MouseLeave, function()
			tween(arrowL, 0.15, { BackgroundColor3 = dimColor })
			tween(arrowR, 0.15, { BackgroundColor3 = dimColor })
			tween(hint, 0.15, { TextColor3 = mutedColor })
		end)
		layoutTab(self2.tab)
		return self2
	end


	local hoverStroke = Color3.fromRGB(62, 62, 62)
	local activeStroke = Color3.fromRGB(88, 88, 88)

	Section._row = function(self2, name, desc, height)
		local h = height or (desc and 40 or 32)
		local row = create("TextButton", {
			Text = "",
			BackgroundColor3 = elemColor,
			AutoButtonColor = false,
			Position = UDim2.fromOffset(8, self2.y),
			Size = UDim2.new(1, -16, 0, h),
			ClipsDescendants = true,
			Parent = self2.card,
		})
		addCorner(row, 7)
		local rowStroke = addStroke(row)
		table.insert(self2.rows, row)
		table.insert(self2.items, {
			row = row,
			y = self2.y,
			h = h,
			name = name,
			desc = desc,
			key = (name .. " " .. (desc or "")):lower(),
		})
		if self2.collapsible and not self2.isOpen then
			row.Visible = false
		end
		self2.y += h + 6
		self2.height = self2.y + 8 - 6
		layoutTab(self2.tab)
		local accent = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(2, 0),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = row,
		})
		addCorner(accent, 1)
		local logo2 = create("TextLabel", {
			Text = name,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, desc and 6 or 0),
			Size = UDim2.new(1, -150, 0, desc and 15 or h),
			Parent = row,
		})
		if desc then
			create("TextLabel", {
				Text = desc,
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextColor3 = mutedColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 21),
				Size = UDim2.new(1, -150, 0, 13),
				Parent = row,
			})
		end
		local hovered, active = false, false

		local function refresh()
			local lit = hovered or active
			tween(accent, 0.3, { Size = UDim2.fromOffset(2, active and h - 14 or (hovered and 12 or 0)) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(row, 0.15, { BackgroundColor3 = hovered and hoverColor or elemColor })
			tween(logo2, 0.2, {
				TextColor3 = lit and accentColor or textColor,
				Position = UDim2.fromOffset(hovered and 15 or 12, logo2.Position.Y.Offset),
			}, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(rowStroke, 0.2, { Color = active and activeStroke or (hovered and hoverStroke or strokeColor) })
		end

		connect(row.MouseEnter, function()
			hovered = true
			refresh()
		end)
		connect(row.MouseLeave, function()
			hovered = false
			refresh()
		end)

		local function highlight(on)
			active = on
			refresh()
		end

		return row, logo2, rowStroke, highlight
	end

	Section.Toggle = function(self2, name, desc, callback)
		local state = false
		local key = configKey(self2, name)
		presentation.toggles[key] = { key = key, tab = self2.tab.name, section = self2.name, name = name,
			get = function() return state end }
		local row, _, _, highlight = self2:_row(name, desc)
		local track = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(34, 18),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			Parent = row,
		})
		makeRound(track)
		local trackStroke = addStroke(track)
		local glow = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = accentColor,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = track,
		})
		makeRound(glow)
		create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(150, 150, 150), accentColor), Parent = glow })
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = dimColor,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = track,
		})
		makeRound(knob)

		local function apply(v, silent)
			state = v
			knob.Size = UDim2.fromOffset(18, 12)
			tween(knob, 0.35, {
				Position = UDim2.new(0, state and 25 or 9, 0.5, 0),
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = state and bgColor or dimColor,
			}, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(glow, 0.25, { BackgroundTransparency = state and 0 or 1 })
			tween(trackStroke, 0.25, { Color = state and accentColor or strokeColor })
			highlight(state)
			setConfig(key, state)
			if not silent then
				spawnCallback(callback, state)
			end
		end

		connect(row.MouseButton1Click, function()
			apply(not state)
		end)
		register(key, function(v)
			if type(v) == "boolean" and v ~= state then
				apply(v)
			end
		end, function()
			return state
		end, false)
		registerAction(key, self2.tab.name .. " / " .. self2.name .. " / " .. name, "toggle", function()
			apply(not state)
		end, function()
			return state
		end)
		return {
			Set = function(v, silent)
				if v ~= state then
					apply(v, silent)
				end
			end,
			Get = function()
				return state
			end,
		}
	end

	Section.Segmented = function(self2, name, options, default, callback, canSelect)
		local cur = table.find(options, default) or 1
		local n = #options
		local key = configKey(self2, name)
		local row, logo2 = self2:_row(name, nil, 34)
		local totalW = n * 60
		logo2.Size = UDim2.new(1, -(totalW + 24), 1, 0)
		local pill = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(totalW, 24),
			BackgroundColor3 = bgColor,
			Parent = row,
		})
		addCorner(pill, 7)
		local pillStroke = addStroke(pill)
		local thumb = create("Frame", {
			Position = UDim2.new((cur - 1) / n, 2, 0, 2),
			Size = UDim2.new(1 / n, -4, 1, -4),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = pill,
		})
		addCorner(thumb, 6)
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(accentColor, Color3.fromRGB(185, 185, 185)),
			Parent = thumb,
		})
		local thumbScale = create("UIScale", { Parent = thumb })
		local optionBtns = {}

		local function set(i, silent)
			if i == cur then
				return
			end
			if canSelect and not canSelect(options[i]) then return end
			tween(optionBtns[cur], 0.2, { TextColor3 = dimColor })
			optionBtns[cur].Font = Enum.Font.GothamMedium
			cur = i
			tween(optionBtns[i], 0.2, { TextColor3 = bgColor })
			optionBtns[i].Font = Enum.Font.GothamBold
			tween(thumb, 0.35, { Position = UDim2.new((i - 1) / n, 2, 0, 2) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			thumbScale.Scale = 0.86
			tween(thumbScale, 0.4, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			pillStroke.Color = accentColor
			tween(pillStroke, 0.45, { Color = strokeColor })
			setConfig(key, options[i])
			if not silent then
				spawnCallback(callback, options[i])
			end
		end

		register(key, function(v)
			local i = table.find(options, v)
			if i then
				set(i)
			end
		end, function()
			return options[cur]
		end, options[table.find(options, default) or 1])
		for i, opt in ipairs(options) do
			local b = create("TextButton", {
				Text = opt,
				Font = i == cur and Enum.Font.GothamBold or Enum.Font.GothamMedium,
				TextSize = 11,
				TextColor3 = i == cur and bgColor or dimColor,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Position = UDim2.fromScale((i - 1) / n, 0),
				Size = UDim2.fromScale(1 / n, 1),
				ZIndex = 3,
				Parent = pill,
			})
			optionBtns[i] = b
			connect(b.MouseEnter, function()
				if i ~= cur then
					tween(b, 0.15, { TextColor3 = textColor })
				end
			end)
			connect(b.MouseLeave, function()
				if i ~= cur then
					tween(b, 0.15, { TextColor3 = dimColor })
				end
			end)
			connect(b.MouseButton1Click, function()
				set(i)
			end)
		end
		registerAction(key, self2.tab.name .. " / " .. self2.name .. " / " .. name, "cycle", function()
			set(cur % n + 1)
		end, function()
			return options[cur]
		end)
		return {
			Set = function(opt, silent)
				local i = table.find(options, opt)
				if i then
					set(i, silent)
				end
			end,
			Get = function()
				return options[cur]
			end,
		}
	end

	Section.Button = function(self2, name, desc, callback)
		local row = self2:_row(name, desc)
		local holder = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = bgColor,
			ZIndex = 2,
			Parent = row,
		})
		makeRound(holder)
		local circleStroke = addStroke(holder)
		local circleScale = create("UIScale", { Parent = holder })
		local arrow = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 1, 0.5, 0),
			Size = UDim2.fromOffset(6, 10),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = holder,
		})
		local a1 = line(arrow, 1, 1, 5, 5, 1.6)
		local a2 = line(arrow, 5, 5, 1, 9, 1.6)
		a1.ZIndex, a2.ZIndex = 3, 3
		connect(row.MouseEnter, function()
			tween(holder, 0.2, { BackgroundColor3 = accentColor })
			tween(circleStroke, 0.2, { Color = accentColor })
			tween(a1, 0.2, { BackgroundColor3 = bgColor })
			tween(a2, 0.2, { BackgroundColor3 = bgColor })
		end)
		connect(row.MouseLeave, function()
			tween(holder, 0.2, { BackgroundColor3 = bgColor })
			tween(circleStroke, 0.2, { Color = strokeColor })
			tween(a1, 0.2, { BackgroundColor3 = dimColor })
			tween(a2, 0.2, { BackgroundColor3 = dimColor })
		end)
		local function fire()
			spawnCallback(callback)
		end
		connect(row.MouseButton1Click, function()
			local w = row.AbsoluteSize.X * 1.15
			local ripple = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = accentColor,
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				Parent = row,
			})
			makeRound(ripple)
			tween(ripple, 0.55, { Size = UDim2.fromOffset(w, w), BackgroundTransparency = 1 })
			task.delay(0.6, function()
				ripple:Destroy()
			end)
			circleScale.Scale = 0.75
			tween(circleScale, 0.4, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			fire()
		end)
		registerAction(configKey(self2, name), self2.tab.name .. " / " .. self2.name .. " / " .. name, "button", fire)
	end

	Section.Input = function(self2, name, desc, placeholder)
		local row = self2:_row(name, desc)
		local box = create("TextBox", {
			Text = "",
			PlaceholderText = placeholder or "enter text",
			PlaceholderColor3 = mutedColor,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			BackgroundColor3 = bgColor,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			Parent = row,
		})
		addCorner(box, 6)
		local outline = addStroke(box)
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box })
		connect(box.Focused, function()
			tween(outline, 0.15, { Color = accentColor })
		end)
		connect(box.FocusLost, function()
			tween(outline, 0.25, { Color = strokeColor })
		end)
		return {
			Box = box,
			Get = function()
				return box.Text
			end,
			Set = function(value)
				box.Text = tostring(value or "")
			end,
			SetPlaceholder = function(value)
				box.PlaceholderText = tostring(value or "")
			end,
			Focus = function()
				box:CaptureFocus()
			end,
		}
	end

	Section.Dropdown = function(self2, name, desc, options, placeholder, callback, localizeValues, thumbnail)
		local row = self2:_row(name, desc)
		local values = table.clone(options or {})
		local selected
		local closePopup
		local badge = create("TextButton", {
			Text = placeholder or "select...",
			Localize = false,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = dimColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundColor3 = bgColor,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			Parent = row,
		})
		addCorner(badge, 6)
		local badgeStroke = addStroke(badge)
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 20), Parent = badge })
		local arrow = create("TextLabel", {
			Text = "v",
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = mutedColor,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, -1),
			Size = UDim2.fromOffset(12, 16),
			ZIndex = 3,
			Parent = badge,
		})

		local function setSelected(value, silent)
			if value ~= nil and not table.find(values, value) then
				return
			end
			selected = value
			badge.Text = value and (localizeValues and locale.translate(value) or value) or locale.translate(placeholder or "select...")
			badge.TextColor3 = value and textColor or dimColor
			if value and not silent then
				spawnCallback(callback, value)
			end
		end
		locale.onChanged(function()
			if badge.Parent then badge.Text = selected and (localizeValues and locale.translate(selected) or selected) or locale.translate(placeholder or "select...") end
			if closePopup then closePopup() end
		end)
		badge.Text = locale.translate(placeholder or "select...")

		connect(badge.MouseButton1Click, function()
			if closePopup then
				closePopup()
				return
			end
			local backdrop = create("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 149,
				Parent = gui,
			})
			local visibleRows = math.max(1, math.min(#values, 5))
			local rowHeight, popupWidth = thumbnail and 38 or 26, thumbnail and 230 or 130
			local popupHeight = visibleRows * rowHeight + 8
			local rel = badge.AbsolutePosition - gui.AbsolutePosition
			local x = math.clamp(rel.X, 4, math.max(4, gui.AbsoluteSize.X - popupWidth - 4))
			local below = rel.Y + badge.AbsoluteSize.Y + 4
			local y = below + popupHeight <= gui.AbsoluteSize.Y - 4 and below or math.max(4, rel.Y - popupHeight - 4)
			local popup = create("Frame", {
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(popupWidth, popupHeight),
				BackgroundColor3 = panelColor,
				ZIndex = 150,
				Parent = gui,
			})
			addCorner(popup, 7)
			create("UIStroke", { Color = accentColor, Transparency = 0.45, Thickness = 1, Parent = popup })
			local list = create("ScrollingFrame", {
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -8),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = #values > 5 and 2 or 0,
				CanvasSize = UDim2.fromOffset(0, math.max(22, #values * rowHeight)),
				ZIndex = 151,
				Parent = popup,
			})
			closePopup = function()
				popupClosers[popup] = nil
				closePopup = nil
				if backdrop.Parent then
					backdrop:Destroy()
				end
				if popup.Parent then
					popup:Destroy()
				end
				tween(badgeStroke, 0.2, { Color = strokeColor })
				tween(arrow, 0.2, { Rotation = 0, TextColor3 = mutedColor })
			end
			popupClosers[popup] = closePopup
			connect(backdrop.MouseButton1Click, closePopup)
			tween(badgeStroke, 0.15, { Color = accentColor })
			tween(arrow, 0.2, { Rotation = 180, TextColor3 = accentColor })
			if #values == 0 then
				create("TextLabel", {
					Text = "no options",
					Font = Enum.Font.GothamMedium,
					TextSize = 10,
					TextColor3 = mutedColor,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 22),
					ZIndex = 152,
					Parent = list,
				})
			else
				for i, value in ipairs(values) do
					local option = create("TextButton", {
						Text = localizeValues and locale.translate(value) or value,
						Localize = false,
						Font = selected == value and Enum.Font.GothamBold or Enum.Font.GothamMedium,
						TextSize = 10,
						TextColor3 = selected == value and accentColor or textColor,
						TextTruncate = Enum.TextTruncate.AtEnd,
						BackgroundColor3 = selected == value and hoverColor or elemColor,
						AutoButtonColor = false,
						Position = UDim2.fromOffset(0, (i - 1) * rowHeight),
						Size = UDim2.new(1, -2, 0, rowHeight - 4),
						ZIndex = 152,
						Parent = list,
					})
					addCorner(option, 5)
					if thumbnail then
						option.TextXAlignment = Enum.TextXAlignment.Left
						create("UIPadding", { PaddingLeft = UDim.new(0, 52), PaddingRight = UDim.new(0, 8), Parent = option })
						local image = create("ImageLabel", { Name = "SkyboxThumbnail", Image = thumbnail(value) or "", Position = UDim2.fromOffset(-46, 3),
							Size = UDim2.fromOffset(40, rowHeight - 10), BackgroundColor3 = panelColor, BorderSizePixel = 0, ZIndex = 153, Parent = option })
						addCorner(image, 4)
					end
					connect(option.MouseButton1Click, function()
						setSelected(value)
						closePopup()
					end)
				end
			end
		end)

		return {
			Get = function()
				return selected
			end,
			Set = setSelected,
			Update = function(newOptions)
				values = table.clone(newOptions or {})
				if selected and not table.find(values, selected) then
					setSelected(nil, true)
				end
				if closePopup then
					closePopup()
				end
			end,
		}
	end

	local dragSlider

	Section.Slider = function(self2, name, min, max, default, callback, fmt)
		fmt = fmt or tostring
		local key = configKey(self2, name)
		local row, logo2 = self2:_row(name, nil, 44)
		logo2.Position = UDim2.fromOffset(12, 7)
		local valueW = 40
		for _, v in ipairs({ min, max, default }) do
			valueW = math.max(valueW, TextService:GetTextSize(fmt(v), 10, Enum.Font.GothamBold, Vector2.new(200, 20)).X + 16)
		end
		logo2.Size = UDim2.new(1, -(valueW + 30), 0, 16)
		local valueLabel = create("TextLabel", {
			Text = fmt(default),
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = textColor,
			BackgroundColor3 = bgColor,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 6),
			Size = UDim2.fromOffset(valueW, 18),
			Parent = row,
		})
		addCorner(valueLabel, 6)
		local valueStroke = addStroke(valueLabel)
		local bar = create("Frame", {
			Position = UDim2.new(0, 12, 0, 31),
			Size = UDim2.new(1, -24, 0, 5),
			BackgroundColor3 = bgColor,
			BorderSizePixel = 0,
			Parent = row,
		})
		makeRound(bar)
		addStroke(bar)
		local pct = (default - min) / (max - min)
		local fillBar = create("Frame", {
			Size = UDim2.new(pct, 6 - 12 * pct, 1, 0),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Parent = bar,
		})
		makeRound(fillBar)
		create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(95, 95, 95), accentColor), Parent = fillBar })
		local track = create("Frame", {
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = bar,
		})
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(pct, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = track,
		})
		makeRound(knob)
		create("UIStroke", { Color = elemColor, Thickness = 2, Parent = knob })
		local knobScale = create("UIScale", { Parent = knob })
		local hit = create("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 22),
			Size = UDim2.new(1, 0, 0, 22),
			ZIndex = 3,
			Parent = row,
		})
		local last = default
		local dragging = false

		local function render(val, t)
			local r = (val - min) / (max - min)
			tween(knob, t, { Position = UDim2.fromScale(r, 0.5) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(fillBar, t, { Size = UDim2.new(r, 6 - 12 * r, 1, 0) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			valueLabel.Text = fmt(val)
		end

		local function set(x)
			local w = math.max(track.AbsoluteSize.X, 1)
			local rel = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
			local val = math.floor(min + (max - min) * rel + 0.5)
			render(val, 0.08)
			if val ~= last then
				last = val
				setConfig(key, val)
				spawnCallback(callback, val)
			end
		end

		connect(row.MouseEnter, function()
			if not dragging then
				tween(knobScale, 0.2, { Scale = 1.15 })
			end
		end)
		connect(row.MouseLeave, function()
			if not dragging then
				tween(knobScale, 0.2, { Scale = 1 })
			end
		end)
		connect(hit.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragSlider = set
				dragging = true
				tween(knobScale, 0.2, { Scale = 1.35 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
				tween(valueStroke, 0.15, { Color = accentColor })
				tween(valueLabel, 0.15, { TextColor3 = accentColor })
				set(input.Position.X)
			end
		end)
		connect(UserInputService.InputEnded, function(input)
			if not dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				tween(knobScale, 0.25, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
				tween(valueStroke, 0.3, { Color = strokeColor })
				tween(valueLabel, 0.3, { TextColor3 = textColor })
			end
		end)

		local function setValue(v, silent)
			v = math.clamp(v, min, max)
			render(v, 0.3)
			if v ~= last then
				last = v
				setConfig(key, v)
				if not silent then
					spawnCallback(callback, v)
				end
			end
		end

		register(key, function(v)
			if type(v) == "number" then
				setValue(v)
			end
		end, function()
			return last
		end, default)
		return {
			Set = setValue,
			Get = function()
				return last
			end,
		}
	end

	Section.Keybind = function(self2, name, desc, getKey, setKey)
		local key = configKey(self2, name)
		local row = self2:_row(name, desc)
		local badge = create("TextLabel", {
			Text = getKey().Name,
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = textColor,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundColor3 = bgColor,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(84, 22),
			Parent = row,
		})
		addCorner(badge, 6)
		local badgeStroke = addStroke(badge)
		connect(row.MouseButton1Click, function()
			if keyCaptureCancel then keyCaptureCancel() end
			local focused = UserInputService:GetFocusedTextBox()
			if focused then focused:ReleaseFocus() end
			badge.Text = "press a key..."
			tween(badgeStroke, 0.15, { Color = accentColor })
			tween(badge, 0.15, { BackgroundColor3 = hoverColor })

			local function finish()
				keyListener, keyCaptureCancel = nil, nil
				badge.Text = getKey().Name
				tween(badgeStroke, 0.3, { Color = strokeColor })
				tween(badge, 0.3, { BackgroundColor3 = bgColor })
			end
			keyCaptureCancel = finish
			keyListener = function(k)
				if k and k ~= Enum.KeyCode.Escape then
					if setKey(k) ~= false then setConfig(key, k.Name) end
				end
				finish()
			end
		end)
		register(key, function(v)
			local ok, k = pcall(function()
				return Enum.KeyCode[v]
			end)
			if ok and k then
				if setKey(k) ~= false then badge.Text = getKey().Name end
			end
		end, function()
			return getKey().Name
		end, getKey().Name)
	end

	Section.Select = function(self2, name, desc, options, default, callback)
		local cur = table.find(options, default) or 1
		local n = #options
		local key = configKey(self2, name)
		local row = self2:_row(name, desc)
		local badge = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			BackgroundColor3 = bgColor,
			ClipsDescendants = true,
			Parent = row,
		})
		addCorner(badge, 6)
		local badgeStroke = addStroke(badge)
		local arrows = {}
		for _, dir in ipairs({ -1, 1 }) do
			local a = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(dir < 0 and 0 or 1, dir < 0 and 10 or -10, 0.5, -1),
				Size = UDim2.fromOffset(5, 8),
				BackgroundTransparency = 1,
				ZIndex = 2,
				Parent = badge,
			})
			local l1, l2
			if dir < 0 then
				l1, l2 = line(a, 4, 0.5, 1, 4, 1.4), line(a, 1, 4, 4, 7.5, 1.4)
			else
				l1, l2 = line(a, 1, 0.5, 4, 4, 1.4), line(a, 4, 4, 1, 7.5, 1.4)
			end
			l1.ZIndex, l2.ZIndex = 2, 2
			arrows[dir] = { frame = a, l1 = l1, l2 = l2 }
		end
		local dots = {}
		if n <= 8 then
			for i = 1, n do
				local d = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, (i - (n + 1) / 2) * 6, 1, -3),
					Size = UDim2.fromOffset(i == cur and 5 or 2, 2),
					BackgroundColor3 = i == cur and accentColor or mutedColor,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = badge,
				})
				makeRound(d)
				dots[i] = d
			end
		end

		local function makeLabel(text, yScale, transp)
			return create("TextLabel", {
				Text = text,
				Font = Enum.Font.GothamMedium,
				TextSize = 11,
				TextColor3 = textColor,
				TextTransparency = transp,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 18, yScale, #dots > 0 and -2 or 0),
				Size = UDim2.new(1, -36, 1, 0),
				Parent = badge,
			})
		end

		local lbl = makeLabel(options[cur], 0, 0)
		local labelY = #dots > 0 and -2 or 0

		local function choose(i, dir, silent)
			if i == cur then
				return
			end
			if dots[cur] then
				tween(dots[cur], 0.25, { Size = UDim2.fromOffset(2, 2), BackgroundColor3 = mutedColor })
			end
			cur = i
			if dots[cur] then
				tween(dots[cur], 0.25, { Size = UDim2.fromOffset(5, 2), BackgroundColor3 = accentColor }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			end
			local old = lbl
			tween(old, 0.15, { Position = UDim2.new(0, 18, -dir, labelY), TextTransparency = 1 })
			task.delay(0.16, function()
				old:Destroy()
			end)
			lbl = makeLabel(options[cur], dir, 1)
			tween(lbl, 0.25, { Position = UDim2.new(0, 18, 0, labelY), TextTransparency = 0 }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			local ar = arrows[dir]
			local base = ar.frame.Position
			ar.frame.Position = base + UDim2.fromOffset(dir * 3, 0)
			tween(ar.frame, 0.3, { Position = base }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			badgeStroke.Color = accentColor
			tween(badgeStroke, 0.4, { Color = strokeColor })
			setConfig(key, options[cur])
			if not silent then
				spawnCallback(callback, options[cur])
			end
		end

		register(key, function(v)
			local i = table.find(options, v)
			if i and i ~= cur then
				choose(i, i > cur and 1 or -1)
			end
		end, function()
			return options[cur]
		end, options[table.find(options, default) or 1])

		local function step(dir)
			choose((cur - 1 + dir) % n + 1, dir)
		end

		connect(row.MouseButton1Click, function()
			step(1)
		end)
		connect(row.MouseButton2Click, function()
			step(-1)
		end)
		connect(row.MouseEnter, function()
			for _, ar in pairs(arrows) do
				tween(ar.l1, 0.15, { BackgroundColor3 = accentColor })
				tween(ar.l2, 0.15, { BackgroundColor3 = accentColor })
			end
		end)
		connect(row.MouseLeave, function()
			for _, ar in pairs(arrows) do
				tween(ar.l1, 0.15, { BackgroundColor3 = dimColor })
				tween(ar.l2, 0.15, { BackgroundColor3 = dimColor })
			end
		end)
		return {
			Set = function(opt, silent)
				local i = table.find(options, opt)
				if i then
					choose(i, i > cur and 1 or -1, silent)
				end
			end,
			Get = function()
				return options[cur]
			end,
		}
	end

	local openPicker
	local presets = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 69, 58),
		Color3.fromRGB(255, 159, 10),
		Color3.fromRGB(255, 214, 10),
		Color3.fromRGB(48, 209, 88),
		Color3.fromRGB(100, 210, 255),
		Color3.fromRGB(10, 132, 255),
		Color3.fromRGB(191, 90, 242),
		Color3.fromRGB(255, 55, 95),
	}

	local function relPos(inst)
		return inst.AbsolutePosition - gui.AbsolutePosition
	end

	local function openColorPicker(anchor, startColor, defaultColor, onChange)
		local h, sat, v = startColor:ToHSV()
		local original = startColor
		local backdrop = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 149,
			Parent = main,
		})
		addCorner(backdrop, 10)
		tween(backdrop, 0.3, { BackgroundTransparency = 0.45 })
		local popup = create("CanvasGroup", {
			Active = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = panelColor,
			GroupTransparency = 1,
			Size = UDim2.fromOffset(264, 344),
			ZIndex = 150,
			Parent = gui,
		})
		addCorner(popup, 12)
		create("UIStroke", { Color = accentColor, Transparency = 0.82, Thickness = 1, Parent = popup })
		local popupScale = create("UIScale", { Scale = 0.08, Parent = popup })

		local function anchorCenter()
			local p, sz = relPos(anchor), anchor.AbsoluteSize
			return UDim2.fromOffset(p.X + sz.X / 2, p.Y + sz.Y / 2)
		end

		local function mainCenter()
			local p, sz = relPos(main), main.AbsoluteSize
			return UDim2.fromOffset(p.X + sz.X / 2, p.Y + sz.Y / 2)
		end

		popup.Position = anchorCenter()
		local lights = {}
		local lightDefs = {
			{ Color3.fromRGB(255, 95, 87), "×" },
			{ Color3.fromRGB(254, 188, 46), "–" },
			{ Color3.fromRGB(40, 200, 64), "+" },
		}
		local lightsBar = create("Frame", {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.fromOffset(56, 12),
			BackgroundTransparency = 1,
			ZIndex = 151,
			Parent = popup,
		})
		for i, l in ipairs(lightDefs) do
			local b = create("TextButton", {
				Text = "",
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = Color3.fromRGB(60, 20, 10),
				TextTransparency = 1,
				AutoButtonColor = false,
				BackgroundColor3 = l[1],
				Position = UDim2.fromOffset((i - 1) * 19, 0),
				Size = UDim2.fromOffset(12, 12),
				ZIndex = 152,
				Parent = lightsBar,
			})
			makeRound(b)
			b.Text = l[2]
			lights[i] = b
		end
		connect(lightsBar.MouseEnter, function()
			for _, b in ipairs(lights) do
				tween(b, 0.12, { TextTransparency = 0.2 })
			end
		end)
		connect(lightsBar.MouseLeave, function()
			for _, b in ipairs(lights) do
				tween(b, 0.12, { TextTransparency = 1 })
			end
		end)
		create("TextLabel", {
			Text = "Color",
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = dimColor,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = 151,
			Parent = popup,
		})
		local sq = create("Frame", {
			Active = true,
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.fromOffset(236, 150),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			ZIndex = 151,
			Parent = popup,
		})
		addCorner(sq, 8)
		local whiteLayer = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = accentColor, ZIndex = 152, Parent = sq })
		addCorner(whiteLayer, 8)
		create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = whiteLayer })
		local blackLayer = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 153, Parent = sq })
		addCorner(blackLayer, 8)
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = blackLayer })
		local svCursor = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			ZIndex = 155,
			Parent = sq,
		})
		makeRound(svCursor)
		create("UIStroke", { Color = accentColor, Thickness = 2, Parent = svCursor })
		local svCursorScale = create("UIScale", { Parent = svCursor })
		local hueBar = create("Frame", {
			Active = true,
			Position = UDim2.fromOffset(14, 198),
			Size = UDim2.fromOffset(236, 12),
			BackgroundColor3 = accentColor,
			ZIndex = 151,
			Parent = popup,
		})
		makeRound(hueBar)
		local hueKps = {}
		for i = 0, 6 do
			hueKps[#hueKps + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1))
		end
		create("UIGradient", { Color = ColorSequence.new(hueKps), Parent = hueBar })
		local hueKnob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = accentColor,
			ZIndex = 153,
			Parent = hueBar,
		})
		makeRound(hueKnob)
		local hueKnobFill = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			ZIndex = 154,
			Parent = hueKnob,
		})
		makeRound(hueKnobFill)
		local hueKnobScale = create("UIScale", { Parent = hueKnob })
		local prev = create("Frame", {
			Position = UDim2.fromOffset(14, 224),
			Size = UDim2.fromOffset(56, 30),
			BackgroundColor3 = original,
			ClipsDescendants = true,
			ZIndex = 151,
			Parent = popup,
		})
		addCorner(prev, 8)
		addStroke(prev, hoverColor)
		local previewNew = create("Frame", {
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.5, 1),
			BorderSizePixel = 0,
			ZIndex = 152,
			Parent = prev,
		})
		local hexBox = create("TextBox", {
			Text = "",
			PlaceholderText = "#FFFFFF",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = textColor,
			PlaceholderColor3 = mutedColor,
			ClearTextOnFocus = false,
			BackgroundColor3 = elemColor,
			Position = UDim2.fromOffset(78, 224),
			Size = UDim2.new(1, -92, 0, 30),
			ZIndex = 151,
			Parent = popup,
		})
		addCorner(hexBox, 8)
		local hexStroke = addStroke(hexBox)
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = hexBox })
		hexBox.TextXAlignment = Enum.TextXAlignment.Left
		local rgbLabel = create("TextLabel", {
			Text = "",
			Font = Enum.Font.Gotham,
			TextSize = 10,
			TextColor3 = mutedColor,
			TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 90, 1, 0),
			ZIndex = 152,
			Parent = hexBox,
		})
		local swatches = {}
		local gap = (236 - #presets * 20) / (#presets - 1)
		for i, c in ipairs(presets) do
			local b = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = c,
				Position = UDim2.fromOffset(14 + (i - 1) * (20 + gap), 266),
				Size = UDim2.fromOffset(20, 20),
				ZIndex = 151,
				Parent = popup,
			})
			makeRound(b)
			local st = create("UIStroke", { Color = accentColor, Thickness = 1.5, Transparency = 1, Parent = b })
			local scale = create("UIScale", { Parent = b })
			connect(b.MouseEnter, function()
				tween(scale, 0.15, { Scale = 1.15 })
			end)
			connect(b.MouseLeave, function()
				tween(scale, 0.15, { Scale = 1 })
			end)
			swatches[i] = { btn = b, stroke = st, color = c, scale = scale }
		end
		local done = create("TextButton", {
			Text = "Done",
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = bgColor,
			AutoButtonColor = false,
			BackgroundColor3 = accentColor,
			Position = UDim2.fromOffset(14, 300),
			Size = UDim2.new(1, -28, 0, 30),
			ZIndex = 151,
			Parent = popup,
		})
		addCorner(done, 8)
		local doneScale = create("UIScale", { Parent = done })
		connect(done.MouseEnter, function()
			tween(done, 0.15, { BackgroundColor3 = Color3.fromRGB(215, 215, 215) })
		end)
		connect(done.MouseLeave, function()
			tween(done, 0.15, { BackgroundColor3 = accentColor })
		end)

		local function currentTab2()
			return Color3.fromHSV(h, sat, v)
		end

		local function refresh(keepText)
			local c = currentTab2()
			sq.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.fromScale(sat, 1 - v)
			hueKnob.Position = UDim2.fromScale(h, 0.5)
			hueKnobFill.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			previewNew.BackgroundColor3 = c
			if not keepText then
				hexBox.Text = "#" .. c:ToHex():upper()
			end
			rgbLabel.Text = ("%d  %d  %d"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
			for _, sw in ipairs(swatches) do
				local match = sw.color:ToHex() == c:ToHex()
				sw.stroke.Transparency = match and 0 or 1
			end
			onChange(c)
		end

		refresh()
		local dragging
		local lastRelease = 0
		local overPopup = false

		local function dragTo(pos)
			if dragging == "sq" then
				local p, sz = sq.AbsolutePosition, sq.AbsoluteSize
				sat = math.clamp((pos.X - p.X) / sz.X, 0, 1)
				v = 1 - math.clamp((pos.Y - p.Y) / sz.Y, 0, 1)
			elseif dragging == "hue" then
				local p, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
				h = math.clamp((pos.X - p.X) / sz.X, 0, 0.999)
			end
			refresh()
		end

		local function isPress(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		end

		local conns = {}

		local function bind(signal, fn)
			local c = connect(signal, fn)
			table.insert(conns, c)
		end

		bind(sq.InputBegan, function(input)
			if not isPress(input) then
				return
			end
			dragging = "sq"
			tween(svCursorScale, 0.15, { Scale = 1.3 })
			dragTo(input.Position)
		end)
		bind(hueBar.InputBegan, function(input)
			if not isPress(input) then
				return
			end
			dragging = "hue"
			tween(hueKnobScale, 0.15, { Scale = 1.2 })
			dragTo(input.Position)
		end)
		bind(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				dragTo(input.Position)
			end
		end)
		bind(UserInputService.InputEnded, function(input)
			if dragging and isPress(input) then
				dragging = nil
				lastRelease = os.clock()
				tween(svCursorScale, 0.2, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
				tween(hueKnobScale, 0.2, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			end
		end)

		local function setColor(c)
			h, sat, v = c:ToHSV()
			refresh()
		end

		for _, sw in ipairs(swatches) do
			bind(sw.btn.MouseButton1Click, function()
				sw.scale.Scale = 0.8
				tween(sw.scale, 0.3, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
				setColor(sw.color)
			end)
		end
		bind(hexBox.Focused, function()
			tween(hexStroke, 0.15, { Color = accentColor })
		end)
		bind(hexBox.FocusLost, function()
			tween(hexStroke, 0.15, { Color = strokeColor })
			local hex = hexBox.Text:gsub("[^%x]", "")
			local ok, c = pcall(Color3.fromHex, hex)
			if ok and c and #hex == 6 then
				setColor(c)
			else
				refresh()
			end
		end)
		tween(popup, 0.5, { Position = mainCenter() }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
		tween(popupScale, 0.55, { Scale = math.min(1, (gui.AbsoluteSize.X - 16) / 264, (gui.AbsoluteSize.Y - 16) / 344) }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
		tween(popup, 0.25, { GroupTransparency = 0 })
		local closing = false

		local function close(instant)
			if closing then
				return
			end
			closing = true
			if openPicker == close then
				openPicker = nil
			end
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
			if instant then
				backdrop:Destroy()
				popup:Destroy()
				return
			end
			tween(backdrop, 0.25, { BackgroundTransparency = 1 })
			tween(popup, 0.32, { Position = anchorCenter() }, Enum.EasingDirection.In, Enum.EasingStyle.Quint)
			tween(popupScale, 0.32, { Scale = 0.05 }, Enum.EasingDirection.In, Enum.EasingStyle.Quint)
			local t = tween(popup, 0.3, { GroupTransparency = 1 }, Enum.EasingDirection.In)
			connectOnce(t.Completed, function()
				backdrop:Destroy()
				popup:Destroy()
			end)
		end

		bind(popup.MouseEnter, function()
			overPopup = true
		end)
		bind(popup.MouseLeave, function()
			overPopup = false
		end)
		bind(backdrop.MouseButton1Click, function()
			if overPopup or dragging or os.clock() - lastRelease < 0.3 then
				return
			end
			close()
		end)
		bind(lights[1].MouseButton1Click, function()
			setColor(original)
			close()
		end)
		bind(lights[2].MouseButton1Click, function()
			close()
		end)
		bind(lights[3].MouseButton1Click, function()
			setColor(defaultColor)
		end)
		bind(done.MouseButton1Click, function()
			doneScale.Scale = 0.92
			tween(doneScale, 0.2, { Scale = 1 })
			close()
		end)
		return close
	end

	local closeActiveAlert

	local function showAlert(logo2, text, buttonText)
		if closeActiveAlert then
			closeActiveAlert()
		end
		local backdrop = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 159,
			Parent = main,
		})
		addCorner(backdrop, 10)
		tween(backdrop, 0.25, { BackgroundTransparency = 0.45 })
		local card = create("CanvasGroup", {
			Active = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(300, 176),
			BackgroundColor3 = panelColor,
			GroupTransparency = 1,
			ZIndex = 160,
			Parent = main,
		})
		addCorner(card, 14)
		local st = create("UIStroke", { Color = accentColor, Transparency = 0.6, Parent = card })
		addGradient(st)
		local scale = create("UIScale", { Scale = 0.85, Parent = card })
		local alertIcon = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = accentColor,
			ZIndex = 161,
			Parent = card,
		})
		makeRound(alertIcon)
		create("TextLabel", {
			Text = "!",
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			TextColor3 = bgColor,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 162,
			Parent = alertIcon,
		})
		local alertIconScale = create("UIScale", { Scale = 0.4, Parent = alertIcon })
		create("TextLabel", {
			Text = logo2,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = accentColor,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 64),
			Size = UDim2.new(1, -32, 0, 20),
			ZIndex = 161,
			Parent = card,
		})
		create("TextLabel", {
			Text = text,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextColor3 = dimColor,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 86),
			Size = UDim2.new(1, -40, 0, 34),
			ZIndex = 161,
			Parent = card,
		})
		local done = create("TextButton", {
			Text = buttonText or "Done",
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = bgColor,
			AutoButtonColor = false,
			BackgroundColor3 = accentColor,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -32, 0, 30),
			ZIndex = 161,
			Parent = card,
		})
		addCorner(done, 8)
		local doneScale = create("UIScale", { Parent = done })
		connect(done.MouseEnter, function()
			tween(done, 0.15, { BackgroundColor3 = Color3.fromRGB(215, 215, 215) })
		end)
		connect(done.MouseLeave, function()
			tween(done, 0.15, { BackgroundColor3 = accentColor })
		end)
		tween(card, 0.25, { GroupTransparency = 0 })
		tween(scale, 0.45, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
		task.delay(0.12, function()
			if window.Destroyed then return end
			tween(alertIconScale, 0.45, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
		end)
		local closed = false

		local function close()
			if closed then
				return
			end
			closed = true
			if closeActiveAlert == close then
				closeActiveAlert = nil
			end
			tween(backdrop, 0.2, { BackgroundTransparency = 1 })
			tween(scale, 0.2, { Scale = 0.9 }, Enum.EasingDirection.In)
			local t = tween(card, 0.2, { GroupTransparency = 1 })
			connectOnce(t.Completed, function()
				backdrop:Destroy()
				card:Destroy()
			end)
		end

		closeActiveAlert = close
		connect(done.MouseButton1Click, function()
			doneScale.Scale = 0.92
			tween(doneScale, 0.2, { Scale = 1 })
			close()
		end)
		connect(backdrop.MouseButton1Click, close)
	end

	Section.ColorPicker = function(self2, name, desc, default, callback)
		local color = default
		local key = configKey(self2, name)
		local row = self2:_row(name, desc)
		local swatch = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(38, 22),
			BackgroundColor3 = color,
			ZIndex = 2,
			Parent = row,
		})
		addCorner(swatch, 6)
		local outline = addStroke(swatch)
		local swatchScale = create("UIScale", { Parent = swatch })
		local hexLabel = create("TextLabel", {
			Text = "#" .. color:ToHex():upper(),
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = dimColor,
			TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -56, 0.5, 0),
			Size = UDim2.fromOffset(70, 20),
			ZIndex = 2,
			Parent = row,
		})

		local function apply(c, silent)
			color = c
			swatch.BackgroundColor3 = c
			hexLabel.Text = "#" .. c:ToHex():upper()
			setConfig(key, c:ToHex())
			if not silent then
				spawnCallback(callback, c)
			end
		end

		connect(row.MouseEnter, function()
			tween(outline, 0.15, { Color = accentColor })
		end)
		connect(row.MouseLeave, function()
			tween(outline, 0.15, { Color = strokeColor })
		end)
		connect(row.MouseButton1Click, function()
			if openPicker then
				openPicker(true)
			end
			swatchScale.Scale = 0.85
			tween(swatchScale, 0.3, { Scale = 1 }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
			openPicker = openColorPicker(swatch, color, default, function(c)
				apply(c)
			end)
		end)
		register(key, function(v)
			if type(v) ~= "string" then
				return
			end
			local ok, c = pcall(Color3.fromHex, v)
			if ok and c then
				apply(c)
			end
		end, function()
			return color:ToHex()
		end, default:ToHex())
		return {
			Set = function(c, silent)
				apply(c, silent)
			end,
			Get = function()
				return color
			end,
		}
	end


-- Public API. Native positional Section methods remain available as well.
local function remember(section, opts, control)
    local key = configKey(section, opts.Name)
    assert(not window.Controls[key], "Duplicate control key: " .. key)
    for name, fn in pairs(control) do
        if type(fn) == "function" then
            control[name] = function(first, ...)
                assert(not window.Destroyed, "RockHubUI window is destroyed")
                if first == control then return fn(...) end
                return fn(first, ...)
            end
        end
    end
    window.Controls[key] = control
    return control
end
local function validate(opts)
    assert(type(opts) == "table" and type(opts.Name) == "string", "Control requires { Name = ... }")
end
function Section:AddToggle(opts)
    validate(opts)
    local control = self:Toggle(opts.Name, opts.Description, opts.Callback)
    if opts.Default then control.Set(true, true) end
    return remember(self, opts, control)
end
function Section:AddButton(opts)
    validate(opts)
    self:Button(opts.Name, opts.Description, opts.Callback)
    return remember(self, opts, { Fire = function() spawnCallback(opts.Callback) end })
end
function Section:AddSlider(opts)
    validate(opts)
    local min, max = opts.Min or 0, opts.Max or 100
    assert(max > min, "Slider Max must be greater than Min")
    return remember(self, opts, self:Slider(opts.Name, min, max, math.clamp(opts.Default or min, min, max), opts.Callback, opts.Format))
end
local function choiceOptions(opts)
    validate(opts)
    assert(type(opts.Options) == "table" and #opts.Options > 0, "Options must be a nonempty string array")
    for _, value in ipairs(opts.Options) do assert(type(value) == "string", "Options must contain strings") end
end
function Section:AddDropdown(opts)
    choiceOptions(opts)
    local control = self:Dropdown(opts.Name, opts.Description, opts.Options, opts.Placeholder, opts.Callback, false, opts.Thumbnail)
    if opts.Default then control.Set(opts.Default, true) end
    register(configKey(self, opts.Name), control.Set, control.Get, opts.Default)
    return remember(self, opts, control)
end
function Section:AddSelect(opts)
    choiceOptions(opts)
    return remember(self, opts, self:Select(opts.Name, opts.Description, opts.Options, opts.Default, opts.Callback))
end
function Section:AddSegmented(opts)
    choiceOptions(opts)
    return remember(self, opts, self:Segmented(opts.Name, opts.Options, opts.Default, opts.Callback, opts.CanSelect))
end
function Section:AddInput(opts)
    validate(opts)
    local control = self:Input(opts.Name, opts.Description, opts.Placeholder)
    local nativeSet = control.Set
    control.Set = function(value, silent)
        nativeSet(value)
        if not silent then spawnCallback(opts.Callback, control.Get(), false) end
    end
    control.Set(opts.Default or "", true)
    connect(control.Box.FocusLost, function(enterPressed)
        spawnCallback(opts.Callback, control.Get(), enterPressed)
    end)
    register(configKey(self, opts.Name), control.Set, control.Get, opts.Default or "")
    return remember(self, opts, control)
end
function Section:AddColorPicker(opts)
    validate(opts)
    return remember(self, opts, self:ColorPicker(opts.Name, opts.Description, opts.Default or Color3.new(1, 1, 1), opts.Callback))
end
function Section:AddKeybind(opts)
    validate(opts)
    local value = opts.Default or Enum.KeyCode.Unknown
    assert(typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode, "Keybind Default must be Enum.KeyCode")
    self:Keybind(opts.Name, opts.Description, function() return value end, function(k)
        value = k
        spawnCallback(opts.Changed, k)
    end)
    local key = configKey(self, opts.Name)
    keybinds[key] = { get = function() return value end, callback = opts.Callback }
    return remember(self, opts, {
        Get = function() return value end,
        Set = function(k, silent)
            assert(typeof(k) == "EnumItem" and k.EnumType == Enum.KeyCode, "Keybind requires Enum.KeyCode")
            if silent then
                local changed = opts.Changed
                opts.Changed = nil
                registry[key].set(k.Name)
                opts.Changed = changed
            else registry[key].set(k.Name) end
        end,
    })
end
function Section:AddLabel(opts)
    validate(opts)
    local row, label = self:_row(opts.Name, opts.Description, opts.Height)
    label.Size = UDim2.new(1, -24, 0, opts.Description and 15 or row.Size.Y.Offset)
    row.Active = false
    return { Set = function(text) label.Text = tostring(text) end, Instance = row }
end

function window:AddTab(opts)
    if type(opts) == "string" then opts = { Name = opts } end
    validate(opts)
    local tab = addTab(opts.Name, opts.Icon or "grid", opts.Description)
    function tab:AddSection(spec)
        if type(spec) == "string" then spec = { Name = spec } end
        validate(spec)
        local section = addSection(self, spec.Name, spec.Group, spec.Priority)
        if spec.Collapsible then section:Collapsible(spec.Open ~= false) end
        return section
    end
    function tab:SetSubTabs(items)
        assert(not self.subs, "Subtabs may only be created once")
        assert(#items > 0, "Subtabs must not be empty")
        setSubTabs(self, items)
        return self
    end
    function tab:SelectSubTab(name) if self.setSub then self.setSub(name) end end
    function tab:Select() selectTab(self) end
    if not currentTab then selectTab(tab) end
    return tab
end
function window:AddSeparator(text) addSeparator(text) end
function window:Search(text)
    searchTerms = nil
    if text and text:match("%S") then
        searchTerms = {}
        for term in text:lower():gmatch("%S+") do table.insert(searchTerms, term) end
    end
    for _, tab in ipairs(tabs) do layoutTab(tab) end
end
function window:GetConfig()
    local result = {}
    for key, entry in pairs(registry) do result[key] = entry.get() end
    return result
end
function window:LoadConfig(values)
    assert(type(values) == "table", "LoadConfig requires a table")
    local errors = {}
    for key, value in pairs(values) do
        if registry[key] then
            local ok, err = pcall(registry[key].set, value)
            if not ok then errors[key] = tostring(err) end
        end
    end
    return errors
end
function window:ExportConfig() return HttpService:JSONEncode(self:GetConfig()) end
function window:ImportConfig(json) return self:LoadConfig(HttpService:JSONDecode(json)) end

local menuSequence = 0
local onMenuToggled
local blur
if (options.Blur or 0) > 0 then
    blur = create("BlurEffect", { Name = "RockHubUIBlur", Size = 0, Parent = game:GetService("Lighting") })
end
function window:SetOpen(state)
    if self.Destroyed then return end
    state = not not state
    menuOpen = state
    if onMenuToggled then onMenuToggled(state) end
    menuSequence += 1
    local sequence = menuSequence
    if not state then
        if keyCaptureCancel then keyCaptureCancel() end
        if openPicker then openPicker(true) end
        for _, close in pairs(table.clone(popupClosers)) do close() end
    end
    if blur then tween(blur, 0.2, { Size = state and options.Blur or 0 }) end
    if state then
        main.Visible = true
        tween(mainScale, 0.3, { Scale = responsiveScale }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
    else
        local tw = tween(mainScale, 0.2, { Scale = 0 }, Enum.EasingDirection.In)
        connectOnce(tw.Completed, function() if sequence == menuSequence then main.Visible = false end end)
    end
    spawnCallback(options.OnOpenChanged, state)
end
function window:IsOpen() return menuOpen end
function window:Toggle() self:SetOpen(not menuOpen) end
function window:Alert(title, text, buttonText) showAlert(title, text, buttonText) end
local notifications = create("Frame", {
    Name = "Notifications", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12),
    Size = UDim2.new(0, 260, 1, -24), BackgroundTransparency = 1, ZIndex = 200, Parent = gui,
})
create("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom,
    SortOrder = Enum.SortOrder.LayoutOrder, Parent = notifications })
function window:Notify(title, text, duration)
    local toast = create("TextLabel", {
        Name = "Notification", Text = tostring(title) .. "\n" .. tostring(text or ""),
        TextWrapped = true, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = textColor,
        BackgroundColor3 = panelColor, BorderSizePixel = 0, ZIndex = 200,
        Size = UDim2.new(1, 0, 0, 64), Parent = notifications,
    })
    addCorner(toast, 10) addStroke(toast, accentColor)
    task.delay(duration or 3, function() toast:Destroy() end)
    return toast
end
local dragging, dragStart, startPosition
topBar.Active = true
connect(topBar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPosition = input, input.Position, main.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if dragSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        dragSlider(input.Position.X)
    end
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging) then
        local delta = input.Position - dragStart
        main.Position = startPosition + UDim2.fromOffset(delta.X, delta.Y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragSlider = nil
        if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = nil end
    end
end)
connect(UserInputService.WindowFocusReleased, function() dragging, dragSlider = nil, nil end)
connect(UserInputService.InputBegan, function(input, processed)
    if keyListener then
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then keyListener(input.KeyCode) end
        return
    end
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == (options.ToggleKey or Enum.KeyCode.RightShift) then window:Toggle() end
    for _, entry in pairs(keybinds) do
        if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode == entry.get() then spawnCallback(entry.callback, input.KeyCode) end
    end
end)
connect(closeBtn.MouseButton1Click, function() window:SetOpen(false) end)
local watermarkUI = (function()
local hud = {}
local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
local onMenuToggled
local function toggleMenu() window:Toggle() end
	local function makeDraggable(inst, key, onClick, onRelease, handle)
		local saved = config[key]
		if type(saved) == "table" and #saved == 4 then
			inst.Position = UDim2.new(saved[1], saved[2], saved[3], saved[4])
		end
		local dragInput, dragStart, startPos, moved
		connect((handle or inst).InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragInput, dragStart, startPos, moved = input, input.Position, inst.Position, false
			end
		end)
		connect(UserInputService.InputChanged, function(input)
			if not dragInput then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then
				return
			end
			local d = input.Position - dragStart
			if not moved and d.Magnitude < 6 then
				return
			end
			moved = true
			inst.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			local absPos, absSize, vel = inst.AbsolutePosition, inst.AbsoluteSize, gui.AbsoluteSize
			local fx = math.clamp(absPos.X, 0, math.max(0, vel.X - absSize.X)) - absPos.X
			local py = math.clamp(absPos.Y, 0, math.max(0, vel.Y - absSize.Y)) - absPos.Y
			if fx ~= 0 or py ~= 0 then
				inst.Position = inst.Position + UDim2.fromOffset(fx, py)
			end
		end)
		connect(UserInputService.InputEnded, function(input)
			if not dragInput then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input ~= dragInput then
				return
			end
			dragInput = nil
			if onRelease then
				onRelease()
			end
			if moved then
				local p = inst.Position
				config[key] = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset }
			elseif onClick then
				onClick()
			end
		end)
	end

	local function setPopVisible(frame, scale, on, targetScale)
		targetScale = targetScale or 1
		frame:SetAttribute("pzOn", on)
		if on then
			frame.Visible = true
			scale.Scale = targetScale * 0.6
			tween(scale, 0.35, { Scale = targetScale }, Enum.EasingDirection.Out, Enum.EasingStyle.Back)
		else
			local tween2 = tween(scale, 0.18, { Scale = 0 }, Enum.EasingDirection.In)
			connectOnce(tween2.Completed, function()
				if not frame:GetAttribute("pzOn") then
					frame.Visible = false
				end
			end)
		end
	end

	local wmGradients = {}
	local wmHolder = create("Frame", {
		Name = "WatermarkHolder",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 62),
		Size = UDim2.fromOffset(320, 36),
		ZIndex = 50,
		Parent = gui,
	})
	local watermark = create("TextButton", {
		Name = "Watermark",
		Text = "",
		AutoButtonColor = false,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = bgColor,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromOffset(0, 36),
		Visible = false,
		ZIndex = 50,
		Parent = wmHolder,
	})
	addCorner(watermark, 10)
	local wmScale = create("UIScale", { Scale = 0, Parent = watermark })
	local watermarkTargetScale = 1
	updateWatermarkResponsive = function()
		local cam = workspace.CurrentCamera
		local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
		if UserInputService.TouchEnabled then
			if math.min(viewport.X, viewport.Y) >= 600 then
				watermarkTargetScale = 0.85
			else
				watermarkTargetScale = math.clamp(responsiveScale, 0.58, 0.75)
			end
		else
			watermarkTargetScale = 1
		end
		if watermark:GetAttribute("pzOn") then
			wmScale.Scale = watermarkTargetScale
		end
	end
	updateWatermarkResponsive()
	local wmStroke = create("UIStroke", {
		Color = accentColor,
		Thickness = 1,
		Transparency = 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = watermark,
	})
	table.insert(wmGradients, create("UIGradient", { Parent = wmStroke }))
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = watermark })
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 9),
		Parent = watermark,
	})
	local wmOrder = 0

	local function wmItem(className, props)
		wmOrder += 1
		props.LayoutOrder = wmOrder
		if props.BackgroundTransparency == nil then
			props.BackgroundTransparency = 1
		end
		props.BorderSizePixel = 0
		props.ZIndex = props.ZIndex or 51
		props.Parent = props.Parent or watermark
		return create(className, props)
	end

	local function wmDivider()
		return wmItem("Frame", { Size = UDim2.fromOffset(1, 14), BackgroundTransparency = 0, BackgroundColor3 = strokeColor })
	end

	local function wmLabel(width)
		return wmItem("TextLabel", {
			Text = "",
			RichText = true,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(width, 36),
		})
	end

	local logo2 = wmItem("Frame", { Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0, BackgroundColor3 = accentColor, ClipsDescendants = true })
	addCorner(logo2, 7)
	table.insert(wmGradients, create("UIGradient", { Rotation = 45, Parent = logo2 }))
	local logoText = create("TextLabel", {
		Text = "rh",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = bgColor,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, -1),
		ZIndex = 52,
		Parent = logo2,
	})
	local logoImage = create("ImageLabel", {
		Image = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 53,
		Parent = logo2,
	})
	if options.Logo then logoImage.Image = options.Logo logoImage.Visible = true logoText.Visible = false else
	task.spawn(function()
		local getAsset = getcustomasset or getsynasset
		if not (writefile and getAsset) then
			return
		end
		local file = "rockhub_logo.png"
		if not (isfile and isfile(file)) then
			local ok, data = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/rockscripter/MM2Drone/refs/heads/main/logo.png")
			if not ok or type(data) ~= "string" or #data == 0 or not pcall(writefile, file, data) then
				return
			end
		end
		local ok, asset = pcall(getAsset, file)
		if ok and asset and not window.Destroyed and logoImage.Parent then
			logoImage.Image = asset
			logoImage.Visible = true
			logoText.Visible = false
		end
	end)
	end
	local brandLabel = wmItem("TextLabel", {
		Text = options.ButtonText or "rock hub",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = accentColor,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
	})
	table.insert(wmGradients, create("UIGradient", { Parent = brandLabel }))
	wmDivider()
	local fpsLabel = wmLabel(50)
	wmDivider()
	local signalIcon = wmItem("Frame", { Size = UDim2.fromOffset(13, 10) })
	local signalBars = {}
	for i = 1, 3 do
		signalBars[i] = create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, (i - 1) * 5, 1, 0),
			Size = UDim2.fromOffset(3, 3 + i * 2.4),
			BackgroundColor3 = hoverColor,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = signalIcon,
		})
		addCorner(signalBars[i], 1)
	end
	local pingLabel = wmLabel(44)
	wmDivider()
	local clockLabel = wmLabel(34)
	local function statText(left, right)
		return string.format("<font color=\"#FFFFFF\">%s</font> <font color=\"#787878\">%s</font>", left, right)
	end

	fpsLabel.Text = statText("--", "fps")
	pingLabel.Text = statText("--", "ms")
	clockLabel.Text = "<font color=\"#FFFFFF\">" .. os.date("%H:%M") .. "</font>"
	local menuButton = wmItem("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = elemColor,
	})
	addCorner(menuButton, 7)
	local menuStroke = create("UIStroke", {
		Color = accentColor,
		Transparency = 0.6,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = menuButton,
	})
	create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 10), Parent = menuButton })
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 7),
		Parent = menuButton,
	})
	local burger = create("Frame", {
		Size = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = menuButton,
	})
	local burgerLines = {}
	for i = 1, 3 do
		burgerLines[i] = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 1 + (i - 1) * 4),
			Size = UDim2.fromOffset(12, 2),
			BackgroundColor3 = textColor,
			BorderSizePixel = 0,
			ZIndex = 53,
			Parent = burger,
		})
		makeRound(burgerLines[i])
	end
	local menuLabel = create("TextLabel", {
		Text = "menu",
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = textColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(32, 24),
		LayoutOrder = 2,
		ZIndex = 53,
		Parent = menuButton,
	})
		local tip = create("Frame", {
			Name = "WatermarkTip",
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = panelColor,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 60,
			Parent = wmHolder,
		})
		addCorner(tip, 8)
		addStroke(tip, hoverColor)
		local tipScale = create("UIScale", { Scale = 0, Parent = tip })
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 7),
			PaddingBottom = UDim.new(0, 7),
			Parent = tip,
		})
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = tip })
		local tipTitle = create("TextLabel", {
			Text = "click to open the menu",
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = accentColor,
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			ZIndex = 61,
			Parent = tip,
		})
		local tipHint = create("TextLabel", {
			Text = "",
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = dimColor,
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			ZIndex = 61,
			Parent = tip,
		})
		local tipArrow = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9),
			Rotation = 45,
			BackgroundColor3 = panelColor,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 59,
			Parent = wmHolder,
		})
		addStroke(tipArrow, hoverColor)
		local wmUsed = config["hud/wm_used"] == true
		local hovering = false
		local tipShown, tipSeq = false, 0

		local function placeTip()
			local x0 = watermark.AbsolutePosition.X
			local relX = menuButton.AbsolutePosition.X - x0
			local y = watermark.AbsoluteSize.Y + 10
			tip.Position = UDim2.fromOffset(relX + menuButton.AbsoluteSize.X + 6, y)
			tipArrow.Position = UDim2.fromOffset(relX + menuButton.AbsoluteSize.X / 2, y)
		end

		local function showTip(on, hideAfter)
			tipSeq += 1
			if on == tipShown then
				if not on then
					return
				end
			else
				tipShown = on
				tipTitle.Text = menuOpen and "click to close the menu" or "click to open the menu"
				tipHint.Text = "drag to move  ·  or press " .. toggleKey.Name
				if on then
					placeTip()
				end
				setPopVisible(tip, tipScale, on)
				tipArrow.Visible = on
			end
			if on and hideAfter then
				local id = tipSeq
				task.delay(hideAfter, function()
					if not window.Destroyed and id == tipSeq and not hovering then
						showTip(false)
					end
				end)
			end
		end

		local function refreshMenuButton()
			local hover = hovering
			tween(wmScale, 0.2, { Scale = watermarkTargetScale * (hover and 1.03 or 1) }, Enum.EasingDirection.Out, Enum.EasingStyle.Quint)
			tween(wmStroke, 0.2, { Transparency = (hover or menuOpen) and 0 or 0.5 })
			local btnColor = hover and accentColor or (menuOpen and hoverColor or elemColor)
			local fg = hover and bgColor or textColor
			tween(menuButton, 0.2, { BackgroundColor3 = btnColor })
			tween(menuLabel, 0.2, { TextColor3 = fg })
			for _, l in ipairs(burgerLines) do
				tween(l, 0.2, { BackgroundColor3 = fg })
			end
			if wmUsed or hover then
				tween(menuStroke, 0.2, { Transparency = hover and 0 or 0.6 })
			end
		end

		local function animateBurger(open)
			local direction, style = Enum.EasingDirection.Out, Enum.EasingStyle.Quint
			tween(burgerLines[1], 0.35, { Position = UDim2.new(0.5, 0, 0, open and 5 or 1), Rotation = open and 45 or 0 }, direction, style)
			tween(burgerLines[2], 0.25, { Size = UDim2.fromOffset(open and 0 or 12, 2), BackgroundTransparency = open and 1 or 0 }, direction, style)
			tween(burgerLines[3], 0.35, { Position = UDim2.new(0.5, 0, 0, open and 5 or 9), Rotation = open and -45 or 0 }, direction, style)
			menuLabel.Text = open and "close" or "menu"
		end

		connect(watermark.MouseEnter, function()
			hovering = true
			refreshMenuButton()
			local id = tipSeq
			task.delay(0.35, function()
				if not window.Destroyed and hovering and id == tipSeq then
					showTip(true)
				end
			end)
		end)
		connect(watermark.MouseLeave, function()
			hovering = false
			refreshMenuButton()
			showTip(false)
		end)
		connect(watermark.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				tween(wmScale, 0.1, { Scale = watermarkTargetScale * 0.96 })
			end
		end)
		makeDraggable(wmHolder, "hud/watermark_pos", function()
			if not wmUsed then
				wmUsed = true
				config["hud/wm_used"] = true
			end
			showTip(false)
			toggleMenu()
		end, function()
			if not UserInputService.MouseEnabled then
				hovering = false
			end
			refreshMenuButton()
		end, watermark)

		hud.setWatermark = function(on)
			if on == (watermark:GetAttribute("pzOn") == true) then
				return
			end
			setPopVisible(watermark, wmScale, on, watermarkTargetScale)
			if not on then
				showTip(false)
			end
		end

		local Stats = game:GetService("Stats")

		local function getPing()
			local ok, ping = pcall(function()
				return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			if ok and type(ping) == "number" then
				return ping
			end
			ok, ping = pcall(function()
				return player:GetNetworkPing() * 2000
			end)
			return ok and ping or 0
		end

		local frameCount, fpsClock, lastLevel = 0, os.clock(), -1
		local wmStart = os.clock()
		connect(RunService.RenderStepped, function()
			frameCount += 1
			local now = os.clock()
			if watermark.Visible then
				local t = (now - wmStart) * 0.35
				local seq = shimmerSeq(t)
				for _, g in ipairs(wmGradients) do
					g.Color = seq
				end
				if not wmUsed and not hovering then
					menuStroke.Transparency = 0.15 + 0.55 * (0.5 + 0.5 * math.cos((now - wmStart) * 4))
				end
				if wmScale.Scale > watermarkTargetScale * 0.99 then
					wmHolder.Size = UDim2.fromOffset(watermark.AbsoluteSize.X, watermark.AbsoluteSize.Y)
				end
				if tip.Visible then
					placeTip()
				end
			end
			if now - fpsClock < 0.5 then
				return
			end
			local fps = math.floor(frameCount / (now - fpsClock) + 0.5)
			frameCount, fpsClock = 0, now
			if not watermark.Visible then
				return
			end
			local pingMs = math.floor(getPing() + 0.5)
			fpsLabel.Text = statText(fps, "fps")
			pingLabel.Text = statText(pingMs, "ms")
			clockLabel.Text = "<font color=\"#FFFFFF\">" .. os.date("%H:%M") .. "</font>"
			local lit = pingMs < 90 and 3 or (pingMs < 180 and 2 or 1)
			if lit ~= lastLevel then
				lastLevel = lit
				for i, b in ipairs(signalBars) do
					tween(b, 0.25, { BackgroundColor3 = i <= lit and accentColor or hoverColor })
				end
			end
		end)

		onMenuToggled = function(state)
			animateBurger(state)
			refreshMenuButton()
			if state then
				showTip(false)
			elseif not wmUsed and watermark:GetAttribute("pzOn") then
				task.delay(0.25, function()
					if not window.Destroyed and not menuOpen and not wmUsed then
						showTip(true, 6)
					end
				end)
			end
		end


hud.setWatermark(options.MenuButton ~= false)
onMenuToggled(menuOpen)
return { Refresh = onMenuToggled, Button = watermark, Holder = wmHolder }
end)()
onMenuToggled = watermarkUI.Refresh
window.MenuButton, window.MenuHolder = watermarkUI.Button, watermarkUI.Holder

local shimmerTime = 0
connect(RunService.RenderStepped, function(dt)
    if not menuOpen then return end
    shimmerTime += dt
    if shimmerTime < 1 / 30 then return end
    shimmerTime = 0
    local seq = shimmerSeq(os.clock() * 0.12)
    for _, gradient in ipairs(gradients) do if gradient.Parent then gradient.Color = seq end end
end)
local guiDestroying = false
function window:Destroy()
    if self.Destroyed then return end
    if openPicker then openPicker(true) end
    if keyCaptureCancel then keyCaptureCancel() end
    self.Destroyed = true
    for connection in pairs(connections) do connection:Disconnect() end
    for tw in pairs(activeTweens) do tw:Cancel() end
    for _, value in ipairs(ownedValues) do value:Destroy() end
    if blur then blur:Destroy() end
    if not guiDestroying then gui:Destroy() end
    table.clear(connections) table.clear(activeTweens) table.clear(registry)
    table.clear(actions) table.clear(keybinds) table.clear(presentation.toggles)
end
connect(gui.Destroying, function()
    guiDestroying = true
    window:Destroy()
end)
window.Gui, window.Main, window.Sidebar, window.Tabs = gui, main, sidebar, tabs
window:SetOpen(options.Open ~= false)
return window
end

return Library
