local _VisualiseRaycast = false -- Prefix with _ since unused

local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(game.ReplicatedStorage:WaitForChild("VehiclePhysics"))
local useState = require(game.ReplicatedStorage.Modules:WaitForChild("useState"))
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local PlrGui = player.PlayerGui
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

PlrGui.gaag.ag:ClearAllChildren()
PlrGui.gaag.ag2:ClearAllChildren()

-- Initialize humanoid with proper line breaks
local humanoid
local function initHumanoid()
    repeat
        task.wait()
    until char:FindFirstChild("Humanoid")
    return char.Humanoid
end
humanoid = initHumanoid()

local isBraking = false
local isBoosting = false
local activeVehicleState = nil
local vehicleInputStates = nil -- To store references to the useState objects
local ownershipConnection = nil
local steeringThread = nil

-- Create a separate function for visual updates that can run regardless of network ownership
local function updateWheelVisuals(carModel, wheelStates, physicsState)
    if not wheelStates then return end

    for wheelName, state in pairs(wheelStates) do
        local wheel = carModel.Wheels:FindFirstChild(wheelName)
        if wheel and wheel:FindFirstChild("Weld") then
            local weld = wheel.Weld
            local basePos = carProps.getWheelPositions(carModel)[wheelName]

            local weldInitPos = CFrame.new(basePos - Vector3.new(0, state.springLength, 0))
            if string.sub(wheelName,1,1)=='F' then
                weldInitPos = weldInitPos * CFrame.Angles(0, -math.rad(physicsState.steeringAngle), 0)
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

-- Create separate function for steering update loop
local function startSteeringUpdateLoop(seatPart, carModel, props, activeVehicleStateRef)
    local thread = coroutine.create(function()
        local lastSteerValue = 0

        while seatPart and carModel:IsDescendantOf(workspace) do
            local delta = RunService.RenderStepped:Wait()

            -- Get current steer value directly from VehicleSeat
            local currentSteer = seatPart.SteerFloat

            -- Only update if steering changed
            if currentSteer ~= lastSteerValue then
                -- Update steering angle in our physics state
                local targetSteer = currentSteer * props.SteerAngle
                activeVehicleStateRef.steeringAngle = activeVehicleStateRef.steeringAngle +
                    (targetSteer - activeVehicleStateRef.steeringAngle) * math.min(1, delta * 10)

                -- Update wheel visuals for steering
                for wheelName, _ in pairs(carProps.getWheelPositions(carModel)) do
                    local wheel = carModel.Wheels:FindFirstChild(wheelName)
                    if wheel and wheel:FindFirstChild("Weld") and string.sub(wheelName,1,1)=='F' then
                        local weld = wheel.Weld
                        local basePos = carProps.getWheelPositions(carModel)[wheelName]

                        -- Get current spring length from physics state or use max
                        local springLength = activeVehicleStateRef.springLengthMemory[wheelName]
                            or props.SuspensionMaxLength

                        local weldInitPos = CFrame.new(basePos - Vector3.new(0, springLength, 0))
                        weldInitPos = weldInitPos * CFrame.Angles(0, -math.rad(activeVehicleStateRef.steeringAngle), 0)

                        -- Preserve wheel rotation but update steering
                        local currentRotation = if basePos.x > 0
                            then -activeVehicleStateRef.wheelRotations[wheelName]
                            else activeVehicleStateRef.wheelRotations[wheelName]

                        weld.C0 = weldInitPos
                        if basePos.x > 0 then
                            weld.C0 = weld.C0 * CFrame.Angles(0,0,0)
                            weld.C0 = weld.C0 * CFrame.Angles(currentRotation,0,0)
                        else
                            weld.C0 = weld.C0 * CFrame.Angles(currentRotation,0,0)
                            weld.C0 = weld.C0 * CFrame.Angles(0, math.rad(180), 0)
                        end
                    end
                end

                lastSteerValue = currentSteer
            end
        end
    end)

    coroutine.resume(thread)
    return thread
end

-- Clean up function to handle all disconnections and state resets
local simRoutine = nil;
local function cleanupVehicle()
    if ownershipConnection then
        ownershipConnection:Disconnect()
        ownershipConnection = nil
    end

    if steeringThread then
        coroutine.close(steeringThread)
        steeringThread = nil
    end

    ContextActionService:UnbindAction("BrakeVehicle")
    ContextActionService:UnbindAction("ToggleParking")

    if vehicleInputStates then
        vehicleInputStates.Throttle:set(0)
        vehicleInputStates.Steer:set(0)
        vehicleInputStates.Braking:set(false)
    end

    activeVehicleState = nil
    vehicleInputStates = nil
    isBraking = false
    isBoosting = false
    simRoutine:Disconnect();
end

humanoid.Seated:Connect(function(isSeated, seat)
    if isSeated and seat then
        if seat:IsA("VehicleSeat") and seat:FindFirstAncestor('Vehicles') then
            local carModel = seat.Parent
            local carPrim = carModel.PrimaryPart
            if not carPrim then return end
            -- Removed GetNetworkOwner() call (server-only API)
            print("[DEBUG] LocalPlayer is:", tostring(player))
            local id = carModel:GetAttribute("id")
            local props = carProps[id]
            -- Immediately start physics and input as soon as seated
            activeVehicleState = VehiclePhysics.createPhysicsState()
            vehicleInputStates = {
                Throttle = useState(0, "ThrottleInput", carModel),
                Steer = useState(0, "SteerInput", carModel),
                Braking = useState(false, "BrakingInput", carModel)
            }
            steeringThread = startSteeringUpdateLoop(seat, carModel, props, activeVehicleState)
            -- Bind Brake Action (Space)
            ContextActionService:BindAction("BrakeVehicle", function(_actionName, inputState)
                if inputState == Enum.UserInputState.Begin then
                    isBraking = true
                    if vehicleInputStates then
                        vehicleInputStates.Braking:set(true)
                    end
                elseif inputState == Enum.UserInputState.End then
                    isBraking = false
                    if vehicleInputStates then
                        vehicleInputStates.Braking:set(false)
                    end
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.Space)
            -- Add Parking Brake Toggle (P key)
            ContextActionService:BindAction("ToggleParking", function(_actionName, inputState, _inputObject)
                if inputState == Enum.UserInputState.Begin and activeVehicleState then
                    activeVehicleState.isParked = not activeVehicleState.isParked
                    if activeVehicleState.isParked then
                        print("Parking brake engaged")
                    else
                        print("Parking brake released")
                    end
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.P)
            -- Main control loop (no ownership wait)

            simRoutine = RunService.Heartbeat:Connect(function(delta: number)
                if humanoid.Sit and seat:IsDescendantOf(workspace) then
                    local currentCarPrim = carModel.PrimaryPart
                    if not currentCarPrim then return end
                    local currentThrottle = seat.ThrottleFloat
                    local currentSteer = seat.SteerFloat
                    local currentBraking = isBraking
                    local currentBoosting = isBoosting
                    if vehicleInputStates then
                        vehicleInputStates.Throttle:set(currentThrottle)
                        vehicleInputStates.Steer:set(currentSteer)
                    end
                    local wheelStates = VehiclePhysics.updateVehiclePhysics(
                        carModel,
                        activeVehicleState,
                        props,
                        delta,
                        currentThrottle,
                        currentSteer,
                        currentBraking,
                        currentBoosting,
                        props.PhysicsConstraints
                    )
                    updateWheelVisuals(carModel, wheelStates, activeVehicleState)
                else

                    cleanupVehicle()

                end
            end)
        end
    end
end)

-- Handle cleanup when player exits vehicle
humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
    if not humanoid.Sit then
        cleanupVehicle()
    end
end)

-- Handle F key for entering vehicles
ContextActionService:BindAction("EnterVehicle", function(_, inputState)
    if inputState ~= Enum.UserInputState.Begin then return end
    if humanoid.Sit then
        -- If seated, pressing F exits the car
        local seatPart = humanoid.SeatPart
        if seatPart and seatPart:IsA("BasePart") then
            local exitOffset = seatPart.CFrame.RightVector * 0 -- 4 studs to the right of the seat
            local exitPosition = seatPart.Position + exitOffset + Vector3.new(0, 10, 0) -- 2 studs above ground
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(exitPosition, exitPosition + seatPart.CFrame.LookVector)
            end
        end
        humanoid.Sit = false
        return
    end
    -- If not seated, try to enter the nearest car
    game.ReplicatedStorage.AskForDoor:FireServer()
    task.wait(0.2)
    local nearestcar, nearestdist = nil, 24
    for _, v in pairs(workspace.Vehicles:GetChildren()) do
        local primPart = v.PrimaryPart
        if not primPart then continue end
        local dist = (primPart.Position - char.HumanoidRootPart.Position).Magnitude
        if dist < nearestdist then
            nearestcar = v
            nearestdist = dist
        end
    end
    if nearestcar then
        local nearestseat, seatDist = nil, nearestdist
        for _, v in pairs(nearestcar:GetChildren()) do
            if (v:IsA('VehicleSeat') or v:IsA("Seat")) and not v.Occupant then
                local dist = (v.Position - char.HumanoidRootPart.Position).Magnitude
                if dist < seatDist then
                    nearestseat = v
                    seatDist = dist
                end
            end
        end
        if nearestseat then
            local curCFrame = char.HumanoidRootPart.CFrame
            nearestseat:Sit(humanoid)
            if nearestseat:IsA("VehicleSeat") then
                local seatweld = nearestseat:FindFirstChild("SeatWeld")
                if seatweld then
                    local oldC0 = seatweld.C0
                    local oldC1 = seatweld.C1
                    seatweld.C0 = nearestseat.CFrame:ToObjectSpace(curCFrame)
                    seatweld.C1 = CFrame.new()
                    TweenService:Create(seatweld, TweenInfo.new(0.35), {
                        C1 = oldC1,
                        C0 = oldC0
                    }):Play()
                    task.wait(0.2)
                    local hinge = nearestcar.PrimaryPart:FindFirstChild(nearestseat.Name)
                    if hinge and hinge:IsA("HingeConstraint") then
                        hinge.TargetAngle = 0
                    end
                end
            end
        end
    end
end, false, Enum.KeyCode.F)

-- Handle L key for lights
ContextActionService:BindAction("lightButton", function(_, inputState)
    if humanoid.SeatPart and inputState == Enum.UserInputState.Begin then
        game.ReplicatedStorage.SwitchLight:FireServer()
    end
end, false, Enum.KeyCode.L)