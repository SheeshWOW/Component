local Root = script.Parent
local Packages = Root.Parent

local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)
local Janitor = require(Packages.Janitor)
local Fusion = require(Packages.Fusion)

export type AncestorList = { Instance }
export type ExtensionFn = (any) -> ()
export type ExtensionShouldFn = (any) -> boolean
export type ShouldLoadFn = (componentScript: ModuleScript) -> boolean

export type Extension = {
	ShouldExtend: ExtensionShouldFn?,
	ShouldConstruct: ExtensionShouldFn?,
	Constructing: ExtensionFn?,
	Constructed: ExtensionFn?,
	Starting: ExtensionFn?,
	Started: ExtensionFn?,
	Stopping: ExtensionFn?,
	Stopped: ExtensionFn?,
}

export type ComponentConfig = {
	Tag: string,
	Ancestors: AncestorList?,
	Extensions: { Extension }?,

	LoadPriority: number?,
}

export type ComponentPointer = ObjectValue --{
-- 	GUID: string,
-- 	PointingGUID: string,
-- }

export type Signal<T...> = Signal.Signal<T...>
export type Value<T> = Fusion.Value<T, T>

export type ComponentAttributeArgs = {
	[string]: any,
} -- AttributeName: AttributeValue

export type ComponentDeclaredArgs = {
	[any]: any,
} -- ArgName: ArgValue

export type Component = {
	GUID: string,
	Instance: Instance,
	Janitor: Janitor.Janitor,
	Scope: Fusion.Scope<{}>,
	RenderPriority: Enum.RenderPriority,

	Started: Signal<Component>,
	Stopped: Signal<Component>,

	GetAll: (self: Component) -> { Component },
	GetByGUID: (self: Component, guid: string) -> Component,
	FromInstance: (self: Component, instance: Instance) -> Component,
	WaitForInstance: (self: Component, instance: Instance, timeout: number?) -> {}, -- IPromise
	GetComponent: (self: Component, componentClass: {}) -> Component,

	Construct: (self: Component, aArgs: ComponentAttributeArgs, dArgs: ComponentDeclaredArgs) -> nil,
	Start: (self: Component) -> nil,
	Stop: (self: Component) -> nil,

	HeartbeatUpdate: (self: Component, deltaTime: number) -> nil,
	SteppedUpdate: (self: Component, deltaTime: number) -> nil,
	RenderSteppedUpdate: (self: Component, deltaTime: number) -> nil,

	CreateReplicationProperty: <T>(
		self: Component,
		propertyName: string,
		initialValue: T?,
		outValue: boolean?
	) -> Value<T?>,
	CreateObserverProperty: <T>(
		self: Component,
		propertyName: string,
		initialValue: T?,
		inValue: boolean?
	) -> Value<T?>,

	CreateComponentPointer: (self: Component) -> ComponentPointer,
	GetAllComponentPointers: (self: Component) -> { ComponentPointer? },
	GetByComponentPointer: (self: Component, componentPointer: ComponentPointer) -> Component?,

	Destroy: (self: Component) -> nil,
}

export type ComponentStatic = {
	new: (config: ComponentConfig) -> Component,
	Load: (directoryInstance: Instance, shouldLoadFn: ShouldLoadFn?) -> { ModuleScript },
}

return nil
