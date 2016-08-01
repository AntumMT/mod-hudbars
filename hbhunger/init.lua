
if not minetest.setting_getbool("enable_damage") then
	return
end

hbhunger = {}
hbhunger.hunger = {} -- HUD statbar values
hbhunger.hunger_out = {}
hbhunger.exhaustion = {} -- Exhaustion is experimental!

-- HUD item ids
local hunger_hud = {}

HUNGER_HUD_TICK = 0.5 -- was 0.1
HUNGER_HUNGER_TICK = 500 -- time in seconds after that 1 hunger point is taken (600)
HUNGER_EXHAUST_DIG = 3  -- exhaustion increased this value after digged node
HUNGER_EXHAUST_PLACE = 1 -- exhaustion increased this value after placed
HUNGER_EXHAUST_MOVE = 0.3 -- exhaustion increased this value if player movement detected
HUNGER_EXHAUST_LVL = 160 -- at what exhaustion player satiation gets lowerd

SPRINT_SPEED = 0.8 -- how much faster player can run if satiated
SPRINT_JUMP = 0.1 -- how much higher player can jump if satiated
SPRINT_DRAIN = 0.35 -- how fast to drain satation while sprinting (0-1)

--[[load custom settings
local set = io.open(minetest.get_modpath("hbhunger").."/hbhunger.conf", "r")
if set then 
	dofile(minetest.get_modpath("hbhunger").."/hbhunger.conf")
	set:close()
end--]]

local function custom_hud(player)

	hb.init_hudbar(player, "satiation", hbhunger.get_hunger(player))
end

dofile(minetest.get_modpath("hbhunger") .. "/hunger.lua")

-- register satiation hudbar
hb.register_hudbar(
	"satiation", 0xFFFFFF, "Satiation",
	{
		icon = "hbhunger_icon.png",
		bgicon = "hbhunger_bgicon.png",
		bar = "hbhunger_bar.png"
	},
	20, 30, false
)

-- update hud elemtents if value has changed
local function update_hud(player)

	if not player then return end

	local name = player:get_player_name()
	local h_out = tonumber(hbhunger.hunger_out[name])
	local h = tonumber(hbhunger.hunger[name])

	if h_out ~= h then

		hbhunger.hunger_out[name] = h
		hb.change_hudbar(player, "satiation", h)
	end
end

hbhunger.get_hunger = function(player)

	local inv = player:get_inventory()

	if not inv then return nil end

	local hgp = inv:get_stack("hunger", 1):get_count()

	if hgp == 0 then

		hgp = 21

		inv:set_stack("hunger", 1, ItemStack({name = ":", count = hgp}))
	else
		hgp = hgp
	end

	return hgp - 1
end

hbhunger.set_hunger = function(player)
	local inv = player:get_inventory()
	local name = player:get_player_name()
	local value = hbhunger.hunger[name]
	if not inv  or not value then return nil end
	if value > 30 then value = 30 end
	if value < 0 then value = 0 end
	inv:set_stack("hunger", 1, ItemStack({name = ":", count = value + 1}))
	return true
end

minetest.register_on_joinplayer(function(player)

	local name = player:get_player_name()
	local inv = player:get_inventory()

	inv:set_size("hunger", 1)

	hbhunger.hunger[name] = hbhunger.get_hunger(player)
	hbhunger.hunger_out[name] = hbhunger.hunger[name]
	hbhunger.exhaustion[name] = 0

	custom_hud(player)

	hbhunger.set_hunger(player)
end)

minetest.register_on_respawnplayer(function(player)

	-- reset hunger (and save)
	local name = player:get_player_name()

	hbhunger.hunger[name] = 20
	hbhunger.set_hunger(player)
	hbhunger.exhaustion[name] = 0
end)

-- 3d armor support
local armor_mod = minetest.get_modpath("3d_armor")

-- Sets the sprint state of a player (false = stopped, true = sprinting)
function set_sprinting(name, sprinting)

	if not hbhunger.hunger[name] then
		return false
	end

	local player = minetest.get_player_by_name(name)

	-- is 3d_armor active, then set to armor defaults
	local def = {}
	if armor_mod and armor and armor.def[name] then
		def = armor.def[name]
	end

	def.speed = def.speed or 1
	def.jump = def.jump or 1
	def.gravity = def.gravity or 1

	if sprinting == true then

		player:set_physics_override({
			speed = def.speed + SPRINT_SPEED,
			jump = def.jump + SPRINT_JUMP,
			gravity = def.gravity
		})

--print ("Speed:", def.speed + SPRINT_SPEED, "Jump:", def.jump + SPRINT_JUMP, "Gravity:", def.gravity)

	else

		player:set_physics_override({
			speed = def.speed,
			jump = def.jump,
			gravity = def.gravity
		})

--print ("Speed:", def.speed, "Jump:", def.jump, "Gravity:", def.gravity)

	end

	return true
end

-- sprint settings
local enable_sprint = minetest.setting_getbool("sprint") ~= false
local enable_sprint_particles = minetest.setting_getbool("sprint_particles") ~= false
local sprinters = {}

local main_timer = 0
local timer = 0
local timer2 = 0

minetest.register_globalstep(function(dtime)

	main_timer = main_timer + dtime
	timer = timer + dtime
	timer2 = timer2 + dtime

	if main_timer > HUNGER_HUD_TICK
	or timer > 4
	or timer2 > HUNGER_HUNGER_TICK then

		if main_timer > HUNGER_HUD_TICK then
			main_timer = 0
		end

		for _,player in pairs(minetest.get_connected_players()) do

			local name = player:get_player_name()
			local h = tonumber(hbhunger.hunger[name])
			local hp = player:get_hp()

			-- check if player should be sprinting (hunger must be over 6 points)
			if enable_sprint
			and player
			and player:get_player_control().aux1
			and player:get_player_control().up
			and not minetest.check_player_privs(name, {fast = true})
			and h > 6 then

				set_sprinting(name, true)

				-- create particles behind player when sprinting
				if enable_sprint_particles then

					local pos = player:getpos()
					local node = minetest.get_node({
						x = pos.x,
						y = pos.y - 1,
						z = pos.z
					})

					if node.name ~= "air" then

					minetest.add_particlespawner({
						amount = 5,
						time = 0.01,
						minpos = {x = pos.x - 0.25, y = pos.y + 0.1, z = pos.z - 0.25},
						maxpos = {x = pos.x + 0.25, y = pos.y + 0.1, z = pos.z + 0.25},
						minvel = {x = -0.5, y = 1, z = -0.5},
						maxvel = {x = 0.5, y = 2, z = 0.5},
						minacc = {x = 0, y = -5, z = 0},
						maxacc = {x = 0, y = -12, z = 0},
						minexptime = 0.25,
						maxexptime = 0.5,
						minsize = 0.5,
						maxsize = 1.0,
						vertical = false,
						collisiondetection = false,
						--texture = "default_dirt.png",
						texture = "default_cloud.png",
					})

					end
				end

				-- Lower the player's hunger
				hbhunger.hunger[name] = h - (SPRINT_DRAIN * HUNGER_HUD_TICK)
				hbhunger.set_hunger(player)
			else
				set_sprinting(name, false)
			end
			-- END sprint

			if timer > 4 then

				-- heal player by 1 hp if not dead and satiation is > 15
				if h > 15
				and hp > 0
				and player:get_breath() > 0 then

					player:set_hp(hp + 1)

				-- or damage player by 1 hp if satiation is < 2
				elseif h <= 1 then

					if hp - 1 >= 0 then
						player:set_hp(hp - 1)
					end
				end
			end

			-- lower satiation by 1 point after xx seconds
			if timer2 > HUNGER_HUNGER_TICK then

					if h > 0 then

					h = h - 1

					hbhunger.hunger[name] = h
					hbhunger.set_hunger(player)
				end
			end

			-- update hud elements
			update_hud(player)

			-- Determine if player is walking
			local controls = player:get_player_control()
			if controls.up
			or controls.down
			or controls.left
			or controls.right then

				hbhunger.handle_node_actions(nil, nil, player)
			end

		end

	end

	if timer > 4 then
		timer = 0
	end

	if timer2 > HUNGER_HUNGER_TICK then
		timer2 = 0
	end

end)
