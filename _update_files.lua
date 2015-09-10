#!/usr/bin/lua
-- requires lua file system
--  https://keplerproject.github.io/luafilesystem/
--  depending on your lua distribution it may be
--  installed already.

-- 

require "lfs"
local md5 = require "md5"


function config()
   -- Windows users: use '/' as directory separator, not '\'
   
   -- set manually to absolute ftb dir if $HOME is not defined:
   ftb_dir = joinpaths(get_home_dir(), "ftb")
   
   computers = {
      ["inf lab 0"] = "FTBInfinity/minecraft/saves/Lab/computer/0",
      ["inf lp 8"] = "FTBInfinity/minecraft/saves/New World/computer/8",
   }
   -- matched against the paths of all files and directories in the cwd and subdirs.
   -- paths are relative to the cwd, i.e. "foo/bar/turtledance"
   ignore = {
      "\\*%.$",              -- "." same dir link
      "\\*%.%.$",            -- ".." parent dir link
      "_update_files%.lua",  -- this script
      "\\*%.git",            -- git related
      "\\*%.gitignore",      --
      ".*~$",                -- emacs auto-backuped files
      "\\*#.*#$",            -- emacs auto-saved files
      "\\*%.#.*",            --
   }
end


function get_home_dir()
   local is_windows = package.config:sub(1,1) == "\\"
   local home
   if is_windows then
      home = os.getenv("AppData")      
      assert(home, "%AppData% not set. Please resolve this issue or set 'ftb_dir' manually in the script.")
      home = home:gsub("\\", "/")
   else
      home = os.getenv("HOME")
      assert(home, "$HOME not set. Please resolve this issue or set 'ftb_dir' manually in the script.")
   end
   return home
end

function joinpaths(base, rel)
   if not rel or rel == "" then
      return base
   elseif not base or base == "" then
      return rel
   end
   if #base > 1 and base:sub(-1) == "/" then
      base = base:sub(1, -2)
   end
   if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
   end
   return base .. "/" .. rel
end

function getmd5(file)
   local rb = io.open(file, "rb")
   local data = rb:read("*all")
   rb:close()
   return md5.sumhexa(data)
end


function isfile(path)
   local mode, err = lfs.attributes(path, "mode")
   return mode and mode == "file"
end

function isdir(path)
   local mode, err = lfs.attributes(path, "mode")
   return mode and mode == "directory"
end   

function init()
   assert(isdir(ftb_dir), "ftb_dir does not exist or is not a directory: " .. tostring(ftb_dir))
   for k,v in pairs(computers) do
      local path = ftp_dir .. "/" .. v
      assert(isdir(path), "path to '" .. tostring(k) .. "' does not exist or is not a directory: " .. tostring(path))
   end
end

function getfilename(path)
   return path:match("([^/]+)$")
end

function copyfile(source, dest)
   local rb = io.open(source, "rb")
   local data = rb:read("*all")
   rb:close()
   local wb = io.open(dest, "wb")
   wb:write(data)
   wb:close()
end



function match_any(str, patterns)
   for _,v in ipairs(patterns) do
      if str:match(v) then return true end
   end
   return false
end


function aggregate_files(basedir, reldir, files)
   files = files or {}
   local dir = joinpaths(basedir, reldir)
   for entry in lfs.dir(dir) do
      local abs = joinpaths(dir, entry)
      local rel = joinpaths(reldir, entry)
      if not match_any(rel, ignore) then
	 local mode = lfs.attributes(abs, "mode")	 
	 if mode == "directory" then
	    aggregate_files(basedir, rel, files)
	 elseif mode == "file" then
	    table.insert(files, {abs=abs, rel=rel, mode=mode})
	 end
      end
   end
   return files
end

function compare_files(basefile, compfile)
   if not basefile.modified then
      basefile.modified = lfs.attributes(basefile.abs, "modification")
   end
   local comp_modified = lfs.attributes(compfile, "modification")
   if comp_modified <= basefile.modified then
      return false
   end
   if not basefile.md5 then
      basefile.md5 = getmd5(basefile.abs)
   end
   local comp_md5 = getmd5(compfile)
   assert(basefile.md5 and comp_md5, "could not get md5 checksum.")
   return basefile.md5 ~= comp_md5 
end


function check_computer(computer, computerdir, basedir, files, options)
   for _, entry in ipairs(files) do
      local compfile = joinpaths(computerdir, entry.rel)
      local compmode = lfs.attributes(compfile, "mode")
      if compmode == "file"  then
	 if compare_files(entry, compfile) then
	    if options.verbose then
	       print(string.format("%s: getting %s", computer, entry.rel))
	    end
	    if not options.test_only then
	       copyfile(compfile, entry.abs)
	    end
	 elseif options.sync and not options.test_only then
	       print("Writing " .. compfile)
	       copyfile(entry.abs, compfile)
	 end
      end
   end
end

knownargs = {
   s = "sync",
   sync = "sync",
   v = "verbose",
   verbose = "verbose",
   t = "test_only",
   ["test-only"] = "test_only",
   d = "debug",
   debug = "debug",
}

function parseargs(args)
   local options = {}
   for _,v in ipairs(args) do
      if knownargs[v] then
	 options[knownargs[v]] = true
	 print("option: " .. knownargs[v])
      end
   end
   if options.debug then options.verbose = true end
   return options
end

function main(args)
   local options = parseargs(args)
   local cwd = lfs.currentdir()
   local files = aggregate_files(cwd)
   if options.debug then
      print("aggregated:")
      for _,v in ipairs(files) do
	 print("  " .. v.rel)
      end
   end
   for name, path in pairs(computers) do      
      if options.verbose then
	 print("Checking " .. name .. "...")
      end      
      check_computer(name, joinpaths(ftb_dir, path), cwd, files, options)
   end
end

config()
main{...}
