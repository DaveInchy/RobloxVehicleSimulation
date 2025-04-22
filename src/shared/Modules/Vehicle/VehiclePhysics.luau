local VehiclePhysics = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleModules = Modules:WaitForChild("Vehicle")

local carProps = require(VehicleModules:WaitForChild("VehiclePropertiesList"))
local RunService = game:GetService("RunService")

-- Constants
local WHEEL_ROTATION_IN_AIR_MULTIPLIER = 0.7 -- Wheels spin slightly slower in air due to air resistance
local WHEEL_ROTATION_SCALE = 1/56 -- Current scale factor from velocity to rotation
local RAYCAST_EXTRA_LENGTH = 2.0 -- How much further to cast the ray beyond max suspension travel

local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 2500, -- Reduced from 5000
    MIN_SUSPENSION_LENGTH = 0.6, -- Increased from 0.2 for more stable suspension
    MAX_LATERAL_FORCE = 1500, -- Reduced from 2000
    MAX_TRACTION_FORCE = 2000, -- Reduced from 2500
    STEERING_DAMPING = 5.0,
    STATIC_FRICTION_THRESHOLD = 1,
    WEIGHT_TO_FRICTION_MULT = 0.1,
    STATIC_FRICTION_COEFFICIENT = 5.0,
    PARKING_BRAKE_FORCE = 1000
}

type PhysicsConstraints = {
    MAX_SUSPENSION_FORCE: number,
    MIN_SUSPENSION_LENGTH: number, -- Added type
    MAX_LATERAL_FORCE: number,
    MAX_TRACTION_FORCE: number,
    STEERING_DAMPING: number,
    STATIC_FRICTION_THRESHOLD: number,
    WEIGHT_TO_FRICTION_MULT: number,
    STATIC_FRICTION_COEFFICIENT: number,
    PARKING_BRAKE_FORCE: number
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
    PhysicsConstraints: PhysicsConstraints,
    SteeringSensitivity: number?
}

type PhysicsState = {
    springLengthMemory: {[string]: number},
    steeringAngle: number,
    wheelRotations: {[string]: number},
    lastUpdateTime: number,
    velocity: Vector3,
    isParked: boolean,
    wheelVelocities: {[string]: Vector3}
}

function VehiclePhysics.createPhysicsState(): PhysicsState
    return {
        springLengthMemory = {},
        steeringAngle = 0,
        wheelRotations = {},
        lastUpdateTime = os.clock(),
        velocity = Vector3.new(0, 0, 0),
        isParked = false,
        wheelVelocities = {}
    }
end

-- Pass constraints down
function VehiclePhysics.updateVehiclePhysics(carModel: Model, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, steerInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel.PrimaryPart
    if not carPrim then return end

    -- Calculate car mass and center of mass
    local totalMass = 0
    local centerOfMass = Vector3.new(0, 0, 0)
    for _, part in pairs(carModel:GetDescendants()) do
        if part:IsA("BasePart") then
            totalMass += part.Mass
            centerOfMass += part.Position * part.Mass
        end
    end
    centerOfMass = centerOfMass / totalMass

    -- Apply steering with sensitivity and damping
    local targetSteerAngle = steerInput * props.SteerAngle
    local steeringSensitivity = props.SteeringSensitivity or 1.0
    local steeringDamping = constraints.STEERING_DAMPING or 5.0
    local steerLerpRate = delta * steeringSensitivity * (1/steeringDamping)
    if steerInput == 0 then
        steerLerpRate = steerLerpRate * 5 -- Centering is 5x faster
        physicsState.steeringAngle = physicsState.steeringAngle +
            (0 - physicsState.steeringAngle) * math.min(1, steerLerpRate)
    else
        physicsState.steeringAngle = physicsState.steeringAngle +
            (targetSteerAngle - physicsState.steeringAngle) * math.min(1, steerLerpRate)
    end

    -- Get car's current velocity
    local carVelocity = carPrim.AssemblyLinearVelocity
    local speed = carVelocity.Magnitude

    -- Determine if we should enter parking/static friction mode
    local isNearlyStatic = speed < (constraints.STATIC_FRICTION_THRESHOLD or 0.5)
    if isNearlyStatic and (isBraking or physicsState.isParked) then
        physicsState.isParked = true
    elseif throttleInput ~= 0 or not isBraking then
        physicsState.isParked = false
    end

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
--[[function VehiclePhysics.calculateWheelPhysics(carModel: Model, wheelName: string, wheelPos: Vector3, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
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
    end

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
    end

    if raycast then
        local RaycastDistance = (rayOrigin - raycast.Position).magnitude
        local effectiveDistance = RaycastDistance - props.wheelRadius
        local surfaceMaterial = raycast.Material -- Get surface material

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

            -- Calculate weight distribution
            local wheelPos = carModel.Wheels:FindFirstChild(wheelName).PrimaryPart.Position
            local distanceFromCoM = (wheelPos - carPrim.Position).Magnitude
            local weightOnWheel = carPrim.Mass * workspace.Gravity * (1 / distanceFromCoM)

            -- Calculate friction based on weight
            local baseFriction = props.wheelFriction
            local weightFrictionMult = constraints.WEIGHT_TO_FRICTION_MULT or 0.1
            local effectiveFriction = baseFriction + (weightOnWheel * weightFrictionMult)

            -- Apply static friction when nearly stopped
            if physicsState.isParked then
                effectiveFriction *= constraints.STATIC_FRICTION_COEFFICIENT or 2.0
            end

            -- Apply parking brake force if needed
            if physicsState.isParked then
                local wheelVel = carModel.Wheels:FindFirstChild(wheelName).PrimaryPart.AssemblyAngularVelocity
                -- Apply opposing force based on current velocity
                local opposingForce = -wheelVel.Unit * constraints.PARKING_BRAKE_FORCE
                -- Also apply downward force to prevent bouncing
                local verticalForce = Vector3.new(0, -constraints.PARKING_BRAKE_FORCE * 0.5, 0)
                carModel.Wheels:FindFirstChild(wheelName).PrimaryPart:ApplyImpulse((opposingForce + verticalForce) * delta)
            end

            -- Calculate Longitudinal Slip Ratio (for burnout/braking)
            local wheelSurfaceSpeed = physicsState.wheelRotations[wheelName] * props.wheelRadius
            local groundSpeedAlongWheel = LocalVelocity.z
            local longitudinalSlipRatio = 0
            if math.abs(groundSpeedAlongWheel) > 0.3 then
                longitudinalSlipRatio = (wheelSurfaceSpeed - groundSpeedAlongWheel) / math.abs(groundSpeedAlongWheel)
            elseif math.abs(wheelSurfaceSpeed) > 0.3 then
                longitudinalSlipRatio = 1.0
            end
            local isSlippingLongitudinally = math.abs(longitudinalSlipRatio) > 0.35 -- Set to 0.35 for balanced sensitivity

            -- Calculate Lateral Slip (for skidding)
            local lateralVelocity = LocalVelocity.x
            local lateralSlipRatio = 0
            local forwardSpeed = math.abs(LocalVelocity.z)
            if forwardSpeed > 1.0 then -- Keep minimum speed requirement to prevent false triggers
                lateralSlipRatio = math.abs(lateralVelocity) / forwardSpeed
            end
            local isSkidding = lateralSlipRatio > 0.1 -- Keep skidding threshold as is

            return {
                onGround = true,
                forces = {
                    suspensionForce = SuspensionForceVec3,
                    lateralForce = Xforce,
                    tractionForce = Zforce,
                    applicationPoint = raycast.Position
                },
                springLength = SpringLength,
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = effectiveFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = longitudinalSlipRatio, -- Renamed
                isSlipping = isSlippingLongitudinally, -- Renamed
                lateralVelocityX = lateralVelocity, -- Added
                lateralSlipRatio = lateralSlipRatio, -- Added
                isSkidding = isSkidding, -- Added
                surfaceMaterial = surfaceMaterial
            }
        else
            -- Ray hit ground, but BEYOND suspension range - treat as air for physics
            physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
            return {
                onGround = false, -- No forces applied
                springLength = props.SuspensionMaxLength, -- Visually fully extended
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = props.wheelFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = 0,
                isSlipping = false,
                lateralVelocityX = 0,
                lateralSlipRatio = 0,
                isSkidding = false,
                surfaceMaterial = Enum.Material.Air
            }
        end
    else
        -- Air physics (ray didn't hit anything)
        physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
        return {
            onGround = false,
            springLength = props.SuspensionMaxLength,
            wheelRotation = physicsState.wheelRotations[wheelName],
            friction = props.wheelFriction,
            isParked = physicsState.isParked,
            longitudinalSlipRatio = 0,
            isSlipping = false,
            lateralVelocityX = 0,
            lateralSlipRatio = 0,
            isSkidding = false,
            surfaceMaterial = Enum.Material.Air
        }
    end
end]]

function VehiclePhysics.calculateWheelPhysics(carModel: Model, wheelName: string, wheelPos: Vector3, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    -- Clamp delta time to prevent extreme values during lag spikes
    local MAX_DELTA = 1/20 -- Don't allow delta to be larger than 1/20th of a second for physics stability
    local clampedDelta = math.min(delta, MAX_DELTA)

    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel.PrimaryPart
    local carCFrame = carPrim.CFrame

    -- On the server, only allow boost/brake if a player is in the seat (Keep this logic)
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
    local rotationDelta = LocalVelocity.z * WHEEL_ROTATION_SCALE
    physicsState.wheelRotations[wheelName] += rotationDelta

    if raycast then
        local RaycastDistance = (rayOrigin - raycast.Position).magnitude
        local effectiveDistance = RaycastDistance - props.wheelRadius
        local surfaceMaterial = raycast.Material -- Get surface material

        -- Check if the hit is within the actual suspension travel range
        if effectiveDistance <= props.SuspensionMaxLength then
            -- Ground physics (within suspension range)
            local SpringLength = math.clamp(effectiveDistance,
                                            constraints.MIN_SUSPENSION_LENGTH,
                                            props.SuspensionMaxLength)

            -- Calculate Stiffness Force (based on compression)
            local StiffnessForce = props.Stiffness * (props.SuspensionMaxLength - SpringLength)

            -- Calculate Velocity-Based Damper Force
            local chassisWheelPointVelocity = carPrim:GetVelocityAtPosition(rayOrigin)
            local groundContactVelocity = Vector3.new(0,0,0) -- Assume terrain/static part
            if raycast.Instance and raycast.Instance.Anchored == false then
                 -- If hitting a non-anchored part, get its velocity at the contact point
                 groundContactVelocity = raycast.Instance:GetVelocityAtPosition(raycast.Position)
            end
            -- Calculate relative velocity along the suspension axis (car's UpVector)
            local relativeVelocityAlongSuspension = (chassisWheelPointVelocity - groundContactVelocity):Dot(carCFrame.UpVector)
            -- Damping force opposes this relative velocity
            local DamperForce = props.Damper * relativeVelocityAlongSuspension

            -- Calculate Total Suspension Force Vector (Stiffness + Damping)
            -- Both forces act along the car's UpVector. Stiffness pushes up based on compression.
            -- Damping pushes up if compressing (negative relative velocity) and down if extending (positive relative velocity).
            local SuspensionForceVec3 = carCFrame.UpVector * (StiffnessForce - DamperForce) -- Subtraction handles the opposing force direction correctly

            -- Optional: Clamp the total suspension force magnitude
            local suspensionForceMagnitude = SuspensionForceVec3.Magnitude
            if suspensionForceMagnitude > constraints.MAX_SUSPENSION_FORCE then
                SuspensionForceVec3 = SuspensionForceVec3.Unit * constraints.MAX_SUSPENSION_FORCE
                -- print("Clamped suspension force for wheel:", wheelName) -- Debugging
            end

            -- Update spring memory (still useful for other logic or debugging, but not for damping calc)
            physicsState.springLengthMemory[wheelName] = SpringLength

            -- Lateral Force (Xforce) - unchanged
            local Xforce = wheelDirCFrame.RightVector * -LocalVelocity.x * props.wheelFriction

            -- Traction Force (Zforce) - calculation logic mostly unchanged, uses throttle/braking/boost
            local baseZForce = throttleInput * props.torque *
                (math.sign(-LocalVelocity.z) == math.sign(throttleInput) and
                (1 - math.min(1, math.abs(LocalVelocity.z) / props.MaxSpeed)) or 1)

            if isBraking then
                local brakeForceMagnitude = -(props.brakeForce or 100)
                if math.abs(LocalVelocity.z) > 0.5 then
                    local brakingForceComponent = -math.sign(LocalVelocity.z) * brakeForceMagnitude * math.min(1, math.abs(LocalVelocity.z) / (props.MaxSpeed or 1))
                    baseZForce = baseZForce + brakingForceComponent
                else
                    isBraking = false
                end
            end

            if isBoosting then
                local boostForce = props.BoostForce or 200
                baseZForce = baseZForce + boostForce
            end

            baseZForce = math.clamp(baseZForce, -constraints.MAX_TRACTION_FORCE * 2, constraints.MAX_TRACTION_FORCE * 2)
            local Zforce = wheelDirCFrame.LookVector * baseZForce

            -- Weight distribution and friction calculations (unchanged)
            local wheelPart = carModel.Wheels:FindFirstChild(wheelName) -- Get the wheel part
            local weightOnWheel = 0
            if wheelPart and wheelPart.PrimaryPart then
                local wheelModelPos = wheelPart.PrimaryPart.Position
                local distanceFromCoM = (wheelModelPos - carPrim.Position).Magnitude
                -- Avoid division by zero and handle cases where distance is very small
                if distanceFromCoM > 0.1 then
                    -- Simplified weight distribution - consider a more accurate method if needed
                    weightOnWheel = carPrim.Mass * workspace.Gravity * (1 / distanceFromCoM)
                else
                    weightOnWheel = carPrim.Mass * workspace.Gravity / 4 -- Fallback: Assume equal distribution
                end
            else
                 weightOnWheel = carPrim.Mass * workspace.Gravity / 4 -- Fallback if wheel part not found
            end

            local baseFriction = props.wheelFriction
            local weightFrictionMult = constraints.WEIGHT_TO_FRICTION_MULT or 0.1
            local effectiveFriction = baseFriction + (weightOnWheel * weightFrictionMult)

            if physicsState.isParked then
                effectiveFriction *= constraints.STATIC_FRICTION_COEFFICIENT or 2.0
            end

            -- Parking brake impulse (unchanged, but uses clampedDelta)
            if physicsState.isParked and wheelPart and wheelPart.PrimaryPart then
                local wheelAngVel = wheelPart.PrimaryPart.AssemblyAngularVelocity
                local opposingForce = -wheelAngVel.Unit * constraints.PARKING_BRAKE_FORCE
                local verticalForce = Vector3.new(0, -constraints.PARKING_BRAKE_FORCE * 0.5, 0)
                wheelPart.PrimaryPart:ApplyImpulse((opposingForce + verticalForce) * clampedDelta) -- Use clampedDelta
            end

            -- Slip calculations (unchanged)
            local wheelSurfaceSpeed = physicsState.wheelRotations[wheelName] * props.wheelRadius -- This might need adjustment based on how rotation is calculated
            local groundSpeedAlongWheel = LocalVelocity.z
            local longitudinalSlipRatio = 0
            if math.abs(groundSpeedAlongWheel) > 0.3 then
                longitudinalSlipRatio = (wheelSurfaceSpeed - groundSpeedAlongWheel) / math.abs(groundSpeedAlongWheel)
            elseif math.abs(wheelSurfaceSpeed) > 0.3 then
                longitudinalSlipRatio = math.sign(wheelSurfaceSpeed) -- Max slip if ground speed is near zero but wheel is spinning
            end
            local isSlippingLongitudinally = math.abs(longitudinalSlipRatio) > 0.35

            local lateralVelocity = LocalVelocity.x
            local lateralSlipRatio = 0
            local forwardSpeed = math.abs(LocalVelocity.z)
            if forwardSpeed > 1.0 then
                lateralSlipRatio = math.abs(lateralVelocity) / forwardSpeed
            end
            local isSkidding = lateralSlipRatio > 0.1

            return {
                onGround = true,
                forces = {
                    suspensionForce = SuspensionForceVec3,
                    lateralForce = Xforce,
                    tractionForce = Zforce,
                    applicationPoint = raycast.Position
                },
                springLength = SpringLength,
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = effectiveFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = longitudinalSlipRatio,
                isSlipping = isSlippingLongitudinally,
                lateralVelocityX = lateralVelocity,
                lateralSlipRatio = lateralSlipRatio,
                isSkidding = isSkidding,
                surfaceMaterial = surfaceMaterial
            }
        else
            -- Ray hit ground, but BEYOND suspension range - treat as air for physics
            physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
            return {
                onGround = false, -- No forces applied
                springLength = props.SuspensionMaxLength, -- Visually fully extended
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = props.wheelFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = 0,
                isSlipping = false,
                lateralVelocityX = 0,
                lateralSlipRatio = 0,
                isSkidding = false,
                surfaceMaterial = Enum.Material.Air
            }
        end
    else
        -- Air physics (ray didn't hit anything)
        physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
        return {
            onGround = false,
            springLength = props.SuspensionMaxLength,
            wheelRotation = physicsState.wheelRotations[wheelName],
            friction = props.wheelFriction,
            isParked = physicsState.isParked,
            longitudinalSlipRatio = 0,
            isSlipping = false,
            lateralVelocityX = 0,
            lateralSlipRatio = 0,
            isSkidding = false,
            surfaceMaterial = Enum.Material.Air
        }
    end
end

return VehiclePhysics