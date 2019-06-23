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

--#if EnableBridge then
-- Set of APIs that can be accessed by the bridge.
local Bridge = {}
--#end

----------------------------------------------------------------
----------------------------------------------------------------
-- Type system

local Impl
local Is
local Interface
do
	local implementedInterfaces = setmetatable({}, {__mode="k"})
	local embeddedInterfaces = {}
	local nillableInterfaces = {}

	-- Impl declares a value to implement zero or more interfaces, which must be
	-- strings. A value can be declared only once, and subsequent attempts do
	-- nothing. Impl returns the value.
	--
	-- If an interface string has been declared previously with Interface, then
	-- the value will automatically implement any embedded interfaces.
	--
	-- When Impl is called with a value and no interfaces, the value is said to
	-- implement nothing. A value that has not been called with Impl is said to
	-- not implement.
	function Impl(value, ...)
		if implementedInterfaces[value] then
			return value
		end
		if value == nil then
			return nil
		end
		local interfaces = {}
		implementedInterfaces[value] = interfaces
		local args = {...}
		for i = 1, #args do
			local interface = args[i]
			if type(interface) == "string" then
				interfaces[interface] = true
				local embedded = embeddedInterfaces[interface]
				if embedded then
					for embed in pairs(embedded) do
						interfaces[embed] = true
					end
				end
			end
		end
		return value
	end

	-- Is returns whether value v implements interface I. If v is nil, then Is
	-- returns true if the interface is nullable. If I is nil, then Is returns
	-- whether v implements.
	function Is(v, I)
		local interfaces = implementedInterfaces[v]
		if interfaces then
			if I == nil or interfaces[I] then
				return true
			end
		end
		if v == nil and nillableInterfaces[I] then
			return true
		end
		-- TODO: If v is a string, check if it is an interface that embeds I.
		return false
	end

	local declaredInterfaces = {}

	-- Interface declares and describes an interface. The first argument is the
	-- interface string, and each remaining argument is a string describing a
	-- behavior of the interface. An interface can be declared only once.
	--
	-- If a behavior string matches an interface string declared previously,
	-- then that previous interface is embedded into the current interface.
	--
	-- If a behavior is a nil value rather than a string, then this makes the
	-- interface "nullable", effectively causing nil to implement the interface.
	-- This behavior is inherited from embedded interfaces.
	function Interface(interface, ...)
		if declaredInterfaces[interface] then
			return
		end
		if type(interface) ~= "string" then
			return
		end
		local embedded = {}
		local behaviors = {}
		local notnull = true
		local args = {...}
		for i = 1, select("#", ...) do
			local behavior = args[i]
			if type(behavior) == "string" then
				local subEmbedded = embeddedInterfaces[behavior]
				if subEmbedded then
					embedded[behavior] = true
					for embed in pairs(subEmbedded) do
						embedded[embed] = true
					end
					if nillableInterfaces[behavior] and notnull then
						notnull = false
						nillableInterfaces[interface] = true
					end
					behaviors[#behaviors+1] = behavior .. " <embedded>"
				else
					behaviors[#behaviors+1] = behavior
				end
			elseif behavior == nil and notnull then
				notnull = false
				nillableInterfaces[interface] = true
				behaviors[#behaviors+1] = "<nullable>"
			end
		end
		declaredInterfaces[interface] = behaviors
		embeddedInterfaces[interface] = embedded
		return
	end

	-- formatInterfaces formats the interfaces in set `is` as a string.
	local function formatInterfaces(is)
		local list = {}
		for I in pairs(is) do
			list[#list+1] = I
		end
		table.sort(list)
		for i = 1, #list do
			local I = list[i]
			local behaviors = declaredInterfaces[I]
			if behaviors then
				local s = {I .. " {"}
				for i = 1, #behaviors do
					s[#s+1] = "\t" .. behaviors[i]
				end
				s[#s+1] = "}"
				list[i] = table.concat(s, "\n")
			else
				list[i] = I .. " <undeclared>"
			end
		end
		return table.concat(list, "\n")
	end

	-- Describe returns a description of the interfaces that the given value
	-- implements. If no value is given, then Describe returns a description of
	-- all declared interfaces. For humans only.
	local function Describe(...)
		if select("#", ...) == 0 then
			return formatInterfaces(declaredInterfaces)
		end
		local is = implementedInterfaces[...]
		if not is then
			return ""
		end
		return formatInterfaces(is)
	end
--#if EnableBridge then
	Bridge.Describe = Describe
--#end
end
Core.Impl = Impl
Core.Is = Is
Core.Interface = Interface

----------------------------------------------------------------
----------------------------------------------------------------
-- Type assertion functions

-- IsType returns whether an arbitrary value is of the given primitive Lua type.
local function IsType(value, t)
	return type(value) == t
end
Core.IsType = IsType

-- IsTypeOf returns whether an arbitrary value is of the given Roblox type.
local function IsTypeOf(value, t)
	return typeof(value) == t
end
Core.IsTypeOf = IsTypeOf

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

-- IsInt returns whether an arbitrary value is an integer.
local function IsInt(value)
	return type(value) == "number" and value == math.modf(value)
end
Core.IsInt = IsInt

----------------------------------------------------------------
----------------------------------------------------------------
-- Declare primitive interfaces.

-- nullable causes an interface to be implemented by nil values when embedded.
Interface("nullable", nil)

-- stringer is implemented by any value that has a __tostring metamethod which
-- returns a string representation of the value.
Interface("stringer",
	"__tostring() string"
)

-- error is the interface used to represent error conditions. error embeds the
-- stringer interface for compatibility with Roblox's error system, which only
-- allows strings.
Interface("error",
	"Error() string",
	"stringer",
	"nullable"
)

-- version is used to contain version information with the following fields:
--
-- - Major: Incremented when an incompatible API change is made.
-- - Minor: Incremented when a backwards compatible change is made.
-- - Patch: Incremented when a backwards compatible fix is made.
--
-- Major is the most significant field, followed by Minor, then Patch. When
-- incrementing a more significant field, the less significant fields are reset
-- to 0.
Interface("version",
	"Major int",
	"Minor int",
	"Patch int"
)

-- A module is a convention for containing exported identifiers returned by a
-- required ModuleScript. In addition, it contains name and version information,
-- which can be retrieved with NameOf and VersionOf, respectively.
Interface("module",
	"_name string",
	"_version version"
)

----------------------------------------------------------------
----------------------------------------------------------------
-- Essential utilities

-- LockMetatable prevents a given metatable from being retrieved with
-- getmetatable; instead, a standard message is returned. Returns the given
-- value. If no value is given, then a new table is created.
local function LockMetatable(...)
	local metatable = ...
	if select("#", ...) == 0 then
		metatable = {}
	end
	if type(metatable) == "table" then
		metatable.__metatable = "The metatable is locked."
	end
	return metatable
end
Core.LockMetatable = LockMetatable

-- Pack returns the received arguments packed into a table, as well as the
-- number of arguments.
local function Pack(...)
	return {...}, select("#", ...)
end
Core.Pack = Pack

----------------------------------------------------------------
----------------------------------------------------------------
-- Version type

local mtVersion = LockMetatable()
local ixVersion = {Major = 1, Minor = 2, Patch = 3}
function mtVersion:__index(k)
	return self[ixVersion[k]]
end
function mtVersion.__eq(v, w)
	for i = 1, 3 do
		if v[i] ~= w[i] then
			return false
		end
	end
	return true
end
function mtVersion.__lt(v, w)
	for i = 1, 3 do
		if v[i] < w[i] then
			return true
		elseif v[i] > w[i] then
			return false
		end
	end
	return false
end
function mtVersion.__le(v, w)
	for i = 1, 3 do
		if v[i] < w[i] then
			return true
		elseif v[i] > w[i] then
			return false
		end
	end
	return true
end
function mtVersion:__tostring()
	return self[1] .. "." .. self[2] .. "." .. self[3]
end

-- Version returns a version object that implements the version interface. Two
-- Versions can be compared with the comparison operators. When converted to a
-- string, a Version is formatted as "Major.Minor.Patch".
local function Version(major, minor, patch)
	major = math.modf(tonumber(major) or 0)
	minor = math.modf(tonumber(minor) or 0)
	patch = math.modf(tonumber(patch) or 0)
	local version = setmetatable({major, minor, patch}, mtVersion)
	return Impl(version, "version")
end
Core.Version = Version

----------------------------------------------------------------
----------------------------------------------------------------
-- Module type

-- Module creates a new table for exporting module identifiers. The first
-- argument is the canonical name of the module, and the remaining optional
-- arguments correspond to version fields, which set the module version.
--
-- If the first argument is a table which does not implement, then that table is
-- augmented into a module. The remaining arguments are the usual name and
-- version fields.
local function Module(table, name, ...)
	if type(table) == "table" and not Is(table) then
		table._name = tostring(name)
		table._version = Version(...)
		return Impl(table, "module")
	end
	local major = name
	name = table
	return Impl({
		_name = tostring(name),
		_version = Version(major, ...),
	}, "module")
end
Core.Module = Module

-- Convert Core table into module.
Core = Module(Core, "Core")

-- NameOf returns the name of the given module, or nil if the argument is not a
-- module.
local function NameOf(module)
	if Is(module, "module") then
		return module._name
	end
	return nil
end
Core.NameOf = NameOf

-- VersionOf returns the version of the given module, or nil if the argument is
-- not a module.
local function VersionOf(module)
	if Is(module, "module") then
		return module._version
	end
	return nil
end
Core.VersionOf = VersionOf

----------------------------------------------------------------
----------------------------------------------------------------
-- Basic error system

-- Error is implemented by errors produced by the Core module.
Interface("Core.Error",
	"error",
	-- Format string.
	"[1] string",
	-- Format arguments.
	"[...] any"
)

-- coreError is a basic wrapper that implements Error.
local coreError = {__index={}}
function coreError:__tostring()
	return string.format(unpack(self, 1, self.n))
end
coreError.__index.Error = coreError.__tostring

-- newError creates an error using ErrorHook, or from a basic default error
-- wrapper otherwise. The wrapper implements Error.
local function newError(type, ...)
	local hook = Core.ErrorHook
	if hook then
		return hook(type, ...)
	end
	local err, n = Pack(...)
	err.n = n
	err.type = type
	return Impl(setmetatable(err, coreError), "Core.Error")
end

-- ErrorHook is a callback function that transforms errors emitted by Core
-- functions. It is used to promote Core errors into a more complex error
-- system.
--
-- The arguments passed to ErrorHook are the error data, which are structured in
-- the following way: the first argument is a string indicating the type of
-- error, which can be used to infer the remaining arguments. The default
-- wrapper implements this as an interface. The second argument is a format
-- string, as would be passed to string.format. The remaining arguments are the
-- values to be formatted.
--
-- ErrorHook must return a value representing the error data.
--
-- If ErrorHook is nil, then an error is represented by a table containing the
-- error data, which will be formatted with string.format when converted to a
-- string.
Core.ErrorHook = nil

-- Panic receives an error value and throws it, ensuring that the value is
-- compatible with Roblox Lua's error handling.
local function Panic(err, level)
	error(tostring(err), (level or 1)+1)
end
Core.Panic = Panic

----------------------------------------------------------------
----------------------------------------------------------------
-- Basic logging system

-- Level indicates the severity of a log event.
local lvlError   = 0 -- A fatal error.
local lvlWarning = 1 -- Noteworthy but non-fatal.
local lvlInfo    = 2 -- Informational.

-- log logs an event to LogHook, or otherwise queues the event and behaves
-- according to the given severity level.
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

		if level == lvlInfo then
			print(...)
		elseif level == lvlWarning then
			warn(...)
		elseif level == lvlError then
			local err, stack = ...
			Panic(err, stack+1)
		end
	end

	-- DrainLogs empties the queue of events logged while LogHook is unset, and
	-- returns the results as an array of events.
	--
	-- Each event is an array containing the event content. The `n` field is the
	-- length of the array, the `level` field indicates the severity of the
	-- event, and the timestamp field indicates when the event was logged.
	local function DrainLogs()
		local q = queue
		queue = {}
		return q
	end
	Core.DrainLogs = DrainLogs
--#if EnableBridge then
	Bridge.DrainLogs = DrainLogs
--#end
end

-- LogHook is a callback function that receives logging events emitted by the
-- Core module. It is used to promote Core logging into a more complex logging
-- system.
--
-- The first argument is an integer indicating the severity level of the event.
-- The second argument is a timestamp marking when the event was logged
-- (relative to elapsedTime epoch). The remaining arguments are the content of
-- the event.
--
-- The severity level determines the content, and how the event is handled by
-- default when LogHook is nil:
--
-- - 0: Error; error(value, level); first argument is a value representing the
--   error, second is a stack level.
-- - 1: Warning; warn(...); arbitrary values to be concatenated as strings.
-- - 2: Info; print(...); arbitrary values to be concatenated as strings.
--
-- While LogHook is nil, events will be added to a queue, which can be retrieved
-- with DrainLogs.
--
-- If LogHook returns true, then the default behavior is used, but the event is
-- not queued.
Core.LogHook = nil

----------------------------------------------------------------
----------------------------------------------------------------
-- Require system

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
				return nil, newError("Core.PathTableError",
					"index %d: string expected, got %s",
					i,
					type(v)
				)
			end
			t[i] = v
		end
	elseif type(path) == "string" then
		for element in string.gmatch(path, "[^%.]+") do
			t[#t+1] = element
		end
	else
		return nil, newError("Core.PathError",
			"table or string expected, got %s",
			type(path)
		)
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
				return newError("Core.RequireError",
					"cyclic dependency detected at module %s",
					module:GetFullName()
				)
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
	-- never be garbage collected. This also occurs with Roblox's internal
	-- module value cache. To resolve, Roblox must backport Lua 5.2's ephemeron
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
	local function GetBlockingModules(duration)
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
--#if EnableBridge then
	Bridge.GetBlockingModules = GetBlockingModules
--#end
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
		log(lvlError, err, 2)
		return nil, err
	end

	pushModuleStack(path)
	if module == nil then
		local target = Manifest[path.string]
		if not target then
			log(lvlWarning, string.format(
				"attempting to require untracked module %s",
				path.string
			))
			module = resolvePath(path)
		else
			module = resolvePath(target, path)
		end
	end
	local result, err = requireModuleScript(module)
	popModuleStack(path)

	if err ~= nil then
		log(lvlError, err, 2)
		return nil, err
	end
	return result, nil
end

--#if EnableBridge then
----------------------------------------------------------------
----------------------------------------------------------------
-- Bridge system
--
-- Create a BindableFunction under ServerStorage for bridging across security
-- identities. The name is formatted as CoreBridge[ID], where ID is the security
-- identity of the corresponding module thread.
--
-- The bindable can be invoked by passing the name of a function in the Core
-- module, followed by the arguments to be passed to the function.
--
-- Must be used only for debugging.
do
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
		function bindable.OnInvoke(name, ...)
			local func = Bridge[name]
			if func then
				return func(...)
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
