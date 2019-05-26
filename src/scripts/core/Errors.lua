--[[ Errors

The Errors module provides functions for manipulating errors.

]]
--[[#Core]]

local Errors = Core.Module("Errors")

-- getStackFrame retrieves the first frame of a stack trace.
local function getStackFrame(level)
--#if not ErrorStackFrames or ErrorStackFrames == 0 then
	return nil
--#elseif ErrorStackFrames > 0 then
	local trace = debug.traceback(level+1)
	local frame = trace:match("^Stack begin\n(.*)\n")
	if not frame then
		-- Format will be changing, according to
		-- https://devforum.roblox.com/t/279676
		frame = trace:match("^(.*)\n")
	end
	return frame
	-- TODO: Retrieve number of frames according to ErrorStackFrames.
--#end
end

----------------------------------------------------------------
----------------------------------------------------------------
-- New error

local errorString = {__index={}}
function errorString.__index:Error()
	-- TODO: expose frame through custom formatter, to be specified in not yet
	-- implemented Fmt module.
	return self.string
end
errorString.__tostring = errorString.__index.Error

-- New returns an error that formats as the given string.
local function New(string)
	local err = setmetatable({
		string = string,
		frame = getStackFrame(2),
	}, errorString)
	return Core.Impl(err, "error")
end
Errors.New = New

----------------------------------------------------------------
----------------------------------------------------------------
-- Error wrapping

-- Wrapper is an error that is caused by another error. The outer error wraps
-- around the inner error. Because the cause of a Wrapper can also be a Wrapper,
-- a chain of errors can be formed.
Core.Interface("Errors.Wrapper",
	"error",
	"Cause error"
)

local errorWrapper = {__index={}}
function errorWrapper.__index:Error()
	local str = self.Cause:Error()
	if msg then
		return self.msg .. ": " .. str
	end
	return str
end
errorString.__tostring = errorString.__index.Error

-- Wrap returns an error that wrap around
local function Wrap(err, msg)
	return Impl(setmetatable({
		Cause = err,
		msg = msg,
		frame = getStackFrame(2),
	}, errorWrapper), "Errors.Wrapper")
end
Errors.Wrap = Wrap

-- Cause returns the result of calling getting the Cause field on err, if err is
-- a Wrapper. Returns nil otherwise.
local function Cause(err)
	if Core.Is(err, "Errors.Wrapper") then
		return err.Cause
	end
	return nil
end
Errors.Cause = Cause

----------------------------------------------------------------
----------------------------------------------------------------
-- Error chain traversal

-- RootCause recursively attempts to find the cause of an error until it reaches
-- a non-Wrapper, or nil.
local function RootCause(err)
	if not Core.Is(err, "error") then
		return nil
	end
	while err ~= nil do
		if not Core.Is(err, "Errors.Wrapper") then
			break
		end
		err = err.Cause
	end
	return err
end
Errors.RootCause = RootCause

Core.Interface("Errors.Iser",
	"error",
	"Is(error) bool"
)

-- Is traverses the causes of err recursively, and returns whether any of the
-- causes match target. An error matches a target if they are equal, or if the
-- error implements Iser and Is(target) returns true.
local function Is(err, target)
	if target == nil then
		return err == nil
	end
	while err ~= nil do
		if err == target then
			return true
		end
		if Core.Is("Errors.Iser") and err:Is(target) then
			return true
		end
		err = Cause(err)
	end
	return false
end
Errors.Is = Is

Core.Interface("Errors.Aser",
	"error",
	"As(target string) error"
)

-- As traverses the causes of err recursively, and returns the first error in
-- the chain that matches the target interface, or nil otherwise. An error
-- matches if the error implements the interface, or if it implements Aser such
-- that As(target) returns a non nil value.
local function As(err, target)
	if target == nil then
		return nil
	end
	while err ~= nil do
		if Core.Is(err, target) then
			return err
		end
		if Core.Is(err, "Errors.Aser") then
			local as = err:As(target)
			if as ~= nil then
				return as
			end
		end
		err = Cause(err)
	end
	return nil
end
Errors.As = As

----------------------------------------------------------------
----------------------------------------------------------------
-- ErrorHook

-- Implement Core.ErrorHook to promote core errors.
local coreError = {__index={}}
function coreError.__index:Error()
	local format = self.format
	if self.frame then
		format = self.frame .. ": " .. format
	end
	return string.format(format, unpack(self, 1, self.n))
end
coreError.__tostring = coreError.__index.Error

Core.Interface("Core.PathTableError",
	"Core.Error",
	"Index int",
	"Type string"
)

Core.Interface("Core.PathError",
	"Core.Error",
	"Type string"
)

Core.Interface("Core.RequireError",
	"Core.Error",
	"Module string"
)

function Core.ErrorHook(errType, format, ...)
	local err, n = Core.Pack(...)
	err.n = n
	err.format = format
	err.frame = getStackFrame(3)  -- ErrorHook<-newError<-caller
	if errType == "Core.PathTableError" then
		err.Index = err[2]
		err.Type = err[3]
	elseif errType == "Core.PathError" then
		err.Type = err[2]
	elseif errType == "Core.RequireError" then
		err.Module = err[2]
	else
		errType = nil
	end
	return Core.Impl(setmetatable(err, coreError), errType)
end

----------------------------------------------------------------
----------------------------------------------------------------
-- Call safety

-- Call safely calls func with the remaining arguments. If func throws an error,
-- then the error is returned as a value that implements the error interface. If
-- no error is thrown, then nil is returned, followed by the values returned by
-- func.
--
-- Call should be used to wrap extraneous functions that throw errors, to make
-- them compatible with the error value system.
local function Call(func, ...)
	local results, n = Core.Pack(pcall(func, ...))
	if results[1] then
		return nil, unpack(results, 2, n)
	end
	local err = setmetatable({
		string = results[2],
		frame = getStackFrame(2),
	}, errorString)
	return Core.Impl(err, "error")
end
Errors.Call = Call

-- Method returns a function that wraps around a method call. When called, the
-- method is called safely with Call.
--
-- Method should be used to wrap extraneous methods that throw errors, to make
-- them compatible with the error value system.
local function Method(object, method)
	method = object[method]
	return function(...)
		return Call(method, object, ...)
	end
end
Errors.Method = Method

----------------------------------------------------------------
----------------------------------------------------------------

return Errors
