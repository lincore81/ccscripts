--#@arcpack
--#file:turtle/build
--build
CTRL_PREFIX = "--#"
COMMENT = "//"
NEWLINE = "\n"
FILE_HEADER = CTRL_PREFIX .. "@build"
STATE_FILE = "build-state"

state = {schematic = {}}


StringBuffer = {}
	function StringBuffer:new(initialValue)
		instance = {}
		instance.buffer = {}
		setmetatable(instance, self)
		self.__index = self

		if initialValue then
			instance:add(initialValue)
		end
		return instance
	end

	function StringBuffer:toString(delimiter)
		return table.concat(self.buffer, delimiter)
	end

	function StringBuffer:dump()
		for k, v in ipairs(self.buffer) do
			print(k .. ": " .. v)
		end
	end

	function StringBuffer:add(...)
		for _, v in ipairs(arg) do
			table.insert(self.buffer, tostring(v))
		end
	end

	function StringBuffer:clear()
		self.buffer = {}
	end

	function StringBuffer:isEmpty()
		return #self.buffer == 0
	end

	function StringBuffer:contains(str)
		for _, v in ipairs(self.buffer) do
			if v == str then return true end
		end
	end



function isAbsolutePath(path)
	return string.sub(path, 1, 1) == "/"
end

function getAbsolutePath(path)
	if isAbsolutePath(path) then
		return path
	else
		return "/" .. fs.combine(shell.dir(), path)
	end
end

function string.trim(str)
	return string.gsub(str, "%s+", "")
end

function string.beginsWith(str, substr)
	if not str or not substr then return false end
	if string.len(substr) > string.len(str) then return false end
	if str == substr then return str, "" end
	return string.sub(str, 1, string.len(substr)) == substr, string.sub(str, string.len(substr) + 1)
end

function string.explode(str)
	local chars = {}
	for i = 1, string.len(str) do
		table.insert(chars, string.sub(str, i, i))
	end
	return chars
end

function table.dump(tabl, recursive, depth)
	local dumpedTables = {} -- to avoid circular references
	local _dump
	_dump = function(tabl, indent, depth)
		dumpedTables[tabl] = true
		for k, v in pairs(tabl) do
			local d = (depth and depth > 0) or not depth
			if type(v) == "table" and recursive and d and not dumpedTables[v] then
				print(string.rep(" ", indent) .. tostring(k) .. ":")
				if depth then
					_dump(v, indent+1, depth-1)
				else
					_dump(v, indent+1)
				end
			else
				print(string.rep(" ", indent) .. tostring(k) .. ": " .. tostring(v))
			end
		end
	end
	_dump(tabl, 0, depth)
end

function cleanLine(line)
	if not line then return line end
	local commentPosition = string.find(line, COMMENT, 1, true)
	if commentPosition then
		line = string.sub(line, 1, commentPosition - 1)
	end
	return string.trim(line)
end

function endFloorSection(floor, floorNumber, lineNumber)
	if state.schematic[floorNumber] then
		error("Error in line " .. lineNumber .. ": more than one floor with the same floor number (" ..
			floorNumber .. ").")
	end
	state.schematic[floorNumber] = floor
end


function isFloorHeader(line)
	local isCtrlSeq, remainder = string.beginsWith(line, CTRL_PREFIX)
	if isCtrlSeq then
		return tonumber(remainder) or false
	else
		return false
	end
end

function parseFloorLine(floor, line)
	if line == "" then return end
	local sequence = {}
	for _, char in ipairs(string.explode(line)) do
		if char ~= ' ' or char ~= '\t' then
			local slot = tonumber(char, 16) or false
			if slot then slot = slot + 1 end
			table.insert(sequence, slot)
		end
	end
	table.insert(floor, sequence)
end


function finalizeSchematic()
	--make sure all rows have the same length:
	for k, floor in ipairs(state.schematic) do
		local maxRowLength = 0
		for l, row in ipairs(state.schematic) do
			if #row > maxRowLength then
				maxRowLength = #row
			end
		end
		for l, row in ipairs(state.schematic) do
			while #row < maxRowLength do
				table.insert(row, false)
			end
		end
	end
end




function parseSchematic(handle)
	if handle.readLine() ~= FILE_HEADER then
		error("File is not a build schematic.")
	end
	local lineNumber = 2
	local floor, floorNumber
	repeat
		local line = cleanLine(handle.readLine())
		local nextFloor = isFloorHeader(line)
		if not line or nextFloor then
			if floorNumber then
				endFloorSection(floor, floorNumber, lineNumber)
			end
		end
		if nextFloor then
				floorNumber = nextFloor
				floor = {}
		elseif line and line ~= "" then
			if not floorNumber then
				error("Error on line " .. lineNumber .. ": Missing floor header.")
			end
			parseFloorLine(floor, line)
		end
		lineNumber = lineNumber + 1
	until line == nil
end

function formatSequence(sequence)
	local buffer = StringBuffer:new()
	for k, v in ipairs(sequence) do
		buffer:add(v or " ")
	end
	return buffer:toString()
end

function build(stack)
	turtl.up()
	local height = #state.schematic
	local width  = #(state.schematic[1])
	local depth  = #(state.schematic[1][1])
	local turnRight = true
	if not stack then stack = 1 end
	for i = 1, stack do
		for k, floor in ipairs(state.schematic) do
			state.floor = k
			for l, sequence in ipairs(floor) do
				state.sequence = l
				state.block = 1
				print(tostring(k) .. "F: " .. formatSequence(sequence))
				for m, block in ipairs(sequence) do
					if block then
						if not turtl.useMaterial(block) then
							state.block = m
							turtl.saveState(state, getAbsolutePath(STATE_FILE))
							error("Out of blocks for slot " .. block .. ".")
						end
						while not turtl.placeBlock(true) do end
					else
						turtle.digDown()
					end
					if m < #sequence then
						turtl.fd(1, true)
					end
				end
				if l < #floor then
					turtl.turn(turnRight)
					turtl.fd(1, true)
					turtl.turn(turnRight)
					turnRight = not turnRight
				else
					if turnRight then
						turtl.move(-1 * (depth - 1), width - 1, 1, true)
						turtl.lt(2)
					else
						turtl.move(0, width - 1, 1, true)
						turtl.lt()
					end
				end
			end
		end
	end
end

function main(args)
	os.loadAPI("/turtle/turtl")
	local file = getAbsolutePath(args[1])
	local handle = fs.open(file, "r")
	if not handle then
		error("Could not open file '" .. file .. "' to read.")
	end
	local success, errmsg = pcall(parseSchematic, handle)
	handle.close()
	if not success then print(errmsg) end
	turtl.saveState(state, getAbsolutePath(STATE_FILE))
	print("Schematic read successfully, state saved...")
	build(args[2])
end
main({...})
--#file:turtle/dn
USAGE = [[
Move the turtle down.
Usage:
	dn (blocks force tries slot)
]]


args = {...}
if #args > 0 and (args[1] == "-h" or args[1] == "help" or args[1] == "-?") then
	print(USAGE)
else
	os.loadAPI("/turtle/turtl")
	turtl.down(unpack(args))
end
--#file:turtle/fd
USAGE = [[
Move the turtle forward.
Usage:
	fd (blocks force tries slot)
]]

args = {...}
if #args > 0 and (args[1] == "-h" or args[1] == "help" or args[1] == "-?") then
	print(USAGE)
else
	os.loadAPI("/turtle/turtl")
	turtl.fd(unpack(args))
end
--#file:turtle/fuel
USAGE = [[
Check the amount of fuel left.
Usage:
	fuel
]]


args = {...}
if #args > 0 and (args[1] == "h" or args[1] == "help" or args[1] == "?") then
	print(USAGE)
else
	print(turtle.getFuelLevel() .. " blocks")
end
--#file:turtle/lt
USAGE = [[
Turn left.
Usage:
	lt (times)
]]


args = {...}
if #args > 0 and (args[1] == "h" or args[1] == "help" or args[1] == "?") then
	print(USAGE)
else
	os.loadAPI("/turtle/turtl")
	turtl.lt(unpack(args))
end
--#file:turtle/read
os.loadAPI("turtle/turtl")
for k, v in pairs(turtl) do
	if not _G[k] then _G[k] = v end
end
z = sleep
turtl.reader()
--#file:turtle/refuel
USAGE = [[
Refuel the turtle.
Usage:
	refuel (QUANTITY) (SLOT)
]]


args = {...}
if #args > 0 and (args[1] == "h" or args[1] == "help" or args[1] == "?") then
	print(USAGE)
else
	if #args >= 2 then
		turtle.select(args[2])
	else
		turtle.select(1)
	end

	fuelBefore = turtle.getFuelLevel()
	if #args >= 1 then
		turtle.refuel(args[1])
	else
		turtle.refuel(1)
	end
	fuelAfter = turtle.getFuelLevel()
	fuelDiff = fuelAfter - fuelBefore
	print(string.format("Fuel: %d blocks (+%d)", fuelAfter, fuelDiff))
end
--#file:turtle/rt
USAGE = [[
Turn right.
Usage:
	rt (times)
]]


args = {...}
if #args > 0 and (args[1] == "h" or args[1] == "help" or args[1] == "?") then
	print(USAGE)
else
	os.loadAPI("/turtle/turtl")
	turtl.rt(unpack(args))
end
--#file:turtle/turtl
local TURTL = {
	FUEL_SLOT = 1,
	MIN_SLOT = 1,
	MAX_SLOT = 16,
}

OUT_OF_BUILDING_MATERIAL = 255

function isFinite(number)
	return number ~= 1/0 and number == number -- is not inf and is not NaN (NaN == NaN is false)
end

function checkFuel(slot, quantity)
	if not slot 	then slot = TURTL.FUEL_SLOT end
	if not quantity	then quantity = 1 end
	fuelLevel = turtle.getFuelLevel()
	if fuelLevel < 1 then
		if (slot > 0) then turtle.select(slot) end
		if turtle.refuel(quantity) then
			return true, fuelLevel
		else
			error("Out of fuel! (slot #" .. slot .. ")")
		end
	end
	return false, fuelLevel
end

function lt(times)
	if not times then times = 1 end
	for i = 1, times do
		turtle.turnLeft()
	end
end

function rt(times)
	if not times then times = 1 end
	for i = 1, times do
		turtle.turnRight()
	end
end

function turn(right, times)
	if right then
		rt(times)
	else
		lt(times)
	end
	return not right -- useful for moving in a snake pattern: fd-fd-rt-fd-rt-fd-fd-lt-fd-lt
end

function sidestep(right, times, force, tries, fuelslot)
	local turnToSide, turnForward
	if right then
		turnToSide  = rt
		turnForward = lt
	else
		turnToSide  = lt
		turnForward = rt
	end
	turnToSide()
	fd(times, force, tries, fuelslot)
	turnForward()
end

function fd(times, force, tries, fuelslot)
	if not times then times = 1 end
	if tries and tries < 0 then tries = nil end
	for i = 1, times do
		checkFuel(fuelslot)
		t = 0
		while not turtle.forward() do
			if not force or (tries and t == tries) then
				error("Can't go forward, there is something in the way.")
			end
			turtle.dig()
			os.sleep(0.5)
			t = t + 1
		end
	end
end

function down(times, force, tries, fuelslot)
	if not times then times = 1 end
	if tries and tries < 0 then tries = nil end
	for i = 1, times do
		checkFuel(fuelslot)
		t = 0
		while not turtle.down() do
			if not force or (tries and t == tries) then
				error("Can't go down, there is something in the way.")
			end
			turtle.digDown()
			os.sleep(0.5)
			t = t + 1
		end
	end
end

dn = down

function up(times, force, tries, fuelslot)
	if not times then times = 1 end
	if tries and tries < 0 then tries = nil end
	for i = 1, times do
		checkFuel(fuelslot)
		t = 0
		while not turtle.up() do
			if not force or (tries and t == tries) then
				error("Can't go up, there is something in the way.")
			end
			turtle.digUp()
			os.sleep(0.5)
			t = t + 1
		end
	end
end

function moveVertical(times, force, tries, fuelslot)
	if times > 0 then
		up(times, force, tries, fuelslot)
	else
		times = times * (-1)
		down(times, force, tries, fuelslot)
	end
end

function hasGps(timeout)
	timeout = timeout or 3
	return gps.locate(timeout) ~= nil
end

function readSignAsScript(p, separator)
	separator = separator or "@"
	pattern = "[^"..separator.."]+"
	results = {}
	stringResults = {}

	signText = table.concat({p.read()}) .. table.concat({p.readDown()}) .. table.concat({p.readUp()})
	if signText == "exit" then
		return signText
	elseif signText ~= "" then
		for seq in string.gmatch(signText, pattern) do
			local func, err = loadstring(seq)
			if func then
				table.insert(results, func)
				table.insert(stringResults, seq)
			else
				error("Bad script on sign:\n"..signText.."\n"..err)
			end
		end
	end
	return results, stringResults
end

function getReader(p)
	if not p then
		p = peripheral.wrap("right")
		if not p then
			peripheral.wrap("left")
			if not p then
				error("Wait, I can't read! Combine me with a sign first.")
			end
		end
	end
	if not p.read then
		error("I need a reader peripheral to read signs.")
	end
	return p
end

function reader(p, initialCmd, statefile, restart)
	p = getReader(p)
	statefile = statefile or "/.reader"
	local cmdStrings = (not restart and loadState(statefile)) or {initialCmd or "fd()"}
	local cmds = {}
	for i, v in ipairs(cmdStrings) do
		local cmd, err = loadstring(v)
		if not cmd then
			error("Initial command contains errors: " .. err)
		end
		cmds[i] = cmd
	end
	if statefile then print("Continuing from last state.") end

	local newCmds, newCmdStrings
	i = 1
	print("next: "..cmdStrings[1])
	while true do
		newCmds, newCmdStrings = readSignAsScript(p)
		if newCmds == "exit" then
			break
		elseif #newCmds > 0 then
			cmds = newCmds
			cmdStrings = newCmdStrings
			print(table.concat(cmdStrings, "\n"))
			saveState(cmdStrings, statefile)
			print("next: "..cmdStrings[1])
		end
		cmds[1]()
		if #cmds > 1 then
			table.remove(cmds, 1)
			table.remove(cmdStrings, 1)
			saveState(cmdStrings, statefile)
			print("next: "..cmdStrings[1])
		end
		sleep(0.1)
	end
	print("Done.")
end

function area(width, height, depth, force, tries, fuelslot)
	local fdStep, rtStep, upStep
	fdStep = depth  / depth -- {+1, -1}
	rtStep = width  / width
	upStep = height / height

	local turnRight = (rtStep > 0)
	local absWidth  = math.abs(width)
	local absHeight = math.abs(height)
	local absDepth  = math.abs(depth)
	local x, y, z, i   = 1, 1, 1, 0

	if fdStep < 0 then -- go backwards
		rt(2)
		turnRight = not turnRight
	end

	return function()
		if i > 0 then
			if z < absDepth then
				fd(1, force, tries, fuelslot)
				z = z + 1
			elseif z == absDepth then
				z = 1
				if x < absWidth then
					turn(turnRight)
					fd(1, force, tries, fuelslot)
					turnRight = turn(turnRight)
					x = x + 1
				elseif x == absWidth then
					x = 1
					if y < absHeight then
						moveVertical(upStep, force, tries, fuelslot)
						rt(2)
						y = y + 1
					elseif y == absHeight then
						rt(2)
						return
					end
				end
			end
		end
		i = i + 1
		return x * rtStep, y * upStep, z * fdStep, i
	end
end

-- the coordinates are relative to the turtle's orientation,
-- i. e. a positive width always points to the right.
function move(depth, width, height, force, tries, fuelslot)
	local az = math.abs(depth)
	local ax = math.abs(width)
	local ay = math.abs(height)

	if depth < 0 then --turn around
		lt(2)
	end
	fd(az, force, tries, fuelslot)
	if width > 0 then
		rt()
	else
		lt()
	end
	fd(ax, force, tries, fuelslot)
	if width > 0 then
		lt()
	else
		rt()
	end
	if height > 0 then
		up(ay, force, tries, fuelslot)
	else
		down(ay, force, tries, fuelslot)
	end
end

function slots(from, to)
	from = from or TURTL.MIN_SLOT
	to = to or TURTL.MAX_SLOT
	if from < 0 then from = TURTL.MAX_SLOT - from + 1 end
	if to < 0 then to = TURTL.MAX_SLOT - to + 1 end
	assert(	from >= TURTL.MIN_SLOT and
			from <= TURTL.MAX_SLOT and
			to >= TURTL.MIN_SLOT and
			to <= TURTL.MAX_SLOT
			)
	local step
	if from > to then step = -1 else step = 1 end
	local slot = from
	--print(string.format("from=%d, to=%d, step=%d", from, to, step))
	return function()
		if slot < TURTL.MIN_SLOT or slot > TURTL.MAX_SLOT then
			return
		else
			turtle.select(slot)
			local i = slot
			slot = slot + step
			return i
		end
	end
end

function getMaxStackSize(slot)
	return turtle.getItemCount(slot) + turtle.getItemSpace(slot)
end

function manageMaterial(matSlot, direction, keep, verbose)
	local stored = getAmount(matSlot)
	local noErrors, amountManaged
	local msg
	if stored > keep then
		msg = "Stored %d pieces of material #%d, keeping %d."
		noErrors, amountManaged = storeMaterial(matSlot, direction, keep)
	elseif stored < keep then
		msg = "Loaded %d pieces of material #%d, got a total of %d."
		noErrors, amountManaged = loadMaterial(matSlot, direction, keep)
	else
		msg = "No hauling."
		noErrors = true
		amountManaged = 0
	end
	if verbose then
		print(string.format(msg, amountManaged, matSlot, keep))
	end
	return noErrors, amountManaged
end
mgMat = manageMatterial

function drop(direction, amount)
	if not direction then
		return turtle.drop(amount)
	elseif direction == "up" or direction == 1 then
		return turtle.dropUp(amount)
	elseif direction == "down" or direction == -1 then
		return turtle.dropDown(amount)
	else
		error("Can't drop in direction '"..direction.."'.")
	end
end

function suck(direction)
	if not direction then
		return turtle.suck()
	elseif direction == "up" or direction == 1 then
		return turtle.suckUp()
	elseif direction == "down" or direction == -1 then
		return turtle.suckDown()
	else
		error("Can't suck in direction '"..direction.."'.")
	end
end


function getAmount(defSlot)
	local stored = 0
	turtle.select(defSlot)
	for slot = TURTL.MIN_SLOT, TURTL.MAX_SLOT do
		if turtle.compareTo(slot) then
			stored = stored + turtle.getItemCount(slot)
		end
	end
	return stored
end

function loadMaterial(defSlot, direction, targetAmount)
	assert(targetAmount >= 0)
	local noErrors = true
	local amountLoaded = 0
	turtle.select(defSlot)
	while getAmount(defSlot) < targetAmount do
		if not suck(direction) then
			error("Could not get materials from direction " .. tostring(direction) .. ".")
		end
	end
	return storeMaterial(defSlot, direction, targetAmount)
end
loadMat = loadMaterial


function storeMaterial(defSlot, direction, keepAmount)
	assert(keepAmount >= 0)
	local count = getAmount(defSlot)
	local noErrors = true
	if count <= keepAmount then
		return noErrors, count - keepAmount
	end
	local maxStackSize = getMaxStackSize(defSlot)
	local result = 0

	for slot = TURTL.MAX_SLOT, TURTL.MIN_SLOT, -1 do
		turtle.select(slot)
		if turtle.compareTo(defSlot) and slot ~= defSlot then
			local dropCount = math.min(count - keepAmount, turtle.getItemCount(slot), maxStackSize)
			if dropCount > 0 then
				if drop(direction, dropCount) then
					count = count - dropCount
					result = result + dropCount
				else
					noErrors = false
				end
			end
		end
	end
	local dropCount = math.min(count - keepAmount, turtle.getItemCount(defSlot), maxStackSize)
	if dropCount > 0 then
		turtle.select(defSlot)
		if drop(direction, dropCount) then
			count = count - dropCount
			result = result + dropCount
		else
			noErrors = false
		end
	end
	return noErrors, result
end
storeMat = storeMaterial


function useMaterial(defSlot, useLastItem)
	turtle.select(defSlot)
	for slot = TURTL.MAX_SLOT, TURTL.MIN_SLOT, -1 do
		if turtle.compareTo(slot) and slot ~= defSlot then
			turtle.select(slot)
			return slot
		end
	end
	if turtle.getItemCount(defSlot) > 0 or useLastItem then
		turtle.select(defSlot)
		return defSlot
	end
end
useMat = useMaterial

function fillSlot(slot)
	local count = turtle.getItemCount(slot)
	local space = turtle.getItemSpace(slot)
	local maxStackSize = count + space
	for s in slots(-1, 1) do
		if s ~= slot and turtle.compareTo(slot) then
			local amount = math.min(space, turtle.getItemCount(s))
			turtle.transferTo(slot, amount)
			space = space - amount
			if space <= 0 then return end
		end
	end
end

function placeBlock(replaceBlocks)
	if turtle.detectDown() then
		if not turtle.compareDown() and replaceBlocks then
			if not turtle.digDown() then
				return false
			end
		else
			return true
		end
	end
	return turtle.placeDown()
end
place = placeBlock

function saveState(state, filepath)
	local str = textutils.serialize(state)
	local handle = fs.open(filepath, "w")
	if not handle then
		error("Could not open file '" .. filepath .. "' to write.")
	end
	handle.write(str)
	handle.close()
end

function loadState(filepath)
	if not fs.exists(filepath) then	return end
	local handle = fs.open(filepath, "r")
		if not handle then
		error("Could not open file '" .. filepath .. "' to read.")
	end
	local str = handle.readAll()
	return textutils.unserialize(str)
end
--#file:turtle/up
USAGE = [[
Move the turtle up.
Usage:
	up (blocks force tries slot)
]]


args = {...}
if #args > 0 and (args[1] == "-h" or args[1] == "help" or args[1] == "-?") then
	print(USAGE)
else
	os.loadAPI("/turtle/turtl")
	turtl.up(unpack(args))
end