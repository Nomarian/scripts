#!/usr/bin/env lua

--[[
	Text shuffler
--]]

--[[
BSD Zero Clause License

Copyright © 2025 by khwerz@gmail.com

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
--]]

local V = _VERSION:match"%d%.%d+$"

if (V and tonumber(V) or 5)<5.3 then
	math.randomseed(os.time())
end
local unpack = unpack or table.unpack

local function Shuffle(text)
	if #text>7000 then return "TEXT TOO LONG" end
	local T = {text:byte(1, #text)}
	for i=1, #text do
		local rand = math.random(1,#text)
		T[rand], T[i] = T[i], T[rand] -- SWAP
	end
	return string.char( unpack(T) )
end

if _G.weechat==nil then -- its a command
	print(Shuffle(arg[1]))
	os.exit(0)
end

--------------------------- Weechat Section

local w = _G.weechat

do local name, author, version, license, description, shutdown_function, charset
 name		= "Shuffle"
 author 	= "Kumool"
 version	= "1.1.0"
 license	= "0BSD"
 description	= "Changes input"
 charset	= ""
 shutdown_function = ""
 w.register(name, author, version, license, description, shutdown_function, charset)
 w.print("","Loaded: " .. name)
end

-- semi global variables
local OK = w.WEECHAT_RC_OK

local t = {}

-- data, buffer, args(string)
function _G.Shuffle(d,b,a)
 if #a>0 then w.command( b, Shuffle(a) ) end
 return OK
end

table.insert(t, w.hook_command("Shuffle", "",
 "","","",
 "Shuffle","")
)
