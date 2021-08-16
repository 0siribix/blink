--[[ To Do:
--Create mesh for marker circle
--Add crafting
Add number of uses
Add height check for destination
Add blink behind mobs/players
Check if entity was recently put down and if blinking close enough to it, don't recalculate destination
Possibly add a priv and priv check?
Localize
Add swoosh sound
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

--  If destination is too short, step backward until we find a place with enough space
-- This may cause a noticeable lag (more testing needed)
--local check_height = core.settings:get_bool("blink:check_height") or false

-- Time to show destination marker
local display_time = core.settings:get("blink:display_time") or 5.0
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

	if not tp_from_prot and core.is_protected(origin, user) then
		chat_send_player(username, S("Cannot blink from protected areas!"))
		return
	end

	-- Move origin up to eye_height
	origin.y = origin.y + user:get_properties().eye_height

	local dir = user:get_look_dir()
	--local dpos = origin:add(dir:multiply(blink_distance))
	local dpos = table.copy(origin)
	dpos.x = dpos.x + (dir.x * blink_distance)
	dpos.y = dpos.y + (dir.y * blink_distance)
	dpos.z = dpos.z + (dir.z * blink_distance)

	local rc = Raycast(origin, dpos, false, false):next()
	-- try to add loop here to pass through unwalkable nodes

	-- first get the pos of the pointed thing
	if rc then
		dpos = core.get_pointed_thing_position(rc)
		-- then move 1 block in the direction of the intersected face
		--dpos = dpos:add(rc.intersection_normal)
		dpos.x = dpos.x + rc.intersection_normal.x
		dpos.y = dpos.y + rc.intersection_normal.y
		dpos.z = dpos.z + rc.intersection_normal.z
	end

	if blink.active_marker then
		blink.active_marker:remove()
		--blink.active_marker.expirationtime = 0
	end

	if marker == nil then
		if not tp_into_prot and core.is_protected(dpos, user) then
			chat_send_player(username, S("Cannot blink into protected areas"))
		end

		-- here is where we would check the height

		dpos.y = dpos.y - 0.5
		user:set_pos(dpos)
		if not core.is_creative_enabled(username) then
			blink.cooldown = true
			core.after(cooldown, function() blink.cooldown = false end)
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

