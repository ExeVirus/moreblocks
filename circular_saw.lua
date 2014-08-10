local S = moreblocks.gettext
circular_saw = {}

circular_saw.known_stairs = setmetatable({}, {
	__newindex = function(k, v)
		local modname = minetest.get_current_modname()
		print(("WARNING: mod %s tried to add node %s to the circular saw"
				.. " manually."):format(modname, v))
	end,
})

-- This is populated by stairsplus:register_all:
circular_saw.known_nodes = {}

-- How many microblocks does this shape at the output inventory cost:
circular_saw.cost_in_microblocks = {
	1, 1, 1, 1, 1, 1, 1, 2,
	2, 3, 2, 4, 2, 4, 5, 6,
	7, 1, 1, 2, 4, 6, 7, 8,
	3, 1, 1, 2, 4, 0, 0, 0,
}

circular_saw.names = {
	{"micro", "_1"},
	{"panel", "_1"},
	{"micro", "_2"},
	{"panel", "_2"},
	{"micro", "_4"},
	{"panel", "_4"},
	{"micro", ""},
	{"panel", ""},
	{"micro", "_12"},
	{"panel", "_12"},
	{"micro", "_14"},
	{"panel", "_14"},
	{"micro", "_15"},
	{"panel", "_15"},
	{"stair", "_outer"},
	{"stair", ""},
	{"stair", "_inner"},
	{"slab", "_1"},
	{"slab", "_2"},
	{"slab", "_quarter"},
	{"slab", ""},
	{"slab", "_three_quarter"},
	{"slab", "_14"},
	{"slab", "_15"},
	{"stair", "_half"},
	{"stair", "_alt_1"},
	{"stair", "_alt_2"},
	{"stair", "_alt_4"},
	{"stair", "_alt"},
}

function circular_saw:get_cost(inv, stackname)
	for i, item in pairs(inv:get_list("output")) do
		if item:get_name() == stackname then
			return circular_saw.cost_in_microblocks[i]
		end
	end
end

function circular_saw:get_output_inv(modname, material, amount, max)
	if (not max or max < 1 or max > 99) then max = 99 end

	local list = {}
	-- If there is nothing inside, display empty inventory:
	if amount < 1 then
		return list
	end

	for i, t in ipairs(circular_saw.names) do
		local cost = circular_saw.cost_in_microblocks[i]
		table.insert(list, modname .. ":" .. t[1] .. "_" .. material .. t[2]
				.. " " .. math.min(math.floor(amount/cost), max))
	end
	return list
end


-- Reset empty circular_saw after last full block has been taken out
-- (or the circular_saw has been placed the first time)
-- Note: max_offered is not reset:
function circular_saw:reset(pos)
	local meta = minetest.get_meta(pos)
	local inv  = meta:get_inventory()

	inv:set_list("input",  {})
	inv:set_list("micro",  {})
	inv:set_list("output", {})
	meta:set_int("anz", 0)

	meta:set_string("infotext",
			S("Circular Saw is empty (owned by %s)")
			:format(meta:get_string("owner") or ""))
end


-- Player has taken something out of the box or placed something inside
-- that amounts to count microblocks:
function circular_saw:update_inventory(pos, amount)
	local meta          = minetest.get_meta(pos)
	local inv           = meta:get_inventory()

	amount = meta:get_int("anz") + amount

	-- The material is recycled automaticly.
	inv:set_list("recycle",  {})

	if amount < 1 then -- If the last block is taken out.
		self:reset(pos)
		return
	end
 
	local stack = inv:get_stack("input",  1)
	-- At least one "normal" block is necessary to see what kind of stairs are requested.
	if stack:is_empty() then
		-- Any microblocks not taken out yet are now lost.
		-- (covers material loss in the machine)
		self:reset(pos)
		return

	end
	local node_name = stack:get_name()
	local name_parts = circular_saw.known_nodes[node_name] or ""
	local modname  = name_parts[1]
	local material = name_parts[2]

	inv:set_list("input", { -- Display as many full blocks as possible:
		node_name.. " " .. math.floor(amount / 8)
	})

	-- The stairnodes made of default nodes use moreblocks namespace, other mods keep own:
	if modname == "default" then
		modname = "moreblocks"
	end
	-- print("circular_saw set to " .. modname .. " : "
	--	.. material .. " with " .. (amount) .. " microblocks.")

	-- 0-7 microblocks may remain left-over:
	inv:set_list("micro", {
		modname .. ":micro_" .. material .. "_bottom " .. (amount % 8)
	})
	-- Display:
	inv:set_list("output",
		self:get_output_inv(modname, material, amount,
				meta:get_int("max_offered")))
	-- Store how many microblocks are available:
	meta:set_int("anz", amount)

	meta:set_string("infotext",
			S("Circular Saw is working on %s (owned by %s)")
			:format(material, meta:get_string("owner") or ""))
end


-- The amount of items offered per shape can be configured:
function circular_saw.on_receive_fields(pos, formname, fields, sender)
	local meta = minetest.get_meta(pos)
	local max = tonumber(fields.max_offered)
	if max and max > 0 then
		meta:set_string("max_offered",  max)
		-- Update to show the correct number of items:
		circular_saw:update_inventory(pos, 0)
	end
end


-- Moving the inventory of the circular_saw around is not allowed because it
-- is a fictional inventory. Moving inventory around would be rather
-- impractical and make things more difficult to calculate:
function circular_saw.allow_metadata_inventory_move(
		pos, from_list, from_index, to_list, to_index, count, player)
	return 0
end


-- Only input- and recycle-slot are intended as input slots:
function circular_saw.allow_metadata_inventory_put(
		pos, listname, index, stack, player)
	-- The player is not allowed to put something in there:
	if listname == "output" or listname == "micro" then
		return 0
	end

	local meta = minetest.get_meta(pos)
	local inv  = meta:get_inventory()
	local stackname = stack:get_name()
	local count = stack:get_count()

	-- Only alow those items that are offered in the output inventory to be recycled:
	if listname == "recycle" then
		if not inv:contains_item("output", stackname) then
			return 0
		end
		local stackmax = stack:get_stack_max()
		local instack = inv:get_stack("input", 1)
		local microstack = inv:get_stack("micro", 1)
		local incount = instack:get_count()
		local incost = (incount * 8) + microstack:get_count()
		local maxcost = (stackmax * 8) + 7
		local cost = circular_saw:get_cost(inv, stackname)
		if (incost + cost) > maxcost then
			return math.max((maxcost - incost) / cost, 0)
		end
		return count
	end

	-- Only accept certain blocks as input which are known to be craftable into stairs:
	if listname == "input" then
		if not inv:is_empty("input") and
				inv:get_stack("input", index):get_name() ~= stackname then
			return 0
		end
		for name, t in pairs(circular_saw.known_nodes) do
			if name == stackname and inv:room_for_item("input", stack) then
				return count
			end
		end
		return 0
	end
end

-- Taking is allowed from all slots (even the internal microblock slot).
-- Putting something in is slightly more complicated than taking anything
-- because we have to make sure it is of a suitable material:
function circular_saw.on_metadata_inventory_put(
		pos, listname, index, stack, player)
	-- We need to find out if the circular_saw is already set to a
	-- specific material or not:
	local meta = minetest.get_meta(pos)
	local inv  = meta:get_inventory()
	local stackname = stack:get_name()
	local count = stack:get_count()

	-- Putting something into the input slot is only possible if that had
	-- been empty before or did contain something of the same material:
	if listname == "input" then
		-- Each new block is worth 8 microblocks:
		circular_saw:update_inventory(pos, 8 * count)
	elseif listname == "recycle" then
		-- Lets look which shape this represents:
		local cost = circular_saw:get_cost(inv, stackname)
		circular_saw:update_inventory(pos, cost * count)
	end
end

function circular_saw.on_metadata_inventory_take(
		pos, listname, index, stack, player)
	-- If it is one of the offered stairs: find out how many
	-- microblocks have to be substracted:
	if listname == "output" then
		-- We do know how much each block at each position costs:
		local cost = circular_saw.cost_in_microblocks[index]
				* stack:get_count()

		circular_saw:update_inventory(pos, -cost)
	elseif listname == "micro" then
		-- Each microblock costs 1 microblock:
		circular_saw:update_inventory(pos, -stack:get_count())
	elseif listname == "input" then
		-- Each normal (= full) block taken costs 8 microblocks:
		circular_saw:update_inventory(pos, 8 * -stack:get_count())
	end
	-- The recycle field plays no role here since it is processed immediately.
end

gui_slots = "listcolors[#606060AA;#808080;#101010;#202020;#FFF]"

function circular_saw.on_construct(pos)
	local meta = minetest.get_meta(pos)
	meta:set_string("formspec", "size[11,9]" ..gui_slots..
			"label[0,0;" ..S("Input\nmaterial").. "]" ..
			"list[current_name;input;1.5,0;1,1;]" ..
			"label[0,1;" ..S("Left-over").. "]" ..
			"list[current_name;micro;1.5,1;1,1;]" ..
			"label[0,2;" ..S("Recycle\noutput").. "]" ..
			"list[current_name;recycle;1.5,2;1,1;]" ..
			"field[0.3,3.5;1,1;max_offered;" ..S("Max").. ":;${max_offered}]" ..
			"button[1,3.2;1,1;Set;" ..S("Set").. "]" ..
			"list[current_name;output;2.8,0;8,4;]" ..
			"list[current_player;main;1.5,5;8,4;]")

	meta:set_int("anz", 0) -- No microblocks inside yet.
	meta:set_string("max_offered", 99) -- How many items of this kind are offered by default?
	meta:set_string("infotext", S("Circular Saw is empty"))

	local inv = meta:get_inventory()
	inv:set_size("input", 1)    -- Input slot for full blocks of material x.
	inv:set_size("micro", 1)    -- Storage for 1-7 surplus microblocks.
	inv:set_size("recycle", 1)  -- Surplus partial blocks can be placed here.
	inv:set_size("output", 4*8) -- 4x8 versions of stair-parts of material x.

	circular_saw:reset(pos)
end


function circular_saw.can_dig(pos,player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if not inv:is_empty("input") or
	   not inv:is_empty("micro") or
	   not inv:is_empty("recycle") then
		return false
	end
	-- Can be dug by anyone when empty, not only by the owner:
	return true
end

minetest.register_node("moreblocks:circular_saw",  {
	description = S("Circular Saw"), 
	drawtype = "nodebox", 
	node_box = {
		type = "fixed", 
		fixed = {
			{-0.4, -0.5, -0.4, -0.25, 0.25, -0.25}, -- Leg
			{0.25, -0.5, 0.25, 0.4, 0.25, 0.4}, -- Leg
			{-0.4, -0.5, 0.25, -0.25, 0.25, 0.4}, -- Leg 
			{0.25, -0.5, -0.4, 0.4, 0.25, -0.25}, -- Leg
			{-0.5, 0.25, -0.5, 0.5, 0.375, 0.5}, -- Tabletop
			{-0.01, 0.4375, -0.125, 0.01, 0.5, 0.125}, -- Saw blade (top)
			{-0.01, 0.375, -0.1875, 0.01, 0.4375, 0.1875}, -- Saw blade (bottom)
			{-0.25, -0.0625, -0.25, 0.25, 0.25, 0.25}, -- Motor case
		},
	},
	tiles = {"moreblocks_circular_saw_top.png",
		"moreblocks_circular_saw_bottom.png",
		"moreblocks_circular_saw_side.png"},
	paramtype = "light", 
	sunlight_propagates = true,
	paramtype2 = "facedir", 
	groups = {choppy = 2,oddly_breakable_by_hand = 2},
	sounds = default.node_sound_wood_defaults(),
	on_construct = circular_saw.on_construct,
	can_dig = circular_saw.can_dig,
	-- Set the owner of this circular saw.
	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		local owner = placer and placer:get_player_name() or ""
		meta:set_string("owner",  owner)
		meta:set_string("infotext",
				S("Circular Saw is empty (owned by %s)")
				:format(owner))
	end,

	-- The amount of items offered per shape can be configured:
	on_receive_fields = circular_saw.on_receive_fields,
	allow_metadata_inventory_move = circular_saw.allow_metadata_inventory_move,
	-- Only input- and recycle-slot are intended as input slots:
	allow_metadata_inventory_put = circular_saw.allow_metadata_inventory_put,
	-- Taking is allowed from all slots (even the internal microblock slot). Moving is forbidden.
	-- Putting something in is slightly more complicated than taking anything because we have to make sure it is of a suitable material:
	on_metadata_inventory_put = circular_saw.on_metadata_inventory_put,
	on_metadata_inventory_take = circular_saw.on_metadata_inventory_take,
})
