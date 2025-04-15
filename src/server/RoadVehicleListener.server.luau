local LastStuff = {
	FL = {},
	FR = {},
	RL = {},
	RR = {},
}

local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(game.ReplicatedStorage:WaitForChild("VehiclePhysics"))
local useState = require(game.ReplicatedStorage.Modules:WaitForChild("useState")) -- Require your module

local VehicleFolder = workspace.Vehicles
local AllCarsMemory = {}
local ExistingCarsTable = {}
local PhysicsStates = {} -- Store physics state for each vehicle
local VehicleInputStates = {} -- Store useState objects for each vehicle

local function AddCar(obj, _cprops) -- Mark cprops as unused
	-- Remove existing Wheels folder or wheel parts to prevent duplicates
	local existingWheels = obj:FindFirstChild("Wheels")
	if existingWheels then
		existingWheels:Destroy()
	end
	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("Model") and child.Name:match("^%a%a$") then -- e.g., FL, FR, RL, RR
			child:Destroy()
		end
	end

	table.insert(ExistingCarsTable,obj)
	-- Only set network ownership if the PrimaryPart is not anchored and not welded to an anchored part
	if obj.PrimaryPart and not obj.PrimaryPart.Anchored then
		local isWeldedToAnchored = false
		for _, constraint in ipairs(obj.PrimaryPart:GetConnectedParts(true)) do
			if constraint.Anchored then
				isWeldedToAnchored = true
				break
			end
		end
		if not isWeldedToAnchored then
			obj.PrimaryPart:SetNetworkOwner(nil)
		end
	end
	AllCarsMemory[obj] = {}
	AllCarsMemory[obj].SpringLengthMemory = {}
	PhysicsStates[obj] = VehiclePhysics.createPhysicsState() -- Initialize physics state

	-- Initialize input states using useState, parented to the car model
	VehicleInputStates[obj] = {
		Throttle = useState(0, "ThrottleInput", obj), -- Initial value 0
		Steer = useState(0, "SteerInput", obj),    -- Initial value 0
		Braking = useState(false, "BrakingInput", obj), -- Initial value false
		IsServerOwned = useState(true, "ServerOwned", obj) -- Add ownership state
	}

	for wheelName, _ in pairs(carProps.getWheelPositions(obj)) do -- Mark v as unused
		AllCarsMemory[obj].SpringLengthMemory[wheelName] = 1.2 -- Use wheelName as key
	end
	-- Handle seat occupant changes
	obj:FindFirstChildOfClass('VehicleSeat'):GetPropertyChangedSignal('Occupant'):Connect(function()
		local seatPart = obj:FindFirstChildOfClass('VehicleSeat')
		local occ = seatPart.Occupant
		local carPrim = obj.PrimaryPart

		if occ then
			local player = game.Players:GetPlayerFromCharacter(occ.Parent)
			if player and carPrim then
				pcall(function()
					carPrim:SetNetworkOwner(player)
					VehicleInputStates[obj].IsServerOwned:set(false) -- Update ownership state
				end)
			end
		else
			 -- Set owner to server *after* ensuring unanchored
			if carPrim then
				pcall(function()
					carPrim:SetNetworkOwner(nil)
					VehicleInputStates[obj].IsServerOwned:set(true) -- Update ownership state
				end)
			end
		end
	end)

	for i,v in pairs(obj:GetChildren())do
		if v:IsA("Seat")then
			v:GetPropertyChangedSignal('Occupant'):Connect(function()--event if seat's occupant value changed
				local carPrim = obj.PrimaryPart -- Get PrimaryPart again for this scope
				if v.Occupant then
					local player = game.Players:GetPlayerFromCharacter(v.Occupant.Parent)
					if player then--if not npc
						-- Ensure unanchored before setting owner (server-side for other seats)
						if carPrim and carPrim.Anchored then
							carPrim.Anchored = false
						end
						-- Don't change owner if it's already the player in the driver seat
						--[[ wait()
						if obj.PrimaryPart:GetNetworkOwner()==player then
							obj.PrimaryPart:SetNetworkOwner(nil)
						end ]]-- Logic seems redundant/potentially problematic, commented out
					end
				else -- Occupant left a non-driver seat
					-- No need to anchor/unanchor here, driver seat logic handles ownership
				end
			end)
		end
	end
	--wheels
	local WheelFolder = Instance.new("Folder",obj)
	WheelFolder.Name = 'Wheels'

	for i,v in pairs(carProps.getWheelPositions(obj))do

		local ClonedWheel = carProps.getWheelModel(obj)
		ClonedWheel.Parent = WheelFolder
		ClonedWheel.Name = i

		local wheelParts = ClonedWheel:GetChildren();
		for k,v in pairs(wheelParts) do
			v.CanCollide = false
		end

		local weld = Instance.new("Weld",ClonedWheel)
		weld.Part0 = obj.PrimaryPart
		weld.Part1 = ClonedWheel.PrimaryPart
		weld.C0 = CFrame.new(carProps.getWheelPositions(obj)[i])
		if v.x > 0 then
			weld.C0 = weld.C0 * CFrame.Angles(0, math.rad(180), 0)
		end
	end
end

for _,object in pairs(VehicleFolder:GetChildren())do
	AddCar(object)
end

-- Add listener for cars added after initialization
VehicleFolder.ChildAdded:Connect(function(child)
	-- Optionally check if it's a valid car model (has PrimaryPart, etc.)
	if child:IsA("Model") and child.PrimaryPart then
		AddCar(child)
	end
end)

local function SpawnCar(carName)

	-- reading VehiclePropertiesList
	local props = carProps[carName]

	if props then

		--remember that it is what it is
		local clonedCar = props.model:Clone()

		clonedCar.Parent = workspace.Vehicles
		clonedCar:MoveTo(Vector3.new(math.random(-50,50),10,math.random(-50,50)))
		clonedCar:SetAttribute("id",carName)

		AddCar(clonedCar,props)

		return clonedCar
	end
end



for _, v in pairs(game.ReplicatedFirst.Vehicles:GetChildren()) do
	SpawnCar(v.Name)
end


local WhatPlayerCarTab = {}
game.Players.PlayerAdded:Connect(function(p)

	local isP = p.MembershipType == Enum.MembershipType.Premium
	p.CharacterAdded:Connect(function(c)

		local nc = SpawnCar("Obey-Drifter")
		nc:SetAttribute("owner",p.Name)
		WhatPlayerCarTab[p] = nc
	end)

	p.CharacterRemoving:Connect(function(c)

		if WhatPlayerCarTab[p] then
			WhatPlayerCarTab[p]:Destroy()
		end
	end)

	if isP or game["Run Service"]:IsStudio() then

		wait(1)
	else

		wait(10)
	end
end)

local function getAllLightTypesInside(parent: Instance): {Light}
	local lightObjects = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
			table.insert(lightObjects, child)
		else --if it's a part, it can have lights inside
			local foundLights = getAllLightTypesInside(child)
			for _, x in ipairs(foundLights) do
				table.insert(lightObjects, x)
			end
		end
	end
	return lightObjects
end

local function switchLightsInside(parent: Instance, state: true|false)
	local lightObjects = getAllLightTypesInside(parent)
	for _, x in ipairs(lightObjects) do
		x.Enabled = true
	end
    return;
end

local LIGHTS_STATE = true
game.ReplicatedStorage.SwitchLight.OnServerEvent:Connect(function(plr)

	if plr.Character and plr.Character.Humanoid.SeatPart and plr.Character.Humanoid.SeatPart:FindFirstAncestor('Vehicles')then

		local partsModel = plr.Character.Humanoid.SeatPart:FindFirstAncestorOfClass('Model').RootPart
		LIGHTS_STATE = not LIGHTS_STATE;
		switchLightsInside(partsModel.HLL,LIGHTS_STATE)
		switchLightsInside(partsModel.TLL,LIGHTS_STATE)
		switchLightsInside(partsModel.HLR,LIGHTS_STATE)
		switchLightsInside(partsModel.TLR,LIGHTS_STATE)
	end
end)


game.ReplicatedStorage.AskForDoor.OnServerEvent:Connect(function(plr)
    if plr.Character then
        local nearestcar, nearestdist = nil, 10
        for _, v in pairs(workspace.Vehicles:GetChildren()) do
            local dist = (v.PrimaryPart.Position - plr.Character.HumanoidRootPart.Position).magnitude
            if dist < nearestdist then
                nearestcar = v
                nearestdist = dist
            end
        end

        if nearestcar then
            local nearestseat, seatDist = nil, nearestdist
            for _, v in pairs(nearestcar:GetChildren()) do
                if (v:IsA('VehicleSeat') or v:IsA("Seat")) and not v.Occupant then
                    local dist = (v.Position - plr.Character.HumanoidRootPart.Position).magnitude
                    if dist < seatDist then
                        nearestseat = v
                        seatDist = dist
                    end
                end
            end

            if nearestseat then
                -- Open door using hinge constraint
                local curHingeConstraint = nearestcar.PrimaryPart[nearestseat.Name]
                if curHingeConstraint then
                    curHingeConstraint.TargetAngle = 90
                    task.wait(0.5)
                    -- Don't automatically close the door, let the client handle that after entry
                end
            end
        end
    end
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpawnPlayerCarEvent = ReplicatedStorage:WaitForChild("SpawnPlayerCar")

-- Table to track which car belongs to which player
local PlayerCars = {}

game.Players.PlayerRemoving:Connect(function(player)
	if PlayerCars[player] then
		PlayerCars[player]:Destroy()
		PlayerCars[player] = nil
	end
end)

SpawnPlayerCarEvent.OnServerEvent:Connect(function(player)
	if PlayerCars[player] and PlayerCars[player].Parent then
		return -- Already has a car
	end
	-- Get all available car names from carProps (only those with a 'model' property)
	local carNames = {}
	for name, value in pairs(carProps) do
		if type(value) == "table" and value.model then
			table.insert(carNames, name)
		end
	end
	if #carNames == 0 then return end
	local randomCarName = carNames[math.random(1, #carNames)]
	local car = SpawnCar(randomCarName)
	if car then
		car:SetAttribute("owner", player.Name)
		PlayerCars[player] = car
		-- Optionally move car to player spawn location
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			car:MoveTo(player.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0))
		end
	end
end)

while true do
    local delta = game["Run Service"].PreSimulation:Wait()
    local success, err = pcall(function()
        for _, carModel in pairs(ExistingCarsTable) do
            local carPrim = carModel.PrimaryPart or carModel:FindFirstChild("Main Part")
            if not carPrim then continue end

            -- Check network ownership without anchoring checks
            local isNetworkOwned = carPrim:GetNetworkOwner() ~= nil

            -- Only process physics if server owns the car
            if not isNetworkOwned then
                local id = carModel:GetAttribute("id")
                local props = carProps[id]
                local inputStates = VehicleInputStates[carModel]

                -- Get current inputs from useState objects
                local throttle = inputStates.Throttle:get() or 0
                local steer = inputStates.Steer:get() or 0
                local braking = inputStates.Braking:get() or false

                -- Check if a player is in the seat
                local seat = carModel:FindFirstChildOfClass('VehicleSeat')
                local occupant = seat and seat.Occupant
                local isPlayerInSeat = false
                if occupant then
                    local player = game.Players:GetPlayerFromCharacter(occupant.Parent)
                    isPlayerInSeat = player ~= nil
                end
                local isBoosting = false
                if not isPlayerInSeat then
                    -- If no player, never boost or brake
                    braking = false
                    isBoosting = false
                end

                -- Update physics using shared module and state inputs
                local wheelStates = VehiclePhysics.updateVehiclePhysics(
                    carModel,
                    PhysicsStates[carModel],
                    props,
                    delta,
                    throttle, -- Pass throttle from state
                    steer,    -- Pass steer from state
                    braking,   -- Pass braking from state
                    isBoosting, -- Pass boosting state
                    props.PhysicsConstraints -- Pass constraints from props
                )

                -- Update visual wheel rotations
                if wheelStates then
                    for wheelName, state in pairs(wheelStates) do
                        local wheel = carModel.Wheels:FindFirstChild(wheelName)
                        if wheel and wheel:FindFirstChild("Weld") then
                            local weld = wheel.Weld
                            local basePos = carProps.getWheelPositions(carModel)[wheelName]

                            local weldInitPos = CFrame.new(basePos - Vector3.new(0, state.springLength, 0))
                            if string.sub(wheelName,1,1)=='F' then
                                weldInitPos = weldInitPos * CFrame.Angles(0,-math.rad(PhysicsStates[carModel].steeringAngle),0)
                            end

                            weld.C0 = weldInitPos
                            if basePos.x > 0 then
                                weld.C0 = weld.C0 * CFrame.Angles(0,math.rad(180),0)
                                weld.C0 = weld.C0 * CFrame.Angles(-state.wheelRotation,0,0)
                            else
                                weld.C0 = weld.C0 * CFrame.Angles(state.wheelRotation,0,0)
                            end
                        end
                    end
                end
            end
        end
    end)
    if not success then
        warn("[Vehicle Loop Error]:", err)
    end
end