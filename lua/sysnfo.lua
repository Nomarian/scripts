
-- luacheck: no unused

-- This program works, however, weechat is HOSTILE to io.popen
-- io.popen randomly fails/succeeds, IDK why it happens
-- It seems to be some sort of race condition? but honestly, if that's how weechat is going to be
-- You're better off not writing any plugins in lua for it
-- Though, reading file does not lead to race conditions

local _G = _G
local M = {}
local env = {}
for k,v in pairs(_G) do M[k] = v end
local envmt = {
	__index = function (t,k)
		return M[k] or _G[k] or error(k, 2)
	end
	,__newindex = function (t,k,v)
		rawset(M,t,v)
	end
}
local _ENV = setmetatable(env, envmt)

-----------------------------

local weechat = _G.weechat
if weechat then
	local name = 'sysnfo'
	local author = 'khwerz+weechat@gmail.com'
	local version = 1
	local license = 'ISC'
	local description = 'displays system info'
	local shutdown_function = ""
	local charset = "" -- utf8
	weechat.register(
		name, author, version, license, description, shutdown_function, charset
	)
end

-----------------------------

-- THE EMPTY TABLE
local E = setmetatable({}, {
	__newindex = function (t,k) error("ASSIGNED TO E TABLE",3) end
})

----------------------------- Functions

-- WARNING: Do not use Save inside of a function, I REPEAT IT WILL BREAK EVERYTHING
local A, a = {} -- always a table, ?
local function Save(...) A, a = table.pack(...), ... return ... end

local Noop = function () end

local Exists = function -- filepath|""
(
	path -- filepath
)
	return os.rename(path,path) and path
end

local function GmatchT( -- returns {mat,ches, ...}
	str
	, patt -- str
)
	local T, i = {}, 0
	for m in str:gmatch(patt) do
		i = i+1
		T[i] = m
	end
	return T, i
end
string.GmatchT = GmatchT

local Which if os.getenv"PATH" or error'no $PATH found' then
	local path = os.getenv"PATH":gsub(":","/?;")
	function Which (executableS)
		return package.searchpath(executableS, path, "", "")
	end
end

local ShellArg = function -- string --
(
	argument -- string
)
	if argument then
		return "'" .. string.gsub(argument, "'","'\\''") .. "'"
	end
	return "''"
end

local ShellArgs = function -- string --
( -- returns arguments escaped for use in shell
	arguments -- string|table
)
	if type(arguments)=="table" then
		local t = arguments
		for i,v in ipairs(arguments) do
			t[i] = ShellArg(v)
		end
		return table.concat(t, " ")
	end
	return arguments
end

local function Run(cmd, mode) local S
	local H, status, msg, code = io.popen(ShellArgs(cmd))
	if H then
		S = H:read(mode or "l") or false
		status, msg, code = H:close()
	else
		return nil, status, msg, code, 'ERROR: POPEN FAILED'
	end
	return S, status, msg, code -- nil is error
end

local function RunS(cmd, mode)
	local S, status, msg, code = Run(cmd, mode)
	return S or '', status, msg, code
end

local bytesSpecifier = {"K","M","G","T","P","E","Z","Y","R","Q"} do
	local t = bytesSpecifier
	local b, B = 1, 1
	for _, byteSpecifier in ipairs(bytesSpecifier) do
		b, B = b*1000, B*1024
		t[byteSpecifier .. "b"] = b
		t[byteSpecifier:lower() .. "B"] = b
		t[byteSpecifier .. "iB"] = B
		t[byteSpecifier:lower() .. "iB"] = B
	end
	-- then you just / or * if you want to descend by this many
	-- kb -> pb
	-- 10 * bytesSpecifier.gB -> 10gb to bytes
	-- 10 / bytesSpecifier.gB -> 10 bytes to gb
end

local ReadableBytes = function -- string -- makes bytes human readable
( -- loop through bytesSpecifier array
	bytes -- num -- bytes, usually just
	,useStandardUnits -- bool -- 1000 or 1024
)
	if type(bytes)~="number" then
		return bytes
	end
	local i = 1
	local unit = useStandardUnits and 1000 or 1024
	while bytes>unit and bytesSpecifier[i] do
		i = i+1
		bytes = bytes / unit
	end
	return string.format("%.3g%s%s", bytes
		, bytesSpecifier[i-1] or bytesSpecifier[i]
		, useStandardUnits and "b" or "B"
	)
end

local ToBytes = function -- return num in bytes
(
	num -- num --
	,specifier -- string --
)
	return num * bytesSpecifier[specifier]
end

-----------------------------

--[[ Design:
	There's a giant conditional on uname/files in the middle
	this conditional fills (dump, info, infoptr, get) tables depending on the os
	dump is the cache and everything is saved here
	get stores functions which fill dump
		get[int] are functions which are refill dump (dynamic)
	info stores static items and gets items from dump
		infoptr is a fallback.__index of info
		infoptr points to the correct item on dump (if string)
		infoptr should also store functions
	A user configurable fmtstr is created which gets items from info[]
	before formatting it, get[*]() is run, this allows dynamic items to be up to date

	get: table
		str: -> function|nil
		int: -> function|nil
			regenerates items in dump[], a copy must exist in gets dictionary
	info: dict -> string|nil
		fallback is infoptr|dump
	infoptr: dict -> string|function|nil
		-> function() -> string
		str is pointer to dump[]
	dump: dict
		Every function stores keys here, this is the cache, which might be fetchable
		by info[] or infoptr[]
		Store items as PREFIX_ for storing variable output, like shell output
		Example: DF_filesystem
--]]

-- cache dump for getter functions
-- ADD A PREFIX LIKE DF_filesystem, never set anything directly and without prefix
-- unless you know its unique, On each print, dump gets wiped
local dump = {}

local info = {}
if Save( Run'uname -a' ) then
	info.os, info.hostname, info.osver = a:match"^(%g+) (%g+) (%g+)"
	info.arch = Run'uname -m'
else
	info = {
		os = os.getenv"HOSTOS" or os.getenv"GOOS" or Run'uname' or error"OS not found"
		,hostname = os.getenv"HOST" or Run"uname -n"
		,arch = os.getenv'HOSTARCH' or Run'uname -m'
		,osver = Run'uname -r'
	}
end

local infoptr = {} -- -> dump, save functions here
-- example: infoptr.StorageSize = "DF_Size" -> dump.DF_Size

setmetatable(info, {
	__index = function (T,k)
		local R = infoptr[k]
		if type(R)=="function" then return R() end
		return dump[R] or dump[k]
	end
})

-- get stores all functions for getting values, they usually fill dump[]
-- but they must be PREFIXED by their key like DF_Avail
-- ipairs(get) will regenerate values for dump[*]
local get = {} -- getters

-- info contains functions that grab stuff from dump, which is a cache
-- get contains functions that fill dump, this refetches everything
local function Refetch()
	for _,ReFetch in ipairs(get) do ReFetch() end
end


get.IniStorer = function(fileS, prefix)
	-- os-release parser
	if Exists(fileS) then
		for line in io.lines(fileS) do
			local key, val = line:match'^([^=]+)="?(.-)"?$'
			dump [prefix .. key] = tonumber(val) or val
		end
		return true
	end
	return false
end

get.df = function()
	local H = io.popen(ShellArgs{'df','-hl', os.getenv"HOME"})
	local headers, usage
	if H then
		headers, usage = H:read'l', H:read'l'
		H:close()
	end
	if headers and usage then
		headers = GmatchT(headers, "%S+")
			for i,v in ipairs(headers) do headers[v] = i end
		local store = GmatchT(usage, "%S+")
		for i,v in ipairs(headers) do
			dump["DF_" .. v ] = store[i]
		end
	end
end
	get.df()
	table.insert(get, get.df)
	info.StorageTotal = dump.DF_Size
	infoptr.StorageAvail = "DF_Avail"


if Save( Run("glxinfo","a") ) then -- all static
	local S = a
	info.VGACard = S:match"OpenGL renderer string:%s*([%g\t ]+)"
	info.VGAMem = S:match"Video memory:%s*([%g\t ]+)"
	dump.GLXVer = S:match"GLX version: ([%d.]+)"
elseif Save( Run('lspci', 'a') ) then
	dump.LSPCI_VGA = a:match'VGA[^:]+:%s+([^\n]+)'
	for slot, key, val in A[1]:gmatch'(%g+)%s+([^:]+):%s+([^\n]+)' do
		dump['LSPCI_' .. key] = val
	end
end


do -- uptime
	local patt =
		"^%s*([%d:]+)" -- current time
		.. "%s+up (.+)" -- uptime
		.. ",%s+(%d+) users?" -- users
		.. ",%s+load average:%s+(([%d.]+)[,%s]+([%d.]+)[,%s]+([%d.]+))$" -- loadavg
	get.uptime = function ()
		local S = RunS"uptime":gsub('%s+',' ')
		dump.UPTIME_current_time, dump.UPTIME_uptime, dump.UPTIME_users
			, dump.UPTIME_loadavg, dump.UPTIME_lavg1, dump.UPTIME_lavg2
			, dump.UPTIME_lavg3
		= S:match(patt)
	end
	table.insert(get, get.uptime)
	infoptr.uptime = "UPTIME_uptime"
	infoptr.loadavg = "UPTIME_lavg1"
end


-- Get OS
if
	get.IniStorer("/etc/os-release", "OS_") or get.IniStorer("/usr/lib/os-release", "OS_")
then
	info.OS = dump.OS_PRETTY_NAME or dump.OS_NAME or dump.OS_ID or info.os
elseif Save( io.popen"lsb_release -a" ) then -- lsb-release
	local H = A[1]
	H:read"l"
	for line in H:lines() do
		local key, val = line:match'^([^:]+):%s*(.+)%s*$'
		val = tonumber(val) or val
		dump["OS_" .. key] = val
	end
	info.OS = dump.OS_Description
else
	info.OS = info.os
end


if info.os=="Linux" then
	infoptr.StorageUse = "DF_Use%"

	-- This gets distro name, you can also run lsb-release
	if Exists"/proc" then
		if Exists"/proc/cpuinfo" then
			for line in io.lines"/proc/cpuinfo" do
				local key, val = line:match'^([^:]-)%s*:%s*(.*)$'
				val = tonumber(val) or val
				if key then dump["CPUINFO_" .. key] = val end
			end
		-- IDK another method to get cpuinfo, maybe sysinfo? getconfig?
		end
		info.CPU = dump["CPUINFO_model name"]
		if Exists"/proc/meminfo" then
			get.Meminfo = function ()
				local R = {}
				for line in io.lines"/proc/meminfo" do
					local key, val, size = line:match"^([^:]+):%s*(%d+)%s*(%S*)$"
					val = tonumber(val) or val
					-- It seems everything is in kB?
					if size=="" then
						val = val or 0
					elseif size:find"^%ai?[Bb]$" then
						val = ToBytes(val, size)
					else
						error( string.format(
							'LINE:[%s]\nsize "%s" is not (kB or empty)'
							, line, size
						))
					end -- val is in bytes now
					val = ReadableBytes(val)
					R[key] = val
					dump["MEM_" .. key] = val -- some static things here so
				end
				return R
			end
			get.Meminfo() table.insert(get, get.Meminfo)
			info.MemTotal = dump.MEM_MemTotal -- static
			info.SwapTotal = dump.MEM_SwapTotal -- static
			infoptr.MemFree = "MEM_MemFree"
			infoptr.MemUse = "MEM_Active"
			infoptr.SwapFree = "MEM_SwapFree"
			infoptr.SwapUse = "MEM_SwapCached"
		end
		-- memory total is static, free/vmstat/top gives free memory
		-- RunS("free -h", "a")
	end
elseif os=='OpenBSD' then
	infoptr.StorageUse = "DF_Capacity"
end

-----------------------------

local function GsubFormatter(all, start, str, close)
	local R = str
	if start=='{' and close=='}' then -- variable
		R = os.getenv(str)
		if R then return R end
		R = info[str] or dump[infoptr[str]] or dump[str]
		local t = type(R)
		return
			t=='string' and R
			or t=='number' and R
			or t=='table' and table.concat(R, ' ')
			or t=='function' and R()
			or '??'
	elseif start=='(' and close==')' then -- shell command
		local S, status, msg, code = Run(str, 'l')
		return status and S or code
	elseif start=='/' and close=='/' then -- pattern/search
		for k,v in pairs(dump) do
			if k:find(str) then return v end
		end
		return '??'
	end
	return R
end

-- search(pattern) searches dump for pattern and returns val, key
-- $/pattern in dump/
-- $(shell command)
-- ${os.getenv or info or dump}
local function Formatter(fmtstr)
	Refetch()
	local newstr = fmtstr
		:gsub("($([({/])([^})/]+)([)}/]))", GsubFormatter)
		:gsub(';;','•')
		:gsub('[\t\n\r]',' • ')
	dump = {} -- GARBAGE OUT
	collectgarbage()
	return newstr
end

local format = "os: ${OS}" -- Usually OS_PRETTY_NAME, or just uname depending on the OS
	.. "	cpu: ${CPU}"
	.. "	ram: ${MemTotal} (${MemFree} free)"
	.. "	swap: ${SwapTotal} (${SwapFree} free)"
	.. "	storage: ${StorageAvail} / ${StorageTotal} (${StorageUse})"
	.. (info.VGAMem and "	vga: ${VGACard}" or "	vga: ${LSPCI_VGA}")
	.. "	uptime: ${uptime}"
	-- Optionals?

----------------------------- Weechat

if weechat then local w = weechat
	--[[ TODO:
		irc colors
	--]]
	info.irc_client = "Weechat"
	info.irc_version = w.info_get("version", "")
	format = "client: Weechat"
		.. (info.irc_version and (' (%s)'):format(info.irc_version) or '')
		.. " ;; " .. format
	-- w.print('', Formatter(format)) -- REMOVEME
	-- w.print('', w.config_is_set_plugin'sysinfo')
	if w.config_is_set_plugin'sysinfo'==0 then
		w.config_set_plugin('format', format)
	end

	local OK = w.WEECHAT_RC_OK
	do
		function _G.F(data, buffer, args)
			local newformat = w.config_string( w.config_get'plugins.var.lua.sysnfo.format' )
			local Action, msg = w.print, Formatter(newformat or format)
			if args=='channel' then -- say in buffer
				Action, msg = w.command, '/say ' .. msg
			end
			Action(buffer, msg)
			return OK
		end
		local name = 'sysnfo'
		local desc = 'Display system info'
		local args = '[channel]'
		local argdesc = 'Say to current channel'
		local completion = 'channel' -- %(irc_channels)'
		local callback = ''
		local hook = w.hook_command(name, desc, args, argdesc, completion, "F", callback)
	end
	return OK
end

----------------------------- Main

local function MAIN()
	Refetch()
	local T = {}
	for k,v in pairs(info) do
		table.insert(T,
			string.format("%s: %s", k, type(v)=="function" and v() or v)
		)
	end
	for k,v in pairs(infoptr) do
		table.insert(T,
			string.format("%s: %s", k, dump[v])
		)
	end
	table.sort(T)
	return table.concat(T, " * ")
end

print(collectgarbage"count")
print( MAIN() )
print"" print""
print(Formatter(format))
print(collectgarbage"count")
os.exit(0)
