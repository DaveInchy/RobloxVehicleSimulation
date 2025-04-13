local VisualiseRaycast = false

local carProps = require(game.ReplicatedStorage:WaitForChild("VehiclePropertiesList"))
local player = game.Players.LocalPlayer;
local char = player.Character or player.CharacterAdded:Wait();
local PlrGui = player.PlayerGui

PlrGui.gaag.ag:ClearAllChildren() -- these are foroverlay visualizatin of the suspension
PlrGui.gaag.ag2:ClearAllChildren() -- these are foroverlay visualizatin of the suspension

local humanoid = nil
humanoid = (function() repeat task.wait() until char:FindFirstChild("Humanoid"); return char.Humanoid end)()

humanoid.Seated:Connect(function(seated,seatPart)

	if seated and seatPart then

		if seatPart:FindFirstAncestor('Vehicles') and seatPart:IsA("VehicleSeat")then--whatever that gives out its car

			local carModel = seatPart.Parent
			local carPrim = carModel.PrimaryPart

			if not carPrim then return end

			-- reading VehiclePropertiesList
			local id = carModel:GetAttribute("id")
			local props = carProps[id]

			local SpringLengthMemory = {}
			for i,v in pairs(carProps.getWheelPositions(carModel))do SpringLengthMemory[i] = 0.5 end

			--current steer pos
			local SmoothSteer = 0
			local serverTakeOverWait = 0

			while true do
				local delta = game["Run Service"].Heartbeat:Wait()

				local carPrim = carModel.PrimaryPart

				if not carPrim then return end

				SmoothSteer = math.abs(
					seatPart.SteerFloat-SmoothSteer)<=delta*2 and seatPart.SteerFloat or SmoothSteer+math.sign(
					seatPart.SteerFloat-SmoothSteer)*delta*2

				local WheelPositions = carProps.getWheelPositions(carModel);
				for wheelName, originalPosition in pairs(WheelPositions)do

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
						local DamperForce = props.Damper * (( SpringLengthMemory[wheelName] - SpringLength) / delta)
						local SuspensionForceVec3 = carCFrame.UpVector * (StiffnessForce + DamperForce)

						local RotationsOnlyWheelDirCFrame = CFrame.lookAt(Vector3.zero,carCFrame.LookVector,carCFrame.UpVector)

						if string.sub(wheelName,1,1)=='F' then

							RotationsOnlyWheelDirCFrame = RotationsOnlyWheelDirCFrame * CFrame.Angles(0,-math.rad(SmoothSteer * props.SteerAngle),0)

						end

						local LocalVelocity = RotationsOnlyWheelDirCFrame:ToObjectSpace(CFrame.new(carPrim:GetVelocityAtPosition(raycast.Position)))

						local Xforce = RotationsOnlyWheelDirCFrame.RightVector * -LocalVelocity.x * props.wheelFriction
						local Zforce = RotationsOnlyWheelDirCFrame.LookVector * seatPart.ThrottleFloat * props.torque * (math.sign(-LocalVelocity.z)==seatPart.Throttle and(1 - math.min(1,math.abs(LocalVelocity.z)/props.MaxSpeed))or 1)

						SpringLengthMemory[wheelName] = SpringLength

						carPrim:ApplyImpulseAtPosition(SuspensionForceVec3 + Xforce + Zforce, raycast.Position)

					else
						SpringLengthMemory[wheelName] = props.SuspensionMaxLength
					end

					if VisualiseRaycast then PlrGui.gaag.ag.CurrentCamera = workspace.CurrentCamera
                    PlrGui.gaag.ag2.CurrentCamera = workspace.CurrentCamera
                    coroutine.wrap(function()
                        local p = Instance.new("Part",PlrGui.gaag.ag)
                        p.Name = 'rayVis'
                        p.Color = Color3.new(0,0,1)
                        p.Anchored = true
                        p.CanCollide = false
                        p.CollisionGroupId = 1
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
                        pp.Parent = PlrGui.gaag.ag2
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

				if seatPart.Occupant ~= humanoid then
                    --check whatever that means that character still sits in car
					serverTakeOverWait = serverTakeOverWait + delta;
					if serverTakeOverWait >= 0.5 then
						break;
					end
				end
            end--sets the car to be not occupied by the player
            if serverTakeOverWait < 0.5 then
                local carModel = seatPart.Parent
                local carPrim = carModel.PrimaryPart

                if not carPrim then return end

                local id = carModel:GetAttribute("id")
                local props = carProps[id]

                local curHingeConstraint = carPrim[seatPart.Name]
                curHingeConstraint.TargetAngle = 90

                game.TweenService:Create(seatPart.SeatWeld,TweenInfo.new(0.5),{
                    C1 = CFrame.new(),
                    C0 = seatPart.SeatWeld.C0 * seatPart.SeatWeld.C1:Inverse() * CFrame.new(math.sign(curHingeConstraint.Attachment0.Position.x)*6,0,0)
                }):Play()

                wait(0.5)

                humanoid.Sit = false
                humanoid.PlatformStand = false
			end
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

		if humanoid.SeatPart then

			local carModel = humanoid.SeatPart:FindFirstAncestorOfClass("Model")

			local curHingeConstraint = carModel.PrimaryPart[humanoid.SeatPart.Name]
			curHingeConstraint.TargetAngle = 90

			game.TweenService:Create(humanoid.SeatPart.SeatWeld,TweenInfo.new(0.5),{
				C1 = CFrame.new(),
				C0 = humanoid.SeatPart.SeatWeld.C0 * humanoid.SeatPart.SeatWeld.C1:Inverse() * CFrame.new(math.sign(curHingeConstraint.Attachment0.Position.x)*6,0,0)
			}):Play()

			wait(0.5)

			humanoid.Sit = false

		else
			local nearestcar, nearestdist = nil, 10

			for i,v in pairs(workspace.Vehicles:GetChildren())do

				local dist = (v.PrimaryPart.Position - char.HumanoidRootPart.Position).Magnitude

				if dist < nearestdist then
					nearestcar = v
					nearestdist = dist
				end

			end

			if nearestcar then

				local carRotations = CFrame.lookAt(Vector3.zero,nearestcar.PrimaryPart.CFrame.LookVector,nearestcar.PrimaryPart.CFrame.UpVector)

				game.ReplicatedStorage.AskForDoor:FireServer()

				wait(0.2)

				local nearestseat;
				for i,v in pairs(nearestcar:GetChildren())do

					if (v:IsA('VehicleSeat')or v:IsA("Seat"))and not v.Occupant then

						local dist = (v.Position - char.HumanoidRootPart.Position).magnitude
						if dist < nearestdist then
							nearestseat = v
							nearestdist = dist
						end

					end

				end

				if nearestseat then

					local curCFram = char.HumanoidRootPart.CFrame
					nearestseat:Sit(humanoid)

					local seatweld = nearestseat:WaitForChild("SeatWeld")
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

						nearestcar.PrimaryPart[nearestseat.Name].TargetAngle = 0

					end

				end

			end

		end

	end

end,false,Enum.KeyCode.F)



local WheelRotations = {}

game["Run Service"]:BindToRenderStep('MoveWheels',5,function(delta)

	for _,vehicle in pairs(workspace.Vehicles:GetChildren())do

		local carPrim = vehicle.PrimaryPart

		if not carPrim then return end

		local id = vehicle:GetAttribute("id")
		local props = carProps[id]

		for i,v in pairs(carProps.getWheelPositions(vehicle))do

			local carCFrame = carPrim.CFrame

			local rayOrigin = carCFrame:ToWorldSpace(CFrame.new(Vector3.new(v.x,v.y - props.wheelRadius,v.z))).p
			local rayDirection = -carCFrame.UpVector * props.SuspensionMaxLength
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = {vehicle}
			local raycast = workspace:Raycast(rayOrigin,rayDirection,rayParams)

			if raycast then

				local LocalVelocity = CFrame.lookAt(Vector3.zero,carCFrame.LookVector,carCFrame.UpVector):ToObjectSpace(CFrame.new(carPrim:GetVelocityAtPosition(raycast.Position)))

				if not WheelRotations[vehicle] then
					WheelRotations[vehicle] = {}
					WheelRotations[vehicle].STEER = 0
					for i,v in pairs(carProps.getWheelPositions(vehicle))do WheelRotations[vehicle][i] = 0.5 end
				end
				WheelRotations[vehicle][i] += LocalVelocity.z/56

				local DatWeld = vehicle.Wheels[i].Weld

				local weldInitPos = CFrame.new(v - Vector3.new(0,(rayOrigin - raycast.Position).magnitude,0))
				if string.sub(i,1,1)=='F' then--if front
					--lerp smoothing below, but for some reason SteerFloat flickers
					WheelRotations[vehicle].STEER = WheelRotations[vehicle].STEER + (vehicle[props.driverSeatName].SteerFloat - WheelRotations[vehicle].STEER)*delta*6
					DatWeld.C0 = weldInitPos * CFrame.Angles(0,-math.rad(WheelRotations[vehicle].STEER * props.SteerAngle),0)
				else--DatWeld.C0.Rotation
					DatWeld.C0 = weldInitPos
				end
				if v.x>0 then
					DatWeld.C0 = DatWeld.C0 * CFrame.Angles(0,math.rad(180),0)
					DatWeld.C0 = DatWeld.C0 * CFrame.Angles(-WheelRotations[vehicle][i],0,0)
				else
					DatWeld.C0 = DatWeld.C0 * CFrame.Angles(WheelRotations[vehicle][i],0,0)
				end
			end
		end
	end
end)