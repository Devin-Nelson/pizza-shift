--!strict
-- Interaction prompts in the store-systems look instead of Roblox's default
-- bubble: a charcoal card with the key on a gold chip, what it is (small) and
-- what it does, and a gold line that fills while a hold prompt is held. The
-- card itself can be clicked or tapped. Prompts opt in by having their Style
-- set to Custom (Main.client does that for every prompt).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Style = require(ReplicatedStorage.Shared.Style)

local Prompts = {}

local C = Style.Color
local F = Style.Font
local player = Players.LocalPlayer

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function build(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): BillboardGui
	local key = keyText(prompt, inputType)
	local gui: BillboardGui = new("BillboardGui", {
		Name = "Prompt",
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(230, 46),
		SizeOffset = Vector2.new(prompt.UIOffset.X / 230, prompt.UIOffset.Y / 46),
		Adornee = prompt.Parent,
		ResetOnSpawn = false,
		Active = true,
	})
	local card = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromScale(1, 1),
	}, gui)
	new("Frame", { BackgroundColor3 = C.Red, Size = UDim2.new(0, 3, 1, 0) }, card)
	local chip = new("Frame", { BackgroundColor3 = C.Gold, Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(if #key > 1 then 42 else 28, 28) }, card)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = F.Mono,
		TextSize = if #key > 1 then 12 else 16,
		TextColor3 = C.Ink,
		Text = key,
	}, chip)
	local x = chip.Position.X.Offset + chip.Size.X.Offset + 10
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, 6),
		Size = UDim2.new(1, -x - 8, 0, 14),
		FontFace = F.Label,
		TextSize = 12,
		TextColor3 = C.CreamDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.upper(prompt.ObjectText),
	}, card)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, 20),
		Size = UDim2.new(1, -x - 8, 0, 20),
		FontFace = F.LabelBold,
		TextSize = 17,
		TextColor3 = C.Cream,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.upper(prompt.ActionText),
	}, card)
	-- Hold progress along the bottom edge.
	local fill = new("Frame", { BackgroundColor3 = C.Gold, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(0, 3) }, card)
	local tween: Tween? = nil
	local held = prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration > 0 then
			tween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 0, 3) })
			;(tween :: Tween):Play()
		end
	end)
	local released = prompt.PromptButtonHoldEnded:Connect(function()
		if tween then
			tween:Cancel()
		end
		fill.Size = UDim2.fromOffset(0, 3)
	end)
	-- Click or tap the card to use it.
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			prompt:InputHoldBegin()
		end
	end)
	card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			prompt:InputHoldEnd()
		end
	end)
	gui.Destroying:Connect(function()
		held:Disconnect()
		released:Disconnect()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

function Prompts.Init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		local gui = build(prompt, inputType)
		local hidden: RBXScriptConnection
		hidden = prompt.PromptHidden:Connect(function()
			hidden:Disconnect()
			gui:Destroy()
		end)
	end)
end

return Prompts
