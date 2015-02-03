--[[
	arc - a text file archiver for computercraft.
	(c)2012, written by Dominik 'lincore' Rosehnal. 
    This program is released into the public domain.
]]

USAGE = [[
arc is an archiver for text files.
Usage:
arc pack|p FILE1 (FILE2 ... FILEN) DEST
arc add|a  FILE1 (FILE2 ... FILEN) DEST
arc extract|x ARCHIVE (-ipvf) (-T DIR)
	(FILE1 (FILE2 ... FILEN))
arc man FILE
]]

MAN = [[
arc
Compiles multiple text files into a single file.
]]


KEY_Y = 21
KEY_N = 49

CTRL_PREFIX = "--#"
PACK_HEADER = CTRL_PREFIX .. "@arcpack"
FILE_HEADER = CTRL_PREFIX .. "file:"
NEWLINE = "\n"
ROM_DIR = "/rom"

END_OF_OPTS = "--"
OPT_PREFIX = "-"
OPT_VAL_OPTIONAL = 1
OPT_VAL_REQUIRED = 2

KNOWN_OPTIONS = {
	PACK = {
		v = {name = "verbose"},
		i = {name = "interactive"},
	},

	ADD = {
		v = {name = "verbose"},
	},

	EXTRACT = {
		T = {hasValue = OPT_VAL_REQUIRED, name = "dest"},
		i = {name = "interactive"},
		p = {name = "preserve"},
		v = {name = "verbose"},
		f = {name = "flat"},
	},
}

function main(args)
	print(shell.dir())
	if #args == 0 then
		print(USAGE)
		return
	end
	local operation = string.lower(args[1])
	local params, options
	if operation == "pack" or operation == "p" then
		options = stripOptions(KNOWN_OPTIONS.PACK, args)
		params = getPackParams(args)
		table.merge(params, options)
		pack(params)
	elseif operation == "add" or operation == "a" then
		options = stripOptions(KNOWN_OPTIONS.ADD, args)
		params = getPackParams(args)
		table.merge(params, options)
		pack(params, true)
	elseif operation == "extract" or operation == "x" then
		options = stripOptions(KNOWN_OPTIONS.EXTRACT, args)
		params = getExtractParams(args)
		table.merge(params, options)
		extract(params)
	elseif operation == "list" or operation == "l" then
		options = stripOptions({}, args)
		params = getListParams(args)
		list(params)
	elseif operation == "man" then
		saveManual(args)
	else
		error("Illegal operation. Use either pack, add or extract.\n" .. USAGE)
	end
end

function pack(params, append)
	local path, content
	local dest = getAbsolutePath(params.dest)
	local buffer = StringBuffer:new()
	if append then
		if not fs.exists(dest) then
			error("Can not append to file " .. dest .. ": does not exist.")
		end
	else
		buffer:add(PACK_HEADER .. NEWLINE)
	end

	for i, file in ipairs(params.files) do
		path = getAbsolutePath(file)
		assertIsExistingFile(path)
		content = getFileContent(path)
		buffer:add(FILE_HEADER .. file .. NEWLINE .. content .. NEWLINE)
	end
	local prompt = params.interactive and not append
	if canWrite(dest, prompt, params.preserve) then
		writeFile(dest, buffer:toString(), append)
		print("Ok.")
	else
		print("Aborted.")
	end
end

function extractFile(path, content, params)
	path = getAbsolutePath(fs.combine(params.dest, path))
	local dir = getDirectoryString(path)
		if not fs.exists(dir) then
		fs.makeDir(dir)
		if params.verbose then
			print("Created directory " .. dir .. ".")
		end
	end
	if canWrite(path, params.interactive, params.preserve) then
		writeFile(path, content)
		if params.verbose then
			print("Wrote '" .. path .. "'.")
		end
	else
		print("Skipped '" .. path .. "'.")
	end
end

function readArchivedFile(fileHandle)
	local buffer = StringBuffer:new()
	local eof = false
	local line
	repeat
		line = fileHandle.readLine()
		if line == nil or string.beginsWith(line, FILE_HEADER) then
			eof = true
		else
			buffer:add(line)
		end
	until eof
	return buffer:toString(NEWLINE), line
end

function parseArchive(archive, params)
	local handle = fs.open(archive, "r")
	if not isValidArcHeader(handle.readLine()) then
		error("Not an archive: " .. archive)
	end

	local line, content
	local files = {}
	line = handle.readLine()
	while line do
		local isFileHeader, path = string.beginsWith(line, FILE_HEADER)
		if isFileHeader then
			content, line = readArchivedFile(handle)
			table.insert(files, {path = path, content = content})
		end
	end
	return files
end

function list(params)
	local archive = getAbsolutePath(params.archive)
	assertIsExistingFile(archive)
	local archiveFiles = parseArchive(archive, params)
	local files = {}
	for _, file in ipairs(archiveFiles) do
		table.insert(files, file.path)
	end
	table.sort(files)
	for _, file in ipairs(files) do
		print("  " .. file)
	end
end

function extract(params)
	local archive = getAbsolutePath(params.archive)
	assertIsExistingFile(archive)
	local archiveFiles = parseArchive(archive, params)
	for _, file in ipairs(archiveFiles) do
		if #params.files == 0 or table.contains(params.files, file.path) then
			local path = file.path
			if params.flat then	__, path = getDirectoryString(file.path) end
			extractFile(path, file.content, params)
		end
	end
end

-- compile a table of parameters for the 'pack' operation to operate on,
-- i.e. files to pack and the destination file.
function getPackParams(args)
	assertMinArgCount(3, args, USAGE)
	local params = {files = {}}
	for i = 2, #args - 1 do
		local path = getAbsolutePath(args[i])
		if not fs.exists(path) then
			error("No such file: " .. path)
		elseif not fs.isDir(path) then
			table.insert(params.files, args[i])
		else
			pathCrawler(args[i], params.files)
		end
	end
	params.dest = args[#args]
	return params
end

-- compile a table of parameters for the 'unpack' operation to operate on,
-- i.e. the file to unpack and the directory to unpack into.
function getExtractParams(args)
	assertMinArgCount(2, args, USAGE)
	local params = {files = {}}
	params.archive = args[2]
	if #args > 2 then
		for i = 3, #arg do
			table.insert(params.files, args[i])
		end
	end
	params.dest = "."
	return params
end

function getListParams(args)
	assertMinArgCount(2, args, USAGE)
	local params = {files = {}}
	params.archive = args[2]
	return params
end


function isOption(arg)
	local isOpt, option = string.beginsWith(arg, OPT_PREFIX)
	if isOpt and arg then
		return option
	end
end

function validateOption(option, args, index, validOps)
	local result = {}
	local optionHasValue = false
	local options
	if string.len(option) > 1 then  -- allows options to be written together, like -fipT /foo/bar
		options = string.explode(option)
	else
		options = {option}
	end
	for i, o in ipairs(options) do
		if validOps[o] then
			local hasValue = validOps[o].hasValue
			local name = validOps[o].name
			if hasValue and i == #options and index < #args and not isOption(args[index+1]) then
				result[name] = args[index+1]
				optionHasValue = true
			elseif hasValue == OPT_VAL_REQUIRED then
				error("Option " .. o .. " requires a value." .. NEWLINE .. USAGE)
			else
				result[name] = true
			end
		else
			error(tostring(o) .. " is not a valid option." .. NEWLINE .. USAGE)
		end
	end
	return result, optionHasValue
end


function checkRequirements(options, validOps)
	for k, v in pairs(validOps) do
		if v.required and not options[v.name] then
			error("Missing required option '" .. k .. "'." .. NEWLINE .. USAGE)
		end
	end
end

function stripOptions(validOps, args)
	local options = {}
	local toStrip = {}
	for i, arg in ipairs(args) do
		if arg == END_OF_OPTS then
			table.insert(toStrip, i)
			break
		elseif isOption(arg) then
			local validates, optHasValue = validateOption(isOption(arg), args, i, validOps)
			table.merge(options, validates)
			table.insert(toStrip, i)
			if optHasValue then table.insert(toStrip, i + 1) end -- remove value of opt as well
		end
	end
	checkRequirements(options, validOps)
	table.strip(args, toStrip)
	return options
end

function pathCrawler(path, files)
	if string.beginsWith(getAbsolutePath(path), ROM_DIR) then
		print("Warning: " .. getAbsolutePath(path) .. " is read-only and will be skipped.")
		return
	end
	for _, file in ipairs(fs.list(path)) do
		local combinedPath = fs.combine(path, file)
		if fs.isDir(combinedPath) then
			pathCrawler(combinedPath, files)
		else
			table.insert(files, combinedPath)
		end
	end
	return files
end


-- Used to get rid of a trailing char event that would otherwise
-- outlast this program and end up on the command line as input.
function purgeEventQueue()
	os.startTimer(0.05)
	os.pullEvent()
end


-- Return a subset of path up to the last slash "/" (exclusive).
-- The function does only operate on the given string and will not
-- check whether path itself denotes an existing directory.
-- If path does not contain a slash the empty string is returned.
-- Example: getDirectoryString("/usr/bin/cmus") returns "/usr/bin"
function getDirectoryString(path)
	local pos = string.find(string.reverse(path), "/", 1, true)
	if not pos then
		return ""
	else
		pos = string.len(path) - pos
		return string.sub(path, 1, pos), string.sub(path, pos + 1)
	end
end

-- Return true if str begins with substr.
-- More precisely, return true if the substring of the first n
-- characters of str equals substr, where n is the length of
-- substr. Return false if str is shorter than substr or if
-- either str or substr are nil.
function string.beginsWith(str, substr)
	if not str or not substr then return false end
	if string.len(substr) > string.len(str) then return false end
	if str == substr then return true end
	return string.sub(str, 1, string.len(substr)) == substr, string.sub(str, string.len(substr) + 1)
end

function string.explode(str)
	local chars = {}
	for i = 1, string.len(str) do
		table.insert(chars, string.sub(str, i, i))
	end
	return chars
end

function assertMinArgCount(count, args, msg)
	if #args < count then
		error(msg or "Not enough arguments.")
	end
end



function assertIsExistingFile(path)
	if not fs.exists(path) then
		error("No such file: " .. path)
	elseif fs.isDir(path) then
		error("Expected a file, found a directory: " .. path)
	end
end

function assertIsExistingWritableDirectory(path)
	if not fs.exists(path) then
		error("No such directory: " .. path)
	elseif not fs.isDir(path) then
		error("Expected a directory, found a file: " .. path)
	elseif not fs.isReadOnly(path) then
		error("Can not extract to '" .. path .. "': is read only")
	end
end

function isValidArcHeader(line)
	return line == PACK_HEADER
end

function getFileContent(file)
	local handle = fs.open(file, "r")
	local result = handle.readAll()
	handle.close()
	return result
end

function writeFile(file, content, append)
	local mode
	if append then
		mode = "a"
	else
		mode = "w"
	end
	local handle = fs.open(file, mode)
	if not handle then
		error("Could not open location '" .. file .. "' to write.")
	end
	handle.write(content)
	handle.close()
end

function ask(question, yesIsDefault)
	print(question)
	if yesIsDefault then
		print("Y/n")
	else
		print("y/N")
	end
	term.setCursorBlink(true)
	local event, key = os.pullEvent("key")
	purgeEventQueue()
	if key == KEY_Y then
		return true
	elseif key == KEY_N then
		return false
	elseif yesIsDefault then
		return true
	else
		return false
	end
end


function canWrite(path, interactive, preserve)
	if fs.isDir(path) then
		error("Can not write to " .. path .. ": is a directory.")
	end
	if fs.exists(path) and not preserve and interactive then
		return ask("File '" .. path .. "' already exists,\nreplace it?")
	else
		return not preserve
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


function table.merge(table1, table2)
	for k, v in pairs(table2) do
		table1[k] = v
	end
	return table1
end

function table.clone(tabl)
	local result = {}
	for k, v in pairs(tabl) do
		result[k] = v
	end
	return result
end


function table.contains(tabl, value)
	for k, v in pairs(tabl) do
		if v == value then
			return k
		end
	end
end

-- print the contents of a table.
--	tabl:		the table to dump
--  recursive:	if true, also dump the contents of all elements that are tables themselves and so on.
--  depth:		should be an integer or nil, limits the recursion to the specified level.
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

function table.strip(tabl, indezes)
	table.sort(indezes, function(a, b) return a > b end) -- sort in descending order
	for _, index in ipairs(indezes) do
		table.remove(tabl, index)
	end
end

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

main({...})
