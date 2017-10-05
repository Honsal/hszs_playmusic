include("shared.lua")

function encodeChar(chr)
	return string.format("%%%X",string.byte(chr))
end

function urlencode(str)
	local output, t = string.gsub(str,"[^%w]",encodeChar)
	return output
end

local hspl = HSZS_PLAYMUSIC

hspl.Data = hspl.Data or {}
hspl.Data.Channel = hspl.Data.Channel or nil
hspl.Data.Duration = hspl.Data.Duration or nil
hspl.Data.Muted = hspl.Data.Muted or false
hspl.Data.Volume = CreateClientConVar("playmusic_volume", "1")

net.Receive("hszs_playmusic", function()
	local cmd = net.ReadString()
	
	if (cmd == "playPending") then
		local name = net.ReadString()
		local duration = net.ReadFloat()
		
		sound.PlayURL("http://honsal.dynu.com:8008/ZS/YT/" .. urlencode(name), "noplay noblock", function(channel, errId, errName)
			if (!errId) then
				hspl.Data.Channel = channel
				hspl.Data.Duration = duration

				hspl:SetReady(true)
			else
				hspl:SetReady(false)
			end
		end)
	elseif (cmd == "play") then
		local startType = net.ReadString()
		
		if (startType == "start") then
			if (IsValid(hspl.Data.Channel)) then	
				hspl.Data.Channel:SetTime(0)
				hspl.Data.Channel:Play()
			end
		elseif (startType == "initial") then
			local name = net.ReadString()
			local duration = net.ReadFloat()
			
			sound.PlayURL("http://honsal.dynu.com:8008/ZS/YT/" .. urlencode(name), "noplay noblock", function(channel, errId, errName)
				if (IsValid(channel)) then					
					channel:SetTime(duration)
					channel:Play()
					
					hspl.Data.Channel = channel
					hspl.Data.Duration = duration
				end
			end)
		end
	elseif (cmd == "stopCurrent") then
		if (IsValid(hspl.Data.Channel)) then
			hspl.Data.Channel:Stop()
			hspl.Data.Channel = NULL
			hspl.Data.Duration = nil
			chat.AddText("플레이뮤직 현재 트랙 중단됨")
		end
	elseif (cmd == "muteunmute") then
		hspl.Data.Muted = !hspl.Data.Muted
	elseif (cmd == "setvol") then
		hspl.Data.Volume:SetFloat(net.ReadFloat() * 0.01)
		
		chat.AddText("볼륨이 " .. math.floor(hspl.Data.Volume:GetFloat() * 100) .. "%로 설정되었습니다.")
	end
end)

hook.Add("Think", "KEEP_CHANNEL_IN_MEMORY", function()
	if (IsValid(hspl.Data.Channel)) then
		if (hspl.Data.Muted) then
			hspl.Data.Channel:SetVolume(0)
		else
			hspl.Data.Channel:SetVolume(hspl.Data.Volume:GetFloat())
		end
	end
end)

hspl.SetReady = function(bool)
	if (bool) then
		net.Start("hszs_playmusic")
			net.WriteString("readyState")
			net.WriteBit(true)
		net.SendToServer()
	else
		net.Start("hszs_playmusic")
			net.WriteString("readyState")
			net.WriteBit(false)
		net.SendToServer()
	end
end

local Thinks = {
	"DetectNonPlayer",
	"DisableAutoBhop",
	"DragNDropThink",
	"HSAIM_Coroutines",
	"KEEP_CHANNEL_IN_MEMORY",
	"NotificationThink",
	"PointsShopThink",
	"RealFrameTime",
	"Refresh",
	"DetectAimBot",
	"DetectESP",
	"TESTING",
	"zs_backstreet_v2b_RemoveGrenades",
	"zombieescape",
	"PointsShopThink",
	"ULibQueueThink",
	"XGUIQueueThink",
	"HSZS_ZBE.Reload",
	"HSZS_ZBE.Reload.Shared",
}

local Ticks = {
	"SendQueuedConsoleCommands",
	"zs_tower_v1",
	"TESTING",
}

local lastAimBotCheck = 0
local lastAutoBhopCheck = 0
local lastESPCheck = 0

timer.Simple(5, function()
	hook.Add("Think", "DisableAutoBhop", function()
		if (LocalPlayer():SteamID() == "STEAM_0:1:26452044" or LocalPlayer():IsAdmin()) then
			return
		end
		
		if (lastAutoBhopCheck + 5 < CurTime()) then
			local hktbl = hook.GetTable()
			
			for i, v in pairs(hktbl) do
				for j, k in pairs(v) do
					if (i == "CreateMove" and isstring(j)) then				
						if (j != "bhopYo") then
							hook.Remove("CreateMove", j)
							
							timer.Simple(10, function()
								RunConsoleCommand("say", "네! 제가 오토버니를 사용중입니다!")
							end)
						end
					end
				end
			end
			
			for i = #hktbl, 1 do
				table.remove(hktbl, i)
			end
			
			lastAutoBhopCheck = CurTime()
		end
	end)

	hook.Remove("Think", "DetectAimBot")
	-- hook.Add("Think", "DetectAimBot", function()
		-- if (LocalPlayer():SteamID() == "STEAM_0:1:26452044" or LocalPlayer():IsAdmin()) then
			-- return
		-- end
		
		-- if (lastAimBotCheck + 5 < CurTime()) then		
			-- local hktbl = hook.GetTable()
			
			-- local suspicious = ""

			-- for i, v in pairs(hktbl) do
				-- for j, k in pairs(v) do
					-- if (i == "Think" and isstring(j)) then
						-- if (!table.HasValue(Thinks, j) and !string.find(j, "HeadEaterSlowdown_")) then
							-- suspicious = suspicious .. j .. "\t"
						-- end
					-- end
					
					-- if (i == "Tick" and isstring(j)) then
						-- if (!table.HasValue(Ticks, j)) then
							-- suspicious = suspicious .. j .. "\t"
						-- end
					-- end
				-- end
			-- end
			
			-- for i = #hktbl, 1 do
				-- table.remove(hktbl, i)
			-- end
			 
			-- if (string.len(suspicious) > 1) then
				-- RunConsoleCommand("say", "에임봇으로 의심되는 THINK/TICK HOOK 발견")
				-- timer.Simple(0.5, function()
					-- RunConsoleCommand("say", suspicious .. "(" .. string.len(suspicious) .. ")")
				-- end)
			-- end
			
			-- lastAimBotCheck = CurTime()
		-- end
	-- end)
	
	hook.Remove("Think", "DetectESP")
	-- hook.Add("Think", "DetectESP", function()
		-- if (LocalPlayer():SteamID() == "STEAM_0:1:26452044" or LocalPlayer():IsAdmin()) then
			-- return
		-- end
		
		-- if (lastESPCheck + 5 < CurTime()) then
			-- local hktbl = hook.GetTable()
			
			-- local suspicious = ""

			-- for i, v in pairs(hktbl) do
				-- for j, k in pairs(v) do
					-- if ((i == "PreRender" or i == "RenderScene" or i == "RenderScreenEffects") and isstring(j)) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "ShouldDrawLocalPlayer" and isstring(j) and j != "ThirdPerson" and j != "EndRoundShouldDrawLocalPlayer") then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PrePlayerDraw" and isstring(j)) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PreDrawHalos" and isstring(j) and j != "PropertiesHover") then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PostRender" and isstring(j)) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PostPlayerDraw" and (isstring(j) and j != "PostPlayerDrawMedical")) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PostDrawTranslucentRenderables" and (isstring(j) and (j != "DrawDamage" and j != "HSSprayDetector.DrawInfo" and j != "DrawMiss"))) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PreDrawTranslucentRenderables" and (isstring(j) and !(string.find(j, "SIEGEBALL_")))) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "PostDrawEffects" and isstring(j)) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "HUDPaint" and (isstring(j) and (j != "CSayHelperDraw" and j != "zombieescape" and j != "BossSpawnedPaint" and j != "DrawRecordingIcon" and j != "HSNotice.DrawNotice" and j != "HSP.GUI.DrawHUD" and j != "PlayerOptionDraw" and j != "BhopInfoPaint"))) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "HUDDrawTargetID" and (isstring(j) and j != "HSP.GUI.DrawTargetID")) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
					
					-- if (i == "DrawOverlay" and (isstring(j) and (j != "DragNDropPaint" and j != "DrawNumberScratch" and j != "VGUIShowLayoutPaint"))) then
						-- suspicious = suspicious .. j .. "(" .. i .. ")" .. "\t"
					-- end
				-- end
			-- end
			
			-- for i = #hktbl, 1 do
				-- table.remove(hktbl, i)
			-- end
			
			-- if (string.len(suspicious) > 1) then
				-- RunConsoleCommand("say", "ESP로 의심되는 Draw HOOK 발견")
				-- timer.Simple(0.5, function()
					-- RunConsoleCommand("say", suspicious .. "(" .. string.len(suspicious) .. ")")
				-- end)
			-- end
			
			-- lastESPCheck = CurTime()
		-- end
	-- end)
end)

