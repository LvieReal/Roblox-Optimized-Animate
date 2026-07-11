# Roblox Optimized Animate

A lightweight, portable replacement for the default `Animate` script Roblox inserts into every character. It keeps full compatibility with Roblox's legacy animation setup (idle, walk, run, jump, climb, swim, tool animations, emotes) while giving you a proper API to add, play, and stop animations on top of it, all from a single shared module.

## Setup

1. Copy the code from `main.luau` into a new ModuleScript in ReplicatedStorage.
2. Inside that module, create a Script named `ActivateScript`. Set its RunContext to Client and paste this in:
   ```lua
   require(script:GetAttribute("Path")).AddCharacter(script, script.Parent)
   ```
3. To turn the module on, create a Script in ServerScriptService and paste:
   ```lua
   require(PATH).InitServer()
   ```
   Replace `PATH` with the path to your module.

### Why does this need a separate ActivateScript?

Whenever a character is loaded from a HumanoidDescription, Roblox automatically inserts its own `Animate` LocalScript into the character and dumps all the animation objects (idle, walk, run, etc) inside it. There's no way to stop this from happening.

Instead of fighting it, this module lets it happen and then replaces it. When a Humanoid is added to a character, the server clones `ActivateScript` into that character, moves every animation object out of Roblox's default `Animate` script and into the clone, then deletes the original. The clone (now named `Animate`, just like Roblox expects) becomes the one actually running your animation logic, so nothing else in your game needs to know the switch happened.

## Features

- **Server driven setup.** `InitServer(playersOnly)` scans the workspace for every Humanoid and keeps watching for new ones, automatically taking over their Animate script. Pass `true` for `playersOnly` if you only want this applied to player characters and not NPCs.
- **Weighted animation variations.** Add multiple animations under the same name (for example several idle animations) and the module will randomly roll between them based on a `Weight` value, so you get natural variety without any extra code.
- **Rig scale aware playback.** Walk, run, swim, and climb animation speeds are automatically adjusted based on the character's scale, so R15 rigs of different heights still look correct.
- **Play locks.** `AddPlayLock` / `RemovePlayLock` let you temporarily block all animation playback for a character (useful for cutscenes or custom states) without tearing down any tracks.
- **Deferred execution.** `DeferUntilCharacterAdded` lets server or client code queue up animation calls for a character that hasn't finished loading yet. The call fires as soon as the character is ready, or times out after 5 seconds if it never shows up.
- **Full lifecycle callbacks.** Every track supports `OnEnd` and `OnLoop` callbacks, plus `TransitionToOnEnd` to automatically chain into another animation once one finishes.
- **Resumable animations.** Animations like walk and run can store their last time position when stopped and pick back up from there instead of restarting, avoiding the foot sliding pop you'd normally see.
- **Emote support.** A `PlayEmote` BindableFunction is created for you, accepting either a legacy emote name or a raw Animation instance, and it transitions cleanly back to idle when finished.
- **Periodic idle animations.** Tracks can be set to replay themselves automatically every N seconds using `PlayEverySeconds`, handled client side on `PostSimulation` so it never gets tied up in a spinning thread.
- **Tool animations.** Equipping and unequipping tools with a handle automatically plays and stops the `ToolNone` animation.
- **Client and server replication.** Animations added or played through `AddAnimationServer`, `PlayAnimationServer`, and `StopAnimationServer` are automatically replicated to all clients, including ones who join later.

## API

The full API is exposed on the module table (`AddAnimation`, `PlayAnimation`, `StopAnimation`, `StopAllAnimations`, `AdjustAnimationSpeed`, `AddPlayLock`, `RemovePlayLock`, `ForEachTrack`, `GetStateFromCharacter`, and their server side counterparts). The source is fairly short and commented through its structure, so reading through `main.luau` directly is the fastest way to understand exactly what each function expects.
