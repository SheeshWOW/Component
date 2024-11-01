local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Component = require(ReplicatedStorage:WaitForChild("Component"))
local Fusion = require(ReplicatedStorage.Component.Packages.Fusion)

type Component = Component.Component

local peek = Fusion.peek

local function printNoTostring(tab: {})
	local metatable = getmetatable(tab) or {}
	local oldTostringMetamethod = metatable.__tostring

	if metatable.__tostring ~= nil then
		metatable.__tostring = nil
	end

	metatable.__tostring = oldTostringMetamethod
end

local Tag = "Apple"
local AppleComponent = Component.new({
	Tag = Tag,
	Ancestors = { workspace },
	Extensions = {},
})

function AppleComponent:Construct()
	local instance = self.Instance

	self.TestValue = self.Scope:Value("TestValue")

	self.MoveSpeed = self:CreateObserverProperty("MoveSpeed", 1, true)
	self.Position = self:CreateReplicationProperty("ApplePosition", Vector3.zero, false)

	self.Pointer = self:CreateComponentPointer()

	warn("<!>", instance, "constructed!")
end

function AppleComponent:HeartbeatUpdate(deltaTime: number)
	local instance = self.Instance :: BasePart

	local instanceCFrame = instance:GetPivot() :: CFrame

	local moveDirection = Vector3.new(0.5, 0.5, 0.5) :: Vector3
	local moveScalar = deltaTime * peek(self.MoveSpeed) :: number

	local moveVector = moveDirection * moveScalar :: Vector3
	local destinationCFrame = instanceCFrame + moveVector :: CFrame
	instance:PivotTo(destinationCFrame)

	self.Position:set(destinationCFrame.Position)
end

function AppleComponent:Start()
	local instance = self.Instance :: BasePart

	task.delay(3, function()
		local component = self:GetByComponentPointer(self.Pointer)
		printNoTostring(component)
		print(component)
	end)
end

function AppleComponent:Stop()
	local instance = self.Instance :: BasePart

	-- warn(self.Scope)
	-- task.defer(function()
	-- 	warn(self.Scope)
	-- end)

	warn("<!>", instance, "deconstructed!")
end

return AppleComponent
