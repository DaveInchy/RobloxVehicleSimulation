local module = {

	["Obey-EV"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Obey-EV"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.9/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,

	},

	["Ubermacht-EV"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Ubermacht-EV"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.725/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,

	},

	["Obey-Drifter"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Obey-Drifter"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1,
		wheelRadius = 2.9/2,

		Stiffness = 320,
		Damper = 5,
		wheelFriction = 2.5,
		torque = 40,
		MaxSpeed = 160,
		SteerAngle = 25,

		-- above area initial values
		-- mod parts would modify each stat.

	},

	["Ubermacht-Cypher"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Ubermacht-Cypher"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.725/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,

	},

	["Obey-Wagon"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Obey-Wagon"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 2.9/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,

	},

	["Ubermacht-Wagon"] = {
		model = game.ReplicatedStorage:WaitForChild("Vehicles"):WaitForChild("Ubermacht-Wagon"),
		driverSeatName = "FL",

		SuspensionMaxLength = 1.6,
		wheelRadius = 3/2,

		Stiffness = 250,
		Damper = 5,
		wheelFriction = 2,
		torque = 50,
		MaxSpeed = 100,
		SteerAngle = 25,

	},

}

module.getWheelPositions = function (carModel): {
	FL: Vector3,
	FR: Vector3,
	RL: Vector3,
	RR: Vector3,
	}

	local RootPart = carModel:WaitForChild("RootPart");

	return {
		FL = RootPart.FL.Position,
		FR = RootPart.FR.Position,
		RL = RootPart.RL.Position,
		RR = RootPart.RR.Position,
	}

end

module.getWheelModel = function (carModel): Model?

	--rotate the wheel on Y axis by 180 degrees
	local offset = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(0), 0)
	local model = game.ReplicatedStorage.Wheels[carModel.Name]:Clone();
	model:PivotTo(carModel.RootPart.FL.CFrame * offset);
	return model;

end

return module
