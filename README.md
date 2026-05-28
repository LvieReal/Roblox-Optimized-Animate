# Roblox Optimized Animate

Optimized Animate is a lightweight, portable replacement for default Animate script provided by Roblox.

## How to use:
- Copy the code from main.luau into new ModuleScript in ReplicatedStorage.
- Create a Script inside the module, name it ActivateScript, set it's RunContext to Client and paste this code in: `require(script:GetAttribute("Path")).AddCharacter(script, script.Parent)`
- To activate the module during run time, create a Script in ServerScriptService and paste: `require(PATH).InitServer()`
- Replace `PATH` with path to the module.
##

## Unique features:
- Control whether all Humanoids in game will be animated by passing `playersOnly: boolean` parameter to `InitServer()`
- Easily add and play custom animations using `AnimateModule.AddAnimation()`, stop with `AnimateModule.StopAnimation()`
- Defer functions until character is added to AnimateModule using `AnimateModule.DeferUntilCharacterAdded` (fires immediately if character is already in registry)
##

Learn more about this module by inspecting it's source, it should be easy to understand!
