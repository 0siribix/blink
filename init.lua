--[[ To Do:
--Create mesh for marker circle
--Add crafting
Add number of uses
--Add height check for destination
--Add blink behind mobs/players
Check if marker was recently put down and if blinking close enough to it, don't recalculate destination
Localize
Add swoosh sound
Flash different color if no space to blink
--Add Raycast to check line-of-sight when blinking behind a player/entity
--Fix valid_entities and add more compatibility
Possibly switch to first weapon in hotbar when blinking behind players/mobs
]]


blink = {}
local S = core.get_translator("blink")


--     SETTINGS     --
-- Maximum distance to teleport
local blink_distance = core.settings:get("blink:blink_distance") or 15

-- Allow teleport into a protected area
local tp_into_prot = core.settings:get_bool("blink:tp_into_prot") or false

-- Allow teleport out of a protected area
local tp_from_prot = core.settings:get_bool("blink:tp_from_prot") or false

-- Cooldown period before next blink
local cooldown = core.settings:get("blink:cooldown") or 3.0

-- Blink Behind players or mobs and face their back
local blink_behind = core.settings:get("blink:blink_behind") or true

-- Time to show destination marker
local display_time = core.settings:get("blink:display_time") or 6.0


blink.valid_entities = {
	["mobs_animal"] = true,
	["mobs_monster"] = true,
	["mobs_npc"] = true,
	["mob_horse"] = true,
	["mobs_sharks"] = true,
	["mobs_crocs"] = true,
	["mobs_fish"] = true,
	["mobs_jellyfish"] = true,
	["mobs_turtles"] = true,
	["nssm"] = true,
	["creeper"] = true,
	["dmobs"] = true
}

local color_loops = 2	-- If display_time is short this the colors will cycle quickly. If it is long then they will cycle very slowly

--     GLOBALS     --
blink.active_marker = nil	-- objref of active marker
blink.cooldown = false	-- Blink can't be used while this is true


-- marker should be a registered entity
function display_marker(user, marker)
	if marker == "" or marker == nil then marker = "blink:marker" end
	blink_tp(user, marker)
end

function blink_tp(user, marker)
	local username = user:get_player_name()
	if not marker then
		if blink.cooldown then
			core.chat_send_player(username,
				S("You must wait before using Blink again"))
			return
		end
	end

	local origin = user:get_pos()
	local yaw	-- use these if we move behind a player or mob
	local reset_pitch = false

	if not tp_from_prot and core.is_protected(origin, username) then
		core.chat_send_player(username, S("Cannot blink from protected areas!"))
		return
	end

	-- Move origin up to eye_height
	origin.y = origin.y + user:get_properties().eye_height

	local dir = user:get_look_dir()
	local dpos = table.copy(origin)
	dpos.x = dpos.x + (dir.x * blink_distance)
	dpos.y = dpos.y + (dir.y * blink_distance)
	dpos.z = dpos.z + (dir.z * blink_distance)

	local no_space_to_blink = false
	local rc = Raycast(origin, dpos, true, false)

	for pt in rc do
		if blink_behind and pt.type == "object" then
			if pt.ref ~= user then		-- Raycast intersects with players head first
				if pt.ref:is_player() or (
						pt.ref:get_luaentity() and
				         blink.valid_entities[pt.ref:get_luaentity().name:split(":")[1]]) then
					local npos = pt.ref:get_pos()
					if pt.ref:is_player() then
						yaw = pt.ref:get_look_horizontal()
					else
						yaw = pt.ref:get_yaw() + pt.ref:get_luaentity().rotate
					end
					npos.y = npos.y + 0.5
					reset_pitch = true
					-- check line-of-site
					-- this is to prevent someone blinking past blocks behind a player or entity
					local lookdir = minetest.yaw_to_dir(yaw)
					dpos.x = npos.x - (lookdir.x * 2)
					dpos.z = npos.z - (lookdir.z * 2)
					dpos.y = npos.y
					npos.y = npos.y + 1		-- cast the ray at an angle to hopefully catch edge case scenarios
					if Raycast(npos, dpos, false, false):next() then no_space_to_blink = true end
					break
				--else	-- other entity
				--	core.chat_send_player(username, tostring(pt.ref:get_luaentity().name))
				end
			end
		elseif pt.type == "node" then
			local npos = core.get_pointed_thing_position(pt)
			local n = core.get_node(npos).name
			if core.registered_nodes[n] == nil or core.registered_nodes[n].walkable then
				dpos.x = npos.x + pt.intersection_normal.x
				dpos.y = npos.y + pt.intersection_normal.y
				dpos.z = npos.z + pt.intersection_normal.z
				break
			end
		end
	end

	if blink.active_marker then
		blink.active_marker:remove()
	end

	if not tp_into_prot and core.is_protected(dpos, username) then
		core.chat_send_player(username, S("Cannot blink into protected areas"))
		return
	else
		if not no_space_to_blink then
			no_space_to_blink = true
			for i = 1,-1,-2 do
				local p = table.copy(dpos)
				p.y = p.y + i
				local n = core.get_node(p).name
				if core.registered_nodes[n] and not core.registered_nodes[n].walkable then
					no_space_to_blink = false
					if i == 1 then
						break
					else
						dpos.y = dpos.y - 1
					end
				end
			end
		end
		if no_space_to_blink then core.chat_send_player(username, S("Not enough space to blink here")) end
	end

	if marker == nil then
		if not no_space_to_blink then
			dpos.y = dpos.y - 0.5
			user:set_pos(dpos)
			if yaw then user:set_look_horizontal(yaw) end
			if reset_pitch then user:set_look_vertical(0) end
			if not core.is_creative_enabled(username) then
				blink.cooldown = true
				core.after(cooldown, function() blink.cooldown = false end)
			end
		end
	else
		blink.active_marker = core.add_entity(dpos, "blink:marker")
	end

end

function end_cooldown()
	blink.cooldown = false
end

core.register_tool("blink:rune", {
	description = S("Blink Rune"),
	inventory_image = "blink_rune.png",
	wield_image = "blink_rune_wield.png",
	on_use = function(itemstack, user, pointed_thing)
		return display_marker(user)
		end,
	on_place = function(itemstack, user, pointed_thing)
		return blink_tp(user)
		end,
	on_secondary_use = function(itemstack, user, pointed_thing)
		return blink_tp(user)
		end
})

core.register_entity("blink:marker", {
	physical = false,
	collisionbox = {0,0,0,0,0,0},
	visual = "mesh",
	visual_size = {x = 3.5, y = 3.5},
	textures = {"blink_spectrum.png"},
	tframe = 1,
	tlast = 28,
	tstep = display_time / (28 * color_loops),
	mesh = "sphere.obj",
	timer = 0,
	glow = 7,
	on_step = function(self, ftime)
		self.timer = self.timer + ftime
		local tframe = math.fmod(math.floor(self.timer / self.tstep), self.tlast)
		if self.tframe ~= tframe then
			self.tframe = tframe
			self.object:set_texture_mod("^[verticalframe:28:" .. tframe)
		end
		self.timer = self.timer + ftime
		if self.timer > display_time then
			self.object:remove()
		end
	end
})


--[[core.register_node("blink:marker_node", {
	walkable = false,
	drawtype = "mesh",
	tiles = {name = "blink_spectrum30.png",
		animation = {
			type = "vertical_frames",
			aspect_w = 1,
			aspect_h = 1,
			length = 5,
		},
	},
	mesh = "dodecagon.obj",
	--not_in_creative_inventory = true
})
]]


--     Register Craft     --
local mod_main
if core.get_modpath("default") then
	mod_main = "default"
elseif core.get_modpath("mcl_core") then
	mod_main = "mcl_core"
end

local ing1, ing2, ing3
if core.get_modpath("moreores") then
	ing1 = "moreores:mithril_ingot"
else
	if mod_main == "default" then
		ing1 = "default:diamondblock"
	elseif mod_main == "mcl_core" then
		ing1 = "mcl_core:diamondblock"
	end
end

if core.get_modpath("quartz") then
	ing2 = "quartz:block"
else
	if mod_main == "default" then
		ing2 = "default:mese"
	elseif mod_main == "mcl_core" and core.get_modpath("mesecons_torch") then
		ing2 = "mesecons_torch:redstoneblock"
	end
end

if core.get_modpath("bonemeal") then
	ing3 = "bonemeal:bone"
elseif core.get_modpath("bones") then
	ing3 = "bones:bones"
else
	if mod_main == "default" then
		ing3 = "default:clay_lump"
	elseif mod_main == "mcl_core" then
		ing3 = "mcl_core:clay_lump"
	end
end

if ing1 and ing2 and ing3 then
	core.register_craft({
		output = "blink:rune",
		recipe = {
			{ing3, ing1, ing3},
			{ing3, ing2, ing3},
			{ing3, ing1, ing3},
		}
	})
end

