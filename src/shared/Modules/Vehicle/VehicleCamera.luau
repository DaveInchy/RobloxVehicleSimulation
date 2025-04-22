--[=[
DrivingCamera.luau

A camera module for vehicle driving in Roblox.
Features to implement:
- Camera follows the vehicle smoothly.
- When going backwards, camera does not reset or snap to a new position.
- Camera shake effect when accelerating, colliding, or driving on rough terrain.
- Adjustable camera distance and angle.
- Optionally, allow player to rotate camera around vehicle with mouse.
- Smooth transitions between camera states (e.g., entering/exiting vehicle).
- Add more features as needed for a polished driving experience.

-- Example usage:
-- local DrivingCamera = require(path.to.DrivingCamera)
-- DrivingCamera:AttachToVehicle(vehicle)
-- DrivingCamera:Detach()
]=]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService") -- Added for potential smooth transitions

local VehicleCamera = {} -- Renamed from DrivingCamera
VehicleCamera.__index = VehicleCamera -- Renamed from DrivingCamera

local currentCamera = workspace.CurrentCamera
local player = Players.LocalPlayer

local attachedVehicle = nil
local baseCameraOffset = Vector3.new(0, 8, 20) -- Base offset (Y increased by 5)
local cameraOffset = baseCameraOffset -- Current offset, can be modified by rotation/shake
local cameraTargetOffset = Vector3.new(0, 2, 0) -- Point slightly above the vehicle base
local cameraSmoothingFactor = 7 -- Adjusted for exponential smoothing (higher = tighter camera)
local isReversing = false -- Track if vehicle is reversing
local cameraCollisionBuffer = 0.5 -- Minimum distance between camera and obstruction

-- Zooming Variables
local currentZoomMultiplier = 1.0
local minZoomMultiplier = 0.5
local maxZoomMultiplier = 5.0
local zoomSensitivity = 0.1

-- Orbiting Variables
local isOrbiting = false
local orbitYaw = 0
local orbitPitch = 0
local orbitSensitivity = 0.005
local orbitReturnSmoothing = 5 -- How fast orbit returns to default when RMB released

-- Camera Shake Variables
local shakeIntensity = 0
local shakeFrequency = 10
local shakeAmplitude = 0.5
local shakeDampening = 5
local shakeSeed = Random.new()

-- Collision Raycast Variables
local lastDownHitDistance = nil
local lastForwardHitTime = 0
local forwardHitCooldown = 0.2 -- Cooldown in seconds to prevent constant shaking against walls
local downRayLength = 5 -- How far down to check from chassis center
local forwardRayLength = 3 -- How far forward to check
local collisionShakeMultiplier = 1.5 -- Make collision shakes more intense

local connection = nil
local inputConnections = {} -- Store input connections for cleanup

-- Function to handle camera shake
local function applyCameraShake(dt)
	if shakeIntensity > 0 then
		local shakeOffsetX = math.noise(shakeSeed:NextNumber() * shakeFrequency, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity
		local shakeOffsetY = math.noise(shakeSeed:NextNumber() * shakeFrequency * 1.1, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity
		local shakeOffsetZ = math.noise(shakeSeed:NextNumber() * shakeFrequency * 1.2, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity

		local shakeCFrame = CFrame.new(shakeOffsetX, shakeOffsetY, shakeOffsetZ)
		currentCamera.CFrame = currentCamera.CFrame * shakeCFrame

		-- Dampen shake over time
		shakeIntensity = math.max(0, shakeIntensity - shakeDampening * dt)
	end
end

-- Function to trigger camera shake
function VehicleCamera:TriggerShake(intensity) -- Renamed from DrivingCamera
	shakeIntensity = math.max(shakeIntensity, intensity) -- Don't override if a stronger shake is active
end

-- Function to update camera position and orientation
local function updateCamera(dt)
	if not attachedVehicle or not attachedVehicle:IsDescendantOf(workspace) then
		return
	end

	local vehicleRoot = attachedVehicle.PrimaryPart
	if not vehicleRoot then
		warn("DrivingCamera: Attached vehicle has no PrimaryPart!")
		return
	end

	local vehicleCFrame = vehicleRoot.CFrame
	local vehicleVelocity = vehicleRoot.AssemblyLinearVelocity
	local speed = vehicleVelocity.Magnitude

	-- Determine if reversing
	local forwardVector = vehicleCFrame.LookVector
	local velocityDirection = vehicleVelocity.Magnitude > 0.1 and vehicleVelocity.Unit or Vector3.zero
	local dotProduct = forwardVector:Dot(velocityDirection)
	isReversing = dotProduct < -0.1 -- Threshold to consider it reversing

	-- Smoothly return orbit angles if not orbiting
	if not isOrbiting then
		local orbitReturnAlpha = 1 - math.exp(-orbitReturnSmoothing * dt)
		orbitYaw = orbitYaw * (1 - orbitReturnAlpha)
		orbitPitch = orbitPitch * (1 - orbitReturnAlpha)
		-- Snap to zero if very close to avoid infinite lerp
		if math.abs(orbitYaw) < 0.001 then orbitYaw = 0 end
		if math.abs(orbitPitch) < 0.001 then orbitPitch = 0 end
	end

	-- Calculate the base offset considering zoom
	local zoomedOffset = Vector3.new(baseCameraOffset.X, baseCameraOffset.Y, baseCameraOffset.Z * currentZoomMultiplier)

	-- Apply orbit rotation
	local orbitRotation = CFrame.Angles(0, orbitYaw, 0) * CFrame.Angles(orbitPitch, 0, 0)
	local rotatedOffset = orbitRotation * zoomedOffset

	-- Adjust offset based on reversing state (apply AFTER orbit/zoom)
	local actualOffset = rotatedOffset
	if isReversing then
		-- Keep camera looking forward relative to vehicle, but adjust offset Z
		-- Note: Reversing logic might need refinement with orbiting enabled
		actualOffset = Vector3.new(rotatedOffset.X, rotatedOffset.Y, -rotatedOffset.Z)
	end

	local idealPosition = vehicleCFrame * (actualOffset + cameraTargetOffset)
	local lookAtPosition = vehicleCFrame * cameraTargetOffset

	-- Raycast to prevent clipping
	local rayOrigin = lookAtPosition
	local rayDirection = idealPosition - rayOrigin
	local rayDistance = rayDirection.Magnitude
	local finalPosition = idealPosition -- Start with the ideal position

	if rayDistance > 0.1 then -- Only cast if there's a significant distance
		rayDirection = rayDirection.Unit
		local clipRayParams = RaycastParams.new()
		clipRayParams.FilterDescendantsInstances = {attachedVehicle, player.Character or Instance.new("Model")} -- Exclude vehicle itself and player character
		clipRayParams.FilterType = Enum.RaycastFilterType.Exclude
		local clipRaycastResult = workspace:Raycast(rayOrigin, rayDirection * rayDistance, clipRayParams)

		if clipRaycastResult then
			-- Hit something, move camera closer
			finalPosition = clipRaycastResult.Position - rayDirection * cameraCollisionBuffer
			-- Optional: Draw debug ray
			-- DebugDraw.drawRay(rayOrigin, clipRaycastResult.Position, Color3.new(1, 1, 0))
		-- else
			-- Optional: Draw debug ray
			-- DebugDraw.drawRay(rayOrigin, idealPosition, Color3.new(0, 1, 1))
		end
	end

	-- Smoothly interpolate camera position using frame-rate independent exponential smoothing
	local currentCFrame = currentCamera.CFrame
	-- Use finalPosition instead of idealPosition for the target CFrame
	local targetCFrame = CFrame.lookAt(finalPosition, lookAtPosition)
	local alpha = 1 - math.exp(-cameraSmoothingFactor * dt) -- Calculate alpha based on delta time
	currentCamera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)

	-- --- Collision Detection Raycasts for Camera Shake ---
	local shakeTriggerIntensity = 0
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {attachedVehicle}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- 1. Downward Raycast (for bumps/landings)
	local downRayOrigin = vehicleCFrame.Position
	local downRayDirection = -vehicleCFrame.UpVector * downRayLength
	local downRaycastResult = workspace:Raycast(downRayOrigin, downRayDirection, rayParams)
	local currentDownDistance = downRayLength -- Assume max distance if no hit
	if downRaycastResult then
		currentDownDistance = (downRayOrigin - downRaycastResult.Position).Magnitude
		-- Optional: Draw debug ray
		-- DebugDraw.drawRay(downRayOrigin, downRaycastResult.Position, Color3.new(0, 1, 0))
	-- else
		-- Optional: Draw debug ray
		-- DebugDraw.drawRay(downRayOrigin, downRayOrigin + downRayDirection, Color3.new(1, 0, 0))
	end

	if lastDownHitDistance then
		local distanceDelta = currentDownDistance - lastDownHitDistance
		-- Check for significant compression (negative delta) or sudden drop (large positive delta if previously grounded)
		if math.abs(distanceDelta) > 0.5 and speed > 5 then -- Thresholds for delta and speed
			local impactIntensity = math.abs(distanceDelta) * speed * 0.02 -- Scale shake with delta and speed
			shakeTriggerIntensity = math.max(shakeTriggerIntensity, impactIntensity * collisionShakeMultiplier)
			-- print("Down Ray Impact! Delta:", distanceDelta, "Speed:", speed, "Shake:", impactIntensity)
		end
	end
	lastDownHitDistance = currentDownDistance

	-- 2. Forward Raycast (for front collisions)
	local now = os.clock()
	if now - lastForwardHitTime > forwardHitCooldown then
		local forwardRayOrigin = vehicleCFrame * CFrame.new(0, 1, -vehicleRoot.Size.Z / 2) -- Origin slightly above center, at the front
		local forwardRayDirection = vehicleCFrame.LookVector * forwardRayLength
		local forwardRaycastResult = workspace:Raycast(forwardRayOrigin.Position, forwardRayDirection, rayParams)

		if forwardRaycastResult then
			local hitDistance = (forwardRayOrigin.Position - forwardRaycastResult.Position).Magnitude
			if hitDistance < forwardRayLength * 0.8 and speed > 2 then -- Hit something close while moving
				local impactIntensity = (forwardRayLength - hitDistance) * speed * 0.1 -- Scale with proximity and speed
				shakeTriggerIntensity = math.max(shakeTriggerIntensity, impactIntensity * collisionShakeMultiplier * 1.5) -- Make front impacts stronger
				lastForwardHitTime = now -- Apply cooldown
				-- print("Forward Ray Impact! Dist:", hitDistance, "Speed:", speed, "Shake:", impactIntensity)
				-- Optional: Draw debug ray
				-- DebugDraw.drawRay(forwardRayOrigin.Position, forwardRaycastResult.Position, Color3.new(0, 0, 1))
			end
		-- else
			-- Optional: Draw debug ray
			-- DebugDraw.drawRay(forwardRayOrigin.Position, forwardRayOrigin.Position + forwardRayDirection, Color3.new(1, 0, 1))
		end
	end

	-- Apply camera shake based on vehicle state (example: shake on high speed)
	if speed > 50 then -- Example threshold for speed shake
		shakeTriggerIntensity = math.max(shakeTriggerIntensity, (speed - 50) / 100)
	end

	-- Trigger combined shake intensity
	if shakeTriggerIntensity > 0 then
		VehicleCamera:TriggerShake(shakeTriggerIntensity) -- Renamed from DrivingCamera
	end

	applyCameraShake(dt)
end

-- Input Handlers
local function handleMouseWheel(inputObject)
	local delta = inputObject.Position.Z -- Z indicates scroll wheel delta
	currentZoomMultiplier = math.clamp(currentZoomMultiplier - delta * zoomSensitivity, minZoomMultiplier, maxZoomMultiplier)
end

local function handleInputBegan(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
		isOrbiting = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local function handleInputEnded(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
		isOrbiting = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function handleInputChanged(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if isOrbiting and inputObject.UserInputType == Enum.UserInputType.MouseMovement then
		orbitYaw = orbitYaw - inputObject.Delta.X * orbitSensitivity
		orbitPitch = math.clamp(orbitPitch - inputObject.Delta.Y * orbitSensitivity, -math.pi/4, math.pi/4) -- Clamp pitch
	end
end

-- Public methods
function VehicleCamera:AttachToVehicle(vehicle) -- Renamed from DrivingCamera
	if connection then
		self:Detach() -- Detach from any previous vehicle
	end

	attachedVehicle = vehicle
	if not attachedVehicle.PrimaryPart then
		warn("VehicleCamera: Cannot attach to vehicle without a PrimaryPart:", vehicle.Name) -- Renamed from DrivingCamera
		attachedVehicle = nil
		return
	end

	currentCamera.CameraType = Enum.CameraType.Scriptable

	-- Connect to RenderStepped for smooth camera updates
	-- Use BindToRenderStep for better control over priority if needed
	connection = RunService.RenderStepped:Connect(updateCamera)

	-- Reset zoom and orbit
	currentZoomMultiplier = 1.0
	orbitYaw = 0
	orbitPitch = 0
	isOrbiting = false

	-- Connect Input Listeners
	inputConnections.MouseWheelForward = UserInputService.InputChanged:Connect(function(inputObject, gameProcessedEvent)
		if not gameProcessedEvent and inputObject.UserInputType == Enum.UserInputType.MouseWheel then
			handleMouseWheel(inputObject)
		end
	end)
	inputConnections.InputBegan = UserInputService.InputBegan:Connect(handleInputBegan)
	inputConnections.InputEnded = UserInputService.InputEnded:Connect(handleInputEnded)
	inputConnections.InputChanged = UserInputService.InputChanged:Connect(handleInputChanged)

	lastDownHitDistance = nil -- Reset collision state on attach
	lastForwardHitTime = 0
	print("VehicleCamera attached to:", vehicle.Name) -- Renamed from DrivingCamera
end

function VehicleCamera:Detach() -- Renamed from DrivingCamera
	if connection then
		connection:Disconnect()
		connection = nil
	end
	attachedVehicle = nil
	currentCamera.CameraType = Enum.CameraType.Custom -- Or restore previous type
	currentCamera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid") or nil

	-- Disconnect Input Listeners
	for _, connection in pairs(inputConnections) do
		connection:Disconnect()
	end
	inputConnections = {}
	if isOrbiting then -- Ensure mouse behavior is reset if detaching while orbiting
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		isOrbiting = false
	end

	lastDownHitDistance = nil -- Reset collision state on detach
	lastForwardHitTime = 0
	print("VehicleCamera detached") -- Renamed from DrivingCamera
end

-- Placeholder methods for settings
function VehicleCamera:SetOffset(newOffset: Vector3) -- Renamed from DrivingCamera
	baseCameraOffset = newOffset
end

function VehicleCamera:SetSmoothingFactor(newFactor: number) -- Renamed from DrivingCamera
	cameraSmoothingFactor = newFactor
end

-- REMOVED EnableMouseControl function as it's replaced by RMB orbiting
-- function VehicleCamera:EnableMouseControl(enabled: boolean)
-- 	...
-- end

return VehicleCamera -- Renamed from DrivingCamera