--!nonstrict

-- Default physics constraints that will be used for all vehicles unless overridden
local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 5000,
    MIN_SUSPENSION_LENGTH = 0.2,
    MAX_LATERAL_FORCE = 2000,
    MAX_TRACTION_FORCE = 2500,
    -- New physics properties
    STEERING_DAMPING = 5.0, -- Higher = slower steering response
    WEIGHT_TO_FRICTION_MULT = 0.1, -- Multiplier for weight-based friction
    STATIC_FRICTION_THRESHOLD = 0.5, -- Speed below which static friction applies
    STATIC_FRICTION_COEFFICIENT = 2.0, -- Multiplier for friction when nearly stopped
    PARKING_BRAKE_FORCE = 10000 -- Force applied when parked/static friction active
}

local module = {

	["TruckSemi"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("TruckSemi"),
		driverSeatName = "FL",

		SuspensionMaxLength = 3.5,
		wheelRadius = 4/2,

		Stiffness = 200,
		Damper = 3,
		wheelFriction = 2.25,
		torque = 30,
		MaxSpeed = 70,
		SteerAngle = 30,
		SteeringSensitivity = 0.7, -- Slower steering for trucks
		brakeForce = 200,
		BoostForce = 20,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Obey-EV"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Obey-EV"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.9/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,
		SteeringSensitivity = 1.2, -- Responsive EV steering
		brakeForce = 100,
		BoostForce = 200,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Ubermacht-EV"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Ubermacht-EV"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.725/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,
		SteeringSensitivity = 1.1, -- Slightly quick steering
		brakeForce = 100,
		BoostForce = 200,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Obey-TenF"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Obey-TenF"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.5,
		wheelRadius = 2.74/2,

		Stiffness = 160,
		Damper = 5,
		wheelFriction = 2,
		torque = 32,
		MaxSpeed = 200,
		SteerAngle = 24,
		brakeForce = 80,
		BoostForce = 50,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Obey-Drifter"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Obey-Drifter"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.5,
		wheelRadius = 2.9/2,

	},

	["Ubermacht-Cypher"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Ubermacht-Cypher"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.725/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,
		brakeForce = 100,
		BoostForce = 200,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Obey-Wagon"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Obey-Wagon"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.9/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,
		brakeForce = 100,
		BoostForce = 200,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},

	["Ubermacht-Wagon"] = {
		model = game.ReplicatedFirst:WaitForChild("Vehicles"):WaitForChild("Ubermacht-Wagon"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 3/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,
		brakeForce = 100,
		BoostForce = 200,
		PhysicsConstraints = DEFAULT_PHYSICS_CONSTRAINTS
	},
}

module.getWheelPositions = function(carModel)
	local RootPart = carModel:WaitForChild("RootPart");

	return {
		FL = RootPart.FL.Position,
		FR = RootPart.FR.Position,
		RL = RootPart.RL.Position,
		RR = RootPart.RR.Position,
	}
end

module.getWheelModel = function (carModel)
	--rotate the wheel on Y axis by 180 degrees
	local offset = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(0), 0)
	local model = game.ReplicatedFirst.Wheels[carModel.Name]:Clone();
	model:PivotTo(carModel.RootPart.FL.CFrame * offset);
	return model;
end

return module
