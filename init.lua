--[[ To Do:
Create mesh for marker circle
Add crafting
Add number of uses
Add height check for destination
Add blink behind mobs/players
Check if entity was recently put down and if blinking close enough to it, don't recalculate destination
Possibly add a priv and priv check?
Localize
]]


blink = {}
local S = minetest.get_translator("blink")


--     SETTINGS     --
-- Maximum distance to teleport
local blink_distance = minetest.settings:get("blink:blink_distance") or 15

-- Allow teleport into a protected area
local tp_into_prot = minetest.settings:get_bool("blink:tp_into_prot") or false

-- Allow teleport out of a protected area
local tp_from_prot = minetest.settings:get_bool("blink:tp_from_prot") or false

-- Cooldown period before next blink
local cooldown = minetest.settings:get("blink:cooldown") or 3.0

--  If destination is too short, step backward until we find a place with enough space
-- This may cause a noticeable lag (more testing needed)
--local check_height = minetest.settings:get_bool("blink:check_height") or false

-- Time to show destination marker
local display_time = minetest.settings:get("blink:display_time") or 5.0


--     GLOBALS     --
blink.active_marker = nil	-- objref of active marker
blink.cooldown = false	-- Blink can't be used while this is true


-- marker should be a registered entity
function display_marker(user, marker)
	if marker == "" or marker == nil then marker = "blink:marker" end
	blink_tp(user, marker)
end

function blink_tp(user, marker)
	if marker then
		if blink.active_marker then
			blink.active_marker:remove()
		end
	else
		if blink.cooldown then
			minetest.chat_send_player(user:get_player_name(),
				S("You must wait before using Blink again"))
			return
		end
	end

	local origin = user:get_pos()

	if not tp_from_prot and minetest.is_protected(origin, user) then
		chat_send_player(user:get_player_name(), S("Cannot blink from protected areas!"))
		return
	end

	-- Move origin up to eye_height
	origin.y = origin.y + user:get_properties().eye_height

	local dir = user:get_look_dir()
	local dpos = origin:add(dir:multiply(blink_distance))

	rc = Raycast(origin, dpos, false, false):next()
	-- try to add loop here to pass through unwalkable nodes

	-- first get the pos of the pointed thing
	if rc then
		dpos = minetest.get_pointed_thing_position(rc)
		-- then move 1 block in the direction of the intersected face
		-- and move down 0.5
		dpos = dpos:add(rc.intersection_normal)
	end

	if marker == nil then
		if not tp_into_prot and minetest.is_protected(dpos, user) then
			chat_send_player(user:get_player_name(), S("Cannot blink into protected areas"))
		end

		-- here is where we would check the height

		dpos.y = dpos.y - 0.5
		user:set_pos(dpos)
		blink.cooldown = true
		minetest.after(cooldown, function() blink.cooldown = false end)
	else

		blink.active_marker = minetest.add_entity(dpos, marker)
	end

end

function end_cooldown()
	blink.cooldown = false
end

minetest.register_tool("blink:rune", {
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

minetest.register_entity("blink:marker", {
	physical = false,
	collisionbox = {0,0,0,0,0,0},
	visual = "sprite",
	visual_size = {x = 0.5, y = 0.5},
	textures = {"blink_rune.png"},
	timer = 0,
	glow = 10,
	on_step = function(self, ftime)
		self.timer = self.timer + ftime
		if self.timer > display_time then
			self.object:remove()
		end
	end
})
