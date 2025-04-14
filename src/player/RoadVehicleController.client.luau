local VisualiseRaycast = false

local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(game.ReplicatedStorage:WaitForChild("VehiclePhysics"))
local useState = require(game.ReplicatedStorage:WaitForChild("useState"))
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local PlrGui = player.PlayerGui
local RunService = game:GetService("RunService")

PlrGui.gaag.ag:ClearAllChildren()
PlrGui.gaag.ag2:ClearAllChildren()

local humanoid = nil
humanoid = (function() repeat task.wait() until char:FindFirstChild("Humanoid"); return char.Humanoid end)()

local isBraking = false
local isBoosting = false
local activeVehicleState = nil
local vehicleInputStates = nil -- To store references to the useState objects

-- Create a separate function for visual updates that can run regardless of network ownership
local function updateWheelVisuals(carModel, wheelStates, physicsState)
    if not wheelStates then return end

    for wheelName, state in pairs(wheelStates) do
        local wheel = carModel.Wheels:FindFirstChild(wheelName)
        if wheel and wheel:FindFirstChild("Weld") then
            local weld = wheel.Weld
            local basePos = carProps.getWheelPositions(carModel)[wheelName]

            local weldInitPos = CFrame.new(basePos - Vector3.new(0, state.springLength, 0))
            -- Apply Y-axis rotation of 180 degrees first
            weldInitPos = weldInitPos * CFrame.Angles(0, math.rad(180), 0)

            -- Then apply steering if it's a front wheel
            if string.sub(wheelName,1,1)=='F' then
                weldInitPos = weldInitPos * CFrame.Angles(0,-math.rad(physicsState.steeringAngle),0)
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

-- Create separate function for steering update loop
local function startSteeringUpdateLoop(seatPart, carModel, props, activeVehicleState)
    local steeringThread = coroutine.create(function()
        local lastSteerValue = 0

        while seatPart and carModel:IsDescendantOf(workspace) do
            local delta = RunService.RenderStepped:Wait()

            -- Get current steer value directly from VehicleSeat
            local currentSteer = seatPart.SteerFloat

            -- Only update if steering changed
            if currentSteer ~= lastSteerValue then
                -- Update steering angle in our physics state
                local targetSteer = currentSteer * props.SteerAngle
                activeVehicleState.steeringAngle = activeVehicleState.steeringAngle +
                    (targetSteer - activeVehicleState.steeringAngle) * math.min(1, delta * 10)

                -- Update wheel visuals for steering
                for wheelName, _ in pairs(carProps.getWheelPositions(carModel)) do
                    local wheel = carModel.Wheels:FindFirstChild(wheelName)
                    if wheel and wheel:FindFirstChild("Weld") and string.sub(wheelName,1,1)=='F' then
                        local weld = wheel.Weld
                        local basePos = carProps.getWheelPositions(carModel)[wheelName]

                        -- Get current spring length from physics state or use max
                        local springLength = activeVehicleState.springLengthMemory[wheelName]
                            or props.SuspensionMaxLength

                        local weldInitPos = CFrame.new(basePos - Vector3.new(0, springLength, 0))
                        weldInitPos = weldInitPos * CFrame.Angles(0, -math.rad(activeVehicleState.steeringAngle), 0)

                        -- Preserve wheel rotation but update steering
                        local currentRotation = if basePos.x > 0
                            then -activeVehicleState.wheelRotations[wheelName]
                            else activeVehicleState.wheelRotations[wheelName]

                        weld.C0 = weldInitPos
                        if basePos.x > 0 then
                            weld.C0 = weld.C0 * CFrame.Angles(0,math.rad(180),0)
                            weld.C0 = weld.C0 * CFrame.Angles(currentRotation,0,0)
                        else
                            weld.C0 = weld.C0 * CFrame.Angles(currentRotation,0,0)
                        end
                    end
                end

                lastSteerValue = currentSteer
            end
        end
    end)

    -- Start the steering thread
    coroutine.resume(steeringThread)
    return steeringThread
end

humanoid.Seated:Connect(function(seated, seatPart)
    if seated and seatPart then
        if seatPart:IsA("VehicleSeat") and seatPart:FindFirstAncestor('Vehicles') then
            local carModel = seatPart.Parent
            local carPrim = carModel.PrimaryPart

            if not carPrim then return end

            if carPrim.Anchored then
                carPrim.Anchored = false
            end

            local id = carModel:GetAttribute("id")
            local props = carProps[id]

            -- Create new physics state for this vehicle session
            activeVehicleState = VehiclePhysics.createPhysicsState()

            -- Find the input states created by the server
            vehicleInputStates = {
                Throttle = useState(0, "ThrottleInput", carModel), -- Hook into existing state
                Steer = useState(0, "SteerInput", carModel),    -- Hook into existing state
                Braking = useState(false, "BrakingInput", carModel) -- Hook into existing state
            }

            local isBraking = false -- Local variable for client-side brake detection
            local serverTakeOverWait = 0 -- Initialize this variable for the scope

            -- Set up steering state change listener that updates visuals regardless of ownership
            local steerConnection
            steerConnection = vehicleInputStates.Steer.useEffect:Connect(function(newSteerValue)
                if not activeVehicleState then return end

                -- Update our local physics state's steering angle
                local targetSteer = newSteerValue * props.SteerAngle
                activeVehicleState.steeringAngle = activeVehicleState.steeringAngle +
                    (targetSteer - activeVehicleState.steeringAngle) * 0.1 -- Smoothing factor

                -- Calculate wheel states without applying forces
                local wheelStates = {}
                for wheelName, originalPosition in pairs(carProps.getWheelPositions(carModel)) do
                    wheelStates[wheelName] = {
                        springLength = activeVehicleState.springLengthMemory[wheelName] or props.SuspensionMaxLength,
                        wheelRotation = activeVehicleState.wheelRotations[wheelName] or 0
                    }
                end

                -- Update visuals using current state
                updateWheelVisuals(carModel, wheelStates, activeVehicleState)
            end)

            -- Bind Brake Action
            game.ContextActionService:BindAction("BrakeVehicle", function(_actionName, inputState, _inputObject)
                if inputState == Enum.UserInputState.Begin then
                    isBraking = true
                    if vehicleInputStates then vehicleInputStates.Braking:set(true) end
                elseif inputState == Enum.UserInputState.End then
                    isBraking = false
                    if vehicleInputStates then vehicleInputStates.Braking:set(false) end
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.Space)

            -- Bind Boost Action (LeftShift)
            game.ContextActionService:BindAction("BoostVehicle", function(_actionName, inputState, _inputObject)
                if inputState == Enum.UserInputState.Begin then
                    isBoosting = true
                elseif inputState == Enum.UserInputState.End then
                    isBoosting = false
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.LeftShift)

            local lastUpdateTime = os.clock()

            -- Start independent steering update loop
            local steeringThread = startSteeringUpdateLoop(seatPart, carModel, props, activeVehicleState)

            while true do
                local delta = RunService.Heartbeat:Wait()

                local currentCarPrim = carModel.PrimaryPart -- Use a different name to avoid shadowing
                if not currentCarPrim then continue end

                -- Always update input states, even without network ownership
                local currentThrottle = seatPart.ThrottleFloat
                local currentSteer = seatPart.SteerFloat
                local currentBraking = isBraking
                local currentBoosting = isBoosting

                if vehicleInputStates then
                    vehicleInputStates.Throttle:set(currentThrottle)
                    vehicleInputStates.Steer:set(currentSteer)
                    -- Braking is set in BindAction callback
                end

                -- Update physics using shared module and CURRENT inputs
                local wheelStates = VehiclePhysics.updateVehiclePhysics(
                    carModel,
                    activeVehicleState,
                    props,
                    delta,
                    currentThrottle, -- Pass current throttle
                    currentSteer,    -- Pass current steer
                    currentBraking,  -- Pass current braking state
                    currentBoosting, -- Pass current boosting state
                    props.PhysicsConstraints -- Pass constraints from props
                )

                -- Update visual wheel rotations
                updateWheelVisuals(carModel, wheelStates, activeVehicleState)
            end

            -- Clean up steering thread when exiting
            coroutine.close(steeringThread)

            -- Clean up when exiting vehicle
            game.ContextActionService:UnbindAction("BrakeVehicle")
            -- Reset states if they exist
            if vehicleInputStates then
                 vehicleInputStates.Throttle:set(0)
                 vehicleInputStates.Steer:set(0)
                 vehicleInputStates.Braking:set(false)
            end
            activeVehicleState = nil
            vehicleInputStates = nil -- Clear references

            if steerConnection then
                steerConnection:Disconnect()
            end

            -- Fix the scope issue for serverTakeOverWait in exit handling
            -- The exit animation/logic should likely run regardless of the timer now,
            -- as the loop breaks when ownership is lost.
            -- Consider removing the serverTakeOverWait check here if exit should always happen.
            -- if serverTakeOverWait < 3.0 then -- This check might be redundant now
            local exitCarModel = seatPart.Parent -- Use different variable names
            local exitCarPrim = exitCarModel.PrimaryPart

            if not exitCarPrim then return end

            -- local exitId = exitCarModel:GetAttribute("id") -- Unused
            -- local exitProps = carProps[exitId] -- Unused

            local curHingeConstraint = exitCarPrim:FindFirstChild(seatPart.Name)
            if curHingeConstraint and curHingeConstraint:IsA("HingeConstraint") then
                 curHingeConstraint.TargetAngle = 90
            end

            game.TweenService:Create(seatPart.SeatWeld,TweenInfo.new(0.5),{
                C1 = CFrame.new(),
                C0 = seatPart.SeatWeld.C0 * seatPart.SeatWeld.C1:Inverse() * CFrame.new(math.sign(curHingeConstraint.Attachment0.Position.x)*6,0,0)
            }):Play()

            wait(0.5)

            humanoid.Sit = false
            humanoid.PlatformStand = false
        end
    end
end)

game.ContextActionService:BindAction('lightButton', function(n,istate,iobject)

    if humanoid.SeatPart and istate==Enum.UserInputState.Begin then
        game.ReplicatedStorage.SwitchLight:FireServer()
    end

end, false, Enum.KeyCode.L)


game.ContextActionService:BindAction('EnterCar',function(n,istate,iobject)

    if istate==Enum.UserInputState.Begin then

        if humanoid.SeatPart then -- Player is currently seated, handle exit

            local currentSeat = humanoid.SeatPart
            local carModel = currentSeat:FindFirstAncestorOfClass("Model")
            local carPrim = carModel and carModel.PrimaryPart

            local curHingeConstraint = carModel and carPrim and carPrim:FindFirstChild(currentSeat.Name) -- Safer access
            if curHingeConstraint and curHingeConstraint:IsA("HingeConstraint") then
                curHingeConstraint.TargetAngle = 90
            end

            -- Check if it's a VehicleSeat before accessing SeatWeld
            if currentSeat:IsA("VehicleSeat") then
                local seatWeld = currentSeat:FindFirstChild("SeatWeld")
                if seatWeld then
                    game.TweenService:Create(seatWeld,TweenInfo.new(0.5),{
                        C1 = CFrame.new(),
                        C0 = seatWeld.C0 * seatWeld.C1:Inverse() * CFrame.new(math.sign(curHingeConstraint and curHingeConstraint.Attachment0.Position.x or 1)*6,0,0)
                    }):Play()
                    wait(0.5)
                else
                    wait(0.5) -- Wait even if no weld animation
                end
            else
                wait(0.5) -- Wait if it's a regular seat
            end

            humanoid.Sit = false

            -- Anchor/Unanchor sequence on 'F' key exit
            if carPrim then
                carPrim.Anchored = true
                task.wait(0.1) -- Brief anchor duration
                carPrim.Anchored = false
            end

        else -- Player is not seated, handle enter
            local nearestcar, nearestdist = nil, 10

            for i,v in pairs(workspace.Vehicles:GetChildren())do
                local primPart = v.PrimaryPart
                if not primPart then continue end -- Skip if no primary part
                local dist = (primPart.Position - char.HumanoidRootPart.Position).Magnitude

                if dist < nearestdist then
                    nearestcar = v
                    nearestdist = dist
                end

            end

            if nearestcar then

                local carRotations = CFrame.lookAt(Vector3.zero,nearestcar.PrimaryPart.CFrame.LookVector,nearestcar.PrimaryPart.CFrame.UpVector)

                game.ReplicatedStorage.AskForDoor:FireServer()

                wait(0.2)

                local nearestseat, seatDist = nil, nearestdist -- Use nearestdist as initial max for seat
                for i,v in pairs(nearestcar:GetChildren())do

                    if (v:IsA('VehicleSeat') or v:IsA("Seat")) and not v.Occupant then
                        local dist = (v.Position - char.HumanoidRootPart.Position).magnitude
                        -- Check if it's the closest seat overall
                        if not nearestseat or dist < seatDist then -- Use seatDist
                            nearestseat = v
                            seatDist = dist -- Update seatDist
                        end
                    end

                end

                if nearestseat then

                    local curCFram = char.HumanoidRootPart.CFrame
                    nearestseat:Sit(humanoid)

                    -- Animation logic (already checks for VehicleSeat)
                    if nearestseat:IsA("VehicleSeat") then
                        local seatweld = nearestseat:WaitForChild("SeatWeld", 0.5) -- Add timeout
                        if seatweld then
                            local oldC0 = seatweld.C0
                            local oldC1 = seatweld.C1
                            seatweld.C0 = nearestseat.CFrame:ToObjectSpace(curCFram)
                            seatweld.C1 = CFrame.new()
                            game.TweenService:Create(seatweld,TweenInfo.new(0.35),{
                                C1 = oldC1,
                                C0 = oldC0
                            }):Play()
                            wait(0.2)
                            local hinge = nearestcar.PrimaryPart:FindFirstChild(nearestseat.Name)
                            if hinge and hinge:IsA("HingeConstraint") then
                                hinge.TargetAngle = 0
                            end
                        end
                    else
                        -- Handle regular seats or cases where SeatWeld doesn't appear
                        wait(0.2)
                        local hinge = nearestcar.PrimaryPart:FindFirstChild(nearestseat.Name)
                        if hinge and hinge:IsA("HingeConstraint") then
                            hinge.TargetAngle = 0
                        end
                    end
                end

            end

        end

    end

    -- Unbind Brake Action if player exits manually (redundant? Seated event handles unbind)
    -- game.ContextActionService:UnbindAction("BrakeVehicle")
    -- isBraking = false
    -- Removed JumpOutDisabled check

end,false,Enum.KeyCode.F)