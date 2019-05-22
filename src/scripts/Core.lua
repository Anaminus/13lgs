--[[ Core

The Core module provides core functions to be used by the rest of the framework.

]]

local Core = {}

-- isServer returns true when the module is running on a server peer.
local isServer
do
	local RunService = game:GetService("RunService")
	isServer = RunService:IsServer()
end

----------------------------------------------------------------
----------------------------------------------------------------

-- Pack returns the received arguments packed into a table, as well as the
-- number of arguments.
local function Pack(...)
	return {...}, select("#", ...)
end

Core.Pack = Pack

----------------------------------------------------------------
----------------------------------------------------------------

local mtError = {__type = "CoreError"}
function mtError:__tostring()
	return string.format(unpack(self, 1, self.n))
end

-- newError creates an error using ErrorHook, or a from a basic default error
-- wrapper otherwise.
local function newError(...)
	local hook = Core.ErrorHook
	if hook then
		return hook(...)
	end
	local err, n = Pack(...)
	err.n = n
	return setmetatable(err, mtError)
end

-- ErrorHook is a callback function that transforms errors emitted by Core
-- functions. It is used to promote Core errors into a more complex error
-- system.
--
-- The arguments passed to ErrorHook are the error data. Core structures data to
-- be passed to string.format: the first argument is the format string, and
-- remaining arguments are the values to be formatted.
--
-- ErrorHook must return a value representing the error data.
--
-- If ErrorHook is nil, then an error is represented by a table containing the
-- error data, which will be formatted with string.format when converted to a
-- string.
Core.ErrorHook = nil

----------------------------------------------------------------
----------------------------------------------------------------

-- Level indicates the severity of a log event.
local LevelError   = 0 -- A fatal error.
local LevelWarning = 1 -- Noteworthy but non-fatal.
local LevelInfo    = 2 -- Informational.

Core.LevelError   = LevelError
Core.LevelWarning = LevelWarning
Core.LevelInfo    = LevelInfo

-- log logs an event to LogHook, or otherwise queues the event and behaves
-- according to the given level.
local log
do
	local queue = {}
	function log(level, ...)
		local timestamp = elapsedTime()
		local hook = Core.LogHook
		if hook then
			if hook(level, timestamp, ...) ~= true then
				return
			end
		else
			local event, n = Pack(...)
			event.n = n
			event.level = level
			event.timestamp = timestamp
			queue[#queue+1] = event
		end

		if level == LevelInfo then
			print(...)
		elseif level == LevelWarning then
			warn(...)
		elseif level == LevelError then
			local err, stack = ...
			error(tostring(err), stack+1)
		end
	end

	-- DrainLogs empties the queue of events logged while LogHook is unset, and
	-- returns the results as an array of events.
	--
	-- Each event is an array containing the event content. The `n` field is the
	-- length of the array, the `level` field indicates the severity of the
	-- event, and the timestamp field indicates when the event was logged.
	function Core.DrainLogs()
		local q = queue
		queue = {}
		return q
	end
end

-- LogHook is a callback function that receives logging events emitted by the
-- Core module. It is used to promote Core logging into a more complex logging
-- system.
--
-- The first argument is a level indicating the severity of the event. The
-- second argument is a timestamp marking when the event was logged (relative to
-- elapsedTime epoch). The remaining arguments are the content of the event.
--
-- The severity level determines the content, and how the event is handled by
-- default when LogHook is nil:
--
-- - LevelError: error(); first argument is a value representing the error,
--   second is a stack level.
-- - LevelWarning: warn(); arbitrary values to be concatenated as strings.
-- - LevelInfo: print(); arbitrary values to be concatenated as strings.
--
-- While LogHook is nil, events will be added to a queue, which can be retrieved
-- with DrainLogs.
--
-- If LogHook returns true, then the default behavior is used, but the event is
-- not queued.
Core.LogHook = nil

----------------------------------------------------------------
----------------------------------------------------------------

-- IsType returns whether an arbitrary value is of the given primitive Lua type.
function Core.IsType(value, t)
	return type(value) == t
end

-- IsTypeOf returns whether an arbitrary value is of the given Roblox type.
function Core.IsTypeOf(value, t)
	return typeof(value) == t
end

-- IsClass returns whether an arbitrary value is an instance of a given Roblox
-- class.
local function IsClass(value, class)
	return typeof(value) == "Instance" and value.ClassName == class
end
Core.IsClass = IsClass

-- IsClassOf returns whether an arbitrary value inherits from an instance of a
-- given Roblox class.
local function IsClassOf(value, class)
	return typeof(value) == "Instance" and value:IsA(class)
end
Core.IsClassOf = IsClassOf

-- IsEnum returns whether an arbitrary value is an enum item of a given Roblox
-- enum.
local function IsEnum(value, enum)
	return typeof(value) == "EnumItem" and value.EnumType == enum
end
Core.IsEnum = IsEnum

----------------------------------------------------------------
----------------------------------------------------------------

-- encodePath converts a list of path elements into a dot-separated string.
local function encodePath(path)
	return table.concat(path, ".")
end

-- newPath creates a path. The argument can be either a table or a string. A
-- table must be a list of elements, each which must be strings. A string must
-- be a dot-separated list of elements.
--
-- Returns a list containing each element as a string. The `string` field will
-- be set to a normalized path string.
local function newPath(path)
	local t = {}
	if type(path) == "table" then
		for i = 1, #path do
			local v = path[i]
			if type(v) ~= "string" then
				return nil, newError("index %d: string expected, got %s", i, type(v))
			end
			t[i] = v
		end
	elseif type(path) == "string" then
		for element in string.gmatch(path, "[^%.]+") do
			t[#t+1] = element
		end
	else
		return nil, newError("table or string expected, got %s", type(path))
	end
	t.string = encodePath(t)
	return t, nil
end

-- Sets of tracked modules. Automatically filled in by the compiler.
local ModuleTargets = --[[@ModuleTargets]]{}--[[@/ModuleTargets]]
local SharedManifest = --[[@SharedManifest]]{}--[[@/SharedManifest]]
local ServerManifest = --[[@ServerManifest]]{}--[[@/ServerManifest]]

-- Merge depending on peer.
local Manifest = {}
for module, target in pairs(SharedManifest) do
	Manifest[newPath(module).string] = newPath(ModuleTargets[target])
end
if isServer then
	for module, target in pairs(ServerManifest) do
		Manifest[newPath(module).string] = newPath(ModuleTargets[target])
	end
end

-- pushRequireStack and popRequireStack are used to disallow module dependency
-- loops.
local pushRequireStack, popRequireStack
do
	local threadStacks = {}
	function pushRequireStack(thread, module)
		local stack = threadStacks[thread]
		if stack == nil then
			stack = {}
			threadStacks[thread] = stack
		end
		for i = 1, #stack do
			if stack[i] == module then
				return newError("cyclic dependency detected at module %s", module:GetFullName())
			end
		end
		stack[#stack+1] = module
	end
	function popRequireStack(thread, module)
		local stack = threadStacks[thread]
		-- stack ~= nil and #stack > 0
		-- stack[#stack] == module
		stack[#stack] = nil
		if #stack == 0 then
			threadStacks[thread] = nil
		end
	end
end

-- resolvePath receives a number of paths and resolves them from the game tree
-- as a single, concatenated path. Blocks until the referent exists, with no
-- timeout.
local function resolvePath(...)
	local paths = {...}
	local current = game
	local i = 1
	if #paths > 0 and #paths[1] > 0 then
		-- Try first element as a service.
		local ok, service = pcall(game.GetService, game, paths[1][1])
		if ok and service then
			current = service
			i = i + 1
		end
	end

	for j = 1, #paths do
		local path = paths[j]
		for i = i, #path do
			current = current:WaitForChild(path[i], math.huge)
		end
		i = 1
	end
	return current
end

-- requireModuleScript safely requires a given ModuleScript. Results are cached
-- per module. Ensures that modules cannot be required cyclically.
local requireModuleScript
do
	-- BUG: A ModuleScript that returns a value containing the ModuleScript will
	-- never be garbage collected. Resolved by backporting Lua 5.2's ephemeron
	-- tables.
	local cache = setmetatable({}, {__mode = "k"})
	function requireModuleScript(module)
		local result = cache[module]
		if result then
			return result[1], result[2]
		end

		local thread = coroutine.running()
		local err = pushRequireStack(thread, module)
		if err ~= nil then
			return nil, err
		end

		local ok, result = pcall(require, module)
		popRequireStack(thread, module)
		if not ok then
			cache[module] = {nil, result}
			return nil, result
		end
		cache[module] = {result, nil}
		return result, nil
	end
end

-- pushModuleStack and popModuleStack are used to track modules that are
-- blocking. The path argument is expected to be a unique object.
local pushModuleStack, popModuleStack
do
	local blockingModules = {}
	function pushModuleStack(path)
		blockingModules[path] = elapsedTime()
	end
	function popModuleStack(path)
		blockingModules[path] = nil
	end

	-- GetBlockingModules returns a list of module paths that are being
	-- required, and are currently blocking. Paths are repeated for each time
	-- the module is required.
	--
	-- Only paths that have been blocking for at least the given duration are
	-- returned. If the argument is not a number, then all paths are returned.
	function Core.GetBlockingModules(duration)
		local modules = {}
		if type(duration) == "number" then
			local t = elapsedTime()
			for path, time in pairs(blockingModules) do
				if t - time >= duration then
					modules[#modules+1] = path.string
				end
			end
		else
			for path in pairs(blockingModules) do
				modules[#modules+1] = path.string
			end
		end
		table.sort(modules)
		return modules
	end
end

-- Require requires a module. Several signatures are possible:
--
-- - Require(module: ModuleScript)
--     - Requires a ModuleScript object directly.
-- - Require(path: string)
--     - Requires according to the given full-name of the module, where each
--       element is dot-separated.
-- - Require(path: table)
--     - Requires according to the given full-name of the module, where each
--       element is an entry in the list.
--
-- Upon success, Require returns the value returned by the module. A nil value
-- cannot be returned on success. If an error occurs, nil is returned, followed
-- by the error.
--
-- When resolving a path, Require will block until the referred module exists.
-- There are no timeouts, so in order to catch deadlocking, a warning will be
-- emitted for modules are that not tracked by the framework. Modules included
-- by the framework compiler are tracked automatically.
function Core.Require(path)
	local module, err
	if IsClassOf(path, "ModuleScript") then
		module = path
		path, err = newPath(module:GetFullName())
	else
		path, err = newPath(path)
	end
	if err ~= nil then
		log(LevelError, err, 2)
		return nil, err
	end

	pushModuleStack(path)
	if module == nil then
		local target = Manifest[path.string]
		if not target then
			log(LevelWarning, string.format("attempting to require untracked module %s", path.string))
			module = resolvePath(path)
		else
			module = resolvePath(target, path)
		end
	end
	local result, err = requireModuleScript(module)
	popModuleStack(path)

	if err ~= nil then
		log(LevelError, err, 2)
		return nil, err
	end
	return result, nil
end

--#if EnableBridge then
-- Create a BindableFunction under ServerStorage for bridging across security
-- identities. The name is formatted as CoreBridge[ID], where ID is the security
-- identity of the corresponding module thread.
--
-- The bindable can be invoked by passing the name of a function in the Core
-- module, followed by the arguments to be passed to the function.
--
-- Must be used only for debugging.
do
	-- Only allow specific APIs.
	local BridgeWhitelist = {
		DrainLogs = true,
		GetBlockingModules = true,
	}

	-- We have to jump through hoops to reliably get the identity. This is done
	-- by generating a GUID, passing it to printidentity, then matching the
	-- message through LogService.
	local guid = "bridge" .. game:GetService("HttpService"):GenerateGUID() .. ":"
	local conn
	conn = game:GetService("LogService").MessageOut:Connect(function(message, type)
		if type ~= Enum.MessageType.MessageOutput then
			return
		end
		-- printidentity appends a space followed by the identity.
		if message:sub(1, #guid+1) ~= guid .. " " then
			return
		end
		local identity = message:sub(#guid+2)

		conn:Disconnect()
		conn = nil

		local bindable = Instance.new("BindableFunction")
		bindable.Name = "CoreBridge" .. identity
		function bindable.OnInvoke(func, ...)
			if BridgeWhitelist[func] then
				return Core[func](...)
			end
			error("invalid call", 2)
		end
		bindable.Archivable = false
		bindable.Parent = game:GetService("ServerStorage")
	end)
	printidentity(guid)
end
--#end
return Core
