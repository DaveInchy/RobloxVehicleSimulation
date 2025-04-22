local LastStuff = {
	FL = {},
	FR = {},
	RL = {},
	RR = {},
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleModules = Modules:WaitForChild("Vehicle")

local carProps = require(VehicleModules:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(VehicleModules:WaitForChild("VehiclePhysics"))
local useState = require(Modules:WaitForChild("useState")) -- Require your module

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

	table.insert(ExistingCarsTable, obj)

	-- Initialize server-side states
	AllCarsMemory[obj] = {}
	AllCarsMemory[obj].SpringLengthMemory = {}
	PhysicsStates[obj] = VehiclePhysics.createPhysicsState()

	-- Initialize input states using useState
	VehicleInputStates[obj] = {
		Throttle = useState(0, "ThrottleInput", obj),
		Steer = useState(0, "SteerInput", obj),
		Braking = useState(false, "BrakingInput", obj),
		IsServerOwned = useState(true, "ServerOwned", obj)
	}

	-- Set up wheel memory
	for wheelName, _ in pairs(carProps.getWheelPositions(obj)) do
		AllCarsMemory[obj].SpringLengthMemory[wheelName] = 1.5
	end

	-- Handle seat occupancy changes
	local driverSeat = obj:FindFirstChildOfClass('VehicleSeat')
	if driverSeat then
		driverSeat:GetPropertyChangedSignal('Occupant'):Connect(function()
			local occ = driverSeat.Occupant
			local carPrim = obj.PrimaryPart
			if not carPrim then return end
			if occ then
				local player = game.Players:GetPlayerFromCharacter(occ.Parent)
				if player then
					carPrim:SetNetworkOwner(player)
					print("[SERVER DEBUG] SetNetworkOwner to", player.Name, "Current owner:", tostring(carPrim:GetNetworkOwner()))
				end
			else
				carPrim:SetNetworkOwner(nil)
				print("[SERVER DEBUG] SetNetworkOwner to nil (server). Current owner:", tostring(carPrim:GetNetworkOwner()))
			end
		end)
	end

	-- Set up wheels
	local WheelFolder = Instance.new("Folder", obj)
	WheelFolder.Name = 'Wheels'

	for i, v in pairs(carProps.getWheelPositions(obj)) do
		local ClonedWheel = carProps.getWheelModel(obj)
		ClonedWheel.Parent = WheelFolder
		ClonedWheel.Name = i

		for _, part in pairs(ClonedWheel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end

		local weld = Instance.new("Weld", ClonedWheel)
		weld.Part0 = obj.PrimaryPart
		weld.Part1 = ClonedWheel.PrimaryPart
		weld.C0 = CFrame.new(carProps.getWheelPositions(obj)[i])
		if v.x > driverSeat.Position.X then
			weld.C0 = weld.C0 * CFrame.Angles(0, 0, 0)
		else
			weld.C0 = weld.C0 * CFrame.Angles(0, math.rad(180), 0)
		end
	end
end

-- Add listener for cars added after initialization
VehicleFolder.ChildAdded:Connect(function(child)
    if child:IsA("Model") then
        if child.PrimaryPart then
            AddCar(child)
        else
            child:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
                if child.PrimaryPart then
                    AddCar(child)
                end
            end)
        end
    end
end)

local function SpawnCar(carName)
    local props = carProps[carName]
    if not props then return end

    local clonedCar = props.model:Clone()
    clonedCar.Parent = workspace.Vehicles
    clonedCar:SetAttribute("id", carName)

    -- Move to spawn position before adding physics
    local spawnPos = Vector3.new(math.random(-50,50), 10, math.random(-50,50))
    clonedCar:PivotTo(CFrame.new(spawnPos))

    -- Initialize the car's physics and components
    AddCar(clonedCar, props)

    -- Make sure network ownership is properly set
    if clonedCar.PrimaryPart then
        task.spawn(function()
            pcall(function()
                clonedCar.PrimaryPart:SetNetworkOwner(nil)
            end)
        end)
    end

    return clonedCar
end


local WhatPlayerCarTab = {}
game.Players.PlayerAdded:Connect(function(p)

	local isP = p.MembershipType == Enum.MembershipType.Premium

	p.CharacterRemoving:Connect(function(c)

		if WhatPlayerCarTab[p] then
			WhatPlayerCarTab[p]:Destroy()
		end
	end)
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
		-- remove the old car

		PlayerCars[player]:Destroy()
		PlayerCars[player] = nil

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

local RunService = game:GetService("RunService")
local PHYSICS_WAKE_INTERVAL = 0.4 -- seconds

local lastWakeNudge = {}

local REST_STATIC_VEL = 2 -- below this velocity is considered nearly static
local REST_STATIC_SUSP = 1 -- below this suspension delta is considered nearly static
local REST_TIME = 3 -- seconds to enter resting state
local carRestTimers = {}
local carIsResting = {}

RunService.Heartbeat:Connect(function(delta)
    local now = os.clock()
    local success, err = pcall(function()
        for _, carModel in pairs(ExistingCarsTable) do
            if not carModel or not carModel.Parent then
                --print("[DEBUG] Skipping carModel: missing or not in workspace", carModel)
                continue
            end
            local carPrim = carModel.PrimaryPart or carModel:FindFirstChild("Main Part")
            if not carPrim then
                --print("[DEBUG] Skipping carModel: missing PrimaryPart", carModel)
                continue
            end

            -- Nudge physics every PHYSICS_WAKE_INTERVAL seconds
            lastWakeNudge[carModel] = lastWakeNudge[carModel] or 0
            if now - lastWakeNudge[carModel] > PHYSICS_WAKE_INTERVAL then
                carPrim:ApplyImpulse(Vector3.new(1e-3, 0, 0))
                lastWakeNudge[carModel] = now
            end

            -- Resting state logic
            carRestTimers[carModel] = carRestTimers[carModel] or 0
            carIsResting[carModel] = carIsResting[carModel] or false

            local isNearlyStatic = carPrim.AssemblyLinearVelocity.Magnitude < REST_STATIC_VEL and carPrim.AssemblyAngularVelocity.Magnitude < REST_STATIC_VEL
            local suspIsStatic = true
            local physicsState = PhysicsStates[carModel]
            if physicsState and physicsState.springLengthMemory then
                for _, v in pairs(physicsState.springLengthMemory) do
                    if math.abs(v - (physicsState.lastSpring or v)) > REST_STATIC_SUSP then
                        suspIsStatic = false
                        break
                    end
                end
                physicsState.lastSpring = physicsState.springLengthMemory and next(physicsState.springLengthMemory) and physicsState.springLengthMemory[next(physicsState.springLengthMemory)] or 0
            end

            if isNearlyStatic and suspIsStatic then
                carRestTimers[carModel] = carRestTimers[carModel] + delta
                if carRestTimers[carModel] > REST_TIME and not carIsResting[carModel] then
                    -- Enter resting state
                    carPrim.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    carPrim.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    carIsResting[carModel] = true
                end
            else
                carRestTimers[carModel] = 0
                if carIsResting[carModel] then
                    carIsResting[carModel] = false
                end
            end

            -- Check network ownership without anchoring checks
            local isNetworkOwned = carPrim:GetNetworkOwner() ~= nil

            -- Only process physics if server owns the car
            if not isNetworkOwned then -- and not carIsResting[carModel]
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
                        local wheel = carModel.Wheels and carModel.Wheels:FindFirstChild(wheelName)
                        if not wheel or not wheel:FindFirstChild("Weld") then
                            print("[DEBUG] Wheel or Weld missing for", wheelName, carModel)
                            continue
                        end
                        local weld = wheel.Weld
                        local basePos = carProps.getWheelPositions(carModel)[wheelName]

                        local weldInitPos = CFrame.new(basePos - Vector3.new(0, state.springLength, 0))
                        if string.sub(wheelName,1,1)=='F' then
                            weldInitPos = weldInitPos * CFrame.Angles(0,-math.rad(PhysicsStates[carModel].steeringAngle),0)
                        end

                        weld.C0 = weldInitPos
						if basePos.x > 0 then
							weld.C0 = weld.C0 * CFrame.Angles(0,0,0)
							weld.C0 = weld.C0 * CFrame.Angles(-state.wheelRotation,0,0)
						else
							weld.C0 = weld.C0 * CFrame.Angles(state.wheelRotation,0,0)
							weld.C0 = weld.C0 * CFrame.Angles(0, math.rad(180), 0)
						end
                    end
                end
            end
        end
    end)
    if not success then
        warn("[Vehicle Loop Error]:", err)
    end
end)