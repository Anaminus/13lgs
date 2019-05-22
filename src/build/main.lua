local options = rbxmk.load{rbxmk.path{"$sd/options.lua"}, ...}
rbxmk.load{rbxmk.path{"$sd/defines.lua"}, options}
if options.help then
	print(rbxmk.load{rbxmk.path{"$sd/help.lua"}})
	return
end

local targetPath = options.target
if type(targetPath) ~= "string" then
	error("options.target: string expected, got " .. type(targetPath))
end

----------------------------------------------------------------
----------------------------------------------------------------

-- Encode instance path table into a string.
local function encodePath(path)
	return table.concat(path, ".")
end

-- Decode an instance path string into a table.
local function newPath(path)
	local t = {}
	if type(path) == "table" then
		for i, v in ipairs(path) do
			if type(v) ~= "string" then
				return nil, string.format("index %d: string expected, got %s", i, type(v))
			end
			t[i] = v
		end
	elseif type(path) == "string" then
		-- TODO: make more robust.
		for element in string.gmatch(path, "[^%.]+") do
			t[#t+1] = element
		end
	else
		return nil, "table or string expected, got " .. type(path)
	end
	t.string = encodePath(t)
	return t, nil
end

-- Compare instance path tables.
local function comparePaths(a, b)
	if #a ~= #b then
		return false
	end
	for i, v in ipairs(a) do
		if b[i] ~= v then
			return false
		end
	end
	return true
end

-- Load a script from a file and run the preprocessor on it.
local function processScript(format, name, ...)
	local script = rbxmk.input{format=format, rbxmk.path{...}}
	if name then
		rbxmk.map{
			rbxmk.output{script, "Name"},
			rbxmk.input{"generate://Value", string.format('string="%s"', name)},
		}
	end
	local ok, script = pcall(rbxmk.filter, {"preprocess", script})
	if not ok then
		return nil, script
	end
	return script, nil
end

-- Generate a Folder instance of the given name.
local function createFolder(name)
	return rbxmk.input{"generate://Instance", string.format('Folder{Name:string="%s"}', name)}
end

-- Validate and add map to mappings table.
local function addMapping(mappings, map)
	if type(map) ~= "table" then
		return "table expected, got " .. type(map)
	end

	local source = map.source
	if type(source) ~= "string" then
		return "field 'source': string expected, got " .. type(source)
	end

	local target, err = newPath(map.target)
	if err then
		return "field 'target': " .. err
	end

	local extension = map.extension
	if extension ~= nil and type(extension) ~= "string" then
		return "field 'extension': string expected, got " .. type(extension)
	end

	local excluded = map.excluded
	if excluded ~= nil and type(excluded) ~= "boolean" then
		return "field 'excluded': boolean expected, got " .. type(excluded)
	end

	local shared = map.shared
	if shared ~= nil and type(shared) ~= "boolean" then
		return "field 'shared': boolean expected, got " .. type(shared)
	end

	table.insert(mappings, {
		source = rbxmk.path{source},
		target = target,
		extension = extension or ".modulescript.lua",
		excluded = excluded or false,
		shared = shared or false,
	})

	return nil
end

-- Retrieve modules from mapping.
local function resolveMapping(map, priority)
	local sourcePath = rbxmk.path{map.source}
	local ok, files = pcall(rbxmk.readdir, {sourcePath})
	if not ok then
		return files
	end

	local modules = {}
	local function findModules(name, files)
		for _, info in ipairs(files) do
			if info.isdir then
				table.insert(name, info.name)
				local ok, subfiles = pcall(rbxmk.readdir, {rbxmk.path{sourcePath, unpack(name)}})
				if ok then
					findModules(name, subfiles)
				end
				table.remove(name)
			elseif rbxmk.filename{info.name, "fext"} == map.extension then
				table.insert(name, info.name)
				local modulePath = rbxmk.path{unpack(name)}
				table.remove(name)

				table.insert(name, rbxmk.filename{info.name, "fstem"})
				table.insert(modules, {
					source = map.source,
					path = modulePath,
					name = newPath(name),
					target = map.target,
					priority = priority,
					excluded = map.excluded,
					shared = map.shared,
				})
				table.remove(name)
			end
		end
	end
	findModules({}, files)
	map.modules = modules
end

-- Add module to list only if it is uniquely named.
local function insertModule(modules, module)
	if module.untracked then
		table.insert(modules, module)
		return nil
	end
	for _, prev in ipairs(modules) do
		if comparePaths(prev.name, module.name) then
			return prev
		end
	end
	table.insert(modules, module)
	return nil
end

-- Write module to an output.
local function writeModule(input, output, module)
	if module.excluded then
		return nil
	end

	-- Ensure path exists.
	local slice = {}
	for _, name in ipairs(module.target) do
		table.insert(slice, name)
		local ok = pcall(rbxmk.input, {input, encodePath(slice)})
		if not ok then
			table.remove(slice)
			if #slice == 0 then
				-- Add to root.
				rbxmk.map{output, createFolder(name)}
			else
				-- Add to descendant.
				rbxmk.map{
					rbxmk.output{input, encodePath(slice)},
					createFolder(name),
				}
			end
			table.insert(slice, name)
		end
	end

	-- Write module.
	local script, err = processScript(
		"modulescript.lua",
		module.name[#module.name],
		module.source, module.path
	)
	if err ~= nil then
		error(module.name.string .. ": " .. err)
	end
	rbxmk.map{
		rbxmk.output{output, module.target.string},
		script,
	}
end

----------------------------------------------------------------
----------------------------------------------------------------

-- Add mappings.
local Mappings = {}
for i, map in ipairs(options.mappings) do
	local err = addMapping(Mappings, map)
	if err ~= nil then
		error(string.format("options.mappings[%d]: %s", i, err))
	end
end

-- Resolve mappings.
for i, map in ipairs(Mappings) do
	local err = resolveMapping(map, i)
	if err ~= nil then
		error(string.format("mappings[%d]: %s", i, err))
	end
end

-- Merge modules.
local Modules = {}
if options.mainserver then
	local path = rbxmk.path{options.mainserver}
	insertModule(Modules, {
		source = rbxmk.filename{path, "dir"},
		path = rbxmk.filename{path, "base"},
		name = newPath("Main"),
		target = newPath("ServerScriptService"),
		priority = 0,
		untracked = true,
	})
end
if options.mainclient then
	local path = rbxmk.path{options.mainclient}
	insertModule(Modules, {
		source = rbxmk.filename{path, "dir"},
		path = rbxmk.filename{path, "base"},
		name = newPath("Main"),
		target = newPath("ReplicatedFirst"),
		priority = 0,
		untracked = true,
	})
end
for i, map in ipairs(Mappings) do
	for _, module in ipairs(map.modules) do
		local prev = insertModule(Modules, module)
		if prev then
			print(string.format("mappings[%d]: ignored %s, already defined in mappings[%d]", i, module.name.string, prev.priority))
		end
	end
end

-- Exclude modules.
for _, module in ipairs(Modules) do
	local include = options.modules[module.name.string]
	if include ~= nil then
		module.excluded = not include
	end
end

-- Sort by priority, then name.
table.sort(Modules, function(a, b)
	if a.priority == b.priority then
		return a.name.string < b.name.string
	end
	return a.priority < b.priority
end)

-- Generate module manifests.
local ModuleTargets  = {}
local SharedManifest = {}
local ServerManifest = {}
for _, module in ipairs(Modules) do
	if not module.untracked then
		if ModuleTargets[module.target.string] == nil then
			table.insert(ModuleTargets, string.format("%q", module.target.string))
			ModuleTargets[module.target.string] = #ModuleTargets
		end
	end
end
for _, module in ipairs(Modules) do
	if not module.untracked then
		local data = string.format("[%q]=%d", module.name.string, ModuleTargets[module.target.string])
		if module.shared then
			table.insert(SharedManifest, data)
		else
			table.insert(ServerManifest, data)
		end
	end
end
ModuleTargets  = "{" .. table.concat(ModuleTargets,  ",") .. "}"
SharedManifest = "{" .. table.concat(SharedManifest, ",") .. "}"
ServerManifest = "{" .. table.concat(ServerManifest, ",") .. "}"

----------------------------------------------------------------
----------------------------------------------------------------

-- Define variable for the preprocessor, causing `--[[#Core]]` to resolve to
-- code that loads the Core module.
rbxmk.configure{
	define = {
		Core = rbxmk.input{rbxmk.path{"$sd/loadcore.lua"}},
	},
}

-- Define variables specified in options.
rbxmk.configure{define = options.define}

-- Load clean-slate place file.
local targetInput = rbxmk.load{rbxmk.path{"$sd/template.lua"}}
-- Create an output to write directly to the target in-memory.
local targetOutput = rbxmk.output{targetInput}

-- Add Core module.
do
	local core = processScript("modulescript.lua", nil, "$sd/../scripts/Core.lua")
	core = rbxmk.filter{"region", core, "ModuleTargets", ModuleTargets}
	core = rbxmk.filter{"region", core, "ServerManifest", ServerManifest}
	core = rbxmk.filter{"region", core, "SharedManifest", SharedManifest}
	rbxmk.map{rbxmk.output{targetOutput, "ReplicatedFirst"}, core}
end

-- Add bootstrappers.
rbxmk.map{
	rbxmk.output{targetOutput, "ServerScriptService"},
	processScript("script.lua", "Bootstrap", "$sd/../scripts/BootstrapServer.lua"),
}
rbxmk.map{
	rbxmk.output{targetOutput, "ReplicatedFirst"},
	processScript("localscript.lua", "Bootstrap", "$sd/../scripts/BootstrapClient.lua"),
}

-- Add modules.
for _, module in ipairs(Modules) do
	local err = writeModule(targetInput, targetOutput, module)
	if err ~= nil then
		error(string.format("module %q: %s", module.name.string, err))
	end
end

-- Write to file.
rbxmk.delete{rbxmk.output{targetPath}}
rbxmk.map{targetInput, rbxmk.output{targetPath}}

if options.debug then
	print("Module    (priority : excluded : shared : source                                                           => target                          )")
	print("-----------------------------------------------------------------------------------------------------------------------------------------------")
	for _, module in pairs(Modules) do
		rbxmk.printf{"%-9s (%-8d : %-8s : %-6s : %-64s => %-32s)\n",
			module.name.string,
			module.priority,
			module.excluded,
			module.shared,
			rbxmk.path{module.source, module.path},
			module.target.string,
		}
	end
end
