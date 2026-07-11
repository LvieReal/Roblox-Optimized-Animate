--!native
--!optimize 2

local module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if RunService:IsServer() then

	local function addHumanoid(humanoid: Humanoid, playersOnly: boolean)
		if playersOnly and not Players:GetPlayerFromCharacter(humanoid.Parent) then
			return
		end
		local newAnimate = script:FindFirstChild("ActivateScript"):Clone()
		local existingAnimate = humanoid.Parent:QueryDescendants("> BaseScript [Name = \"Animate\"]")[1]
		if existingAnimate then
			for _, v in existingAnimate:GetChildren() do
				v.Parent = newAnimate
			end
			existingAnimate:Destroy()
		end
		newAnimate.Name = "Animate"
		newAnimate:SetAttribute("Path", "@game/" .. script:GetFullName():gsub("%.", "/"))
		newAnimate.Parent = humanoid.Parent
		newAnimate.Enabled = true
	end

	function module.InitServer(playersOnly: boolean)
		local remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "AnimateClientEvent"
		remoteEvent.Parent = ReplicatedStorage
		module.__RemoteEvent = remoteEvent

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

	function module.AddAnimationServer(character: Model, parameters: {})
		local args = {"AddAnimation", {
			Character = character,
			Parameters = parameters
		}}
		module.__RemoteEvent:FireAllClients(unpack(args))
		Players.PlayerAdded:Connect(function(player)
			module.__RemoteEvent:FireClient(player, unpack(args))
		end)
	end

	function module.PlayAnimationServer(character: Model, parameters: {})
		module.__RemoteEvent:FireAllClients("PlayAnimation", {
			Character = character,
			Parameters = parameters
		})
	end

	function module.StopAnimationServer(character: Model, parameters: {})
		module.__RemoteEvent:FireAllClients("StopAnimation", {
			Character = character,
			Parameters = parameters
		})
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

export type Track = {
	Obj: AnimationTrack,
	Weight: number,
	WeightInstance: NumberValue?,
	AlwaysPlaying: boolean?,
	PlayEverySeconds: number?,
	PlayEverySecondsElapsed: number?,
	LastTimePosition: number,
	OnEnd: () -> ()?,
	OnEndConnection: RBXScriptConnection,
	OnLoop: () -> ()?,
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

type AddAnimationParameters = {
	Name: string?,
	Animation: Animation?,
	Priority: Enum.AnimationPriority?,
	Looped: boolean?,
	AlwaysPlaying: boolean?,
	PlayEverySeconds: number?,
	OnEnd: () -> ()?,
	OnLoop: () -> ()?,
	PlayAfterLoaded: boolean?
}

type PlayAnimationParameters = {
	Name: string?,
	SubId: number?,
	Speed: number?,
	Weight: number?,
	FadeTime: number?,
	OverrideAll: boolean?,
	OverrideWhitelist: {string},
	OverrideBlacklist: {string},
	OnEnd: () -> ()?,
	OnLoop: () -> ()?,
}

type StopAnimationParameters = {
	StoreTimePosition: boolean?,
	FadeTime: number?
}

type StopAllAnimationsParameters = {
	FadeTime: number,
	Whitelist: {string}?,
	Blacklist: {string}?,
	StoreTimePositionFor: {string}?
}

local active: {[Model]: AnimateState} = {}
local deferred = {}

local function resolveTrack(state, parameters: { Name: string?, SubId: number? }): Track?
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

function rollAnimation(state: AnimateState, animName: string)
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

local function addAnimationLegacyWay(state: AnimateState, v: Animation)
	local n = module.LEGACY_ANIM_NAMES_MAP[v.Parent.Name]
	if not n then
		return
	end
	local alwaysPlaying = n:match("Tool")
	local trackInfo, subId = module.AddAnimation(state, {
		Name = n,
		Animation = v,
		AlwaysPlaying = alwaysPlaying,
		Priority = if alwaysPlaying then Enum.AnimationPriority.Idle else nil
	})
	if trackInfo then
		if not table.find(module.NON_LOOPED_ANIMS, v.Parent.Name) then
			trackInfo.Obj.Looped = if n == "Idle" then trackInfo.Weight == 9 else true
		end
		if n == "Idle" and trackInfo.Weight == 9 then
			module.PlayAnimation(state, { Name = "Idle", SubId = subId })
		end
	end
end

function module.GetStateFromCharacter(character: Model): AnimateState
	return active[character]
end

function module.AddAnimation(state: AnimateState, parameters: AddAnimationParameters): (Track?, number?)

	if not state.Animator then
		return nil
	end

	local n = parameters.Name
	if not n then
		return nil
	end

	local animationObj = parameters.Animation
	if not animationObj then
		return nil
	end

	local trackObj = state.Animator:LoadAnimation(animationObj)
	if not trackObj then
		return nil
	end
	trackObj.Name = n
	trackObj.Priority = parameters.Priority or Enum.AnimationPriority.Core
	if typeof(parameters.Looped) == "boolean" then
		trackObj.Looped = parameters.Looped
	end

	local trackInfo: Track = {
		Obj = trackObj,
		Weight = 1,
		AlwaysPlaying = parameters.AlwaysPlaying,
		PlayEverySeconds = parameters.PlayEverySeconds,
		PlayEverySecondsElapsed = if parameters.PlayEverySeconds then 0 else nil,
		OnEnd = parameters.OnEnd,
		OnLoop = parameters.OnLoop
	}

	local function addWeight(weight: NumberValue?)
		if not weight or trackInfo.WeightInstance and trackInfo.WeightInstance.Parent then
			return
		end
		trackInfo.WeightInstance = weight
		trackInfo.Weight = weight.Value
		table.insert(state.Connections, weight:GetPropertyChangedSignal("Value"):Connect(function()
			trackInfo.Weight = weight.Value
			if state.Tracks[n] then
				local totalWeight = 0
				for _, v in state.Tracks[n].List do
					totalWeight += v.Weight
				end
				state.Tracks[n].TotalWeight = totalWeight
			end
		end))
	end

	addWeight(animationObj:QueryDescendants("> NumberValue [Name = \"Weight\"]")[1])
	table.insert(state.Connections, animationObj.ChildAdded:Connect(function(child)
		if not child:IsA("NumberValue") then
			return
		end
		addWeight(child)
	end))

	local existingTrack = state.Tracks[n]
	local subId
	if existingTrack then
		existingTrack.TotalWeight += trackInfo.Weight
		table.insert(existingTrack.List, trackInfo)
		subId = #existingTrack.List
	else
		state.Tracks[n] = {
			List = { trackInfo },
			TotalWeight = trackInfo.Weight
		}
		subId = 1
	end

	if parameters.PlayAfterLoaded then
		module.PlayAnimation(state, { Name = n, SubId = subId })
	end

	trackObj.KeyframeReached:Connect(function(keyframeName)
		if keyframeName == "End" and n == "Idle" then
			if state.HumanoidStates.Standing then
				module.PlayAnimation(state, { Name = "Idle", OverrideAll = true })
			end
			return
		end
	end)

	return trackInfo, subId

end

function module.AdjustAnimationSpeed(state: AnimateState, parameters: { Value: number })
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

function module.StopAnimation(state: AnimateState, parameters: StopAnimationParameters)
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

function module.StopAllAnimations(state: AnimateState, parameters: StopAllAnimationsParameters)
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

function module.PlayAnimation(state: AnimateState, parameters: PlayAnimationParameters): Track?

	if #state.PlayLocks ~= 0 then
		return nil
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
			local transitionToOnEnd = parameters.TransitionToOnEnd
			if trackHasOnEnd or parametersHaveOnEnd or transitionToOnEnd then
				track.OnEndConnection = track.Obj.Ended:Once(function()
					track.OnEndConnection = nil
					if trackHasOnEnd then
						task.spawn(track.OnEnd, track)
					end
					if parametersHaveOnEnd then
						task.spawn(parameters.OnEnd, track)
					end
					if transitionToOnEnd then
						module.PlayAnimation(state, { Name = transitionToOnEnd })
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
						task.spawn(track.OnLoop, track)
					end
					if parametersHaveOnLoop then
						task.spawn(parameters.OnLoop, track)
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
	if state.Animator then
		for _, v in state.Animator:GetPlayingAnimationTracks() do
			v:Stop()
		end
	end
	for _, v in state.Connections do
		if not v.Connected then
			continue
		end
		v:Disconnect()
	end
	active[character] = nil
end

function module.AddCharacter(sourceScript: BaseScript?, character: Model)

	if Players:GetPlayerFromCharacter(character) and character ~= Players.LocalPlayer.Character then
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
		HumanoidStates = { Standing = true },
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

	local animationsFolder = character:QueryDescendants("> Folder [Name = \"Animations\"]")[1]
	if animationsFolder then
		for _, v in animationsFolder:QueryDescendants("Animation") do
			addAnimationLegacyWay(state, v)
		end
	end

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
			state.Threads.JumpToFallTransition = nil
			if
				state.HumanoidStates.Landed == true
				or state.HumanoidStates.Climbing == true
			then
				return
			end
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

	local playEmoteBindable = sourceScript:QueryDescendants("> BindableFunction [Name = \"PlayEmote\"]")[1]
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
			local track: Track
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
					TransitionToOnEnd = "Idle"
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

function module.InitClient()

	local remoteEvent: RemoteEvent? = ReplicatedStorage:WaitForChild("AnimateClientEvent", 5)
	if remoteEvent then
		remoteEvent.OnClientEvent:Connect(function(action: string, parameters: {})
			if action == "AddAnimation" then
				module.DeferUntilCharacterAdded(parameters.Character, function()
					module.AddAnimation(module.GetStateFromCharacter(parameters.Character), parameters.Parameters)
				end)
				return
			end
			if action == "PlayAnimation" then
				module.DeferUntilCharacterAdded(parameters.Character, function()
					module.PlayAnimation(module.GetStateFromCharacter(parameters.Character), parameters.Parameters)
				end)
				return
			end
			if action == "StopAnimation" then
				module.DeferUntilCharacterAdded(parameters.Character, function()
					module.StopAnimation(module.GetStateFromCharacter(parameters.Character), parameters.Parameters)
				end)
				return
			end
		end)
	end

	RunService.PostSimulation:Connect(function(deltaTime)
		for character, state in active do
			module.ForEachTrack(state, function(name, _, track: Track)
				if not track.PlayEverySeconds or track.Obj.IsPlaying then
					return
				end
				track.PlayEverySecondsElapsed += deltaTime
				if track.PlayEverySecondsElapsed < track.PlayEverySeconds then
					return
				end
				track.PlayEverySecondsElapsed = 0
				module.PlayAnimation(state, { Name = name })
			end)
		end
	end)

end

return module
