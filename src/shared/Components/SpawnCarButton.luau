local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Roact = require(ReplicatedStorage.Packages.Roact)

local SpawnPlayerCarEvent = ReplicatedStorage:WaitForChild("SpawnPlayerCar")

local SpawnCarButton = Roact.Component:extend("SpawnCarButton")

function SpawnCarButton:init()
    self:setState({hovered = false, pressed = false})
end

function SpawnCarButton:render()
    local scale = self.state.pressed and 1.1 or (self.state.hovered and 1.05 or 1)
    return Roact.createElement("ImageButton", {
        Size = UDim2.new(0, 220 *scale, 0, 60 *scale),
        Position = UDim2.new(0.5, -110, 0.85, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(40, 180, 255),
        BorderSizePixel = 0,
        [Roact.Event.MouseEnter] = function()
            self:setState({hovered = true})
        end,
        [Roact.Event.MouseLeave] = function()
            self:setState({hovered = false, pressed = false})
        end,
        [Roact.Event.MouseButton1Down] = function()
            self:setState({pressed = true})
        end,
        [Roact.Event.MouseButton1Up] = function()
            self:setState({pressed = false})
            SpawnPlayerCarEvent:FireServer()
        end,
        [Roact.Event.Activated] = nil, -- Remove Activated event
    }, {
        UICorner = Roact.createElement("UICorner", {CornerRadius = UDim.new(0, 18)}),
        UIText = Roact.createElement("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "🚗 Spawn Vehicle",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextScaled = true,
        })
    })
end

return function()
    return Roact.createElement(SpawnCarButton)
end
