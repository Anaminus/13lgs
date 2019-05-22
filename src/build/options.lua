local defaults = {
	debug      = {"boolean"    , false},
	help       = {"boolean"    , false},
	mainserver = {"string"     , nil},
	mainclient = {"string"     , nil},
	modules    = {"dictionary" , {}},
	target     = {"string"     , nil},

	define = {"dictionary", {
		EnableBridge = false,
	}},
	mappings = {"array", {
		{
			source = "$sd/../scripts/core",
			target = "ReplicatedFirst.Core",
			extension = ".lua",
			excluded = false,
			shared = true,
		},
		{
			source = "$sd/../scripts/server",
			target = "ServerScriptService.Modules",
			excluded = true,
			shared = false,
		},
		{
			source = "$sd/../scripts/shared",
			target = "ReplicatedStorage.Modules",
			excluded = true,
			shared = true,
		},
	}},
}

-- Get build options.
local options = ...
if type(options) == "string" then
	-- Load options from file.
	options = rbxmk.load{...}
end
if type(options) ~= "table" then
	error("expected options table")
end

local handle = {
	array = function(key, default)
		local t = {}
		for _, v in ipairs(default) do
			table.insert(t, v)
		end
		if type(options[key]) == "table" then
			for _, v in ipairs(options[key]) do
				table.insert(t, v)
			end
		end
		options[key] = t
	end,
	dictionary = function(key, default)
		local t = {}
		for k, v in pairs(default) do
			t[k] = v
		end
		if type(options[key]) == "table" then
			for k, v in pairs(options[key]) do
				t[k] = v
			end
		end
		options[key] = t
	end,
}

-- Merge default options.
for name, default in pairs(defaults) do
	local typ = default[1]
	local value = default[2]
	if handle[typ] then
		handle[typ](name, value)
	elseif type(options[name]) ~= typ then
		options[name] = value
	end
end

return options
