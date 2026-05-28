# Roblox Optimized Animate

Optimized Animate is a lightweight, portable replacement for default Animate script provided by Roblox.

## How to use:
- Copy the code from main.luau into new ModuleScript in ReplicatedStorage.
- Create a Script inside the module, name it ActivateScript, set it's RunContext to Client and paste this code in: `require(script:GetAttribute("Path")).AddCharacter(script, script.Parent)`
- To activate the module during run time, create a Script in ServerScriptService and paste: `require(PATH).InitServer()`
- Replace `PATH` with path to the module.
##

Learn more about this module by inspecting it's source, it should be easy to understand!
