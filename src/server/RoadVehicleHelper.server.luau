local LastStuff = {
	FL = {},
	FR = {},
	RL = {},
	RR = {},
}

local VisualiseRaycast = true
local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local VehicleFolder = workspace.Vehicles
local AllCarsMemory = {}
local ExistingCarsTable = {}--it stores every car

local function AddCar(obj,cprops)

	table.insert(ExistingCarsTable,obj)--adds car to table
	obj.PrimaryPart:SetNetworkOwner(nil)--now car physics are calculated only on server
	AllCarsMemory[obj] = {}--adds table for any memory you want, but i need it only for suspension right now
	AllCarsMemory[obj].SpringLengthMemory = {}--adds table for springs length memory, values added below
	for i,v in pairs(carProps.getWheelPositions(obj))do AllCarsMemory[obj].SpringLengthMemory[i] = 1.2 end--sets spring lenth
	obj:FindFirstChildOfClass('VehicleSeat'):GetPropertyChangedSignal('Occupant'):Connect(function()--event if seat's occupant value changed
		local occ = obj:FindFirstChildOfClass('VehicleSeat').Occupant
		if occ then--if someone just sat
			local player = game.Players:GetPlayerFromCharacter(occ.Parent)
			if player then--if not npc
				obj.PrimaryPart:SetNetworkOwner(player)--now player can do car's physics on their own
			end
		else
			obj.PrimaryPart:SetNetworkOwner(nil)--player exited, physics go back to server
		end
	end)

	for i,v in pairs(obj:GetChildren())do
		if v:IsA("Seat")then
			v:GetPropertyChangedSignal('Occupant'):Connect(function()--event if seat's occupant value changed
				if v.Occupant then
					local player = game.Players:GetPlayerFromCharacter(v.Occupant.Parent)
					if player then--if not npc
						wait()
						if obj.PrimaryPart:GetNetworkOwner()==player then
							obj.PrimaryPart:SetNetworkOwner(nil)
						end
					end
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
		weld.C0 = CFrame.new(carProps.getWheelPositions(obj)[i]) * CFrame.Angles(0,math.rad(-180),0)

		if v.x>0 then

			weld.C0 = weld.C0 * CFrame.Angles(0,math.rad(180),0)

		end
	end
end

for _,object in pairs(VehicleFolder:GetChildren())do
	AddCar(object)
end


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



for _, v in pairs(game.ReplicatedStorage.Vehicles:GetChildren()) do
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

----------------------

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
		for i,v in pairs(workspace.Vehicles:GetChildren()) do

			local dist = (v.PrimaryPart.Position - plr.Character.HumanoidRootPart.Position).magnitude
			if dist < nearestdist then

				nearestcar = v
				nearestdist = dist
			end
		end

		local nearestseat;
		for i,v in pairs(nearestcar:GetChildren()) do

			if (v:IsA('VehicleSeat')or v:IsA("Seat"))and not v.Occupant then

				local dist = (v.Position - plr.Character.HumanoidRootPart.Position).magnitude
				if dist < nearestdist then

					nearestseat = v
					nearestdist = dist
				end
			end
		end

		if nearestseat then

			local curHingeConstraint = nearestcar.PrimaryPart[nearestseat.Name]
			curHingeConstraint.TargetAngle = 90

			wait(0.5)

			curHingeConstraint.TargetAngle = 0
		end
	end
end)



while true do

	local delta = game["Run Service"].PreSimulation:Wait()

	for _, carModel in pairs(ExistingCarsTable)do

		local carPrim = carModel.PrimaryPart

		if not (carModel.Parent == game.Workspace.Vehicles) or not (carModel.Parent == game.Workspace) then
			continue;
		else if not carPrim:GetNetworkOwner() then

			--get the properties
			local id = carModel:GetAttribute("id")
			local owner = carModel:GetAttribute("owner")
			local props = carProps[id]

			local DisCarSpringLength = AllCarsMemory[carModel].SpringLengthMemory
			local WheelPositions = carProps.getWheelPositions(carModel);

			for wheelName, originalPosition in pairs(WheelPositions) do

				local carCFrame = carPrim.CFrame
				local rayOrigin = carCFrame:ToWorldSpace(CFrame.new(originalPosition)).p
				local rayDirection = -carCFrame.UpVector * (props.SuspensionMaxLength + props.wheelRadius)
				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = {carModel}
				local raycast = workspace:Raycast(rayOrigin,rayDirection,rayParams)

				if raycast then

					local RaycastDistance = (rayOrigin - raycast.Position).magnitude

					local SpringLength = math.clamp(RaycastDistance - props.wheelRadius, 0, props.SuspensionMaxLength)
					local StiffnessForce = props.Stiffness * (props.SuspensionMaxLength - SpringLength)
					local DamperForce = props.Damper * (( DisCarSpringLength[wheelName] - SpringLength) / delta)
					local SuspensionForceVec3 = carCFrame.UpVector * (StiffnessForce + DamperForce)

					local RotationsOnlyWheelDirCFrame = CFrame.lookAt(Vector3.zero,carCFrame.LookVector,carCFrame.UpVector)

					local LocalVelocity = RotationsOnlyWheelDirCFrame:ToObjectSpace(CFrame.new(carPrim:GetVelocityAtPosition(raycast.Position)))

					local Xforce = carCFrame.RightVector * -LocalVelocity.x * props.wheelFriction
					local Zforce = carCFrame.LookVector * LocalVelocity.z * (props.wheelFriction/3)

					DisCarSpringLength[wheelName] = SpringLength

					carPrim:ApplyImpulseAtPosition(SuspensionForceVec3 + Xforce + Zforce, raycast.Position)

				else

					DisCarSpringLength[wheelName] = props.SuspensionMaxLength

				end

				if VisualiseRaycast then

					game.StarterGui.gaag.ag.CurrentCamera = workspace.Camera
					game.StarterGui.gaag.ag2.CurrentCamera = workspace.Camera

					coroutine.wrap(function()

						local p = Instance.new("Part",game.StarterGui.gaag.ag)
						p.Name = 'rayVis'
						p.Color = Color3.new(0,0,1)
						p.Anchored = true
						p.CanCollide = false
						p.Material = Enum.Material.Neon
						p.Shape = Enum.PartType.Cylinder

						local pe = p:Clone()
						pe.Color = Color3.new(1,0,0)
						pe.Parent = p.Parent

						local Rdestination = (rayOrigin + rayDirection)
						if raycast then

							local rDist = (rayOrigin - raycast.Position).magnitude
							local s = rayOrigin - carCFrame.UpVector * rDist/2

							p.CFrame = CFrame.lookAt(s, s + carCFrame.RightVector,-carCFrame.LookVector)
							p.Size = Vector3.new(rDist, 0.1, 0.1)

							rDist = (raycast.Position - Rdestination).magnitude
							s =  raycast.Position - carCFrame.UpVector * rDist/2

							pe.Size = Vector3.new(rDist, 0.1, 0.1)
							pe.CFrame = CFrame.lookAt(s, s + carCFrame.RightVector,-carCFrame.LookVector)


						else

							p.Size = Vector3.new((rayOrigin - Rdestination).magnitude, 0.1, 0.1)

							local s = rayOrigin + rayDirection/2

							p.CFrame = CFrame.lookAt(s, s + carCFrame.RightVector,-carCFrame.LookVector)

							Rdestination = Rdestination + carCFrame.UpVector*0.02

							pe.CFrame = CFrame.lookAt(Rdestination, Rdestination + carCFrame.RightVector,-carCFrame.LookVector)
							pe.Size = Vector3.new(0,0.1,0.1)

						end

						local pp = p:Clone()
							pp.Parent = game.StarterGui.gaag.ag2
							pp.Size = p.Size + Vector3.new(0.01,0.01,0.01)

							local ppe = pe:Clone()
							ppe.Parent = pp.Parent
							ppe.Size = pe.Size + Vector3.new(0.01,0.01,0.01)

							game["Run Service"].Heartbeat:Wait()

							pp:Destroy()
							ppe:Destroy()

							p:Destroy()
							pe:Destroy()

						end)()
					end
				end
			end
		end
	end
end