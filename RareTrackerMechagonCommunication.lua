-- Redefine often used functions locally.
local UnitName = UnitName
local GetRealmName = GetRealmName
local GetServerTime = GetServerTime
local GetTime = GetTime
local C_ChatInfo = C_ChatInfo
local strsplit = strsplit
local CreateFrame = CreateFrame
local GetChannelName = GetChannelName
local JoinTemporaryChannel = JoinTemporaryChannel
local UnitInRaid = UnitInRaid
local UnitInParty = UnitInParty
local GetNumDisplayChannels = GetNumDisplayChannels
local LeaveChannelByName = LeaveChannelByName
local PlaySoundFile = PlaySoundFile

--localization
local L = LibStub ("AceLocale-3.0"):GetLocale ("RareTrackerMechagon", true)

-- ####################################################################
-- ##                         Communication                          ##
-- ####################################################################

-- The time at which you broad-casted the joined the shard group.
RTM.arrival_register_time = nil

-- The name and realm of the player.
local player_name = UnitName("player").."-"..GetRealmName()

-- A flag that ensures that the version warning is only given once per session.
local reported_version_mismatch = false

-- The last time the health of an entity has been reported.
-- Used for limiting the number of messages sent to the channel.
RTM.last_health_report = {}
RTM.last_health_report["CHANNEL"] = {}
RTM.last_health_report["RAID"] = {}

-- ####################################################################
-- ##                        Helper Functions                        ##
-- ####################################################################

-- A time stamp at which the last message was sent in the rate limited message sender.
RTM.last_message_sent = {}
RTM.last_message_sent["CHANNEL"] = 0
RTM.last_message_sent["RAID"] = 0

-- A function that acts as a rate limiter for channel messages.
function RTM:SendRateLimitedAddonMessage(message, target, target_id, target_channel)
	-- We only allow one message to be sent every ~5 seconds.
	if GetTime() - self.last_message_sent[target_channel] > 5 then
		C_ChatInfo.SendAddonMessage("RTM", message, target, target_id)
		self.last_message_sent[target_channel] = GetTime()
	end
end

-- Compress all the kill data the user has to Base64.
function RTM:GetCompressedSpawnData(time_stamp)
	local result = ""
	
	for i=1, #RTM.rare_ids do
		local npc_id = self.rare_ids[i]
		local kill_time = self.last_recorded_death[npc_id]
		
		if kill_time ~= nil then
			result = result..self.toBase64(time_stamp - kill_time)..","
		else
			result = result..self.toBase64(0)..","
		end
	end
	
	return result:sub(1, #result - 1)
end

-- Decompress all the Base64 data sent by a peer to decimal and update the timers.
function RTM:DecompressSpawnData(spawn_data, time_stamp)
	local spawn_data_entries = {strsplit(",", spawn_data, #self.rare_ids)}

	for i=1, #self.rare_ids do
		local npc_id = self.rare_ids[i]
		local kill_time = self.toBase10(spawn_data_entries[i])
		
		if kill_time ~= 0 then
			if self.last_recorded_death[npc_id] then
				-- If we already have an entry, take the minimal.
				if time_stamp - kill_time < self.last_recorded_death[npc_id] then
					self.last_recorded_death[npc_id] = time_stamp - kill_time
				end
			else
				self.last_recorded_death[npc_id] = time_stamp - kill_time
			end
		end
	end
end

-- A function that enables the delayed execution of a function.
function RTM:DelayedExecution(delay, _function)
	local frame = CreateFrame("Frame", "RTM.message_delay_frame", self)
	frame.start_time = GetTime()
	frame:SetScript("OnUpdate",
		function(self2)
			if GetTime() - self2.start_time > delay then
				_function()
				self2:SetScript("OnUpdate", nil)
				self2:Hide()
			end
		end
	)
	frame:Show()
end

-- ####################################################################
-- ##            Shard Group Management Register Functions           ##
-- ####################################################################

-- Inform other clients of your arrival.
function RTM:RegisterArrival(shard_id)
	-- Attempt to load previous data from our cache.
	if RTMDB.previous_records[shard_id] then
		if GetServerTime() - RTMDB.previous_records[shard_id].time_stamp < 900 then
			print(L["<RTM> Restoring data from previous session in shard "]..(shard_id + 42)..".")
			self.last_recorded_death = RTMDB.previous_records[shard_id].time_table
		else
			RTMDB.previous_records[shard_id] = nil
		end
	end

	self.channel_name = "RTM"..shard_id
	
	local is_in_channel = false
	if select(1, GetChannelName(RTM.channel_name)) ~= 0 then
		is_in_channel = true
	end

	-- Announce to the others that you have arrived.
	self.arrival_register_time = GetServerTime()
	self.rare_table_updated = false
		
	if not is_in_channel then
		-- Join the appropriate channel.
		JoinTemporaryChannel(self.channel_name)
		
		-- We want to avoid overwriting existing channel numbers. So delay the channel join.
		self:DelayedExecution(1, function()
				print(L["<RTM> Requesting rare kill data for shard "]..(shard_id + 42)..".")
				C_ChatInfo.SendAddonMessage(
					"RTM",
					"A-"..shard_id.."-"..self.version..":"..self.arrival_register_time,
					"CHANNEL",
					select(1, GetChannelName(self.channel_name))
				)
			end
		)
	else
		C_ChatInfo.SendAddonMessage(
			"RTM",
			"A-"..shard_id.."-"..self.version..":"..self.arrival_register_time,
			"CHANNEL",
			select(1, GetChannelName(self.channel_name))
		)
	end
	
	-- Register your arrival within the group.
	if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
		C_ChatInfo.SendAddonMessage("RTM", "AP-"..shard_id.."-"..self.version..":"..self.arrival_register_time, "RAID", nil)
	end
end

-- Inform the others that you are still present and give them your data.
function RTM:RegisterPresenceWhisper(shard_id, target, time_stamp)
	if next(self.last_recorded_death) ~= nil then
		-- Announce to the others that you are still present on the shard.
		C_ChatInfo.SendAddonMessage(
			"RTM",
			"PW-"..shard_id.."-"..self.version..":"..self:GetCompressedSpawnData(time_stamp),
			"WHISPER",
			target
		)
	end
end

-- Inform the others that you are still present and give them your data through the group/raid channel.
function RTM:RegisterPresenceGroup(shard_id, time_stamp)
	if next(self.last_recorded_death) ~= nil then
		-- Announce to the others that you are still present on the shard.
		C_ChatInfo.SendAddonMessage(
			"RTM",
			"PP-"..shard_id.."-"..self.version..":"..self:GetCompressedSpawnData(time_stamp).."-"..time_stamp,
			"RAID",
			nil
		)
	end
end

--Leave the channel.
function RTM:RegisterDeparture(shard_id)
	local n_channels = GetNumDisplayChannels()
	local channels_to_leave = {}
	
	-- Leave all channels with an RTM prefix.
	for i = 1, n_channels do
		local _, channel_name = GetChannelName(i)
		if channel_name and channel_name:find("RTM") then
			channels_to_leave[channel_name] = true
		end
	end
	
	for channel_name, _ in pairs(channels_to_leave) do
		LeaveChannelByName(channel_name)
	end
	
	-- Store any timer data we previously had in the saved variables.
	if shard_id then
		RTMDB.previous_records[shard_id] = {}
		RTMDB.previous_records[shard_id].time_stamp = GetServerTime()
		RTMDB.previous_records[shard_id].time_table = self.last_recorded_death
	end
end

-- ####################################################################
-- ##          Shard Group Management Acknowledge Functions          ##
-- ####################################################################

-- Acknowledge that the player has arrived and whisper your data table.
function RTM:AcknowledgeArrival(player, time_stamp)
	-- Notify the newly arrived user of your presence through a whisper.
	if player_name ~= player then
		self:RegisterPresenceWhisper(self.current_shard_id, player, time_stamp)
	end
end

-- Acknowledge that the player has arrived and whisper your data table.
function RTM:AcknowledgeArrivalGroup(player, time_stamp)
	-- Notify the newly arrived user of your presence through a whisper.
	if player_name ~= player then
		if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
			self:RegisterPresenceGroup(self.current_shard_id, time_stamp)
		end
	end
end

-- Acknowledge the welcome message of other players and parse and import their tables.
function RTM:AcknowledgePresence(spawn_data)
	self:DecompressSpawnData(spawn_data, self.arrival_register_time)
end

-- ####################################################################
-- ##               Entity Information Share Functions               ##
-- ####################################################################

-- Inform the others that a specific entity has died.
function RTM:RegisterEntityDeath(shard_id, npc_id, spawn_uid)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		-- Mark the entity as dead.
		self.last_recorded_death[npc_id] = GetServerTime()
		self.is_alive[npc_id] = nil
		self.current_health[npc_id] = nil
		self.current_coordinates[npc_id] = nil
		self.recorded_entity_death_ids[spawn_uid..npc_id] = true
		
		-- We want to avoid overwriting existing channel numbers. So delay the channel join.
		self:DelayedExecution(3, function() self:UpdateDailyKillMark(npc_id) end)
		
		-- Send the death message.
		C_ChatInfo.SendAddonMessage(
			"RTM",
			"ED-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid,
			"CHANNEL",
			select(1, GetChannelName(self.channel_name))
		)
	
		if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
			C_ChatInfo.SendAddonMessage(
				"RTM",
				"EDP-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid,
				"RAID",
				nil
			)
		end
	end
end

-- Inform the others that you have spotted an alive entity.
function RTM:RegisterEntityAlive(shard_id, npc_id, spawn_uid, x, y)
	if self.recorded_entity_death_ids[spawn_uid..npc_id] == nil then
		-- Mark the entity as alive.
		self.is_alive[npc_id] = GetServerTime()
	
		-- Send the alive message.
		if x ~= nil and y ~= nil then
			RTM.current_coordinates[npc_id] = {}
			RTM.current_coordinates[npc_id].x = x
			RTM.current_coordinates[npc_id].y = y
			C_ChatInfo.SendAddonMessage(
				"RTM",
				"EA-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..x.."-"..y,
				"CHANNEL",
				select(1, GetChannelName(self.channel_name))
			)
		
			if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
				C_ChatInfo.SendAddonMessage(
					"RTM",
					"EAP-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..x.."-"..y,
					"RAID",
					nil
				)
			end
		else
			C_ChatInfo.SendAddonMessage(
				"RTM",
				"EA-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."--",
				"CHANNEL",
				select(1, GetChannelName(self.channel_name))
			)
		
			if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
				C_ChatInfo.SendAddonMessage(
					"RTM",
					"EAP-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."--",
					"RAID",
					nil
				)
			end
		end
	end
end

-- Inform the others that you have spotted an alive entity.
function RTM:RegisterEntityTarget(shard_id, npc_id, spawn_uid, percentage, x, y)
	if self.recorded_entity_death_ids[spawn_uid..npc_id] == nil then
		-- Mark the entity as targeted and alive.
		self.is_alive[npc_id] = GetServerTime()
		self.current_health[npc_id] = percentage
		self.current_coordinates[npc_id] = {}
		self.current_coordinates[npc_id].x = x
		self.current_coordinates[npc_id].y = y
		self:UpdateStatus(npc_id)
	
		-- Send the target message.
		C_ChatInfo.SendAddonMessage(
			"RTM",
			"ET-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..percentage.."-"..x.."-"..y,
			"CHANNEL",
			select(1, GetChannelName(self.channel_name))
		)
		
		if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
			C_ChatInfo.SendAddonMessage(
				"RTM",
				"ETP-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..percentage.."-"..x.."-"..y,
				"RAID",
				nil
			)
		end
	end
end

-- Inform the others the health of a specific entity.
function RTM:RegisterEntityHealth(shard_id, npc_id, spawn_uid, percentage)
	if not self.last_health_report["CHANNEL"][npc_id]
		or GetTime() - self.last_health_report["CHANNEL"][npc_id] > 2 then
		-- Mark the entity as targeted and alive.
		self.is_alive[npc_id] = GetServerTime()
		self.current_health[npc_id] = percentage
		self:UpdateStatus(npc_id)
	
		-- Send the health message, using a rate limited function.
		self:SendRateLimitedAddonMessage(
			"EH-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..percentage,
			"CHANNEL",
			select(1, GetChannelName(self.channel_name)),
			"CHANNEL"
		)
	end
	
	if RTMDB.enable_raid_communication and (UnitInRaid("player") or UnitInParty("player")) then
		if not self.last_health_report["RAID"][npc_id] or GetTime() - self.last_health_report["RAID"][npc_id] > 2 then
			-- Mark the entity as targeted and alive.
			self.is_alive[npc_id] = GetServerTime()
			self.current_health[npc_id] = percentage
			self:UpdateStatus(npc_id)
		
			-- Send the health message, using a rate limited function.
			self:SendRateLimitedAddonMessage(
				"EHP-"..shard_id.."-"..self.version..":"..npc_id.."-"..spawn_uid.."-"..percentage,
				"RAID",
				nil,
				"RAID"
			)
		end
	end
end

-- Acknowledge that the entity has died and set the according flags.
function RTM:AcknowledgeEntityDeath(npc_id, spawn_uid)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		-- Mark the entity as dead.
		self.last_recorded_death[npc_id] = GetServerTime()
		self.is_alive[npc_id] = nil
		self.current_health[npc_id] = nil
		self.current_coordinates[npc_id] = nil
		self.recorded_entity_death_ids[spawn_uid..npc_id] = true
		self:UpdateStatus(npc_id)
		self:DelayedExecution(3, function() self:UpdateDailyKillMark(npc_id) end)
	end

	if self.waypoints[npc_id] and TomTom then
		TomTom:RemoveWaypoint(self.waypoints[npc_id])
		self.waypoints[npc_id] = nil
	end
end

-- Acknowledge that the entity is alive and set the according flags.
function RTM:AcknowledgeEntityAlive(npc_id, spawn_uid, x, y)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		self.is_alive[npc_id] = GetServerTime()
		self:UpdateStatus(npc_id)
		
		if x ~= nil and y ~= nil then
			self.current_coordinates[npc_id] = {}
			self.current_coordinates[npc_id].x = x
			self.current_coordinates[npc_id].y = y
		end
		
		if RTMDB.favorite_rares[npc_id] and not self.reported_spawn_uids[spawn_uid] then
			-- Play a sound file.
			PlaySoundFile(RTMDB.selected_sound_number)
			self.reported_spawn_uids[spawn_uid] = true
		end
	end
end

-- Acknowledge that the entity is alive and set the according flags.
function RTM:AcknowledgeEntityTarget(npc_id, spawn_uid, percentage, x, y)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		self.last_recorded_death[npc_id] = nil
		self.is_alive[npc_id] = GetServerTime()
		self.current_health[npc_id] = percentage
		self.current_coordinates[npc_id] = {}
		self.current_coordinates[npc_id].x = x
		self.current_coordinates[npc_id].y = y
		self:UpdateStatus(npc_id)
		
		if RTMDB.favorite_rares[npc_id] and not self.reported_spawn_uids[spawn_uid] then
			-- Play a sound file.
			PlaySoundFile(RTMDB.selected_sound_number)
			self.reported_spawn_uids[spawn_uid] = true
		end
	end
end

-- Acknowledge the health change of the entity and set the according flags.
function RTM:AcknowledgeEntityHealth(npc_id, spawn_uid, percentage)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		self.last_recorded_death[npc_id] = nil
		self.is_alive[npc_id] = GetServerTime()
		self.current_health[npc_id] = percentage
		self.last_health_report["CHANNEL"][npc_id] = GetTime()
		self:UpdateStatus(npc_id)
		
		if RTMDB.favorite_rares[npc_id] and not self.reported_spawn_uids[spawn_uid] then
			-- Play a sound file.
			PlaySoundFile(RTMDB.selected_sound_number)
			self.reported_spawn_uids[spawn_uid] = true
		end
	end
end

-- Acknowledge the health change of the entity and set the according flags.
function RTM:AcknowledgeEntityHealthRaid(npc_id, spawn_uid, percentage)
	if not self.recorded_entity_death_ids[spawn_uid..npc_id] then
		self.last_recorded_death[npc_id] = nil
		self.is_alive[npc_id] = GetServerTime()
		self.current_health[npc_id] = percentage
		self.last_health_report["RAID"][npc_id] = GetTime()
		self:UpdateStatus(npc_id)
		
		if RTMDB.favorite_rares[npc_id] and not self.reported_spawn_uids[spawn_uid] then
			-- Play a sound file.
			PlaySoundFile(RTMDB.selected_sound_number)
			self.reported_spawn_uids[spawn_uid] = true
		end
	end
end

-- ####################################################################
-- ##                      Core Chat Management                      ##
-- ####################################################################

-- Determine what to do with the received chat message.
function RTM:OnChatMessageReceived(player, prefix, shard_id, addon_version, payload)
	-- The format of messages might change over time and as such, versioning is needed.
	-- To ensure optimal performance, all users should use the latest version.
	if not reported_version_mismatch and self.version < addon_version and addon_version ~= 9001 then
		print(L["<RTM> Your version or RareTrackerMechagon is outdated. "]..
			L["Please update to the most recent version at the earliest convenience."])
		reported_version_mismatch = true
	end
	
	self.Debug(player, prefix, shard_id, addon_version, payload)
	
	-- Only allow communication if the users are on the same shards and if their addon version is equal.
	if self.current_shard_id == shard_id and self.version == addon_version then
		if prefix == "A" then
			local time_stamp = tonumber(payload)
			self:AcknowledgeArrival(player, time_stamp)
		elseif prefix == "PW" then
			self:AcknowledgePresence(payload)
		elseif prefix == "ED" then
			local npcs_id_str, spawn_uid = strsplit("-", payload)
			local npc_id = tonumber(npcs_id_str)
			self:AcknowledgeEntityDeath(npc_id, spawn_uid)
		elseif prefix == "EA" then
			local npcs_id_str, spawn_uid, x_str, y_str = strsplit("-", payload)
			local npc_id, x, y = tonumber(npcs_id_str), tonumber(x_str), tonumber(y_str)
			self:AcknowledgeEntityAlive(npc_id, spawn_uid, x, y)
		elseif prefix == "ET" then
			local npc_id_str, spawn_uid, percentage_str, x_str, y_str = strsplit("-", payload)
			local npc_id, percentage, x, y = tonumber(npc_id_str), tonumber(percentage_str), tonumber(x_str), tonumber(y_str)
			self:AcknowledgeEntityTarget(npc_id, spawn_uid, percentage, x, y)
		elseif prefix == "EH" then
			local npc_id_str, spawn_uid, percentage_str = strsplit("-", payload)
			local npc_id, percentage = tonumber(npc_id_str), tonumber(percentage_str)
			self:AcknowledgeEntityHealth(npc_id, spawn_uid, percentage)
		elseif RTMDB.enable_raid_communication then
			if prefix == "AP" then
				local time_stamp = tonumber(payload)
				self:AcknowledgeArrivalGroup(player, time_stamp)
			elseif prefix == "PP" then
				local rare_data, arrival_time_str = strsplit("-", payload)
				local arrival_time = tonumber(arrival_time_str)
				if self.arrival_register_time == arrival_time then
					self:AcknowledgePresence(rare_data)
				end
			elseif prefix == "EDP" then
				local npcs_id_str, spawn_uid = strsplit("-", payload)
				local npc_id = tonumber(npcs_id_str)
				self:AcknowledgeEntityDeath(npc_id, spawn_uid)
			elseif prefix == "EAP" then
				local npcs_id_str, spawn_uid, x_str, y_str = strsplit("-", payload)
				local npc_id, x, y = tonumber(npcs_id_str), tonumber(x_str), tonumber(y_str)
				self:AcknowledgeEntityAlive(npc_id, spawn_uid, x, y)
			elseif prefix == "ETP" then
				local npc_id_str, spawn_uid, percentage_str, x_str, y_str = strsplit("-", payload)
				local npc_id, percentage, x, y = tonumber(npc_id_str), tonumber(percentage_str), tonumber(x_str), tonumber(y_str)
				self:AcknowledgeEntityTarget(npc_id, spawn_uid, percentage, x, y)
			elseif prefix == "EHP" then
				local npc_id_str, spawn_uid, percentage_str = strsplit("-", payload)
				local npc_id, percentage = tonumber(npc_id_str), tonumber(percentage_str)
				self:AcknowledgeEntityHealthRaid(npc_id, spawn_uid, percentage)
			end
		end
	end
end