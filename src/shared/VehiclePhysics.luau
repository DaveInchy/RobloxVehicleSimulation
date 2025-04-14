local VehiclePhysics = {}
local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local RunService = game:GetService("RunService")

-- Constants
local WHEEL_ROTATION_IN_AIR_MULTIPLIER = 0.7 -- Wheels spin slightly slower in air due to air resistance
local WHEEL_ROTATION_SCALE = 1/56 -- Current scale factor from velocity to rotation
local RAYCAST_EXTRA_LENGTH = 2.0 -- How much further to cast the ray beyond max suspension travel

local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 5000,
    MIN_SUSPENSION_LENGTH = 0.2,
    MAX_LATERAL_FORCE = 2000,
    MAX_TRACTION_FORCE = 2500
}

type PhysicsConstraints = {
    MAX_SUSPENSION_FORCE: number,
    MIN_SUSPENSION_LENGTH: number, -- Added type
    MAX_LATERAL_FORCE: number,
    MAX_TRACTION_FORCE: number
}

type VehicleProps = {
    SuspensionMaxLength: number,
    wheelRadius: number,
    Stiffness: number,
    Damper: number,
    wheelFriction: number,
    torque: number,
    MaxSpeed: number,
    SteerAngle: number,
    driverSeatName: string,
    brakeForce: number?,
    PhysicsConstraints: PhysicsConstraints
}

type PhysicsState = {
    springLengthMemory: {[string]: number},
    steeringAngle: number,
    wheelRotations: {[string]: number},
    lastUpdateTime: number
}

function VehiclePhysics.createPhysicsState(): PhysicsState
    return {
        springLengthMemory = {},
        steeringAngle = 0,
        wheelRotations = {},
        lastUpdateTime = os.clock()
    }
end

-- Pass constraints down
function VehiclePhysics.updateVehiclePhysics(carModel: Model, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, steerInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel.PrimaryPart
    if not carPrim then return end

    -- Update steering angle based on input
    local targetSteer = steerInput * props.SteerAngle
    physicsState.steeringAngle = physicsState.steeringAngle +
        (targetSteer - physicsState.steeringAngle) * math.min(1, delta * 10)

    local forces = {}
    local wheelStates = {}

    -- Use module-level getWheelPositions function
    for wheelName, originalPosition in pairs(carProps.getWheelPositions(carModel)) do
        local wheelState = VehiclePhysics.calculateWheelPhysics(
            carModel,
            wheelName,
            originalPosition,
            physicsState,
            props,
            delta,
            throttleInput,
            isBraking,
            isBoosting,
            constraints
        )

        wheelStates[wheelName] = wheelState
        if wheelState.forces then
            table.insert(forces, wheelState.forces)
        end
    end

    -- Apply accumulated forces
    for _, force in ipairs(forces) do
        carPrim:ApplyImpulseAtPosition(
            force.suspensionForce + force.lateralForce + force.tractionForce,
            force.applicationPoint
        )
    end

    return wheelStates
end

-- Accept constraints
function VehiclePhysics.calculateWheelPhysics(carModel: Model, wheelName: string, wheelPos: Vector3, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel.PrimaryPart
    local carCFrame = carPrim.CFrame

    -- On the server, only allow boost/brake if a player is in the seat
    if RunService:IsServer() then
        local seat = carModel:FindFirstChildOfClass('VehicleSeat')
        local occupant = seat and seat.Occupant
        local isPlayerInSeat = false
        if occupant then
            local player = game.Players:GetPlayerFromCharacter(occupant.Parent)
            isPlayerInSeat = player ~= nil
        end
        if not isPlayerInSeat then
            isBraking = false
            isBoosting = false
        end
    end

    -- Debugging: Print position if far from origin
    local carPosition = carPrim.Position
    local distanceFromOrigin = carPosition.Magnitude
    --[[if distanceFromOrigin > 1000 then -- Only print when far away
        print(string.format("[%s] Far from origin (%.1f). Pos: %.1f, %.1f, %.1f",
            wheelName, distanceFromOrigin, carPosition.X, carPosition.Y, carPosition.Z))
    end]]

    -- Initialize rotation for this wheel if not exists
    if not physicsState.wheelRotations[wheelName] then
        physicsState.wheelRotations[wheelName] = 0
    end

    -- Setup raycast with extra length
    local rayOrigin = carCFrame:ToWorldSpace(CFrame.new(wheelPos)).p
    local rayLength = props.SuspensionMaxLength + props.wheelRadius + RAYCAST_EXTRA_LENGTH
    local rayDirection = -carCFrame.UpVector * rayLength
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {carModel}
    local raycast = workspace:Raycast(rayOrigin, rayDirection, rayParams)

    -- Base wheel orientation
    local wheelDirCFrame = CFrame.lookAt(Vector3.zero, carCFrame.LookVector, carCFrame.UpVector)

    -- Apply steering for front wheels
    if string.sub(wheelName, 1, 1) == 'F' then
        wheelDirCFrame = wheelDirCFrame * CFrame.Angles(0, -math.rad(physicsState.steeringAngle), 0)
    end

    -- Get wheel velocity (use raycast hit point if available, otherwise estimate at max suspension)
    local velocityCheckPos = if raycast
        then raycast.Position
        else rayOrigin - carCFrame.UpVector * (props.SuspensionMaxLength + props.wheelRadius) -- Estimate velocity check point when in air
    local wheelVelocity = carPrim:GetVelocityAtPosition(velocityCheckPos)
    local LocalVelocity = wheelDirCFrame:ToObjectSpace(CFrame.new(wheelVelocity))

    -- Always update wheel rotation based on velocity, even in air
    local rotationDelta = LocalVelocity.z * WHEEL_ROTATION_SCALE *
        (if raycast then 1 else WHEEL_ROTATION_IN_AIR_MULTIPLIER)
    physicsState.wheelRotations[wheelName] += rotationDelta

    -- Debugging: Print velocity and rotation delta if far from origin
    --[[if distanceFromOrigin > 1000 then
        print(string.format("  [%s] WheelVel: %.2f, %.2f, %.2f | LocalVel.z: %.4f | RotDelta: %.6f",
            wheelName, wheelVelocity.X, wheelVelocity.Y, wheelVelocity.Z, LocalVelocity.z, rotationDelta))
    end]]

    if raycast then
        local RaycastDistance = (rayOrigin - raycast.Position).magnitude
        local effectiveDistance = RaycastDistance - props.wheelRadius

        -- Check if the hit is within the actual suspension travel range
        if effectiveDistance <= props.SuspensionMaxLength then
            -- Ground physics (within suspension range)
            local SpringLength = math.clamp(effectiveDistance,
                                            constraints.MIN_SUSPENSION_LENGTH,
                                            props.SuspensionMaxLength)

            -- Initialize spring memory if needed
            if not physicsState.springLengthMemory[wheelName] then
                physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
            end

            -- Calculate forces
            local StiffnessForce = props.Stiffness * (props.SuspensionMaxLength - SpringLength)
            local DamperForce = props.Damper * ((physicsState.springLengthMemory[wheelName] - SpringLength) / delta)
            local SuspensionForceVec3 = carCFrame.UpVector * (StiffnessForce + DamperForce)

            local Xforce = wheelDirCFrame.RightVector * -LocalVelocity.x * props.wheelFriction

            -- Calculate base traction force using throttleInput
            local baseZForce = throttleInput * props.torque *
                (math.sign(-LocalVelocity.z) == math.sign(throttleInput) and
                (1 - math.min(1, math.abs(LocalVelocity.z) / props.MaxSpeed)) or 1)

            -- Apply Braking Force if isBraking is true
            if isBraking then
                local brakeForceMagnitude = -(props.brakeForce or 100)
                -- Interpolate speed toward zero
                if math.abs(LocalVelocity.z) > 0.5 then
                    local brakingForceComponent = -math.sign(LocalVelocity.z) * brakeForceMagnitude * math.min(1, math.abs(LocalVelocity.z) / (props.MaxSpeed or 1))
                    baseZForce = baseZForce + brakingForceComponent
                else
                    -- If speed is near zero, stop braking
                    isBraking = false
                end
            end

            -- Apply Boost Force if isBoosting is true
            if isBoosting then
                local boostForce = props.BoostForce or 200
                baseZForce = baseZForce + boostForce
            end

            -- Clamp the final Z force to prevent extreme values (optional but recommended)
            baseZForce = math.clamp(baseZForce, -constraints.MAX_TRACTION_FORCE * 2, constraints.MAX_TRACTION_FORCE * 2) -- Example clamp

            local Zforce = wheelDirCFrame.LookVector * baseZForce -- Apply final force along wheel's Z

            physicsState.springLengthMemory[wheelName] = SpringLength

            return {
                onGround = true,
                forces = {
                    suspensionForce = SuspensionForceVec3,
                    lateralForce = Xforce,
                    tractionForce = Zforce,
                    applicationPoint = raycast.Position
                },
                springLength = SpringLength,
                wheelRotation = physicsState.wheelRotations[wheelName]
            }
        else
            -- Ray hit ground, but BEYOND suspension range - treat as air for physics
            physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
            return {
                onGround = false, -- No forces applied
                springLength = props.SuspensionMaxLength, -- Visually fully extended
                wheelRotation = physicsState.wheelRotations[wheelName]
            }
        end
    else
        -- Air physics (ray didn't hit anything)
        physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
        return {
            onGround = false,
            springLength = props.SuspensionMaxLength,
            wheelRotation = physicsState.wheelRotations[wheelName]
        }
    end
end

return VehiclePhysics