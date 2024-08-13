Queue = {}
Queue.Ready = false
Queue.Exports = nil
Queue.ReadyCbs = {}
Queue.CurResource = GetCurrentResourceName()
Queue.MaxPlayers = GetConvarInt('sv_maxclients', 30)
Queue.Debug = GetConvar('sv_debugqueue', 'true') == 'true' and true or false
Queue.DisplayQueue = GetConvar('sv_displayqueue', 'true') == 'true' and true or false
Queue.InitHostName = GetConvar('sv_hostname', '')

function Queue.OnReady(cb)
    if not cb then return end
    if Queue.IsReady() then cb() return end
    table.insert(Queue.ReadyCbs, cb)
end

function Queue.OnJoin(cb, resource)
    if not cb then return end
    local tmp = {resource = resource, func = cb}
    table_insert(_Queue.JoinCbs, tmp)
end

function Queue.AddPriority(id, power, temp)
    if not Queue.IsReady() then return end
    Queue.Exports:AddPriority(id, power, temp)
end

function Queue.RemovePriority(id)
    if not Queue.IsReady() then return end
    Queue.Exports:RemovePriority(id)
end

function Queue.IsReady()
    return Queue.Ready
end

function Queue.LoadExports()
    Queue.Exports = GetQueueExports()
    Queue.Ready = true
    Queue.ReadyCallbacks()
end

function Queue.ReadyCallbacks()
    if not Queue.IsReady() then return end
    for _, cb in ipairs(Queue.ReadyCbs) do
        cb()
    end
end

function Queue:HexIdToSteamId(hexId)
    local cid = math.floor(tonumber(string.sub(hexId, 7), 16))
	local steam64 = math.floor(tonumber(string.sub(cid, 2)))
	local a = steam64 % 2 == 0 and 0 or 1
	local b = math.floor(math_abs(6561197960265728 - steam64 - a) / 2)
	local sid = "steam_0:"..a..":"..(a == 1 and b -1 or b)
    return sid
end


-- This is needed because msgpack will break when tables are too large
_Queue = {}
_Queue.QueueList = {}
_Queue.PlayerList = {}
_Queue.PlayerCount = 0
_Queue.Priority = {}
_Queue.Connecting = {}
_Queue.JoinCbs = {}
_Queue.TempPriority = {}
_Queue.JoinDelay = GetGameTimer() + Config.JoinDelay and Config.JoinDelay or 0

for id, power in pairs(Config.Priority) do
    _Queue.Priority[string.lower(id)] = power
end

function Queue:DebugPrint(msg)
    if Queue.Debug then
        msg = "^3QUEUE: ^0" .. tostring(msg) .. "^7"
        print(msg)
    end
end


function Queue:IsSteamRunning(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if string.sub(id, 1, 5) == "steam" then
            return true
        end
    end
    
    return false
end

function Queue:GetPlayerCount()
    return _Queue.PlayerCount
end

function Queue:GetSize()
    return #_Queue.QueueList
end

function Queue:ConnectingSize()
    return #_Queue.Connecting
end

function Queue:GetQueueList()
    return _Queue.QueueList
end

function Queue:GetPriorityList()
    return _Queue.Priority
end

function Queue:GetPlayerList()
    return _Queue.PlayerList
end

function Queue:GetTempPriorityList()
    return _Queue.TempPriority
end

function Queue:GetConnectingList()
    return _Queue.Connecting
end

function Queue:IsInQueue(ids, rtnTbl, bySource, connecting)
    local connList = Queue:GetConnectingList()
    local queueList = Queue:GetQueueList()

    for genericKey1, genericValue1 in ipairs(connecting and connList or queueList) do
        local inQueue = false

        if not bySource then
            for genericKey2, genericValue2 in ipairs(genericValue1.ids) do
                if inQueue then break end

                for genericKey3, genericValue3 in ipairs(ids) do
                    if genericValue3 == genericValue2 then inQueue = true break end
                end
            end
        else
            inQueue = ids == genericValue1.source
        end

        if inQueue then
            if rtnTbl then
                return genericKey1, connecting and connList[genericKey1] or queueList[genericKey1]
            end

            return true
        end
    end

    return false
end

function Queue:IsPriority(ids)
    local prio = false
    local tempPower, tempEnd = Queue:HasTempPriority(ids)
    local prioList = Queue:GetPriorityList()

    for _, id in ipairs(ids) do
        id = string.lower(id)

        if prioList[id] then prio = prioList[id] break end

        if string.sub(id, 1, 5) == "steam" then
            local steamid = Queue:HexIdToSteamId(id)
            if prioList[steamid] then prio = prioList[steamid] break end
        end
    end

    if tempPower or prio then
        if tempPower and prio then
            return tempPower > prio and tempPower or prio
        else
            return tempPower or prio
        end
    end

    return false
end

function Queue:HasTempPriority(ids)
    local tmpPrio = Queue:GetTempPriorityList()

    for _, id in pairs(ids) do
        id = string.lower(id)

        if tmpPrio[id] then return tmpPrio[id].power, tmpPrio[id].endTime, id end

        if string.sub(id, 1, 5) == "steam" then
            local steamid = Queue:HexIdToSteamId(id)
            if tmpPrio[steamid] then return tmpPrio[steamid].power, tmpPrio[steamid].endTime, id end
        end
    end

    return false
end

function Queue:AddToQueue(ids, connectTime, name, src, deferrals,point,roleStrings)
    if Queue:IsInQueue(ids) then return end
    local tmp = {
        source = src,
        ids = ids,
        name = name,
        priority = Queue:IsPriority(ids) or (src == "debug" and math.random(0, 15)),
        timeout = 0,
        point = point,
        roleStrings = roleStrings,
        deferrals = deferrals,
        firstconnect = connectTime,
        queuetime = function() return (os.time() - connectTime) end
    }

    local _pos = false
    local queueCount = Queue:GetSize() + 1
    local queueList = Queue:GetQueueList()
    if Config.enableDiscordWhitelist then
        local tempPos = 0
        for pos, data in ipairs(queueList) do
            
            if data.point >= point then
                _pos = pos+1
            end
        end
    else
        for pos, data in ipairs(queueList) do
            if tmp.priority then
                if not data.priority then
                    _pos = pos
                else
                    if tmp.priority > data.priority then
                        _pos = pos
                    end
                end
                
    
                if _pos then
                    Queue:DebugPrint(string.format("%s[%s] was prioritized and placed %d/%d in queue", tmp.name, ids[1], _pos, queueCount))
                    break
                end
            end
        end
    end
    

    if not _pos then
        _pos = Queue:GetSize() + 1
        Queue:DebugPrint(string.format("%s[%s] was placed %d/%d in queue", tmp.name, ids[1], _pos, queueCount))
    end
    queueList[_pos] = tmp
end

function Queue:RemoveFromQueue(ids, bySource, byIndex)
    local queueList = Queue:GetQueueList()

    if byIndex then
        if queueList[byIndex] then
            queueList[byIndex] = nil
        end

        return
    end

    if Queue:IsInQueue(ids, false, bySource) then
        local pos, data = Queue:IsInQueue(ids, true, bySource)
        queueList[pos] = nil
    end
end

function Queue:TempSize()
    local count = 0

    for _pos, data in pairs(Queue:GetQueueList()) do
        if Queue:HasTempPriority(data.ids) then count = count +1 end
    end

    return count > 0 and count or false
end

function Queue:IsInConnecting(ids, bySource, refresh)
    local inConnecting, tbl = Queue:IsInQueue(ids, refresh and true or false, bySource and true or false, true)

    if not inConnecting then return false end

    if refresh and inConnecting and tbl then
        Queue:GetConnectingList()[inConnecting].timeout = 0
    end

    return true
end

function Queue:RemoveFromConnecting(ids, bySource, byIndex)
    local connList = Queue:GetConnectingList()

    if byIndex then
        if connList[byIndex] then
            connList[byIndex] = nil
        end

        return
    end

    for genericKey1, genericValue1 in ipairs(connList) do
        local inConnecting = false

        if not bySource then
            for genericKey2, genericValue2 in ipairs(genericValue1.ids) do
                if inConnecting then break end

                for genericKey3, genericValue3 in ipairs(ids) do
                    if genericValue3 == genericValue2 then inConnecting = true break end
                end
            end
        else
            inConnecting = ids == genericValue1.source
        end

        if inConnecting then
            connList[genericKey1] = nil
            return true
        end
    end

    return false
end

function Queue:AddToConnecting(ids, ignorePos, autoRemove, done)
    local function remove()
        if not autoRemove then return end

        done(Config.Language.connectingerr)
        Queue:RemoveFromConnecting(ids)
        Queue:RemoveFromQueue(ids)
        Queue:DebugPrint("Player could not be added to the connecting list")
    end

    local connList = Queue:GetConnectingList()

    if Queue:ConnectingSize() + Queue:GetPlayerCount() + 1 > Queue.MaxPlayers then remove() return false end
    
    if ids[1] == "debug" then
        connList[#connList+1] = {source = ids[1], ids = ids, name = ids[1], firstconnect = ids[1], priority = ids[1], timeout = 0}
        return true
    end

    if Queue:IsInConnecting(ids) then Queue:RemoveFromConnecting(ids) end

    local pos, data = Queue:IsInQueue(ids, true)
    if not ignorePos and (not pos or pos > 1) then remove() return false end

    connList[#connList+1] = data
    Queue:RemoveFromQueue(ids)

    return true
end

function Queue:GetIds(src)
    local ids = GetPlayerIdentifiers(src)
    local ip = GetPlayerEndpoint(src)

    ids = (ids and ids[1]) and ids or (ip and {"ip:" .. ip} or false)
    ids = ids ~= nil and ids or false

    if ids and #ids > 1 then
        for k, id in ipairs(ids) do
            if string.sub(id, 1, 3) == "ip:" and not Queue:IsPriority({id}) then ids[k] = nil end
        end
    end

    return ids
end

function Queue:AddPriority(id, power, temp)
    if not id then return false end

    if type(id) == "table" then
        for _id, power in pairs(id) do
            if _id and type(_id) == "string" and power and type(power) == "number" then
                Queue:GetPriorityList()[_id] = power
            else
                Queue:DebugPrint("Error adding a priority id, invalid data passed")
                return false
            end
        end

        return true
    end

    power = (power and type(power) == "number") and power or 10

    if temp then
        local tempPower, tempEnd, tempId = Queue:HasTempPriority({id})
        id = tempId or id

        Queue:GetTempPriorityList()[string.lower(id)] = {power = power, endTime = os.time() + temp} 
    else
        Queue:GetPriorityList()[string.lower(id)] = power
    end
    
    return true
end

function Queue:RemovePriority(id)
    if not id then return false end
    id = string.lower(id)
    Queue:GetPriorityList()[id] = nil
    return true
end

function Queue:UpdatePosData(src, ids, deferrals)
    local pos, data = Queue:IsInQueue(ids, true)
    data.source = src
    data.ids = ids
    data.timeout = 0
    data.firstconnect = os.time()
    data.name = GetPlayerName(src)
    data.deferrals = deferrals
end

function Queue:NotFull(firstJoin)
    local canJoin = Queue:GetPlayerCount() + Queue:ConnectingSize() < Queue.MaxPlayers
    if firstJoin and canJoin then canJoin = Queue:GetSize() <= 1 end
    return canJoin
end

function Queue:SetPos(ids, newPos)
    if newPos <= 0 or newPos > Queue:GetSize() then return false end

    local pos, data = Queue:IsInQueue(ids, true)
    local queueList = Queue:GetQueueList()

    queueList[pos] = nil
    queueList[newPos] = data
end

function Queue:CanJoin(src, cb)
    local allow = true
    
    for _, data in ipairs(_Queue.JoinCbs) do
        print(data)
        local await = true

        data.func(src, function(reason)
            if reason and type(reason) == "string" then allow = false cb(reason) end
            await = false
        end)

        while await do Citizen.Wait(0) end

        if not allow then return end
    end

    if allow then cb(false) end
end

function GetQueueExports()
    return Queue
end

local function playerConnect(name, setKickReason, deferrals)
    local src = source
    local ids = Queue:GetIds(src)
    local name = GetPlayerName(src)
    local connectTime = os.time()
    local connecting = true
    deferrals.defer()
    local point = 0
    local RoleStrings = ""
	if Config.AntiSpam then
		for i=Config.AntiSpamTimer,0,-1 do
			deferrals.update(string.format(Config.PleaseWait, i))
			Citizen.Wait(1000)
		end
	end

    Citizen.CreateThread(function()
        while connecting do
            Citizen.Wait(100)
            if not connecting then return end
            deferrals.update(Config.Language.connecting)
        end
    end)

    Citizen.Wait(500)

    local function done(msg, _deferrals)
        connecting = false

        local deferrals = _deferrals or deferrals

        if msg then deferrals.update(tostring(msg) or "") end

        Citizen.Wait(500)

        if not msg then
            deferrals.done()
            if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end
        else
            deferrals.done(tostring(msg) or "") CancelEvent()
        end

        return
    end

    local function update(msg, _deferrals)
        local deferrals = _deferrals or deferrals
        connecting = false
        deferrals.update(tostring(msg) or "")
    end

    if not ids then
        -- prevent joining
        done(Config.Language.idrr)
        CancelEvent()
        Queue:DebugPrint("Dropped " .. name .. ", couldn't retrieve any of their id's")
        return
    end
    local currentDiscordID = ""
    for k, v in ipairs(ids) do
        if string.sub(v, 1, string.len("discord:")) == "discord:" then
            currentDiscordID = v
        end
    end
    
    -- print(enableDiscordWhitelist)
    if Config.enableDiscordWhitelist then
        if Config.enableDiscordWhitelist and currentDiscordID == "" then
            -- prevent joining
            done(Config.Language.whitelist.noDiscord)
            CancelEvent()
            Queue:DebugPrint("Dropped " .. name .. ", couldn't retrieve Discord id")
            return
            
        else
            
            deferrals.update(Config.Language.whitelist.checkingRoles)
            -- deferrals.update(Config.Language..connecting)
            PerformHttpRequest("https://discord.com/api/v10/guilds/"..Config.discordServerGuild.."/members".."/"..string.sub(currentDiscordID, 9), function (errorCode, rdata, resultHeaders)
                local res=json.decode(rdata)
                if errorCode == 200 then
                    local roles = json.encode(res.roles)
    
                    for key, roleData in pairs(Config.Roles) do
                        if string.find(roles,roleData.roleID) then
                            print(roleData.point)
                            point = point + roleData.point
                            RoleStrings = RoleStrings .. key .." ,"
                        end
                    end
    
                end
            end, "GET", "", {["Content-type"] = "application/json", ["Authorization"] = "Bot " .. Config.discordBotToken})
            Wait(1000)
    
            
            print(point)
            if point > 0 then
                connecting = false
                deferrals.update(Config.Language.whitelist.checkingQueue)
    
            else
                done(Config.Language.whitelist.noRole)
                CancelEvent()
                return 
            end
        end
    end


    if Config.RequireSteam and not Queue:IsSteamRunning(src) then
        -- prevent joining
        done(Config.Language.steam)
        CancelEvent()
        return
    end

    local allow

    Queue:CanJoin(src, function(reason)
        if reason == nil or allow ~= nil then return end
        if reason == false or #_Queue.JoinCbs <= 0 then allow = true return end
        

        if reason then
            -- prevent joining
            allow = false
            done(reason and tostring(reason) or "You were blocked from joining")
            Queue:RemoveFromQueue(ids)
            Queue:RemoveFromConnecting(ids)
            Queue:DebugPrint(string.format("%s[%s] was blocked from joining; Reason: %s", name, ids[1], reason))
            CancelEvent()
            return
        end

        allow = true
    end) 

    while allow == nil do Citizen.Wait(0) end
    if not allow then return end

    if Config.PriorityOnly and not Queue:IsPriority(ids) then done(Config.Language.wlonly) return end

    local rejoined = false

    if Queue:IsInConnecting(ids, false, true) then
        Queue:RemoveFromConnecting(ids)

        if Queue:NotFull() then
            -- let them in the server

            if not Queue:IsInQueue(ids) then
                Queue:AddToQueue(ids, connectTime, name, src, deferrals,point,RoleStrings)
            end

            local added = Queue:AddToConnecting(ids, true, true, done)
            if not added then CancelEvent() return end
            done()

            return
        else
            rejoined = true
        end
    end

    if Queue:IsInQueue(ids) then
        rejoined = true
        Queue:UpdatePosData(src, ids, deferrals)
        Queue:DebugPrint(string.format("%s[%s] has rejoined queue after cancelling", name, ids[1]))
    else
        Queue:AddToQueue(ids, connectTime, name, src, deferrals,point,RoleStrings)

        if rejoined then
            Queue:SetPos(ids, 1)
            rejoined = false
        end
    end

    local pos, data = Queue:IsInQueue(ids, true)
    
    if not pos or not data then
        done(Config.Language.err .. " [1]")

        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)

        CancelEvent()
        return
    end

    if Queue:NotFull(true) and _Queue.JoinDelay <= GetGameTimer() then
        -- let them in the server
        local added = Queue:AddToConnecting(ids, true, true, done)
        if not added then CancelEvent() return end

        done()
        Queue:DebugPrint(name .. "[" .. ids[1] .. "] is loading into the server")

        return
    end
    
    update(string.format(Config.Language.pos .. ((Queue:TempSize() and Config.ShowTemp) and " (" .. Queue:TempSize() .. " temp)" or "00:00:00"), pos, Queue:GetSize(), ""))

    if rejoined then return end

    while true do
        Citizen.Wait(500)

        local pos, data = Queue:IsInQueue(ids, true)

        local function remove(msg)
            if data then
                if msg then
                    update(msg, data.deferrals)
                end

                Queue:RemoveFromQueue(data.source, true)
                Queue:RemoveFromConnecting(data.source, true)
            else
                Queue:RemoveFromQueue(ids)
                Queue:RemoveFromConnecting(ids)
            end
        end

        if not data or not data.deferrals or not data.source or not pos then
            remove("[Queue] Removed from queue, queue data invalid :(")
            Queue:DebugPrint(tostring(name .. "[" .. ids[1] .. "] was removed from the queue because they had invalid data"))
            return
        end

        local endPoint = GetPlayerEndpoint(data.source)
        if not endPoint then data.timeout = data.timeout + 0.5 else data.timeout = 0 end

        if data.timeout >= Config.QueueTimeOut and os.time() - connectTime > 5 then
            remove("[Queue] Removed due to timeout")
            Queue:DebugPrint(name .. "[" .. ids[1] .. "] was removed from the queue because they timed out")
            return
        end

        if pos <= 1 and Queue:NotFull() and _Queue.JoinDelay <= GetGameTimer() then
            -- let them in the server
            local added = Queue:AddToConnecting(ids)

            update(Config.Language.joining, data.deferrals)
            Citizen.Wait(500)

            if not added then
                done(Config.Language.connectingerr)
                CancelEvent()
                return
            end

            done(nil, data.deferrals)

            if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end

            Queue:RemoveFromQueue(ids)
            Queue:DebugPrint(name .. "[" .. ids[1] .. "] is loading into the server")
            return
        end

        local seconds = data.queuetime()
        local qTime = string.format("%02d", math.floor((seconds % 86400) / 3600)) .. ":" .. string.format("%02d", math.floor((seconds % 3600) / 60)) .. ":" .. string.format("%02d", math.floor(seconds % 60))

        local msg = string.format(Config.Language.pos .. ((Queue:TempSize() and Config.ShowTemp) and " (" .. Queue:TempSize() .. " temp)" or ""), pos, Queue:GetSize(), qTime)
        update(msg, data.deferrals)
    end
end
AddEventHandler("playerConnecting", playerConnect)

Citizen.CreateThread(function()
    local function remove(data, pos, msg)
        if data and data.source then
            Queue:RemoveFromQueue(data.source, true)
            Queue:RemoveFromConnecting(data.source, true)
        elseif pos then
            Queue:GetQueueList()[pos] = nil
        end
    end

    while true do
        Citizen.Wait(1000)
    
        local i = 1
    
        while i <= Queue:ConnectingSize() do
            local data = Queue:GetConnectingList()[i]
    
            local endPoint = GetPlayerEndpoint(data.source)
    
            data.timeout = data.timeout + 1
    
            if ((data.timeout >= 300 and not endPoint) or data.timeout >= Config.ConnectTimeOut) and data.source ~= "debug" and os.time() - data.firstconnect > 5 then
                remove(data)
                Queue:DebugPrint(data.name .. "[" .. data.ids[1] .. "] was removed from the connecting queue because they timed out")
            else
                i = i + 1
            end
        end

        for id, data in pairs(Queue:GetTempPriorityList()) do
            if os.time() >= data.endTime then
                Queue:GetTempPriorityList()[id] = nil
            end
        end
    
        Queue.MaxPlayers = GetConvarInt("sv_maxclients", 30)
        Queue.Debug = GetConvar("sv_debugqueue", "true") == "true" and true or false
        Queue.DisplayQueue = GetConvar("sv_displayqueue", "true") == "true" and true or false

        local qCount = Queue:GetSize()

        if Queue.DisplayQueue then
            if Queue.InitHostName then
                SetConvar("sv_hostname", (qCount > 0 and "[" .. tostring(qCount) .. "] " or "") .. Queue.InitHostName)
            else
                Queue.InitHostName = GetConvar("sv_hostname")
                Queue.InitHostName = Queue.InitHostName ~= "default FXServer" and Queue.InitHostName or false
            end
        end
    end
end)

RegisterServerEvent("Queue:playerActivated")
AddEventHandler("Queue:playerActivated", function()
    local src = source
    local ids = Queue:GetIds(src)

    if not Queue:GetPlayerList()[src] then
        _Queue.PlayerCount = Queue:GetPlayerCount() + 1
        Queue:GetPlayerList()[src] = true
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    local ids = Queue:GetIds(src)

    if Queue:GetPlayerList()[src] then
        _Queue.PlayerCount = Queue:GetPlayerCount() - 1
        Queue:GetPlayerList()[src] = nil
        Queue:RemoveFromQueue(ids)
        Queue:RemoveFromConnecting(ids)
        if Config.EnableGrace then Queue:AddPriority(ids[1], Config.GracePower, Config.GraceTime) end
    end
end)



AddEventHandler("onResourceStart", function(resourceName)
    local announce=false
    Queue:DebugPrint("^1 [connectqueue] Disabling hardcap ^7")
    if Config.DisableHardCap then
        if resourceName == "hardcap" then CancelEvent() return end
        StopResource("hardcap")
    end

    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    if Queue.DisplayQueue and Queue.InitHostName then
        SetConvar("sv_hostname", Queue.InitHostName)
    end
    
    if Config.enableDiscordWhitelist then
        PerformHttpRequest("https://discord.com/api/v10/guilds/"..Config.discordServerGuild, function (errorCode, resultData, resultHeaders)
            if errorCode == 200 then
                PerformHttpRequest("https://discord.com/api/v10/guilds/"..Config.discordServerGuild.."/preview", function (errorCode, rdata, resultHeaders)
                    local res=json.decode(rdata)
                    if errorCode == 200 then
                        if not announce then
                            announce=true
                        print('^6 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n  Bot Connect To '..res.name..' Server  \n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                        end
                    elseif errorCode == 403 then
                        if not announce then
                            announce=true
                            print('^1 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n xxxxxxxxxxxxxx Please Invite / ReInvite Bot xxxxxxxxxxxxxx \n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                        end
                    elseif errorCode == 401 then
                        if not announce then
                            announce=true
                            print('^1 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n xxxxxxxxxxxxxx Please Check Discord Token xxxxxxxxxxxxxx\n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                        end
                    end
                  end, "GET", "", {["Content-type"] = "application/json", ["Authorization"] = "Bot " .. Config.discordBotToken})
            elseif errorCode == 403 then
                if not announce then
                    announce=true
                    print('^1 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n xxxxxxxxxxxxxx Please Invite/ReInvite Bot xxxxxxxxxxxxxx \n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                end
            elseif errorCode == 401 then
                if not announce then
                    announce=true
                    print('^1 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n xxxxxxxxxxxxxx Please Check Discord Token xxxxxxxxxxxxxx\n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                end
            else
                if not announce then
                    announce=true
                    print('^1 xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \n xxxxxxxx Please Check Discord Token and Guild ID xxxxxxxx\n xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
                end

            end
          end, "GET", "", {["Content-type"] = "application/json", ["Authorization"] = "Bot " .. Config.discordBotToken})
    end
    Queue.LoadExports()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    Queue.Ready = false
    Queue.Exports = nil

    if Queue.DisplayQueue and Queue.InitHostName then SetConvar("sv_hostname", Queue.InitHostName) end
    
    for k, data in ipairs(_Queue.JoinCbs) do
        if data.resource == resourceName then
            _Queue.JoinCbs[k] = nil
        end
    end
end)



local testAdds = 0
local commands = {}

commands.addq = function()
    Queue:DebugPrint("ADDED DEBUG QUEUE")
    Queue:AddToQueue({"steam:110000103fd1bb1"..testAdds}, os.time(), "TestAdd: " .. testAdds,math.random(1,100), "debug",100,"DeBUG 100")
    testAdds = testAdds + 1
end

commands.addqq = function()
    Queue:DebugPrint("ADDED DEBUG QUEUE")
    Queue:AddToQueue({"steam:110000103fd1bb1"..testAdds}, os.time(), "TestAdd: " .. testAdds,math.random(1,100), "debug",10,"DeBUG 10")
    testAdds = testAdds + 1
end

commands.removeq = function(args)
    args[1] = tonumber(args[1])
    local name = Queue:GetQueueList()[args[1]] and Queue:GetQueueList()[args[1]].name or nil
    Queue:RemoveFromQueue(nil, nil, args[1])
    Queue:DebugPrint("REMOVED " .. tostring(name) .. " FROM THE QUEUE")
end

commands.printq = function()
    Queue:DebugPrint("CURRENT QUEUE LIST")

    for pos, data in ipairs(Queue:GetQueueList()) do
        Queue:DebugPrint(pos .. ": [src: " .. data.source .. "] " .. data.name .. "[" .. data.ids[1] .. "] | Priority: " .. (tostring(data.priority and data.priority or false)) .. " | Last Msg: " .. (data.source ~= "debug" and GetPlayerLastMsg(data.source) or "debug") .. " | Timeout: " .. data.timeout .. " | Queue Time: " .. data.queuetime() .. " Seconds")
    end
end

commands.addc = function()
    Queue:AddToConnecting({"debug"})
    Queue:DebugPrint("ADDED DEBUG CONNECTING QUEUE")
end

commands.removec = function(args)
    args[1] = tonumber(args[1])
    local name = Queue:GetConnectingList()[args[1]] and Queue:GetConnectingList()[args[1]].name or nil
    Queue:RemoveFromConnecting(nil, nil, args[1])
    Queue:DebugPrint("REMOVED " .. tostring(name) .. " FROM THE CONNECTING LIST")
end

commands.printc = function()
    Queue:DebugPrint("CURRENT CONNECTING LIST")

    for pos, data in ipairs(Queue:GetConnectingList()) do
        Queue:DebugPrint(pos .. ": [src: " .. data.source .. "] " .. data.name .. "[" .. data.ids[1] .. "] | Priority: " .. (tostring(data.priority and data.priority or false)) .. " | Last Msg: " .. (data.source ~= "debug" and GetPlayerLastMsg(data.source) or "debug") .. " | Timeout: " .. data.timeout)
    end
end

commands.printl = function()
    for k, joined in pairs(Queue:GetPlayerList()) do
        Queue:DebugPrint(k .. ": " .. tostring(joined))
    end
end

commands.printp = function()
    Queue:DebugPrint("CURRENT PRIORITY LIST")

    for id, power in pairs(Queue:GetPriorityList()) do
        Queue:DebugPrint(id .. ": " .. tostring(power))
    end
end

commands.printcount = function()
    Queue:DebugPrint("Player Count: " .. Queue:GetPlayerCount())
end

commands.printtp = function()
    Queue:DebugPrint("CURRENT TEMP PRIORITY LIST")

    for k, data in pairs(Queue:GetTempPriorityList()) do
        Queue:DebugPrint(k .. ": Power: " .. tostring(data.power) .. " | EndTime: " .. tostring(data.endTime) .. " | CurTime: " .. tostring(os.time()))
    end
end

commands.removetp = function(args)
    if not args[1] then return end

    Queue:GetTempPriorityList()[args[1]] = nil
    Queue:DebugPrint("REMOVED " .. args[1] .. " FROM THE TEMP PRIORITY LIST")
end

commands.setpos = function(args)
    if not args[1] or not args[2] then return end

    args[1], args[2] = tonumber(args[1]), tonumber(args[2])

    local data = Queue:GetQueueList()[args[1]]

    Queue:SetPos(data.ids, args[2])

    Queue:DebugPrint("SET " .. data.name .. "'s QUEUE POSITION TO: " .. args[2])
end

commands.setdata = function(args)
    if not args[1] or not args[2] or not args[3] then return end
    args[1] = tonumber(args[1])

    local num = tonumber(args[3])
    local data = Queue:GetQueueList()[args[1]]

    if args[2] == "queuetime" then
        local time = data.queuetime()
        local dif = time - num

        data.firstconnect = data.firstconnect + dif
        data.queuetime = function() return (os.time() - data.firstconnect) end
    else
        data[args[2]] = num and num or args[3]
    end

    Queue:DebugPrint("SET " .. data.name .. "'s " .. args[2] .. " DATA TO " .. args[3])
end

commands.commands = function()
    for cmd, func in pairs(commands) do
        Queue:DebugPrint(tostring(cmd))
    end
end

AddEventHandler("rconCommand", function(command, args)
    if command == "queue" and commands[args[1]] then
        command = args[1]
        args[1] = nil
        commands[command](args)
        CancelEvent()
    end
end)

SetTimeout(1, function() Queue.LoadExports() end)