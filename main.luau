local module = {}

if game.RunService:IsServer() then

	local function addHumanoid(humanoid: Humanoid, playersOnly: boolean)
		if playersOnly and not game.Players:GetPlayerFromCharacter(humanoid.Parent) then
			return
		end
		local newAnimate = script:FindFirstChild("ActivateScript"):Clone()
		local existingAnimates = humanoid.Parent:QueryDescendants("> BaseScript [Name = \"Animate\"]")
		if #existingAnimates ~= 0 then
			for _, v in existingAnimates[1]:GetChildren() do
				v.Parent = newAnimate
			end
			existingAnimates[1]:Destroy()
		end
		newAnimate.Name = "Animate"
		newAnimate:SetAttribute("Path", "@game/" .. script:GetFullName():gsub("%.", "/"))
		newAnimate.Parent = humanoid.Parent
		newAnimate.Enabled = true
	end

	function module.InitServer(playersOnly: boolean)
		for _, v in workspace:QueryDescendants("Humanoid") do
			task.spawn(addHumanoid, v, playersOnly)
		end
		workspace.DescendantAdded:Connect(function(descendant)
			if not descendant:IsA("Humanoid") then
				return
			end
			addHumanoid(descendant, playersOnly)
		end)
	end

	return module

end

module.DEFAULTS = {
	FADE_TIME_PLAY = 0.1,
	FADE_TIME_STOP = 0.1
}

module.LEGACY_ANIM_NAMES_MAP = {
	idle = "Idle",
	walk = "Walk",
	run = "Run",
	jump = "Jump",
	fall = "Fall",
	climb = "Climb",
	sit = "Sit",
	swimidle = "SwimIdle",
	swim = "Swim",
	toolnone = "ToolNone",
	mood = "Mood",
	dance = "Dance",
	dance2 = "Dance2",
	dance3 = "Dance3",
	wave = "Wave",
	point = "Point",
	laugh = "Laugh",
	cheer = "Cheer"
}

module.NON_LOOPED_ANIMS = { "wave", "point", "laugh", "cheer" }

local active = {}
local deferred = {}

export type Track = {
	Obj: AnimationTrack,
	Weight: number,
	AlwaysPlaying: boolean,
	LastTimePosition: number,
	OnEnd: () -> (),
	OnEndConnection: RBXScriptConnection,
	OnLoop: () -> (),
	OnLoopConnection: RBXScriptConnection
}

export type AnimateState = {
	Tracks: {[string]: {List: {Track}, TotalWeight: number}},
	HumanoidStates: {[string]: boolean},
	Connections: {RBXScriptConnection},
	Threads: {thread},
	PlayLocks: {string},
	Character: Model,
	Humanoid: Humanoid,
	Animator: Animator,
	PlayingEmote: Track?
}

local function resolveTrack(state, parameters): Track?
	local track = state.Tracks[parameters.Name]
	if not track then
		return nil
	end
	if parameters.SubId then
		return track.List[parameters.SubId]
	end
	return track.List[1]
end

local function getRigScale(state: AnimateState)
	return state.Character:GetScale()
end

function rollAnimation(state: AnimateState, animName)
	local track = state.Tracks[animName]
	if not track then
		return nil
	end
	local roll = math.random(1, track.TotalWeight)
	local idx = 1
	while roll > track.List[idx].Weight do
		roll -= track.List[idx].Weight
		idx += 1
	end
	return idx
end

local function addAnimationLegacyWay(state: AnimateState, v)
	local n = module.LEGACY_ANIM_NAMES_MAP[v.Parent.Name]
	if not n then
		return
	end
	local isLooped = not table.find(module.NON_LOOPED_ANIMS, v.Parent.Name)
	local alwaysPlaying = n:match("Tool") or n == "Mood"
	module.AddAnimation(state, {
		Name = n,
		Animation = v,
		AlwaysPlaying = alwaysPlaying,
		Looped = isLooped,
		Priority = if alwaysPlaying then Enum.AnimationPriority.Idle else nil
	})
end

function module.GetStateFromCharacter(character: Model): AnimateState
	return active[character]
end

function module.AddAnimation(state: AnimateState, parameters): Track

	local n = parameters.Name
	local animationObj = parameters.Animation

	local weight = animationObj:FindFirstChild("Weight")
	local weightValue = if weight and weight:IsA("NumberValue") then weight.Value else 1

	local trackObj = state.Animator:LoadAnimation(animationObj)
	trackObj.Name = n
	trackObj.Priority = parameters.Priority or Enum.AnimationPriority.Core
	if typeof(parameters.Looped) == "boolean" then
		trackObj.Looped = parameters.Looped
	end

	if n == "Idle" then
		trackObj.KeyframeReached:Connect(function(keyframeName)
			if keyframeName == "End" then
				if state.HumanoidStates.Standing then
					module.PlayAnimation(state, { Name = "Idle", OverrideAll = true })
				end
				return
			end
		end)
	end

	local trackInfo: Track = {
		Obj = trackObj,
		Weight = weightValue,
		AlwaysPlaying = parameters.AlwaysPlaying,
		OnEnd = parameters.OnEnd,
		OnLoop = parameters.OnLoop
	}

	local existingTrack = state.Tracks[n]
	if existingTrack then
		existingTrack.TotalWeight += weightValue
		table.insert(existingTrack.List, trackInfo)
	else
		state.Tracks[n] = {
			List = { trackInfo },
			TotalWeight = weightValue
		}
	end

	return trackInfo

end

function module.AdjustAnimationSpeed(state: AnimateState, parameters)
	local track = resolveTrack(state, parameters)
	if not track then
		return
	end
	track.Obj:AdjustSpeed(parameters.Value)
end

function module.AddPlayLock(state: AnimateState, tag: string)
	if table.find(state.PlayLocks, tag) then
		return
	end
	table.insert(state.PlayLocks, tag)
end

function module.RemovePlayLock(state: AnimateState, tag: string)
	local i = table.find(state.PlayLocks, tag)
	if not i then
		return
	end
	table.remove(state.PlayLocks, i)
end

function module.ForEachTrack(state: AnimateState, f: () -> ())
	for name, info in state.Tracks do
		for i, track in info.List do
			task.spawn(f, name, i, track)
		end
	end
end

function module.StopAnimation(state: AnimateState, parameters)
	local track = resolveTrack(state, parameters)
	if not track or not track.Obj.IsPlaying then
		return
	end
	if parameters.StoreTimePosition then
		track.LastTimePosition = track.Obj.TimePosition
	end
	if track.OnEndConnection then
		track.OnEndConnection:Disconnect()
		track.OnEndConnection = nil
	end
	if track.OnLoopConnection then
		track.OnLoopConnection:Disconnect()
		track.OnLoopConnection = nil
	end
	track.Obj:Stop(parameters.FadeTime or module.DEFAULTS.FADE_TIME_STOP)
end

function module.StopAllAnimations(state: AnimateState, parameters)
	if typeof(parameters) ~= "table" then
		parameters = {}
	end
	module.ForEachTrack(state, function(name, subId, track: Track)
		if
			track.AlwaysPlaying
			or (parameters.Whitelist and table.find(parameters.Whitelist, name))
			or (parameters.Blacklist and not table.find(parameters.Blacklist, name))
		then
			return
		end
		module.StopAnimation(state, {
			Name = name,
			SubId = subId,
			FadeTime = parameters.FadeTime,
			StoreTimePosition =
				if
				parameters.StoreTimePositionFor
				then
				table.find(parameters.StoreTimePositionFor, name) ~= nil
				else
				false
		})
	end)
end

function module.PlayAnimation(state: AnimateState, parameters): Track?

	if #state.PlayLocks ~= 0 then
		return nil
	end

	if typeof(parameters) ~= "table" then
		parameters = {}
	end

	if not parameters.SubId then
		parameters.SubId = rollAnimation(state, parameters.Name)
	end

	local track = resolveTrack(state, parameters)
	if not track then
		return nil
	end

	if track.Obj.IsPlaying then

		if parameters.Speed then
			module.AdjustAnimationSpeed(
				state,
				{
					Name = parameters.Name,
					Value = parameters.Speed
				}
			)
		end

	else

		if
			parameters.OverrideAll
			or parameters.OverrideWhitelist
			or parameters.OverrideBlacklist
		then
			module.StopAllAnimations(state, {
				FadeTime = parameters.FadeTimeStop,
				Whitelist = parameters.OverrideWhitelist,
				Blacklist = parameters.OverrideBlacklist,
				StoreTimePositionFor = parameters.StoreTimePositionFor
			})
		end

		track.Obj:Play(
			parameters.FadeTime or module.DEFAULTS.FADE_TIME_PLAY,
			parameters.Weight,
			parameters.Speed
		)

		if not track.Obj.Looped then
			local trackHasOnEnd = typeof(track.OnEnd) == "function"
			local parametersHaveOnEnd = typeof(parameters.OnEnd) == "function"
			if trackHasOnEnd or parametersHaveOnEnd then
				track.OnEndConnection = track.Obj.Ended:Once(function()
					track.OnEndConnection = nil
					if trackHasOnEnd then
						task.spawn(track.OnEnd)
					end
					if parametersHaveOnEnd then
						task.spawn(parameters.OnEnd)
					end
				end)
			end
		end

		if track.Obj.Looped then
			local trackHasOnLoop = typeof(track.OnLoop) == "function"
			local parametersHaveOnLoop = typeof(parameters.OnLoop) == "function"
			if trackHasOnLoop or parametersHaveOnLoop then
				track.OnLoopConnection = track.Obj.DidLoop:Connect(function()
					if trackHasOnLoop then
						task.spawn(track.OnLoop)
					end
					if parametersHaveOnLoop then
						task.spawn(parameters.OnLoop)
					end
				end)
			end
		end

		if track.LastTimePosition then
			track.Obj.TimePosition = track.LastTimePosition
			track.LastTimePosition = nil
		end

	end

	return track
end

function module.DeferUntilCharacterAdded(character: Model, f: () -> ())
	if active[character] then
		task.spawn(f, active[character])
		return
	end
	if not deferred[character] then
		deferred[character] = {f}
	else
		table.insert(deferred[character], f)
	end
	task.delay(5, function()
		if not deferred[character] then
			return
		end
		warn("Animate Module defer for character " .. tostring(character) .. " timed out")
		deferred[character] = nil
	end)
end

function module.RemoveCharacter(character: Model)
	local state = active[character]
	if not state then
		return
	end
	for _, v in state.Connections do
		v:Disconnect()
	end
	active[character] = nil
end

function module.AddCharacter(sourceScript: BaseScript?, character: Model)

	if game.Players:GetPlayerFromCharacter(character) and character ~= game.Players.LocalPlayer.Character then
		return
	end

	if active[character] then
		warn("Animate Module failed to add character " .. tostring(character) .. " because it's already active")
		return nil
	end

	local start = time()
	local humanoid: Humanoid
	while not humanoid do
		if not character or not character.Parent then
			return nil
		end
		if time() - start > 5 then
			warn("Animate Module timed out waiting for humanoid in character: " .. tostring(character))
			return nil
		end
		humanoid = character:FindFirstChildWhichIsA("Humanoid")
		task.wait()
	end

	local animator: Animator = humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		warn("Animate Module found no Animator in character: " .. tostring(character))
		return nil
	end

	for _, v in animator:GetPlayingAnimationTracks() do
		v:Stop()
	end

	local state: AnimateState = {
		Tracks = {},
		HumanoidStates = {},
		Connections = {},
		Threads = {},
		PlayLocks = {},
		Character = character,
		Humanoid = humanoid,
		Animator = animator
	}

	active[character] = state

	if deferred[character] then
		for _, f in deferred[character] do
			task.spawn(f, state)
		end
		deferred[character] = nil
	end

	for _, v in sourceScript:QueryDescendants("Animation") do
		addAnimationLegacyWay(state, v)
	end
	table.insert(state.Connections, sourceScript.DescendantAdded:Connect(function(v)
		if not v:IsA("Animation") then
			return
		end
		addAnimationLegacyWay(state, v)
	end))

	local animationsFolders = character:QueryDescendants("> Folder [Name = \"Animations\"]")
	if animationsFolders[1] then
		for _, v in animationsFolders[1]:QueryDescendants("Animation") do
			addAnimationLegacyWay(state, v)
		end
	end

	module.PlayAnimation(state, { Name = "Idle" })
	module.PlayAnimation(state, { Name = "Mood" })

	table.insert(state.Connections, humanoid.Running:Connect(function(speed)
		if
			state.Threads.JumpToFallTransition
			or state.HumanoidStates.Landed == false
			or state.HumanoidStates.Climbing == true
		then
			state.HumanoidStates.Standing = false
			return
		end
		if state.PlayingEmote then
			module.StopAnimation(state, { Name = state.PlayingEmote.Name })
			state.PlayingEmote = nil
		end
		if speed < 1 then
			state.HumanoidStates.Standing = true
			module.PlayAnimation(state, { Name = "Idle", OverrideAll = true })
			return
		end
		state.HumanoidStates.Standing = false
		module.PlayAnimation(state, {
			Name = humanoid.WalkSpeed >= 16 and "Run" or "Walk",
			Speed = (speed / getRigScale(state)) / 14.5,
			StoreTimePositionFor = { "Run", "Walk" },
			OverrideAll = true,
			FadeTime = 0.25
		})
	end))

	table.insert(state.Connections, humanoid.Jumping:Connect(function(active)
		if not active then
			return
		end
		state.HumanoidStates.Landed = false
		state.HumanoidStates.Climbing = false
		if state.Threads.JumpToFallTransition then
			task.cancel(state.Threads.JumpToFallTransition)
		end
		module.PlayAnimation(state, { Name = "Jump", OverrideAll = true })
		state.Threads.JumpToFallTransition = task.delay(0.3, function()
			if
				state.HumanoidStates.Landed == true
				or state.HumanoidStates.Climbing == true
			then
				return
			end
			state.Threads.JumpToFallTransition = nil
			module.PlayAnimation(state, { Name = "Fall", OverrideAll = true })
		end)
	end))

	table.insert(state.Connections, humanoid.FreeFalling:Connect(function(active)
		if
			not active
			or state.Threads.JumpToFallTransition
			or state.HumanoidStates.Landed == false
			or state.HumanoidStates.Climbing == true
		then
			return
		end
		state.HumanoidStates.Landed = false
		module.PlayAnimation(state, { Name = "Fall", OverrideAll = true })
	end))

	table.insert(state.Connections, humanoid.Climbing:Connect(function(speed)
		state.HumanoidStates.Landed = false
		state.HumanoidStates.Climbing = true
		if math.abs(speed) < 1 then
			module.AdjustAnimationSpeed(state, { Name = "Climb", Value = 0 })
			return
		end
		module.PlayAnimation(state, {
			Name = "Climb",
			Speed = (speed / getRigScale(state)) / 10,
			OverrideAll = true
		})
	end))

	table.insert(state.Connections, humanoid.Seated:Connect(function(active)
		if not active then
			state.HumanoidStates.Seated = false
			module.StopAnimation(state, { Name = "Sit" })
			return
		end
		state.HumanoidStates.Seated = true
		module.PlayAnimation(state, { Name = "Sit", OverrideAll = true })
	end))

	table.insert(state.Connections, humanoid.Swimming:Connect(function(speed)
		if speed < 1 then
			module.PlayAnimation(state, {
				Name = "SwimIdle",
				OverrideAll = true
			})
			return
		end
		module.PlayAnimation(state, {
			Name = "Swim",
			Speed = (speed / getRigScale(state)) / 14.5,
			OverrideAll = true,
			FadeTime = 0.25
		})
	end))

	table.insert(state.Connections, humanoid.StateChanged:Connect(function(old, new)
		if old == Enum.HumanoidStateType.Swimming then
			state.HumanoidStates.Landed = true
			state.HumanoidStates.Climbing = false
			module.StopAnimation(state, { Name = "SwimIdle" })
			module.StopAnimation(state, { Name = "Swim" })
			return
		end
		if old == Enum.HumanoidStateType.Climbing then
			state.HumanoidStates.Landed = true
			state.HumanoidStates.Climbing = false
			module.StopAnimation(state, { Name = "Climb" })
			return
		end
		if new == Enum.HumanoidStateType.Landed then
			if state.Threads.JumpToFallTransition then
				task.cancel(state.Threads.JumpToFallTransition)
				state.Threads.JumpToFallTransition = nil
			end
			state.HumanoidStates.Landed = true
		end
	end))

	table.insert(state.Connections, character.ChildAdded:Connect(function(child)
		if not child:IsA("Tool") or not child.RequiresHandle then
			return
		end
		module.PlayAnimation(state, { Name = "ToolNone" })
	end))
	table.insert(state.Connections, character.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") or not child.RequiresHandle or character:FindFirstChildWhichIsA("Tool") then
			return
		end
		module.StopAnimation(state, { Name = "ToolNone" })
	end))

	local playEmoteBindable = sourceScript:FindFirstChild("PlayEmote")
	if not playEmoteBindable then
		playEmoteBindable = Instance.new("BindableFunction")
		playEmoteBindable.Name = "PlayEmote"
		playEmoteBindable.Parent = sourceScript
	end

	playEmoteBindable.OnInvoke = function(emote: string | Animation)
		if state.HumanoidStates.Standing ~= true then
			return nil
		end
		local isAnimInstance = typeof(emote) == "Instance" and emote:IsA("Animation")
		if typeof(emote) == "string" or isAnimInstance then
			local track
			if isAnimInstance then
				track = resolveTrack(state, { Name = emote.AnimationId })
				if not track then
					track = module.AddAnimation(state, {
						Name = emote.AnimationId,
						Animation = emote
					})
				end
			else
				track = resolveTrack(state, { Name = module.LEGACY_ANIM_NAMES_MAP[emote] })
			end
			module.PlayAnimation(
				state,
				{
					Name = track.Obj.Name,
					OverrideAll = true,
					OnEnd = function()
						module.PlayAnimation(state, { Name = "Idle" })
					end
				}
			)
			state.PlayingEmote = track
			return true, track.Obj
		end
		return false
	end

	table.insert(state.Connections, humanoid.Died:Once(function()
		module.StopAllAnimations(state)
		module.RemoveCharacter(character)
	end))
	table.insert(state.Connections, character.Destroying:Once(function()
		module.RemoveCharacter(character)
	end))

	return state

end

return module
