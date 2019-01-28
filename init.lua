simplecrafting_lib = {}
simplecrafting_lib.type = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath .. "/util.lua")
dofile(modpath .. "/register.lua")
dofile(modpath .. "/craft.lua")
dofile(modpath .. "/inventory.lua")
dofile(modpath .. "/legacy.lua")

dofile(modpath .. "/templates/guide.lua")
dofile(modpath .. "/templates/table.lua")
dofile(modpath .. "/templates/multifurnace.lua")
dofile(modpath .. "/templates/autocraft.lua")

dofile(modpath .. "/postprocessing.lua")

if minetest.settings:get_bool("simplecrafting_lib_enable_developer_commands") then
	dofile(modpath .. "/saveload/saveload.lua")
end