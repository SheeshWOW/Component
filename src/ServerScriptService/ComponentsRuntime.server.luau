local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedComponents = ReplicatedStorage:WaitForChild("SharedComponents") :: Folder

local Component = require(ReplicatedStorage:WaitForChild("Component"))

local loadedComponentScripts = Component.Load(SharedComponents)
