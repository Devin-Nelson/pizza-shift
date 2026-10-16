--!strict
-- Small UI toolkit: element builder, themed buttons/panels, toasts.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Theme = {
	Bg = Color3.fromRGB(28, 24, 30),
	Panel = Color3.fromRGB(44, 38, 48),
	Card = Color3.fromRGB(62, 54, 68),
	Accent = Color3.fromRGB(230, 70, 50),
	Accent2 = Color3.fromRGB(255, 190, 60),
	Good = Color3.fromRGB(70, 200, 110),
	Text = Color3.fromRGB(250, 245, 240),
	Muted = Color3.fromRGB(180, 170, 185),
	Font = Enum.Font.GothamBold,
	Title = Enum.Font.FredokaOne,
}
local T = Ui.Theme

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Ui.stroke(color: Color3?, thickness: number?): UIStroke
	return Ui.new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thickness or 2, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function Ui.pad(px: number): UIPadding
	local u = UDim.new(0, px)
	return Ui.new("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function Ui.label(text: string, props: { [string]: any }?): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = T.Font,
		Text = text,
		TextColor3 = T.Text,
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, 30),
	}
	if props then
		for k, v in props do
			if k ~= "MaxText" then
				base[k] = v
			end
		end
	end
	local l = Ui.new("TextLabel", base)
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 28, Parent = l })
	return l
end

function Ui.button(text: string, color: Color3?, props: { [string]: any }?): TextButton
	local base = {
		BackgroundColor3 = color or T.Accent,
		Font = T.Font,
		Text = text,
		TextColor3 = T.Text,
		TextScaled = true,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 44),
	}
	if props then
		for k, v in props do
			if k ~= "MaxText" then
				base[k] = v
			end
		end
	end
	local b = Ui.new("TextButton", base, { Ui.corner(10), Ui.pad(6) })
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 24, Parent = b })
	return b
end

local player = Players.LocalPlayer
local screen: ScreenGui = Ui.new("ScreenGui", {
	Name = "GameUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
Ui.Screen = screen

-- Modal panel centered on screen. Returns (root, body, close button).
function Ui.panel(title: string, width: number, height: number): (Frame, Frame, TextButton)
	local root = Ui.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = T.Panel,
		Parent = screen,
	}, { Ui.corner(16), Ui.stroke(T.Accent, 3) })
	-- Shrink to fit small (mobile) screens.
	local scale = Ui.new("UIScale", { Parent = root })
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (view.X - 20) / width, (view.Y - 60) / height)
	end
	fit()
	local resize = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	root.Destroying:Connect(function()
		resize:Disconnect()
	end)

	Ui.new("Frame", { Name = "TitleBar", Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = T.Accent, Parent = root }, {
		Ui.corner(16),
		Ui.label(title, { Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -70, 0, 36), Font = T.Title, TextXAlignment = Enum.TextXAlignment.Left }),
	})
	local close = Ui.button("X", Color3.fromRGB(60, 30, 30), { Position = UDim2.new(1, -46, 0, 6), Size = UDim2.fromOffset(36, 36), Parent = root })
	local body = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 1, -76),
		BackgroundTransparency = 1,
		Parent = root,
	})
	return root, body, close
end

-- Control strip docked at the bottom of the screen (for 3D minigames, so the
-- view of the work stays clear). Returns (root, body, close button).
function Ui.dock(title: string, height: number): (Frame, Frame, TextButton)
	local root = Ui.new("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, height),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.08,
		Parent = screen,
	}, { Ui.corner(14), Ui.stroke(T.Accent, 2) })
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(760, height), Parent = root })
	Ui.label(title, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -70, 0, 26), Font = T.Title, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22, Parent = root })
	local close = Ui.button("X", Color3.fromRGB(60, 30, 30), { Position = UDim2.new(1, -40, 0, 6), Size = UDim2.fromOffset(32, 32), Parent = root })
	local body = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 1, -48),
		BackgroundTransparency = 1,
		Parent = root,
	})
	return root, body, close
end

-- Toasts
local toastHolder = Ui.new("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0.6, 0, 0.5, 0),
	BackgroundTransparency = 1,
	Parent = screen,
}, {
	Ui.new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local toastOrder = 0

function Ui.toast(text: string, color: Color3?)
	toastOrder += 1
	local frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.15,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	}, { Ui.corner(10), Ui.stroke(color or T.Accent2, 2), Ui.pad(6) })
	local l = Ui.label(text, { Size = UDim2.fromScale(1, 1), TextColor3 = color or T.Text, MaxText = 20, Parent = frame })
	task.delay(3.5, function()
		local info = TweenInfo.new(0.4)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, info, { TextTransparency = 1 }):Play()
		local s = frame:FindFirstChildOfClass("UIStroke")
		if s then
			TweenService:Create(s, info, { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		frame:Destroy()
	end)
	-- Keep at most 5 on screen: drop the oldest (GetChildren order isn't guaranteed).
	local toasts = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end

return Ui
