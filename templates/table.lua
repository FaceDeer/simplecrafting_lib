local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local modpath_default = minetest.get_modpath("default")

-- table_def can have the following:
--{
--	show_guides = true or false,
--	alphabetize_items = true or false,
--	description = string,
--	hopper_node_name = string,
--	enable_pipeworks = true or false,
--	append_to_formspec = string,
--	protect_inventory = true or false,
--}

simplecrafting_lib.generate_table_functions = function(craft_type, table_def)

if table_def == nil then
	table_def = {}
end

local output_width = 8
local output_height = 6
local output_count = output_width * output_height

-- Hopper compatibility
if table_def.hopper_node_name and minetest.get_modpath("hopper") and hopper ~= nil and hopper.add_container ~= nil then
	hopper:add_container({
		{"top", table_def.hopper_node_name, "input"},
		{"bottom", table_def.hopper_node_name, "input"},
		{"side", table_def.hopper_node_name, "input"},
	})
end

local function make_formspec(pos, meta, inv)

	local row = meta:get_int("row")
	local item_count = inv:get_size("output")
	local max_mode = meta:get_string("max_mode") == "True"
	local pos_string = pos.x .. "," .. pos.y .. "," ..pos.z

	local inventory = {
		"size[10.2,10.2]",
		"list[nodemeta:"..pos_string..";input;0,0.5;2,5;]",
		"list[nodemeta:"..pos_string..";output;2.2,0;"..output_width..","..output_height..";" , tostring(row*output_width), "]",
		"list[current_player;main;1.1,6.25;8,1;]",
		"list[current_player;main;1.1,7.5;8,3;8]",
		"listring[nodemeta:"..pos_string..";output]",
		"listring[current_player;main]",
		"listring[nodemeta:"..pos_string..";input]",
		"listring[current_player;main]",
	}

	if table_def.description then
		inventory[#inventory+1] = "label[0,0;"..table_def.description.."]"
	end

	if modpath_default then
		inventory[#inventory+1] = default.gui_bg
		inventory[#inventory+1] = default.gui_bg_img
		inventory[#inventory+1] = default.gui_slots
	end

	local pages = false
	local page_button_y = "7.3"
	if item_count > ((row/output_height)+1) * output_count then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;next;»]"
		inventory[#inventory+1] = "tooltip[next;"..S("Next page of crafting products").."]"
		page_button_y = "8.0"
		pages = true
	end
	if row >= output_height then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;prev;«]"
		inventory[#inventory+1] = "tooltip[prev;"..S("Previous page of crafting products").."]"
		pages = true
	end
	if pages then
		inventory[#inventory+1] = "label[9.3,6.5;" .. S("Page @1", tostring(row/output_height+1)) .. "]"
	end

	if max_mode then
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Max\nOutput").."]"
	else
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Min\nOutput").."]"
	end

	if table_def.show_guides then
		inventory[#inventory+1] = "button[9.3,9.7;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end

	if table_def.append_to_formspec then
		inventory[#inventory+1] = table_def.append_to_formspec
	end

	return table.concat(inventory), row
end

local function refresh_output(inv, max_mode)
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list("input"), max_mode, table_def.alphabetize_items)
	inv:set_size("output", #craftable + (output_count - (#craftable%output_count)))
	inv:set_list("output", craftable)
end

local function refresh_inv(pos, meta)
	local inv = meta:get_inventory()
	local max_mode = meta:get_string("max_mode")
	refresh_output(inv, max_mode == "True")

	local row = meta:get_int("row")
	local item_count = inv:get_size("output")
	if item_count < output_count then
		meta:set_int("row", 0)
	elseif (row*output_width)+output_count > item_count then
		meta:set_int("row", (item_count - output_count) / output_width)
	end
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("input", 2*5)
	inv:set_size("output", output_count)
	meta:set_int("row", 0)
end

local allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
	if to_list == "output" then
		return 0
	end
	if table_def.protect_inventory and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if to_list == "input" then
		if from_list == "input" then
			return number
		end
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local stack = inv:get_stack(from_list, from_index)
		if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
			return number
		end
	end
	return 0
end

local _pipeworks_override_player = {} -- Horrible hack. Pipeworks gets to insert stuff regardless of protection.

local allow_metadata_inventory_put = function(pos, list_name, index, stack, player)
	if table_def.protect_inventory and
		player ~= _pipeworks_override_player and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if list_name == "output" then
		return 0
	end
	if list_name == "input" and simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
		return stack:get_count()
	end
	return 0
end

-- Pipeworks compatibility
local tube = nil
if table_def.enable_pipeworks and minetest.get_modpath("pipeworks") then
	tube = {
		insert_object = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return inv:add_item("input", stack)
		end,
		can_insert = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return allow_metadata_inventory_put(pos, "input", 1, stack, _pipeworks_override_player) > 0 and inv:room_for_item("input", stack)
		end,
		input_inventory = "input",
		connect_sides = {left = 1, right = 1, back = 1, bottom = 1, top = 1}
	}
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local input_stack = inv:get_stack(listname,  index)
	local player_inv = player:get_inventory()
	if table_def.protect_inventory and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if not player_inv:room_for_item('main', input_stack) then
		return 0
	end
	return stack:get_count()
end

local on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
	local meta = minetest.get_meta(pos)
	if from_list == "output" and to_list == "input" then
		local inv = meta:get_inventory()
		local stack = inv:get_stack(to_list, to_index)
		stack:set_count(number)
		simplecrafting_lib.craft_stack(craft_type, stack, inv, "input", inv, to_list, player)
		if simplecrafting_lib.award_crafting then
			simplecrafting_lib.award_crafting(player, stack)
		end
	end
	refresh_inv(pos, meta)
end

local on_metadata_inventory_take = function(pos, list_name, index, stack, player)
	local meta = minetest.get_meta(pos)
	if list_name == "output" then
		local inv = meta:get_inventory()
		local input_stack = inv:get_stack(list_name, index)
		if not input_stack:is_empty() and input_stack:get_name()~=stack:get_name() then
			local player_inv = player:get_inventory()
			if player_inv:room_for_item("main", input_stack) then
				player_inv:add_item("main", input_stack)
			end
		end
		simplecrafting_lib.craft_stack(craft_type, stack, inv, "input", player:get_inventory(), "main", player)
		if modpath_awards then
			awards.increment_item_counter(awards.players[player:get_player_name()], "craft", ItemStack(stack):get_name(), ItemStack(stack):get_count())
		end
	end
	refresh_inv(pos, meta)
end

local on_metadata_inventory_put = function(pos, list_name, index, stack, player)
	local meta = minetest.get_meta(pos)
	refresh_inv(pos, meta)
end

local on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	minetest.show_formspec(clicker:get_player_name(),
		"simplecrafting_lib:table_"..craft_type..minetest.pos_to_string(pos),
		make_formspec(pos, meta, inv))
end

local can_dig = function(pos, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	return inv:is_empty("input")
end

local prefix_length = string.len("simplecrafting_lib:table_"..craft_type)
minetest.register_on_player_receive_fields(function(sender, formname, fields)
	if string.sub(formname, 1, prefix_length) ~= "simplecrafting_lib:table_"..craft_type then
		return false -- not a formspec we handle
	end

	local pos = minetest.string_to_pos(string.sub(formname, prefix_length+1))
	if pos == nil then return false end

	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local size = inv:get_size("output")
	local row = meta:get_int("row")

	if fields.next then
		minetest.sound_play("paperflip1", {to_player=sender:get_player_name(), gain = 1.0})
		row = row + output_height
		meta:set_int("row", row)

	elseif fields.prev  then
		minetest.sound_play("paperflip2", {to_player=sender:get_player_name(), gain = 1.0})
		row = row - output_height
		meta:set_int("row", row)

	elseif fields.max_mode then
		local max_mode = meta:get_string("max_mode")
		if max_mode == "" then
			max_mode = "True"
		else
			max_mode = ""
		end
		meta:set_string("max_mode", max_mode)
		refresh_output(inv, max_mode == "True")

	elseif fields.show_guide and table_def.show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, sender, function()
			minetest.after(0.1, function()
				minetest.show_formspec(sender:get_player_name(), formname, make_formspec(pos, meta, inv))
			end)
		end)
		return true
	elseif fields.quit then
		return true
	end

	minetest.show_formspec(sender:get_player_name(), formname, make_formspec(pos, meta, inv))
	return true
end)

return {
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	can_dig = can_dig,
	on_construct = on_construct,
	on_metadata_inventory_move = on_metadata_inventory_move,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
	on_rightclick = on_rightclick,
	tube = tube,
}
end
