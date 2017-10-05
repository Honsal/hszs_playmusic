if SERVER then
	include ("hszs_playmusic/init.lua")
	AddCSLuaFile ("hszs_playmusic/cl_init.lua")
	AddCSLuaFile ("hszs_playmusic/shared.lua")
end

if CLIENT then
	include ("hszs_playmusic/cl_init.lua")
end