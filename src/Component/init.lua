-- Component.lua
-- SnerMorY
-- November 1, 2024

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Root = script
local Packages = Root.Packages

local Types = require(Root.Types)

local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)
local Janitor = require(Packages.Janitor)
local Fusion = require(Packages.Fusion)

type Signal<T...> = Types.Signal<T...>
type Value<T> = Types.Value<T>

local IS_SERVER = RunService:IsServer()
local DEFAULT_ANCESTORS = { workspace, game:GetService("Players") }
local DEFAULT_TIMEOUT = 10

-- Function that makes table readonly (means can't be changed)
local function ReadOnlyTable<T>(tab: { T }): T
	local userdata = newproxy(true)

	local metatable = getmetatable(userdata)
	metatable.__index = tab
	metatable.__metatable = "LOCKED!"

	return userdata
end

-- Function that creates unique key
type UniqueKey<T> = { KeyIdentifier: T }
local function CreateUniqueKey<T>(keyIdentifier: T): UniqueKey<T>
	if not keyIdentifier then
		error("keyIdentifier expected!", 1)
	end

	local key = newproxy(true)
	local metatable = getmetatable(key)

	metatable.__tostring = function()
		return `[{keyIdentifier}]`
	end

	metatable.__index = {
		KeyIdentifier = keyIdentifier,
	}

	return key
end

-- Function that creates unique id
local function CreateGUID(): string
	return HttpService:GenerateGUID(false)
end

-- Symbol keys:
local KEY_ANCESTORS = CreateUniqueKey("Ancestors")
local KEY_INST_TO_COMPONENTS = CreateUniqueKey("InstancesToComponents")
local KEY_GUID_TO_COMPONENTS = CreateUniqueKey("GUIDToComponents")
local KEY_LOCK_CONSTRUCT = CreateUniqueKey("LockConstruct")
local KEY_POINTERS = CreateUniqueKey("Pointers")
local KEY_COMPONENTS = CreateUniqueKey("Components")
local KEY_JANITOR = CreateUniqueKey("Janitor")
local KEY_EXTENSIONS = CreateUniqueKey("Extensions")
local KEY_ACTIVE_EXTENSIONS = CreateUniqueKey("ActiveExtensions")
local KEY_STARTING = CreateUniqueKey("Starting")
local KEY_STARTED = CreateUniqueKey("Started")

local renderId = 0
local function NextRenderName(): string
	renderId += 1
	return "ComponentRender_" .. tostring(renderId)
end

local function InvokeExtensionFn(component, fnName: string)
	for _, extension in ipairs(component[KEY_ACTIVE_EXTENSIONS]) do
		local fn = extension[fnName]
		if type(fn) == "function" then
			fn(component)
		end
	end
end

local function ShouldConstruct(component): boolean
	for _, extension in ipairs(component[KEY_ACTIVE_EXTENSIONS]) do
		local fn = extension.ShouldConstruct
		if type(fn) == "function" then
			local shouldConstruct = fn(component)

			return shouldConstruct
		end
	end
	return true
end

local function GetActiveExtensions(component, extensionList)
	local activeExtensions = table.create(#extensionList)

	for _, extension in ipairs(extensionList) do
		local fn = extension.ShouldExtend
		local shouldExtend = type(fn) ~= "function" or not not fn(component)
		if shouldExtend then
			table.insert(activeExtensions, extension)
		end
	end

	return activeExtensions
end

-- Shortcuts:
local scoped = Fusion.scoped
local peek = Fusion.peek
local New = Fusion.New

local Component = ({} :: any) :: ComponentStatic
Component.__index = Component

export type Component = Types.Component
export type ComponentStatic = Types.ComponentStatic

function Component.new(config: Types.ComponentConfig): Component
	local customComponent = ({} :: any) :: Component

	customComponent.__index = customComponent
	customComponent.__tostring = function()
		return "Component<" .. config.Tag .. ">"
	end

	customComponent[KEY_ANCESTORS] = config.Ancestors or DEFAULT_ANCESTORS
	customComponent[KEY_INST_TO_COMPONENTS] = {}
	customComponent[KEY_GUID_TO_COMPONENTS] = {}
	customComponent[KEY_POINTERS] = {}
	customComponent[KEY_COMPONENTS] = {}
	customComponent[KEY_LOCK_CONSTRUCT] = {}
	customComponent[KEY_JANITOR] = Janitor.new()
	customComponent[KEY_EXTENSIONS] = config.Extensions or {}
	customComponent[KEY_STARTED] = false

	customComponent.Tag = config.Tag

	customComponent.Started = customComponent[KEY_JANITOR]:Add(Signal.new())
	customComponent.Stopped = customComponent[KEY_JANITOR]:Add(Signal.new())

	setmetatable(customComponent, Component)

	customComponent:_setup()

	return customComponent
end

function Component.Load(directoryInstance: Instance, shouldLoadFn: Types.ShouldLoadFn?): { ModuleScript }
	if typeof(directoryInstance) ~= "Instance" then
		return nil
	end

	local prioritedComponents = {} :: { [number]: { ModuleScript } }

	if typeof(shouldLoadFn) ~= "function" then
		shouldLoadFn = function(componentScript)
			return true
		end
	end

	for index: number, componentScript: ModuleScript in ipairs(directoryInstance:GetDescendants()) do
		if componentScript:IsA("ModuleScript") == false then
			continue
		end
		if not shouldLoadFn(componentScript) then
			continue
		end

		local loadPriority = componentScript:GetAttribute("LoadPriority") or 0
		if prioritedComponents[loadPriority] == nil then
			prioritedComponents[loadPriority] = {}
		end

		table.insert(prioritedComponents[loadPriority], componentScript)
	end

	local sortedPriorities = {}
	for priority: number, _ in pairs(prioritedComponents) do
		table.insert(sortedPriorities, priority)
	end
	table.sort(sortedPriorities)

	local loadedComponentScripts = {} :: { ModuleScript }
	for _, priority: number in ipairs(sortedPriorities) do
		for _, componentScript: ModuleScript in ipairs(prioritedComponents[priority]) do
			require(componentScript)
			table.insert(loadedComponentScripts, componentScript)
		end
	end

	return loadedComponentScripts
end

function Component:_instantiate(instance: Instance)
	local component = setmetatable({}, self)

	component.Instance = instance
	component.Janitor = Janitor.new()
	component.Janitor:LinkToInstance(component.Instance)
	component.Scope = component.Janitor:Add(scoped(Fusion), "doCleanup", "ScopeCleanupConnection")
	component.GUID = CreateGUID()
	component.Instance:SetAttribute("GUID", component.GUID)

	component[KEY_ACTIVE_EXTENSIONS] = GetActiveExtensions(component, self[KEY_EXTENSIONS])

	if not ShouldConstruct(component) then
		return nil
	end

	InvokeExtensionFn(component, "Constructing")

	if type(component.Construct) == "function" then
		component:Construct()
	end

	InvokeExtensionFn(component, "Constructed")

	return component
end

function Component:_setup()
	local watchingInstances = {}

	local function StartComponent(component)
		component[KEY_STARTING] = coroutine.running()

		InvokeExtensionFn(component, "Starting")

		component:Start()
		if component[KEY_STARTING] == nil then
			-- Component's Start method stopped the component
			return
		end

		InvokeExtensionFn(component, "Started")

		local hasHeartbeatUpdate = typeof(component.HeartbeatUpdate) == "function"
		local hasSteppedUpdate = typeof(component.SteppedUpdate) == "function"
		local hasRenderSteppedUpdate = typeof(component.RenderSteppedUpdate) == "function"

		if hasHeartbeatUpdate then
			component._heartbeatUpdate = RunService.Heartbeat:Connect(function(dt)
				component:HeartbeatUpdate(dt)
			end)
		end

		if hasSteppedUpdate then
			component._steppedUpdate = RunService.Stepped:Connect(function(_, dt)
				component:SteppedUpdate(dt)
			end)
		end

		if hasRenderSteppedUpdate and not IS_SERVER then
			if component.RenderPriority then
				component._renderName = NextRenderName()
				RunService:BindToRenderStep(component._renderName, component.RenderPriority, function(dt)
					component:RenderSteppedUpdate(dt)
				end)
			else
				component._renderSteppedUpdate = RunService.RenderStepped:Connect(function(dt)
					component:RenderSteppedUpdate(dt)
				end)
			end
		end

		component[KEY_STARTED] = true
		component[KEY_STARTING] = nil

		self.Started:Fire(component)
	end

	local function StopComponent(component)
		if component[KEY_STARTING] then
			-- Stop the component during its start method invocation:
			local startThread = component[KEY_STARTING]
			if coroutine.status(startThread) ~= "normal" then
				pcall(function()
					task.cancel(startThread)
				end)
			else
				task.defer(function()
					pcall(function()
						task.cancel(startThread)
					end)
				end)
			end
			component[KEY_STARTING] = nil
		end

		if component._heartbeatUpdate then
			component._heartbeatUpdate:Disconnect()
		end

		if component._steppedUpdate then
			component._steppedUpdate:Disconnect()
		end

		if component._renderSteppedUpdate then
			component._renderSteppedUpdate:Disconnect()
		elseif component._renderName then
			RunService:UnbindFromRenderStep(component._renderName)
		end

		InvokeExtensionFn(component, "Stopping")
		component:Stop()
		InvokeExtensionFn(component, "Stopped")

		self.Stopped:Fire(component)

		component.Instance:SetAttribute("GUID", nil)
		component.Janitor:Cleanup()
	end

	local function SafeConstruct(instance, id)
		if self[KEY_LOCK_CONSTRUCT][instance] ~= id then
			return nil
		end

		local component = self:_instantiate(instance)

		if self[KEY_LOCK_CONSTRUCT][instance] ~= id then
			return nil
		end

		return component
	end

	local function TryConstructComponent(instance)
		if self[KEY_INST_TO_COMPONENTS][instance] then
			return
		end

		local id = self[KEY_LOCK_CONSTRUCT][instance] or 0
		id += 1
		self[KEY_LOCK_CONSTRUCT][instance] = id
		task.defer(function()
			local component = SafeConstruct(instance, id)
			if not component then
				return
			end

			self[KEY_INST_TO_COMPONENTS][instance] = component
			self[KEY_GUID_TO_COMPONENTS][component.GUID] = component

			table.insert(self[KEY_COMPONENTS], component)
			task.defer(function()
				if self[KEY_INST_TO_COMPONENTS][instance] == component then
					StartComponent(component)
				end
			end)
		end)
	end

	local function TryDeconstructComponent(instance)
		local component = self[KEY_INST_TO_COMPONENTS][instance]
		if not component then
			return
		end

		self[KEY_INST_TO_COMPONENTS][instance] = nil
		self[KEY_GUID_TO_COMPONENTS][component.GUID] = nil
		self[KEY_LOCK_CONSTRUCT][instance] = nil

		local components = self[KEY_COMPONENTS]
		local index = table.find(components, component)
		if index then
			local n = #components
			components[index] = components[n]
			components[n] = nil
		end
		if component[KEY_STARTED] or component[KEY_STARTING] then
			task.spawn(StopComponent, component)
		end
	end

	local function StartWatchingInstance(instance)
		if watchingInstances[instance] then
			return
		end

		local function IsInAncestorList(): boolean
			for _, parent in ipairs(self[KEY_ANCESTORS]) do
				if instance:IsDescendantOf(parent) then
					return true
				end
			end
			return false
		end

		local ancestryChangedHandle = self[KEY_JANITOR]:Add(
			instance.AncestryChanged:Connect(function(_, parent)
				if parent and IsInAncestorList() then
					TryConstructComponent(instance)
				else
					TryDeconstructComponent(instance)
				end
			end),
			"Disconnect",
			"AncestryChangedConnection"
		)

		watchingInstances[instance] = ancestryChangedHandle

		if IsInAncestorList() then
			TryConstructComponent(instance)
		end
	end

	local function InstanceTagged(instance: Instance)
		StartWatchingInstance(instance)
	end

	local function InstanceUntagged(instance: Instance)
		local watchHandle = watchingInstances[instance]

		if watchHandle then
			watchingInstances[instance] = nil
			self[KEY_JANITOR]:Remove("AncestryChangedConnection")
		end

		TryDeconstructComponent(instance)
	end

	self[KEY_JANITOR]:Add(
		CollectionService:GetInstanceAddedSignal(self.Tag):Connect(InstanceTagged),
		"Disconnect",
		"InstanceAddedConnection"
	)
	self[KEY_JANITOR]:Add(
		CollectionService:GetInstanceRemovedSignal(self.Tag):Connect(InstanceUntagged),
		"Disconnect",
		"InstanceRemovedConnection"
	)

	local taggedInstances = CollectionService:GetTagged(self.Tag)
	for _, instance: Instance in ipairs(taggedInstances) do
		task.defer(InstanceTagged, instance)
	end
end

function Component:GetAll()
	return self[KEY_COMPONENTS]
end

function Component:GetByGUID(guid: string)
	if typeof(guid) ~= "string" then
		return nil
	end

	return self[KEY_GUID_TO_COMPONENTS][guid]
end

function Component:FromInstance(instance: Instance)
	return self[KEY_INST_TO_COMPONENTS][instance]
end

function Component:WaitForInstance(instance: Instance, timeout: number?)
	local componentInstance = self:FromInstance(instance)
	if componentInstance and componentInstance[KEY_STARTED] then
		return Promise.resolve(componentInstance)
	end
	return Promise.fromEvent(self.Started, function(c)
		local match = c.Instance == instance
		if match then
			componentInstance = c
		end
		return match
	end)
		:andThen(function()
			return componentInstance
		end)
		:timeout(if type(timeout) == "number" then timeout else DEFAULT_TIMEOUT)
end

function Component:Construct() end -- Absent

function Component:Start() end -- Absent

function Component:Stop() end -- Absent

function Component:GetComponent(componentClass)
	return componentClass[KEY_INST_TO_COMPONENTS][self.Instance]
end

function Component:Destroy()
	self[KEY_JANITOR]:Destroy()
end

function Component:CreateComponentPointer(): Types.ComponentPointer
	local instance = self.Instance :: Instance

	local componentPointer = Instance.new("ObjectValue")
	componentPointer:SetAttribute("PointingGUID", self.GUID)
	componentPointer:SetAttribute("InstanceName", instance.Name)
	componentPointer.Value = instance
	componentPointer.Parent = instance
	componentPointer.Name = "ComponentPointer"

	table.insert(self[KEY_POINTERS], componentPointer)

	CollectionService:AddTag(componentPointer, "ComponentPointer")
	return componentPointer
end

function Component:GetAllComponentPointers(): { Types.ComponentPointer? }
	return self[KEY_POINTERS]
end

function Component:GetByComponentPointer(componentPointer: Types.ComponentPointer): Component
	if typeof(componentPointer) ~= "Instance" then
		return nil
	end
	if CollectionService:HasTag(componentPointer, "ComponentPointer") == false then
		return nil
	end

	local index = table.find(self[KEY_POINTERS], componentPointer)
	if index ~= nil then
		local component = self:GetByGUID(componentPointer:GetAttribute("PointingGUID"))
		if component then
			return component
		end

		local componentInstance = componentPointer.Value :: Instance
		if typeof(componentInstance) ~= "Instance" then
			return nil
		end

		return self:FromInstance(componentInstance)
	end
end

function Component:CreateReplicationProperty<T>(propertyName: string, initialValue: T?, outValue: boolean?): Value<T?>
	if typeof(propertyName) ~= "string" then
		error("<!> Property name expected!", 1)
	end

	local instance = self.Instance :: Instance
	initialValue = initialValue or nil :: any

	local replicationValue = self.Scope:Value(initialValue) :: Value<T?>

	self.Scope:Observer(replicationValue):onBind(function()
		local updatedValue = peek(replicationValue) :: T
		if typeof(updatedValue) == "table" then
			return -- <!> Table cannot be replicated by attributes
		end

		instance:SetAttribute(propertyName, updatedValue)
	end)

	if outValue == true then
		self.Scope.Hydrate({}, instance)({
			[Fusion.AttributeOut(propertyName)] = replicationValue,
		})
	end

	return replicationValue
end

function Component:CreateObserverProperty<T>(propertyName: string, initialValue: T?, inValue: boolean?): Value<T?>
	if typeof(propertyName) ~= "string" then
		error("<!> Property name expected!", 1)
	end

	local instance = self.Instance :: Instance
	initialValue = initialValue or nil :: any

	local observerValue = self.Scope:Value(initialValue) :: Value<T?>

	if instance:GetAttribute(propertyName) == nil then
		instance:SetAttribute(propertyName, initialValue)
	end

	self.Scope.Hydrate({}, instance)({
		[Fusion.AttributeOut(propertyName)] = observerValue,
	})

	if inValue == true then
		self.Scope.Hydrate({}, instance)({
			[Fusion.Attribute(propertyName)] = observerValue,
		})
	end

	return observerValue
end

return (Component :: any) :: ComponentStatic
