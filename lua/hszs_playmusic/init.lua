AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local hspl = HSZS_PLAYMUSIC

hspl.Data = hspl.Data or {}
hspl.Data.MusicQueue = hspl.Data.MusicQueue or {}
hspl.Data.NextPlayTime = hspl.Data.NextPlayTime or 0
hspl.Data.CurrentPlaying = hspl.Data.CurrentPlaying or {}
hspl.Data.PlayPendingList = hspl.Data.PlayPendingList or {}
hspl.Data.NextVoteList = hspl.Data.NextVoteList or {}
hspl.Data.SkipVotes = hspl.Data.SkipVotes or {}

hspl.Config = {}
hspl.Config.MaxQueueSize = 3
hspl.Config.PlayDelayPerPerson = 30
hspl.Config.PrivateListPath = "playmusic/plist"

if (!file.Exists(hspl.Config.PrivateListPath, "data")) then
	file.CreateDir(hspl.Config.PrivateListPath, "data")
end

util.AddNetworkString("hszs_playmusic")

local _queue = {
	__index = {
		GetPlayer = function(self)
			return self._pl
		end,
		GetPlayerName = function(self)
			if (self._pl:IsValid()) then
				return _pl:GetName()
			end
		end,
		SetPlayer = function(self, pl)
			self._pl = pl
		end,
		GetDuration = function(self)
			return self._duration
		end,
		SetDuration = function(self, duration)
			self._duration = tonumber(duration)
		end,
		GetName = function(self)
			return self._name
		end,
		SetName = function(self, name)
			self._name = name
		end,
	}
}

local MakeQueue = function(pl, name, duration)
	local queue = {}
	setmetatable(queue, _queue)
	
	queue:SetPlayer(pl)
	queue:SetName(name)
	queue:SetDuration(duration)
	
	return queue
end

local MakePrivateList = function(title, url, duration)
	return {
		Title = title,
		Url = url,
		Duration = duration,
	}
end

hspl.GetPlayerQueueCount = function(self, pl)
	local queues = self:GetQueue()
	
	local count = 0
	
	for i, v in pairs(queues) do
		if (v:GetPlayer() == pl) then
			count = count + 1
		end
	end
	
	return count
end

hspl.InsertQueue = function(self, pl, name, duration)
	if (self:GetPlayerQueueCount(pl) >= self.Config.MaxQueueSize) then
		ulx.tsay(NULL, (pl:IsValid() and pl:Nick() or "SERVER") .. "님의 큐 대기열이 꽉 찼기 때문에 더이상 예약할 수 없습니다.")
		MsgC(Color(200, 0, 0), (pl:IsValid() and pl:Nick() or "SERVER"), "님께서 대기열이 꽉 찬 플레이뮤직 큐 예약 시도.\n")
		return false
	end

	local queue = MakeQueue(pl, name, duration)
	
	table.insert(self:GetQueue(), queue)
	
	return queue
end

hspl.PopQueue = function(self)
	local queue = self:GetQueue()[1]
	
	if (queue == nil) then
		return nil
	end
	
	table.remove(self:GetQueue(), 1)
	
	return queue
end

hspl.GetQueue = function(self)
	return self.Data.MusicQueue
end

hspl.ConvertUrl = function(self, pl, url)
	http.Fetch("http://localhost:8888/?reqConvert=" .. url, function(body)
		if (body == "ERROR: COULD NOT RECEIVE VIDEO DATA") then
			self:ConvertErrorCallback(pl, "이미 처리중인 URL이거나 처리할 수 없는 URL입니다.")
		elseif (body == "OVER 6 MIN") then
			self:ConvertErrorCallback(pl, "10분이 넘는 음악은 재생할 수 없습니다.")
		else
			local exploded = string.Explode("|", body)
			self:ConvertCallback(pl, url, exploded[1], exploded[2])
		end
	end, function(err)
		self:ConvertErrorCallback(pl, "플레이뮤직 컨버팅 서버가 닫혀있습니다.")
	end)
end

hspl.ConvertCallback = function(self, pl, url, name, durationStr)	
	local queue = self:InsertQueue(pl, name, tonumber(durationStr))
	
	if (queue) then
		local plStr = (pl:IsValid() and pl:Nick() or "SERVER")
		ulx.tsay(NULL, plStr .. "님께서 PlayMusic을 예약했습니다: " .. name .. ", " .. durationStr)
		MsgC(Color(0, 192, 0), plStr, "님께서 예약한 PlayMusic: ", name, ", ", url, ", ", durationStr, "초\n")
	end
end

hspl.ConvertErrorCallback = function(self, pl, err)
	ulx.tsay(NULL, err)
	MsgC(Color(0, 192, 0), err, "\n")
end 

hspl.PrintMessage = function(self, pl, msg)
	local func = (!pl:IsValid() and function(pl, msg) MsgC(msg, "\n") end or function(pl, msg) pl:PrintMessage(HUD_PRINTTALK, msg) end)
	
	func(pl, msg)
end

hspl.GetQueueByPlayer = function(self, pl)
	local queue = self:GetQueue()
	
	local _queue = {}
	
	for i, v in pairs(queue) do
		if (v:GetPlayer() == pl) then
			_queue[i] = table.Copy(v)
		end
	end
	
	return _queue
end

hspl.Dequeue = function(self, pl, idx)
	if (self:GetQueue()[idx] != nil) then
		table.remove(self:GetQueue(), idx)
		self:PrintMessage(pl, idx .. "번째 트랙이 제거되었습니다.")
	else
		self:PrintMessage(pl, idx .. "번째 트랙이 존재하지 않습니다.")
	end
end

hspl.PlayQueue = function(self, queue) 
	net.Start("hszs_playmusic")
		net.WriteString("playPending")
		net.WriteString(queue:GetName())
		net.WriteFloat(queue:GetDuration())
	net.Broadcast()
	
	self.Data.CurrentPlaying = queue
	self.Data.PlayPendingList = player.GetAll()
	self.Data.PlayPendingCount = 0
end

hook.Add("PlayerInitialSpawn", "HSZS_PLAYMUSIC_PlayerInitialSpawn", function(pl)
	local self = hspl
	
	local current = self.Data.CurrentPlaying
	
	if (self.Data.NextPlayTime > CurTime()) then
		net.Start("hszs_playmusic")
			net.WriteString("play")
			net.WriteString("initial")
			net.WriteString(current:GetName())
			net.WriteFloat(current:GetDuration() - (self.Data.NextPlayTime - CurTime()))
		net.Send(pl)
	end 
end)

net.Receive("hszs_playmusic", function(len, pl)
	local cmd = net.ReadString()
	
	if (cmd == "readyState") then
		local ready = net.ReadBit()
		
		for i = table.Count(hspl.Data.PlayPendingList), 1, -1 do
			local _pl = hspl.Data.PlayPendingList[i]
			
			if (_pl == pl || _pl == NULL) then
				local plNick = (pl:IsValid() and pl:Nick() or "UNKNOWN")
				table.remove(hspl.Data.PlayPendingList, i)
				-- ulx.tsay(NULL, plNick .. "님의 트랙 펜딩이 완료됨..." .. table.Count(hspl.Data.PlayPendingList))
				MsgC(plNick .. "님의 트랙 펜딩이 완료됨", "\n")
		
				local cnt = table.Count(hspl.Data.PlayPendingList)
				  
				if (cnt == 0) then
					hspl:PlayPendedQueue()
				end
			end
		end
	end
end)

hspl.PlayPendedQueue = function(self)
	ulx.tsay(NULL, "모든 플레이어의 펜딩이 완료되었습니다. 플레이 시작.")
	MsgC("모든 플레이어의 펜딩이 완료되었습니다. 플레이 시작.\n")
	net.Start("hszs_playmusic")
		net.WriteString("play")
		net.WriteString("start")
	net.Broadcast()
	
	self.Data.NextPlayTime = CurTime() + self.Data.CurrentPlaying:GetDuration()
end
 
hspl.CrProcessQueueBody = function()
	local self = hspl

	while(true) do
		coroutine.yield()
		
		if (self.Data.NextPlayTime < CurTime()) then
			local queue = self:PopQueue()
			
			if (queue) then
				self:PlayQueue(queue)
				self.Data.NextPlayTime = CurTime() + queue:GetDuration()
			end
		end
	end
end

hspl.CrProcessQueue = coroutine.create(hspl.CrProcessQueueBody)

hspl.ProcessQueue = function(self)
	if (coroutine.status(hspl.CrProcessQueue) == "dead") then
		MsgC("CrProcessQueue is dead. recreating...\n")
		hspl.CrProcessQueue = coroutine.create(hspl.CrProcessQueueBody)
	end
	
	coroutine.resume(hspl.CrProcessQueue)
end

hspl.RequestStopPlaying = function(self, pl, queue)
	if (istable(queue)) then
		net.Start("hszs_playmusic")
			net.WriteString("stopCurrent")
		net.Broadcast()
		
		self.Data.CurrentPlaying = nil
		self.Data.NextPlayTime = 0
		self.Data.PlayPendingList = {}
		self.Data.SkipVotes = {}
	end
end

hspl.IsPlaying = function(self)
	return istable(self.Data.CurrentPlaying) and self.Data.NextPlayTime > CurTime()
end

hspl.RequestMuteUnMutePlayer = function(self, pl)
	net.Start("hszs_playmusic")
		net.WriteString("muteunmute")
	net.Send(pl)
end

hspl.RequestSetVolume = function(self, pl, vol)
	net.Start("hszs_playmusic")
		net.WriteString("setvol")
		net.WriteFloat(vol)
	net.Send(pl)
end

hspl.GetNextVote = function(self, pl)
	if (pl == NULL) then
		return 0
	end
	
	local nextVote = hspl.Data.NextVoteList[pl:EntIndex()]
	
	return nextVote or 0
end

hspl.SetNextVote = function(self, pl, time)
	if (pl == NULL) then
		return
	end
	
	hspl.Data.NextVoteList[pl:EntIndex()] = time
end

hspl.SetNextVoteAfter = function(self, pl, after)
	self:SetNextVote(pl, CurTime() + after)
end

hspl.AddSkipVote = function(self, pl)
	if (pl == NULL) then
		return
	end
	
	local vote = self.Data.SkipVotes[pl:EntIndex()]
	
	if (vote) then
		hspl:PrintMessage(pl, "이미 이 트랙에 스킵 투표하셨습니다.")
	else
		self.Data.SkipVotes[pl:EntIndex()] = true
		self:SkipVoteCallback(pl)
	end
end

hspl.SkipVoteCallback = function(self, pl)
	local curVoteCount = table.Count(hspl.Data.SkipVotes)
	
	local destPlayerCount = 3
	
	ulx.tsay(NULL, pl:Nick() .. " 님께서 현재 트랙 스킵을 원합니다. (" .. curVoteCount .. "/" .. destPlayerCount .. ")")
	
	hspl:SetNextVoteAfter(pl, 240)
	
	if (curVoteCount == destPlayerCount) then
		hspl:RequestStopPlaying(NULL, hspl.Data.CurrentPlaying)
	end
end

hook.Add("Think", "HSZS_PLAYMUSIC_Think", function()
	hspl:ProcessQueue()
end)

concommand.Remove("playmusic")
concommand.Add("playmusic", function(pl, cmd, args, fullstr) 
	if (#args <= 0) then
		hspl:PrintMessage(pl, "사용법:")
		hspl:PrintMessage(pl, "!playmusic current: 현재 재생중인 곡 정보 보기")
		hspl:PrintMessage(pl, "!playmusic queue YOUTUBE_URL: 해당 youtube url 음원을 추출해 큐에 넣음")
		hspl:PrintMessage(pl, "!playmusic list: 모든 플레이어가 예약한 플레이뮤직 큐 보기")
		hspl:PrintMessage(pl, "!playmusic mylist: 자신이 예약한 플레이뮤직 큐와 번호 보기")
		hspl:PrintMessage(pl, "!playmusic dequeue idx: playmusic mylist에서 확인한 번호(idx)에 해당하는 큐 취소")
		hspl:PrintMessage(pl, "!playmusic dequeue all: 모든 플레이뮤직 큐 취소")
		hspl:PrintMessage(pl, "!playmusic stop: (현재 자신의 트랙이 플레이중이라면) 음악 중지, 어드민의 경우 현재 플레이중인 트랙 중지")
		hspl:PrintMessage(pl, "!playmusic pmute: 현재 플레이중인 음악 뮤트/뮤트 해제")
		hspl:PrintMessage(pl, "!playmusic vol [0-100]: 볼륨 설정")
		hspl:PrintMessage(pl, "!playmusic plist list: 1페이지 개인 리스트 보기")
		hspl:PrintMessage(pl, "!playmusic plist list idx: idx페이지 개인 리스트 보기")
		hspl:PrintMessage(pl, "!playmusic plist add YOUTUBE_URL: 해당 유튜브 음원을 개인 리스트에 등록")
		hspl:PrintMessage(pl, "!playmusic plist remove idx: idx에 해당되는 번호의 플레이뮤직을 개인 리스트에서 제거")
		
		if (pl:IsValid() and pl:IsAdmin()) then
			hspl:PrintMessage(pl, "!playmusic adequeue idx: playmusic list로 확인한 idx에 해당하는 트랙을 큐에서 제외")
			hspl:PrintMessage(pl, "!playmusic adequeue all: 모든 playmusic 큐 제외")
		end
	end
	
	local _cmd = string.lower(args[1])
	
	local _arg = ""
	
	if (#args >= 2) then
		for i = 2, #args do
			_arg = _arg .. (i > 2 and " " or "") .. args[i]
		end
	end
	
	if (_cmd == "current") then
		if (hspl.Data.CurrentPlaying and hspl.Data.NextPlayTime > CurTime()) then
			hspl:PrintMessage(pl, "현재 재생중: " .. hspl.Data.CurrentPlaying:GetName() .. ", " .. math.ceil(hspl.Data.CurrentPlaying:GetDuration() - (hspl.Data.NextPlayTime - CurTime())) .. "초 / " .. math.ceil(hspl.Data.CurrentPlaying:GetDuration()) .. "초")
		else
			hspl:PrintMessage(pl, "현재 재생중인 곡이 없습니다.")
		end
	elseif (_cmd == "queue") then
		hspl:ConvertUrl(pl, _arg)
	elseif (_cmd == "list") then
		for i, v in pairs(hspl:GetQueue()) do
			hspl:PrintMessage(pl, i .. ": " .. v:GetName() .. ", " .. v:GetDuration() .. "초")
		end
	elseif (_cmd == "mylist") then
		for i, v in pairs(hspl.Data.MusicQueue) do
			if (pl == v:GetPlayer()) then
				hspl:PrintMessage(pl, i .. ": " .. v:GetName() .. ", " .. v:GetDuration() .. "초")
			end
		end
	elseif (_cmd == "dequeue") then
		local isIdx = tonumber(_arg) != nil
		
		if (isIdx) then
			local idx = tonumber(_arg)
		
			local items = hspl:GetQueueByPlayer(pl)
			
			local idxExist = false
			
			for i, v in pairs(items) do
				if (i == idx) then
					idxExist = true
					break
				end
			end
			
			if (idxExist) then
				hspl:Dequeue(pl, idx)
			else
				hspl:PrintMessage(pl, idx .. "번째 큐가 존재하지 않습니다.")
			end
		elseif (_arg == "all") then
			local items = hspl:GetQueueByPlayer(pl)
			
			if (table.Count(items) > 0) then
				for i, v in pairs(items) do
					hspl:Dequeue(pl, i)
				end
			else
				hspl:PrintMessage(pl, "큐가 비어있습니다.") 
			end
		else
			hspl:PrintMessage(pl, "플레이뮤직 도움말: !playmusic")
		end
	elseif (_cmd == "adequeue") then
		local isIdx = tonumber(_arg) != nil
		
		if (isIdx) then
			local idx = tonumber(_arg)
			
			hspl:Dequeue(pl, idx)
		elseif (_arg == "all") then
			for i, v in pairs(hspl:GetQueue()) do
				hspl:Dequeue(pl, i)
			end
		else
			hspl:PrintMessage(pl, "플레이뮤직 도움말: !playmusic")
		end
	elseif (_cmd == "stop") then
		if (pl == NULL or pl:IsAdmin() or pl == hspl.Data.CurrentPlaying:GetPlayer()) then
			if (hspl:IsPlaying()) then
				hspl:RequestStopPlaying(pl, hspl.Data.CurrentPlaying)
			else
				hspl:PrintMessage(pl, "현재 플레이중인 트랙이 없습니다.")
			end
		end
	elseif (_cmd == "pmute") then
		if (hspl:IsPlaying()) then
			hspl:RequestMuteUnMutePlayer(pl)
		else
			hspl:PrintMessage(pl, "현재 플레이중인 트랙이 없습니다.")
		end
	elseif (_cmd == "vol") then
		local vol = tonumber(_arg)
		
		if (!vol or vol < 0 or vol > 100) then
			hspl:PrintMessage("볼륨은 숫자 0부터 100 사이로 입력해주세요.")
		else
			hspl:RequestSetVolume(pl, vol)
		end
	elseif (_cmd == "voteskip") then
		if (hspl:IsPlaying()) then
			local nextVote = hspl:GetNextVote(pl)
			
			if (nextVote > CurTime()) then
				hspl:PrintMessage(pl, "스킵 투표를 다시 사용할 수 있을 때까지 " .. math.ceil(hspl:GetNextVote(pl) - CurTime()) .. "초 남았습니다.")
			else
				hspl:AddSkipVote(pl)
			end
		else
			hspl:PrintMessage(pl, "현재 플레이중인 트랙이 없습니다.")
		end
	elseif (_cmd == "plist") then
		if (_arg == "") then
			hspl:PrintPrivateList(pl)
		elseif (tonumber(_arg)) then
			local idx = tonumber(_arg)
			
			local plist = hspl:GetPrivateList(pl)
			
			local max = #plist
			
			if (idx > max || idx < 1) then
				hspl:PrintMessage(pl, "개인 리스트의 범위를 벗어났습니다. !playmusic plist list 명령어로 사용 가능한 리스트를 확인하세요.")
			else
				local data = plist[idx]
				hspl:PrintMessage(pl, data.Title .. " [" .. data.Duration .. "] 요청 중...")
				hspl:ConvertUrl(pl, data.Url)
			end
		else
			local exploded = string.Explode(" ", _arg)
			
			local subcmd = exploded[1]
			local subarg = exploded[2]
			
			if (subcmd == "list") then
				if (!subarg) then
					hspl:PrintPrivateList(pl)
				elseif (tonumber(subarg)) then
					local idx = tonumber(subarg)
					
					hspl:PrintPrivateList(pl, idx)
				end
			elseif (subcmd == "add") then
				if (!subarg) then
					hspl:PrintMessage(pl, "사용법: !playmusic plist add 유튜브주소")
				else
					local url = ""
					
					for i = 2, #exploded do
						url = url .. exploded[i]
					end
					
					if (string.find(url, "youtu.be/", 1, true) or string.find(url, "youtube.com/watch?v=", 1, true)) then
						hspl:AddPrivateList(pl, url)
					else
						hspl:PrintMessage(pl, "잘못된 주소를 입력하셨습니다.")
					end
				end
			elseif (subcmd == "remove") then
				if (!tonumber(subarg)) then
					hspl:PrintMessage(pl, "사용법: !playmusic plist remove 트랙ID")
				else
					local idx = tonumber(subarg)
					
					hspl:RemovePrivateList(pl, idx)
				end
			end
		end
	end
end)
 
hspl.AddPrivateList = function(self, pl, url)
	http.Fetch("http://localhost:8888/?reqConvert=" .. url, function(body)
		if (body == "ERROR: COULD NOT RECEIVE VIDEO DATA") then
			self:ConvertErrorCallback(pl, "이미 처리중인 URL이거나 처리할 수 없는 URL입니다.")
		elseif (body == "OVER 6 MIN") then
			self:ConvertErrorCallback(pl, "7분이 넘는 음악은 재생할 수 없습니다.")
		else
			local exploded = string.Explode("|", body)
			self:PrivateListCallback(pl, url, exploded[1], exploded[2])
		end
	end, function(err)
		self:ConvertErrorCallback(pl, "플레이뮤직 컨버팅 서버가 닫혀있습니다.")
	end)
end

hspl.RemovePrivateList = function(self, pl, idx)
	local plist = self:GetPrivateList(pl)
	
	if (table.Count(plist) > 0) then
		local data = plist[idx]
		
		if (!data) then
			hspl:PrintMessage(pl, "해당 번호의 트랙이 없습니다.")
		else
			local title = data.Title
			local duration = data.Duration
		
			table.remove(plist, idx)
			
			if (hspl:SavePrivateList(pl, plist)) then
				hspl:PrintMessage(pl, idx .. ", " .. title .. " [" .. duration .. "], 성공적으로 제거되었습니다.")
			end
		end
	else
		hspl:PrintMessage(pl, "개인 리스트가 비어있습니다.")
	end
end

hspl.SavePrivateList = function(self, pl, plist)
	file.Write(hspl:GetPrivateListPath(pl), util.TableToJSON(plist))
	
	if (file.Exists(self:GetPrivateListPath(pl), "DATA")) then
		return true
	end
	
	return false
end

hspl.PrivateListCallback = function(self, pl, url, title, duration)
	local data = MakePrivateList(title, url, duration)
	
	self:WritePrivateList(pl, data)
end

hspl.WritePrivateList = function(self, pl, data)
	local existList = self:GetPrivateList(pl)
	
	local alreadyExist = false
	
	for i, v in pairs(existList) do
		if (v.Url == data.Url) then
			alreadyExist = i
			break
		end
	end
	
	if (alreadyExist) then
		hspl:PrintMessage(pl, "해당 트랙은 이미 " .. alreadyExist .. "번째 리스트에 저장돼 있습니다.")
		return
	end
	
	table.insert(existList, data)
	
	file.Write(self:GetPrivateListPath(pl), util.TableToJSON(existList))
	
	if (file.Exists(self:GetPrivateListPath(pl), "DATA")) then
		local idx = #existList
		local title = data.Title
		local duration = data.Duration
		hspl:PrintMessage(pl, idx .. ": " .. title .. " [" .. duration .. "] , 성공적으로 저장되었습니다.")
	end
end

hspl.GetPrivateListPath = function(self, pl)
	if (pl == NULL) then
		return self.Config.PrivateListPath .. "/server.txt"
	else
		return self.Config.PrivateListPath .. "/" .. pl:UniqueID() .. ".txt"
	end
end

hspl.GetPrivateList = function(self, pl)	
	local path = self:GetPrivateListPath(pl)
	
	if (file.Exists(path, "DATA")) then
		local tbl = util.JSONToTable(file.Read(path, "DATA"))
		
		return tbl
	else
		return {}
	end
end

hspl.PrintPrivateList = function(self, pl, idx)
	local plist = self:GetPrivateList(pl)
	
	local page = idx and idx or 1
	
	if (table.Count(plist) == 0) then
		hspl:PrintMessage(pl, "개인 리스트에 아무런 곡도 없습니다.")
	else
		local pgMin = (page - 1) * 10 + 1
		local pgMax = pgMin + 9
		
		if (pgMax > table.Count(plist)) then
			pgMin = math.Max(1, table.Count(plist) - 9)
			pgMax = table.Count(plist)
		end
		
		for i = pgMin, pgMax do
			local data = plist[i]
			
			hspl:PrintMessage(pl, i ..": " .. data.Title)
		end
	end
end

hook.Add("EndRound", "HSZS_PLAYMUSIC_EndRound", function(winner, nextmap)
	hook.Add("Think", "HSZS_PLAYMUSIC_EndRound", function()
		if (hspl:IsPlaying()) then
			hspl:RequestStopPlaying(NULL, hspl.Data.CurrentPlaying)	
		else
			hook.Remove("Think", "HSZS_PLAYMUSIC_EndRound")
		end
	end)
end)