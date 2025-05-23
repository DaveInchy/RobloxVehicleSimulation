--!nonstrict

-- Default physics constraints that will be used for all vehicles unless overridden
local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 5000,
    MIN_SUSPENSION_LENGTH = 1.8,
    MAX_LATERAL_FORCE = 2000,
    MAX_TRACTION_FORCE = 2500,
    -- New physics properties
    STEERING_DAMPING = 5000, -- Higher = slower steering response
    WEIGHT_TO_FRICTION_MULT = 0.4, -- Multiplier for weight-based friction
    STATIC_FRICTION_THRESHOLD = 5, -- Speed below which static friction applies
    STATIC_FRICTION_COEFFICIENT = 2.0, -- Multiplier for friction when nearly stopped
    PARKING_BRAKE_FORCE = 10000 -- Force applied when parked/static friction active
}

local model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("ProtoVehicle")

local module = {
	["ProtoVehicle"] = {
		model = model,
		driverSeatName = "FL",
		SuspensionMaxLength = 2,
		wheelRadius = 2.8/2,
		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 30,
		MaxSpeed = 140,
		SteerAngle = 24,
		SteeringSensitivity = 5,
		brakeForce = 250,
		BoostForce = 50,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},
}

module.getWheelPositions = function(carModel)
	local Chassis = carModel:WaitForChild("Chassis")
	local wheelPositions = {}
	for _, wheelName in ipairs({"FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"}) do
		local attach = Chassis:WaitForChild(wheelName)
		-- Position relative to chassis center, at rest height (no suspension)
		wheelPositions[wheelName:sub(1,2)] = attach.Position - Vector3.new(0, 0, 0) -- No offset, let physics handle it
	end
	return wheelPositions
end
return module
