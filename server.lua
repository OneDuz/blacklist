function sendToDiscordDebug(webhookUrl, message)
    local discordData = {
        ["embeds"] = {{
            ["title"] = "DEBUG",
            ["description"] = message,
            ["type"] = "rich",
            ["color"] = 65280,
            ["footer"] = {
                ["text"] = os.date("%Y-%m-%d %H:%M:%S", os.time())
            }
        }}
    }
    PerformHttpRequest(webhookUrl, function(err, text, headers) end, 'POST', json.encode(discordData), { ['Content-Type'] = 'application/json' })
end

function sendToDiscordActionLog(webhookUrl, title, message)
    local discordData = {
        ["embeds"] = {{
            ["title"] = title,
            ["description"] = message,
            ["type"] = "rich",
            ["color"] = 16711680,
            ["footer"] = {
                ["text"] = os.date("%Y-%m-%d %H:%M:%S", os.time())
            }
        }}
    }
    PerformHttpRequest(webhookUrl, function(err, text, headers) end, 'POST', json.encode(discordData), { ['Content-Type'] = 'application/json' })
end




local waitingList = {}

local function LoadBans()
	local content = LoadResourceFile(GetCurrentResourceName(), "bans.json")
	if content then
		local bans = json.decode(content)
		if bans then
            sendToDiscordDebug(config.debugWebhookUrl, "Ban list loaded successfully with " .. #bans .. " entries.")
			print("Ban list loaded successfully with " .. #bans .. " entries.")
			return bans
		else
            sendToDiscordDebug(config.debugWebhookUrl, "Failed to parse bans.json - file might be corrupted.")
			print("Failed to parse bans.json - file might be corrupted.")
		end
	else
        sendToDiscordDebug(config.debugWebhookUrl, "No bans.json file found - starting with an empty ban list.")
		print("No bans.json file found - starting with an empty ban list.")
	end
	return {}
end

local banList = LoadBans()


function SaveWaitingList()
	SaveResourceFile(GetCurrentResourceName(), "waitinglist.json", json.encode(waitingList), -1)
	print("Waiting list saved with " .. #waitingList .. " entries.")
end

local function LoadWaitingList()
    local content = LoadResourceFile(GetCurrentResourceName(), "waitinglist.json")
    if content then
        local waitlist = json.decode(content)
        if waitlist then
            local waitingListInfo = "Waiting List:\n"
            for i, entry in ipairs(waitlist) do
                waitingListInfo = waitingListInfo .. string.format("Entry #%d: License: %s | Reason: %s | Since: %s\n", i, entry.license, entry.reason, entry.timestamp)
            end
            sendToDiscordDebug(config.debugWebhookUrl, waitingListInfo)

            print("Waiting list loaded successfully with " .. #waitlist .. " entries.")
            return waitlist
        else
            sendToDiscordDebug(config.debugWebhookUrl, "Failed to parse waitinglist.json - file might be corrupted.")
            print("Failed to parse waitinglist.json - file might be corrupted.")
        end
    else
        sendToDiscordDebug(config.debugWebhookUrl, "No waitinglist.json file found - starting with an empty waiting list.")
        print("No waitinglist.json file found - starting with an empty waiting list.")
    end
    return {}
end


waitingList = LoadWaitingList()

function SaveBans()
	SaveResourceFile(GetCurrentResourceName(), "bans.json", json.encode(banList), -1)
    sendToDiscordDebug(config.debugWebhookUrl, "Ban list saved with " .. #banList .. " entries.")
	print("Ban list saved with " .. #banList .. " entries.")
end

local function isPlayerWhitelisted(source)
	local identifiers = GetPlayerIdentifiers(source)
	for _, id in pairs(identifiers) do
		if id == "steam:11000014e99295e" then
			return true
		end
	end
	return false
end

function IsPlayerBanned(identifiers, tokens)
	for _, ban in ipairs(banList) do
		for _, id in pairs(identifiers) do
			if ban.identifiers[id] then
				return true, ban
			end
		end
		for _, token in pairs(tokens) do
			if ban.tokens[token] then
				return true, ban
			end
		end
	end
	return false
end

function GetPlayerIdentifiersAndTokens(source)
	local identifiers, tokens = {}, {}
	for i = 0, GetNumPlayerIdentifiers(source) - 1 do
		table.insert(identifiers, GetPlayerIdentifier(source, i))
	end
	for i = 0, GetNumPlayerTokens(source) - 1 do
		table.insert(tokens, GetPlayerToken(source, i))
	end
	return identifiers, tokens
end

RegisterCommand("blacklist", function(source, args, rawCommand)
    if source == 0 or isPlayerWhitelisted(source) then
        local action = args[1]
        if action then
            if action == "black" then
                local playerId = args[2]
                if not playerId then
                    print("Failed to blacklist: No player ID provided.")
                    return
                end
                table.remove(args, 1)
                table.remove(args, 1)
                local reason = table.concat(args, " ")
                if reason == "" then
                    print("Failed to blacklist: No reason provided.")
                    return
                end
                local identifiers, tokens = GetPlayerIdentifiersAndTokens(playerId)
        
                if #identifiers == 0 and #tokens == 0 then
                    sendToDiscordDebug(config.debugWebhookUrl, "Failed to blacklist: No identifiers or tokens found for player ID " .. playerId)
                    print("Failed to blacklist: No identifiers or tokens found for player ID " .. playerId)
                    return
                end
        
                local newBan = {
                    banId = #banList + 1,
                    reason = reason,
                    identifiers = {},
                    tokens = {},
                    bannedBy = "",
                    timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time()),
                }
        
                if source == 0 then
                    newBan.bannedBy = "Console"
                else
                    newBan.bannedBy = GetPlayerName(source)
                end
        
                for _, id in pairs(identifiers) do
                    newBan.identifiers[id] = true
                end
                for _, token in pairs(tokens) do
                    newBan.tokens[token] = true
                end
        
                banList[#banList + 1] = newBan
                SaveBans()
                sendToDiscordActionLog(config.actionWebhookUrl, "Blacklist Action", "Player " .. playerId .. " has been blacklisted by " .. newBan.bannedBy)
                print("Player " .. playerId .. " has been blacklisted by " .. newBan.bannedBy)
                DropPlayer(playerId, "You have been blacklisted for the following reason: " .. reason)
            elseif action == "unblack" then
                local banId = tonumber(args[2])
                local foundBan = false
            
                for index, ban in ipairs(banList) do
                    if ban.banId == banId then
                        foundBan = true
                        table.remove(banList, index)
                        sendToDiscordActionLog(config.actionWebhookUrl, "Unblacklist Action", "Player with ban ID: "..banId.." has been unblacklisted.")
                        print("Player with ban ID: " .. banId .. " has been unblacklisted.")
                        break
                    end
                end
            
                if not foundBan then
                    sendToDiscordActionLog(config.actionWebhookUrl, "Unblacklist Failed", "No ban entry found with ID: "..banId)
                    print("No ban entry found with ID: " .. banId)
                end
            
                SaveBans()
            elseif action == "wait" then
                local license = args[2]
                if not license then
                    print("Failed to add to blacklist wait: No license provided.")
                    return
                end
        
                local validPrefixes = {"steam:", "license:", "xbl:", "live:", "discord:", "fivem:"}

                local hasValidPrefix = false
                for _, prefix in ipairs(validPrefixes) do
                    if license:sub(1, #prefix) == prefix then
                        hasValidPrefix = true
                        break
                    end
                end

                if not hasValidPrefix then
                    print("Failed to add to blacklist wait: Invalid license provided.")
                    print("The license must start with one of the following prefixes: " .. table.concat(validPrefixes, ", "))
                    print("Example: license:123456789abcdef or steam:123456789abcdef")
                    return
                end
        
                table.remove(args, 1)
                table.remove(args, 1)
                local reason = table.concat(args, " ")
                if reason == "" then
                    print("Failed to add to blacklist wait: No reason provided.")
                    return
                end

                table.insert(waitingList, {
                    license = license,
                    reason = reason,
                    timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time()),
                })

                SaveWaitingList()
                print("License " .. license .. " added to blacklist wait.")
                sendToDiscordActionLog(config.actionWebhookUrl, "Wait Action", "License " .. license .. " reason "..reason.." added to blacklist wait.")
            elseif action == "check" then
                local banId = tonumber(args[2])
                for _, ban in ipairs(banList) do
                    if ban.banId == banId then
                        local identifiersList = {}
                        for identifier, _ in pairs(ban.identifiers) do
                            table.insert(identifiersList, identifier)
                        end
                        local identifiersStr = table.concat(identifiersList, ", ")
                        local tokensList = {}
                        for token, _ in pairs(ban.tokens) do
                            table.insert(tokensList, token)
                        end
                        local tokensStr = table.concat(tokensList, ", ")
                        
                        local bannedBy = ban.bannedBy or "Unknown"
                        local banTime = ban.timestamp or "Unknown"
        
                        local message = string.format(
                            "Ban ID: %d\nReason: %s\nIdentifiers: %s\nTokens: %s\nBanned By: %s\nBan Time: %s",
                            ban.banId,
                            ban.reason,
                            identifiersStr,
                            tokensStr,
                            bannedBy,
                            banTime
                        )
                        print(message)
                        break
                    end
                end
            elseif action == "waits" then
                if #waitingList == 0 then
                    print("The blacklist waiting list is currently empty.")
                else
                    for _, waitEntry in ipairs(waitingList) do
                        print("Waiting for license: " .. waitEntry.license .. " | Reason: " .. waitEntry.reason .. " | Since: " .. waitEntry.timestamp)
                    end
                end
            elseif action == "help" then
                print("Blacklist System developed by @onecodes")
                print("---------------------------------------------------")
                print("Available Commands:")
                print("/blacklist wait - Displays the waiting list for blacklisting. It will automatically blacklist individuals when they are detected online.")
                print("/blacklist waits [IDENTIFIER] [REASON] - Adds a player to the blacklist waiting list. The identifier should include the relevant prefix, such as steam:, license:, live:, discord:, or fivem:. Do not use token identifiers.")
                print("/blacklist check [BANID] - Provides detailed information about a specific ban based on its ID.")
                print("/blacklist black [ID] [REASON] - Blacklists a player currently in the server. Specify the player's server ID and the reason for blacklisting.")
                print("/blacklist unblack [BANID] - Removes a player from the blacklist based on the ban ID.")
                print("---------------------------------------------------")
                print("For support or inquiries, contact @onecodes")                
            else
                print("Blacklist System developed by @onecodes")
                print("---------------------------------------------------")
                print("Available Commands:")
                print("/blacklist wait - Displays the waiting list for blacklisting. It will automatically blacklist individuals when they are detected online.")
                print("/blacklist waits [IDENTIFIER] [REASON] - Adds a player to the blacklist waiting list. The identifier should include the relevant prefix, such as steam:, license:, live:, discord:, or fivem:. Do not use token identifiers.")
                print("/blacklist check [BANID] - Provides detailed information about a specific ban based on its ID.")
                print("/blacklist black [ID] [REASON] - Blacklists a player currently in the server. Specify the player's server ID and the reason for blacklisting.")
                print("/blacklist unblack [BANID] - Removes a player from the blacklist based on the ban ID.")
                print("---------------------------------------------------")
                print("For support or inquiries, contact @onecodes")
            end
        else
            print("Blacklist System developed by @onecodes")
            print("---------------------------------------------------")
            print("Available Commands:")
            print("/blacklist wait - Displays the waiting list for blacklisting. It will automatically blacklist individuals when they are detected online.")
            print("/blacklist waits [IDENTIFIER] [REASON] - Adds a player to the blacklist waiting list. The identifier should include the relevant prefix, such as steam:, license:, live:, discord:, or fivem:. Do not use token identifiers.")
            print("/blacklist check [BANID] - Provides detailed information about a specific ban based on its ID.")
            print("/blacklist black [ID] [REASON] - Blacklists a player currently in the server. Specify the player's server ID and the reason for blacklisting.")
            print("/blacklist unblack [BANID] - Removes a player from the blacklist based on the ban ID.")
            print("---------------------------------------------------")
            print("For support or inquiries, contact @onecodes")
        end
    else
        print("Unauthorized attempt to use /blacklistsystem command by player " .. GetPlayerName(source))
    end
end, true)

local function CheckForBannedPlayers()
    for _, playerId in ipairs(GetPlayers()) do
        local identifiers, tokens = GetPlayerIdentifiersAndTokens(playerId)
        local isBanned, ban = IsPlayerBanned(identifiers, tokens)
        if isBanned then
            sendToDiscordDebug(config.debugWebhookUrl, "Banned player found: " .. GetPlayerName(playerId) .. ". Removing from the server.")
            DropPlayer(playerId, "You are banned from this server. Reason: " .. ban.reason)
        end
    end
end

-- Check for banned players every 10 seconds
Citizen.CreateThread(function()
    while true do
        CheckForBannedPlayers()
        Citizen.Wait(10000) -- 10000 milliseconds = 10 seconds
    end
end)


AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    deferrals.defer()
    print("Player connecting: " .. playerName)
    local success, identifiers, tokens = pcall(GetPlayerIdentifiersAndTokens, source)
    if not success then
        sendToDiscordDebug(config.debugWebhookUrl, "Failed to fetch identifiers or tokens for player: " .. playerName)
        print("Failed to fetch identifiers or tokens for player: " .. playerName)
        deferrals.done("There was an error in processing your connection. Please try again later.")
        return
    end

    for index, waitEntry in ipairs(waitingList) do
        for _, id in pairs(identifiers) do
            if id == waitEntry.license then
                print("License found in waiting list: " .. id)
                sendToDiscordActionLog(config.actionWebhookUrl, "Automated Blacklist Wait System", "License found in waiting list: " .. id)

                local banEntry = {
                    banId = #banList + 1,
                    reason = waitEntry.reason,
                    identifiers = {},
                    tokens = {},
                    bannedBy = "Automated Blacklist Wait System",
                    timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time()),
                }
    

                for _, idToBan in pairs(identifiers) do
                    banEntry.identifiers[idToBan] = true
                end
    

                for _, tokenToBan in pairs(tokens) do
                    banEntry.tokens[tokenToBan] = true
                end

                table.insert(banList, banEntry)
    
                SaveBans()
                table.remove(waitingList, index)
                SaveWaitingList()
    

                local message = [[

                    %s
                    %s %s
                    %s %d
                    
                    %s
                    %s %s
                    %s %s
                    
                    %s
                ]]
                message = message:format(config.autotext1, config.reasontextauto, waitEntry.reason, config.banidtextauto, banEntry.banId, config.autotext2, config.discordtextauto, config.discordserverlink, config.contacttextauto, config.contacts, config.autotext3)
                deferrals.done(message)
                return
            end
        end
    end

    print("Identifiers: " .. table.concat(identifiers, ", "))
    local isBanned, ban = IsPlayerBanned(identifiers, tokens)
    if isBanned then
        print("Banned player attempted to connect: " .. playerName)
        print("Ban reason: " .. ban.reason .. ", Ban ID: " .. ban.banId)

        local message = [[

        %s
        %s %s
        %s %d
        
        %s
        %s %s
        %s %s
        
        %s
        ]]
        message = message:format(config.text1, config.reasontext, ban.reason, config.banidtext, ban.banId, config.text2, config.discordtext, config.discordserverlink, config.contacttext, config.contacts, config.text3)

        deferrals.done(message)
    else
        print("Player passed the ban check: " .. playerName)
        deferrals.done()
    end
end)
