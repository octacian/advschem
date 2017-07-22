-- advschem/init.lua

advschem = {}

local contexts   = {}
advschem.markers = {}

---
--- Formspec API
---

local contexts = {}
local tabs = {}
local forms = {}

-- [function] Add form
function advschem.add_form(name, def)
	def.name = name
	forms[name] = def

	if def.tab then
		tabs[#tabs + 1] = name
	end
end

-- [function] Generate tabs
function advschem.generate_tabs(current)
	local retval = "tabheader[0,0;tabs;"
	for _, t in pairs(tabs) do
		local f = forms[t]
		if f.tab ~= false and f.caption then
			retval = retval..f.caption..","

			if type(current) ~= "number" and current == f.name then
				current = _
			end
		end
	end
	retval = retval:sub(1, -2) -- Strip last comma
	retval = retval..";"..current.."]" -- Close tabheader
	return retval
end

-- [function] Handle tabs
function advschem.handle_tabs(pos, name, fields)
	local tab = tonumber(fields.tabs)
	if tab and tabs[tab] and forms[tabs[tab]] then
		advschem.show_formspec(pos, name, forms[tabs[tab]].name)
		return true
	end
end

-- [function] Show formspec
function advschem.show_formspec(pos, player, tab, show, ...)
	if forms[tab] then
		if type(player) == "string" then
			player = minetest.get_player_by_name(player)
		end
		local name = player:get_player_name()

		if show ~= false then
			local form = forms[tab].get(pos, name, ...)
			if forms[tab].tab then
				form = form..advschem.generate_tabs(tab)
			end

			minetest.show_formspec(name, "advschem:"..tab, form)
			contexts[name] = pos

			-- Update player attribute
			if forms[tab].cache_name ~= false then
				player:set_attribute("advschem:tab", tab)
			end
		else
			minetest.close_formspec(pname, "advschem:"..tab)
		end
	end
end

-- [event] On receive fields
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local formname = formname:split(":")

	if formname[1] == "advschem" and forms[formname[2]] then
		local handle = forms[formname[2]].handle
		local name = player:get_player_name()
		if contexts[name] then
			if not advschem.handle_tabs(contexts[name], name, fields) and handle then
				handle(contexts[name], name, fields)
			end
		end
	end
end)

---
--- Formspec Tabs
---

advschem.add_form("main", {
	tab = true,
	caption = "Main",
	get = function(pos, name)
		local meta = minetest.get_meta(pos):to_table().fields
		local strpos = minetest.pos_to_string(pos)

		local border_button
		if meta.schem_border == "true" and advschem.markers[strpos] then
			border_button = "button[3.5,7.5;3,1;border;Hide Border]"
		else
			border_button = "button[3.5,7.5;3,1;border;Show Border]"
		end

		-- TODO: Show information regarding volume, pos1, pos2, etc... in formspec
		return [[
			size[7,8]
			label[0.5,-0.1;Position: ]]..strpos..[[]
			label[3,-0.1;Owner: ]]..name..[[]

			field[0.8,1;5,1;name;Schematic Name:;]]..(meta.schem_name or "")..[[]
			button[5.3,0.69;1.2,1;save_name;Save]
			tooltip[save_name;Save schematic name]
			field_close_on_enter[name;false]

			button[0.5,1.5;6,1;export;Export Schematic]
			label[0.5,2.2;Schematic will be exported as a .mts file and stored in]
			label[0.5,2.45;<minetest dir>/worlds/<worldname>/schems/<name>.mts]

			field[0.8,7;2,1;x;X-Size:;]]..meta.x_size..[[]
			field[2.8,7;2,1;y;Y-Size:;]]..meta.y_size..[[]
			field[4.8,7;2,1;z;Z-Size:;]]..meta.z_size..[[]
			field_close_on_enter[x;false]
			field_close_on_enter[y;false]
			field_close_on_enter[z;false]

			button[0.5,7.5;3,1;save;Save Size]
		]]..
		border_button
	end,
	handle = function(pos, name, fields)
		local realmeta = minetest.get_meta(pos)
		local meta = realmeta:to_table().fields
		local strpos = minetest.pos_to_string(pos)

		-- Toggle border
		if fields.border then
			if meta.schem_border == "true" and advschem.markers[strpos] then
				advschem.unmark(pos)
				meta.schem_border = "false"
			else
				advschem.mark(pos)
				meta.schem_border = "true"
			end
		end

		-- Save size vector values
		if (fields.save or fields.key_enter_field == "x" or
				fields.key_enter_field == "y" or fields.key_enter_field == "z")
				and (fields.x and fields.y and fields.z and fields.x ~= ""
				and fields.y ~= "" and fields.z ~= "") then
			local x, y, z = tonumber(fields.x), tonumber(fields.y), tonumber(fields.z)

			if x then
				meta.x_size = math.max(x, 1)
			end
			if y then
				meta.y_size = math.max(y, 1)
			end
			if z then
				meta.z_size = math.max(z, 1)
			end
		end

		-- Save schematic name
		if fields.save_name or fields.key_enter_field == "name" and fields.name and
				fields.name ~= "" then
			meta.schem_name = fields.name
		end

		-- Export schematic
		if fields.export and meta.schem_name and meta.schem_name ~= "" then
			local pos1, pos2 = advschem.size(pos)
			local path = minetest.get_worldpath().."/schems/"
			minetest.mkdir(path)

			local filepath = path..meta.schem_name..".mts"
			local res = minetest.create_schematic(pos1, pos2, {}, filepath, {})

			if res then
				minetest.chat_send_player(name, minetest.colorize("#00ff00",
						"Exported schematic to "..filepath))
			else
				minetest.chat_send_player(name, minetest.colorize("red",
						"Failed to export schematic to "..filepath))
			end
		end

		-- Save meta before updating visuals
		realmeta:from_table({fields = meta})

		-- Update border
		if not fields.border and meta.schem_border == "true" then
			advschem.mark(pos)
		end

		-- Update formspec
		if not fields.quit then
			advschem.show_formspec(pos, minetest.get_player_by_name(name), "main")
		end
	end,
})

---
--- API
---

--- Copies and modifies positions `pos1` and `pos2` so that each component of
-- `pos1` is less than or equal to the corresponding component of `pos2`.
-- Returns the new positions.
function advschem.sort_pos(pos1, pos2)
	if not pos1 or not pos2 then
		return
	end

	pos1, pos2 = table.copy(pos1), table.copy(pos2)
	if pos1.x > pos2.x then
		pos2.x, pos1.x = pos1.x, pos2.x
	end
	if pos1.y > pos2.y then
		pos2.y, pos1.y = pos1.y, pos2.y
	end
	if pos1.z > pos2.z then
		pos2.z, pos1.z = pos1.z, pos2.z
	end
	return pos1, pos2
end

-- [function] Prepare size
function advschem.size(pos)
	local pos1   = vector.new(pos)
	local meta   = minetest.get_meta(pos)
	local node   = minetest.get_node(pos)
	local param2 = node.param2
	local size   = {
		x = meta:get_int("x_size"),
		y = math.max(meta:get_int("y_size") - 1, 0),
		z = meta:get_int("z_size"),
	}

	if param2 == 1 then
		local new_pos = vector.add({x = size.z, y = size.y, z = -size.x}, pos)
		pos1.x = pos1.x + 1
		new_pos.z = new_pos.z + 1
		return pos1, new_pos
	elseif param2 == 2 then
		local new_pos = vector.add({x = -size.x, y = size.y, z = -size.z}, pos)
		pos1.z = pos1.z - 1
		new_pos.x = new_pos.x + 1
		return pos1, new_pos
	elseif param2 == 3 then
		local new_pos = vector.add({x = -size.z, y = size.y, z = size.x}, pos)
		pos1.x = pos1.x - 1
		new_pos.z = new_pos.z - 1
		return pos1, new_pos
	else
		local new_pos = vector.add(size, pos)
		pos1.z = pos1.z + 1
		new_pos.x = new_pos.x - 1
		return pos1, new_pos
	end
end

-- [function] Mark region
function advschem.mark(pos)
	advschem.unmark(pos)

	local id = minetest.pos_to_string(pos)
	local owner = minetest.get_meta(pos):get_string("owner")
	local pos1, pos2 = advschem.size(pos)
	pos1, pos2 = advschem.sort_pos(pos1, pos2)

	local thickness = 0.2
	local sizex, sizey, sizez = (1 + pos2.x - pos1.x) / 2, (1 + pos2.y - pos1.y) / 2, (1 + pos2.z - pos1.z) / 2
	local m = {}

	-- XY plane markers
	for _, z in ipairs({pos1.z - 0.5, pos2.z + 0.5}) do
		local marker = minetest.add_entity({x = pos1.x + sizex - 0.5, y = pos1.y + sizey - 0.5, z = z}, "advschem:display")
		if marker ~= nil then
			marker:set_properties({
				visual_size={x=sizex * 2, y=sizey * 2},
				collisionbox = {-sizex, -sizey, -thickness, sizex, sizey, thickness},
			})
			marker:get_luaentity().id = id
			marker:get_luaentity().owner = owner
			table.insert(m, marker)
		end
	end

	-- YZ plane markers
	for _, x in ipairs({pos1.x - 0.5, pos2.x + 0.5}) do
		local marker = minetest.add_entity({x = x, y = pos1.y + sizey - 0.5, z = pos1.z + sizez - 0.5}, "advschem:display")
		if marker ~= nil then
			marker:set_properties({
				visual_size={x=sizez * 2, y=sizey * 2},
				collisionbox = {-thickness, -sizey, -sizez, thickness, sizey, sizez},
			})
			marker:set_yaw(math.pi / 2)
			marker:get_luaentity().id = id
			marker:get_luaentity().owner = owner
			table.insert(m, marker)
		end
	end

	advschem.markers[id] = m
	return true
end

-- [function] Unmark region
function advschem.unmark(pos)
	local id = minetest.pos_to_string(pos)
	if advschem.markers[id] then
		local retval
		for _, entity in ipairs(advschem.markers[id]) do
			entity:remove()
			retval = true
		end
		return retval
	end
end

---
--- Registrations
---

-- [register] On receive fields
minetest.register_on_player_receive_fields(function(player, formname, fields)
	formname = formname:split(":")
	if formname and formname[1] == "advschem" then
		local name    = player:get_player_name()
		local fname   = formname[2]
		local context = contexts[name]
		if forms[fname] and context and context.name == fname then
			forms[fname].handle(name, fields, context.pos)
		end
	end
end)

-- [priv] schematic_override
minetest.register_privilege("schematic_override", {
	description = "Allows you to access advschem nodes not owned by you",
	give_to_singleplayer = false,
})

-- [node] Schematic creator
minetest.register_node("advschem:creator", {
	description = "Schematic Creator",
	tiles = {"advschem_creator_top.png", "advschem_creator_bottom.png",
			"advschem_creator_sides.png"},
	groups = {cracky = 3},
	paramtype2 = "facedir",

	after_place_node = function(pos, player)
		local name = player:get_player_name()
		local meta = minetest.get_meta(pos)

		meta:set_string("owner", name)
		meta:set_string("infotext", "Schematic Creator\n(owned by "..name..")")

		local node = minetest.get_node(pos)
		local dir  = minetest.facedir_to_dir(node.param2)

		meta:set_int("x_size", 1)
		meta:set_int("y_size", 1)
		meta:set_int("z_size", 1)

		-- Don't take item from itemstack
		return true
	end,
	can_dig = function(pos, player)
		local name = player:get_player_name()
		local meta = minetest.get_meta(pos)
		if meta:get_string("owner") == name or
				minetest.check_player_privs(player, "schematic_override") == true then
			return true
		end

		return false
	end,
	on_rightclick = function(pos, node, player)
		local meta = minetest.get_meta(pos)
		local name = player:get_player_name()
		if meta:get_string("owner") == name or
				minetest.check_player_privs(player, "schematic_override") == true then
			-- Get player attribute
			local tab = player:get_attribute("advschem:tab")
			if not forms[tab] then
				tab = "main"
			end

			advschem.show_formspec(pos, player, tab, true)
		end
	end,
	after_destruct = function(pos)
		advschem.unmark(pos)
	end,
})

-- [entity] Display
minetest.register_entity("advschem:display", {
	initial_properties = {
		visual = "upright_sprite",
		visual_size = {x=1.1, y=1.1},
		textures = {"advschem_border.png"},
		visual_size = {x=10, y=10},
		physical = false,
	},
	on_step = function(self, dtime)
		if not self.id then
			self.object:remove()
		elseif not advschem.markers[self.id] then
			self.object:remove()
		end
	end,
	on_punch = function(self, hitter)
		local pos = minetest.string_to_pos(self.id)
		local meta = minetest.get_meta(pos)
		if meta:get_string("owner") == hitter:get_player_name() or
				minetest.check_player_privs(hitter, "schematic_override") == true then
			advschem.unmark(pos)
			meta:set_string("schem_border", "false")
		end
	end,
	on_activate = function(self)
		self.object:set_armor_groups({immortal = 1})
	end,
})
