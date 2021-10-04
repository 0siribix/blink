--[[

Blink for Minetest

Code is licensed under the GNU LGPL version 3 or later.
See LICENSE.txt and http://www.gnu.org/licenses/lgpl-3.0.txt


To Do:
Localize
Maybe switch to first weapon in hotbar when blinking behind players or mobs
Maybe put messages in HUD instead of in chat
Add a check for destination when raycast doesn't intersect
	It may be possible to glitch through a single layer of nodes if player uses blink at maximum distance since we move the Y - 0.5
]]


blink = {}
local S = core.get_translator("blink")


--     SETTINGS     --
-- Maximum distance to teleport
local blink_distance = core.settings:get("blink:blink_distance") or 20

-- Allow teleport into a protected area
local tp_into_prot = core.settings:get_bool("blink:tp_into_prot") or false

-- Allow teleport out of a protected area
local tp_from_prot = core.settings:get_bool("blink:tp_from_prot") or false

-- Cooldown period before next blink
local cooldown_base = core.settings:get("blink:cooldown_base") or 0

-- Multiply this by distance travelled and add to base
local cooldown_factor = core.settings:get("blink:cooldown_factor") or 0.1

-- Blink Behind players or mobs and face their back
local blink_behind = core.settings:get("blink:blink_behind") or true

-- Time to show destination marker
local display_time = core.settings:get("blink:display_time") or 6.0

-- Public areas username. Any areas owned by this user are considered public and will allow users to blink
local public_username = core.settings:get("blink:public_username") or ""

-- If placing a second marker in the same place as an existing one, tp there
local double_tap_tp = core.settings:get("blink:double_tap_tp") or true

-- Number of uses for Blink Rune
local num_uses = core.settings:get("blink:num_uses") or 150


-- You can easily add to this list externally
-- Simply add blink as an optional dependency and do blink.valid_entities["modname"] = true
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

-- This is number of times to loop through the colors in blink_spectrum.png
-- display time of each color is display_time / (number of colors * color_loops)
local color_loops = 2	-- If display_time is short this the colors will cycle quickly. If it is long then they will cycle very slowly
local tool_wear = math.ceil(65536 / num_uses)

--     GLOBALS     --
blink.active_marker = {}	-- Table of users marker objects
blink.cooldown = {}	-- Collection of users still in cooldown


-- marker should be a registered entity
function display_marker(user, itemstack, marker)
	if marker == "" or marker == nil then marker = "blink:marker" end
	blink_tp(user, itemstack, marker)
end

-- This function is available to other mods
-- Marker should be nil if you want to tp the player or a string name of a registered entity to display
-- Currently blink:marker2 is hardcoded but this could be easily changed if someone wanted to have that functionality in the future
-- if itemstack is not nil then add wear and return that itemstack
function blink_tp(user, itemstack, marker)

	local username = user:get_player_name()
	if not marker then
		if blink.cooldown[username] then
			core.chat_send_player(username,
				S("You must wait before using Blink again"))
			return
		end
	end

	local markername = marker or "blink:marker"	-- change this to 2 if we can't tp to this destination
	local origin = user:get_pos()
	local yaw	-- use these if we move behind a player or mob
	local reset_pitch = false

	if not tp_from_prot and core.is_protected(origin, username) and core.is_protected(origin, public_username) then
		core.chat_send_player(username, S("Cannot blink from protected areas!"))
		return
	end

	-- Move origin up to eye_height
	origin.y = origin.y + user:get_properties().eye_height

	local dir = user:get_look_dir()
	local dpos = table.copy(origin)
	-- It's possible to use vector.add but this is a fairly new feature and waasn't compatible with Multicraft servers at the time of development
	-- The builtin function is written in LUA so there is no performance loss by doing it here manually
	dpos.x = dpos.x + (dir.x * blink_distance)
	dpos.y = dpos.y + (dir.y * blink_distance)
	dpos.z = dpos.z + (dir.z * blink_distance)

	local no_space_to_blink = false
	-- Create a ray from player's eyes to blink_distance in the direction player is looking
	local rc = Raycast(origin, dpos, true, false)

	-- When I first wrote this code, I thought that all this calculation might cause server lag but it actually does very well
	-- Loop through objects that the ray intersects with
	for pt in rc do
		if blink_behind and pt.type == "object" then
			if pt.ref ~= user then		-- Raycast intersects with players head first
				local ref_ent = pt.ref:get_luaentity()
				if pt.ref:is_player() or (
						ref_ent and
				         blink.valid_entities[ref_ent.name:split(":")[1]]) then
					local npos = pt.ref:get_pos()
					-- It took LOTS of testing and crashing to get this to work correctly
					if pt.ref:is_player() then
						yaw = pt.ref:get_look_horizontal()
					else
						yaw = pt.ref:get_yaw() + (ref_ent.rotate or 0)
					end
					npos.y = npos.y + 0.5
					reset_pitch = true
					-- check line-of-site
					-- this is to prevent someone blinking past blocks behind a player or entity
					local lookdir = core.yaw_to_dir(yaw)
					dpos.x = npos.x - (lookdir.x * 2)
					dpos.z = npos.z - (lookdir.z * 2)
					dpos.y = npos.y
					-- The purpose of adding one here is because we are checking for any blockage between the player/mob and the blink destination
					-- It's possible that checking a straight line would allow someone to blink behind the target where there is not enough room to blink otherwise
					-- By adding 1 to the Y, we are now casting a ray at an angle which should only allow to blink as long as it's clear two blocks tall
					npos.y = npos.y + 1
					if Raycast(npos, dpos, false, false):next() then no_space_to_blink = true end
					break	-- At this point, the raycast has intersected with a player or mob and there is no reason to keep looking further
				end
			end
		elseif pt.type == "node" then
			local npos = core.get_pointed_thing_position(pt)
			local n = core.get_node(npos).name
			-- First check for unknown node, then see if node is walkable
			if core.registered_nodes[n] == nil or core.registered_nodes[n].walkable then
				dpos.x = npos.x + pt.intersection_normal.x
				dpos.y = npos.y + pt.intersection_normal.y
				dpos.z = npos.z + pt.intersection_normal.z
				break
			end
		end
	end

	-- Save marker pos to oldpos and compare location to see whether we need to blink to the current dpos or create a new marker
	local oldpos

	-- Remove marker if there is one
	if blink.active_marker[username] then
		if double_tap_tp and marker then
			oldpos = blink.active_marker[username]:get_pos()
		end
		blink.active_marker[username]:remove()
		blink.active_marker[username] = nil
	end

	if not tp_into_prot and core.is_protected(dpos, username) and core.is_protected(origin, public_username) then
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
		if no_space_to_blink then
			markername = "blink:marker2"
			core.chat_send_player(username, S("Not enough space to blink here"))
		end
	end

	-- if oldpos is set then that means we just removed a marker from this pos
	-- if oldpos == dpos then we should blink there instead of creating a new marker
	if (not no_space_to_blink) and oldpos and math.floor(oldpos.x) == math.floor(dpos.x) and
				math.floor(oldpos.y) == math.floor(dpos.y) and
				math.floor(oldpos.z) == math.floor(dpos.z) then
		marker = nil
	end

	-- if marker is not nil then we need to create a marker at dpos, otherwise blink to dpos
	if marker == nil then
		if not no_space_to_blink then
			-- When we set_pos, the player's feet is set to the Y level. Move down 0.5 so we don't fall half a block every time we blink
			dpos.y = dpos.y - 0.5
			user:set_pos(dpos)
			core.sound_play("blink_swoosh", {pos = dpos, max_hear_distance = 10})
			if yaw then user:set_look_horizontal(yaw) end
			if reset_pitch then user:set_look_vertical(0) end
			if not core.is_creative_enabled(username) then
				local cooldown = cooldown_base +
						cooldown_factor * vector.distance(origin, dpos)
				blink.cooldown[username] = true
				core.after(cooldown, function() blink.cooldown[username] = false end)
			end
		end
	else
		blink.active_marker[username] = core.add_entity(dpos, markername, username)
	end

	if itemstack then
		itemstack:add_wear(tool_wear)
		return itemstack
	end
end

core.register_tool("blink:rune", {
	description = S("Blink Rune"),
	inventory_image = "blink_rune.png",
	wield_image = "blink_rune_wield.png",
	on_use = function(itemstack, user, pointed_thing)
		return display_marker(user, itemstack)
		end,
	on_place = function(itemstack, user, pointed_thing)
		return blink_tp(user, itemstack)
		end,
	on_secondary_use = function(itemstack, user, pointed_thing)
		return blink_tp(user, itemstack)
		end
})

core.register_tool("blink:forever_rune", {
	description = S("Forever Rune"),
	inventory_image = "blink_rune2.png",
	wield_image = "blink_rune2_wield.png",
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

e_def = {
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
	owner = nil,
	on_activate = function(self, staticdata, dtime_s)
		self.owner = staticdata
	end,
	on_step = function(self, ftime)
		self.timer = self.timer + ftime
		local tframe = math.fmod(math.floor(self.timer / self.tstep), self.tlast)
		if self.tframe ~= tframe then
			self.tframe = tframe
			self.object:set_texture_mod("^[verticalframe:".. self.tlast .. ":" .. tframe)
		end
		self.timer = self.timer + ftime
		if self.timer > display_time then
			blink.active_marker[self.owner] = nil
			self.object:remove()
		end
	end
}

core.register_entity("blink:marker", table.copy(e_def))

e_def.textures = {"blink_spectrum2.png"}
e_def.tlast = 7

-- This is the Red/Orange glow when there is no space to blink
core.register_entity("blink:marker2", e_def)



--     Register items     --
local mod_main
if core.get_modpath("default") then
	mod_main = "default"
elseif core.get_modpath("mcl_core") then
	mod_main = "mcl_core"
end

-- Basic crafting items for Blink runes
core.register_craftitem("blink:bone_shard", {
	description = S("Bone shard"),
	inventory_image = "blink_bone_shard.png"
})

if core.get_modpath("bonemeal") then
	core.register_alias("blink:bone", "bonemeal:bone")

	core.register_craft({
		output = "blink:bone_shard 4",
		type = "shapeless",
		recipe = {"bonemeal:bone", "bonemeal:bone"}
	})

	if core.get_modpath("tubelib_addons1") then
		tubelib.add_grinder_recipe({input = "bonemeal:bone", output = "blink:bone_shard 3"})
	end
else
	core.register_craftitem("blink:bone", {
		description = S("Bone"),
		inventory_image = "blink_bone.png"
	})

	if core.get_modpath("bones") then
		core.register_craft({
			output = "blink:bone 3",
			recipe = {{"bones:bones"}}
		})
	end

	core.register_craft({
		output = "blink:bone_shard 2",
		recipe = {{"blink:bone"}}
	})

	if core.get_modpath("tubelib_addons1") then
		tubelib.add_grinder_recipe({input = "blink:bone", output = "blink:bone_shard 3"})
	end

	for k, v in pairs(core.registered_nodes) do
		if v.groups["soil"] or v.groups["dirt"] then
			core.log("verbose", "Adding blink:bone drop to " .. k)
			local ndrop
			if v.drop then
				if type(v.drop) == "string" then
					ndrop = {items = {items = {v.drop}}}
				elseif type(v.drop) == "table" then
					ndrop = table.copy(v.drop)
				end
				table.insert(ndrop.items, {
					items = {"blink:bone"},
					rarity = 50
				})
				core.override_item(k, {drop = ndrop})
			end
		end
	end
end

-- If bones is not installed and we have dmobs:skeleton, add Blink:bone to skeleton drops
local skel = core.registered_entities["dmobs:skeleton"]
if skel then skel.drops = {name = "blink:bone_shard", chance = 2, min = 2, max = 5} end

--     Register Rune Crafts     --
local ing1, ing2 = "", ""
if mod_main == "default" then
	ing1 = "default:mese_crystal"
	ing2 = "default:mese"
elseif mod_main == "mcl_core" then
	if core.get_modpath("mesecons") then
		ing1 = "mesecons:redstone"
	end
	if core.get_modpath("mesecons_torch") then
		ing2 = "mesecons_torch:redstoneblock"
	end
end


core.register_craft({
	output = "blink:rune",
	recipe = {
		{"blink:bone_shard", "blink:bone_shard", ""},
		{"blink:bone_shard", "blink:bone_shard", ing1},
		{"blink:bone_shard", "blink:bone_shard", ""}
	}
})

core.register_craft({
	output = "blink:forever_rune",
	recipe = {
		{"blink:rune", "blink:rune", "blink:rune"},
		{"blink:rune", ing2, "blink:rune"},
		{"blink:rune", "blink:rune", "blink:rune"},
	}
})
