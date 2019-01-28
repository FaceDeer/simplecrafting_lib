local modpath = minetest.get_modpath(minetest.get_current_modname())

local OptionParser = dofile(modpath .. "/saveload/optparse.lua")
local orderedPairs = dofile(modpath .. "/saveload/orderedpairs.lua")
local parse_graphml_recipes = dofile(modpath .. "/saveload/readrecipegraph.lua")
local write_graphml_recipes = dofile(modpath .. "/saveload/writerecipegraph.lua")

-- Writing recipe dump to a .lua file
---------------------------------------------------------------------------------

-- Writes a single recipe to a table in the output file
local write_recipe = function(file, recipe)
	file:write("\t{\n")
	for key, val in orderedPairs(recipe) do
		file:write("\t\t"..key.." = ")
		if key == "output" then
			file:write("\t\"" .. ItemStack(val):to_string() .."\",\n")
		elseif type(val) == "table" then
			file:write("\t{")
			for kk, vv in orderedPairs(val) do
				if type(vv) == "string" then
					file:write("[\"" .. kk .. "\"] = \"" .. tostring(vv) .. "\", ")
				else
					file:write("[\"" .. kk .. "\"] = " .. tostring(vv) .. ", ")
				end
			end
			file:write("},\n")
		elseif type(val) == "string" then
			file:write("\t\"" .. tostring(val) .. "\",\n")
		else
			file:write("\t" .. tostring(val) .. ",\n")
		end			
	end
	file:write("\t},\n")
end

-- Dumps all recipes from the existing crafting system into a file that can be used to recreate them.
local save_recipes = function(param)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end
	
	file:write("return {\n")
	for craft_type, recipe_list in orderedPairs(simplecrafting_lib.type) do	
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
		for out, recipe_list in orderedPairs(recipe_list.recipes_by_out) do
			file:write("-- Output: " .. out .. "\n")
			for _, recipe in ipairs(recipe_list) do
				write_recipe(file, recipe)
			end
		end
		file:write("},\n")
	end
	file:write("}\n")

	file:flush()
	file:close()
	return true
end

-------------------------------------------------------------------------------------------

local save_recipes_graphml = function(name, craft_types)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end

	if not craft_types or table.getn(craft_types) == 0 then
		write_graphml_recipes(file, simplecrafting_lib.type)
	else
		local recipes = {}
		for _, craft_type in pairs(craft_types) do
			recipes[craft_type] = simplecrafting_lib.type[craft_type]
		end
		write_graphml_recipes(file, recipes)	
	end

	return true
end

local read_recipes_graphml = function(name)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"

	local file, err = io.open(filename, "r")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	local myxml = file:read('*all')
	local parse_error
	myxml, parse_error = parse_graphml_recipes(myxml)
	if parse_error then
		minetest.log("error", "Failed to parse graphml " .. filename .. " with error: " .. parse_error)
		return false
	end		
		
	return myxml
end

-------------------------------------------------------------

-- registers all recipes in the provided filename, which is usually a file generated by save_recipes and then perhaps modified by the developer.
local load_recipes = function(param)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()	
	
	for crafting_type, recipes in pairs(new_recipes) do
		for _, recipe in pairs(recipes) do
			simplecrafting_lib.register(crafting_type, recipe)
		end	
	end	
	return true
end

-- What the function name says it does
local get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list = function(first_recipe_list, second_recipe_list)
	if first_recipe_list == nil then
		return nil
	elseif second_recipe_list == nil then
		return first_recipe_list
	end
	
	local returns

	for _, first_recipe in pairs(first_recipe_list) do
		local found = false
		for _, second_recipe in pairs(second_recipe_list) do
			if simplecrafting_lib.recipe_equals(first_recipe, second_recipe) then
				found = true
				break
			end
		end
		if found ~= true then
			returns = returns or {}
			table.insert(returns, first_recipe)
		end
	end
	
	return returns
end

-- Used in diff_recipes for writing lists of recipes
local write_recipe_lists = function(file, recipe_lists)
	for craft_type, recipe_list in orderedPairs(recipe_lists) do	
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
		for _, recipe in ipairs(recipe_list) do
			write_recipe(file, recipe)
		end
		file:write("},\n")
	end
end

-- compares the recipes in the infile (of the form written by save_recipes) to the recipes in the existing crafting system, and outputs differences to outfile
local diff_recipes = function(infile, outfile)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. infile .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()
	
	local new_only_recipes = {}
	local existing_only_recipes = {}
	
	for craft_type, recipe_lists in pairs(simplecrafting_lib.type) do
		if new_recipes[craft_type] ~= nil then
			new_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(new_recipes[craft_type], recipe_lists.recipes)
		else
			existing_only_recipes[craft_type] = recipe_lists.recipes
		end
	end
	for craft_type, recipe_lists in pairs(new_recipes) do
		local existing_recipes = simplecrafting_lib.type[craft_type]
		if existing_recipes ~= nil then
			existing_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(existing_recipes.recipes, recipe_lists)
		else
			new_only_recipes[craft_type] = recipe_lists
		end
	end
	
	filename = path .. "/" .. outfile .. ".txt"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipe diffs to \"" .. filename .. "\"")
		return false
	end
		
	file:write("-- Recipes found only in the external file:\n--------------------------------------------------------\n")
	write_recipe_lists(file, new_only_recipes)
	file:write("\n")

	file:write("-- Recipes found only in the existing crafting database:\n--------------------------------------------------------\n")
	write_recipe_lists(file, existing_only_recipes)
	file:write("\n")
	
	file:flush()
	file:close()
	
	return true
end

---------------------------------------------------------------

function split(inputstr, seperator)
	if inputstr == nil then return {} end
	if seperator == nil then
		seperator = "%s"
	end
	local out={}
	local i=1
	for substring in string.gmatch(inputstr, "([^"..seperator.."]+)") do
		out[i] = substring
		i = i + 1
	end
	return out
end

local saveoptparse = OptionParser{usage="[options] file"}
saveoptparse.add_option{"-h", "--help", action="store_true", dest="help", help = "displays help text"}
saveoptparse.add_option{"-l", "--lua", action="store_true", dest="lua", help="saves recipes as \"(world folder)/<file>.lua\""}
saveoptparse.add_option{"-g", "--graphml", action="store_true", dest="graphml", help="saves recipes as \"(world folder)/<file>.graphml\""}
saveoptparse.add_option{"-t", "--type", action="store", dest="type", help="craft_type to save. Leave unset to save all. Use a comma-delimited list (eg, \"table,furnace\") to save multiple specific craft types"}

minetest.register_chatcommand("recipesave", {
	params = saveoptparse.print_help(),
	description = "Saves recipes to external files",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
	
		local success, options, args = saveoptparse.parse_args(param)
		if not success then
			minetest.chat_send_player(name, options)
			return
		end
		
		if options.help then
			minetest.chat_send_player(name, saveoptparse.print_help())
			return
		end
		
		if table.getn(args) ~= 1 then
			minetest.chat_send_player(name, "A filename argument is needed.")
			return
		end

		if not (options.lua or options.graphml) then
			minetest.chat_send_player(name, "Neither lua nor graphml output was selected, defaulting to lua")
			options.lua = true
		end
		
		local craft_types = split(options.type, ",")
		if options.lua then
			if save_recipes(args[1], craft_types) then
				minetest.chat_send_player(name, "Lua recipes saved", false)
			else
				minetest.chat_send_player(name, "Failed to save lua recipes", false)
			end
		end
		
		if options.graphml then
			if save_recipes_graphml(args[1], craft_types) then
				minetest.chat_send_player(name, "Graphml recipes saved", false)
			else
				minetest.chat_send_player(name, "Failed to save graphml recipes", false)
			end
		end
	end,
})

minetest.register_chatcommand("loadrecipesgraph", {
	params = "<file>",
	description = "Read the current recipes from \"(world folder)/<file>.graphml\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		local read_recipes = read_recipes_graphml(param)		
		if read_recipes then
			for _, recipe in pairs(read_recipes) do
				local craft_type = recipe.craft_type
				recipe.craft_type = nil				
				simplecrafting_lib.register(craft_type, recipe)				
			end
		
			minetest.chat_send_player(name, "Recipes read", false)
		else
			minetest.chat_send_player(name, "Failed to read recipes", false)
		end
	end,
})

minetest.register_chatcommand("clearrecipes", {
	params = "",
	description = "Clear all recipes from simplecrafting_lib",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		simplecrafting_lib.type = {}
		minetest.chat_send_player(name, "Recipes cleared", false)
	end,
})

minetest.register_chatcommand("loadrecipes", {
	params="<file>",
	description="Clear recipes and load replacements from \"(world folder)/<file>.lua\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end

		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		if load_recipes(param) then		
			minetest.chat_send_player(name, "Recipes loaded", false)
		else
			minetest.chat_send_player(name, "Failed to load recipes", false)
		end
	end,
})

minetest.register_chatcommand("diffrecipes", {
	params="<infile> <outfile>",
	description="Compares existing recipe data to the data in \"(world folder)/<infile>.lua\", outputting the differences to \"(world folder)/<outfile>.txt\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end

		local params = split(param)
		if #params ~= 2 then
			minetest.chat_send_player(name, "Invalid usage, two filename parameters separted by a space are needed", false)
			return
		end
		
		if diff_recipes(params[1], params[2]) then
			minetest.chat_send_player(name, "Recipes diffed", false)
		else
			minetest.chat_send_player(name, "Failed to diff recipes", false)
		end
	end,
})