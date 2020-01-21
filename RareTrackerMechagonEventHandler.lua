-- Redefine often used functions locally.
local UnitGUID = UnitGUID
local strsplit = strsplit
local UnitBuff = UnitBuff
local UnitHealth = UnitHealth
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local C_VignetteInfo = C_VignetteInfo
local GetServerTime = GetServerTime
local LinkedSet = LinkedSet
local CreateFrame = CreateFrame
local GetChannelList = GetChannelList

-- Redefine often used variables locally.
local C_Map = C_Map
local COMBATLOG_OBJECT_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN
local COMBATLOG_OBJECT_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET
local COMBATLOG_OBJECT_TYPE_OBJECT = COMBATLOG_OBJECT_TYPE_OBJECT
local UIParent = UIParent

-- ####################################################################
-- ##                      Localization Support                      ##
-- ####################################################################

-- Get an object we can use for the localization of the addon.
local L = LibStub("AceLocale-3.0"):GetLocale("RareTrackerMechagon", true)

-- ####################################################################
-- ##                         Event Handlers                         ##
-- ####################################################################

-- Listen to a given set of events and handle them accordingly.
function RTM:OnEvent(event, ...)
	if event == "PLAYER_TARGET_CHANGED" then
		self:OnTargetChanged()
	elseif event == "UNIT_HEALTH" and self.chat_frame_loaded then
		self:OnUnitHealth(...)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and self.chat_frame_loaded then
		self:OnCombatLogEvent()
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" then
		self:OnZoneTransition()
	elseif event == "CHAT_MSG_ADDON" then
		self:OnChatMsgAddon(...)
	elseif event == "VIGNETTE_MINIMAP_UPDATED" and self.chat_frame_loaded then
		self:OnVignetteMinimapUpdated(...)
	elseif event == "CHAT_MSG_MONSTER_EMOTE" and self.chat_frame_loaded then
		self:OnChatMsgMonsterEmote(...)
	elseif event == "CHAT_MSG_MONSTER_YELL" and self.chat_frame_loaded then
		self:OnChatMsgMonsterYell(...)
	elseif event == "ADDON_LOADED" then
		self:OnAddonLoaded()
	elseif event == "PLAYER_LOGOUT" then
		self:OnPlayerLogout()
	end
end

-- Change from the original shard to the other.
function RTM:ChangeShard(old_zone_uid, new_zone_uid)
	-- Notify the users in your old shard that you have moved on to another shard.
	self:RegisterDeparture(old_zone_uid)
	
	-- Reset all the data we have, since it has all become useless.
	self.is_alive = {}
	self.current_health = {}
	self.last_recorded_death = {}
	self.recorded_entity_death_ids = {}
	self.current_coordinates = {}
	self.reported_spawn_uids = {}
	self.reported_vignettes = {}
	
	-- Announce your arrival in the new shard.
	self:RegisterArrival(new_zone_uid)
end

-- Check whether the user has changed shards and proceed accordingly.
function RTM:CheckForShardChange(zone_uid)
	local has_changed = false

	if self.current_shard_id ~= zone_uid and zone_uid ~= nil then
		print(L["<RTM> Moving to shard "]..(zone_uid + 42)..".")
		self:UpdateShardNumber(zone_uid)
		has_changed = true
		
		if self.current_shard_id == nil then
			-- Register yourRTM for the given shard.
			self:RegisterArrival(zone_uid)
		else
			-- Move from one shard to another.
			self:ChangeShard(self.current_shard_id, zone_uid)
		end
		
		self.current_shard_id = zone_uid
	end
	
	return has_changed
end

function RTM.CheckForRedirectedRareIds(npc_id)
	-- Next, we check whether this is Mecharantula.
	if npc_id == 151672 then
		-- Check if the player has the time displacement buff.
		for i=1, 40 do
			local spell_id = select(10, UnitBuff("player", i))
			if spell_id == nil then
				break
			elseif spell_id == 296644 then
				-- Chance the NPC id to a bogus id.
				npc_id = 8821909
				break
			end
		end
	end

	return npc_id
end

-- Called when a target changed event is fired.
function RTM:OnTargetChanged()
	if UnitGUID("target") ~= nil then
		-- Get information about the target.
		local guid = UnitGUID("target")
		
		-- unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid
		local unittype, _, _, _, zone_uid, npc_id, spawn_uid = strsplit("-", guid)
		npc_id = tonumber(npc_id)
	
		-- It might occur that the NPC id is nil. Do not proceed in such a case.
		if not npc_id then return end
		
		if not self.banned_NPC_ids[npc_id] and not RTMDB.banned_NPC_ids[npc_id] then
			if self:CheckForShardChange(zone_uid) then
				self.Debug("[Target]", guid)
			end
		end
		
		--A special check for the future variant for Mecharantula, which for some reason has a duplicate NPC id.
		npc_id = self.CheckForRedirectedRareIds(npc_id)
		
		if unittype == "Creature" and self.rare_ids_set[npc_id] then
			-- Find the health of the entity.
			local health = UnitHealth("target")
		
			if health > 0 then
				-- Get the current position of the player and the health of the entity.
				local pos = C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
				local x, y = math.floor(pos.x * 10000 + 0.5) / 100, math.floor(pos.y * 10000 + 0.5) / 100
				local percentage = self.GetTargetHealthPercentage()
				
				-- Mark the entity as alive and report to your peers.
				self:RegisterEntityTarget(self.current_shard_id, npc_id, spawn_uid, percentage, x, y)
			else
				-- Mark the entity has dead and report to your peers.
				self:RegisterEntityDeath(self.current_shard_id, npc_id, spawn_uid)
			end
		end
	end
end

-- Called when a unit health update event is fired.
function RTM:OnUnitHealth(unit)
	-- If the unit is not the target, skip.
	if unit ~= "target" then
		return
	end
	
	if UnitGUID("target") ~= nil then
		-- Get information about the target.
		local guid = UnitGUID("target")
		
		-- unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid
		local _, _, _, _, zone_uid, npc_id, spawn_uid = strsplit("-", guid)
		npc_id = tonumber(npc_id)
	
		-- It might occur that the NPC id is nil. Do not proceed in such a case.
		if not npc_id then return end
		
		if not self.banned_NPC_ids[npc_id] and not RTMDB.banned_NPC_ids[npc_id] then
			if self:CheckForShardChange(zone_uid) then
				self.Debug("[OnUnitHealth]", guid)
			end
		end
		
		--A special check for the future variant for Mecharantula, which for some reason has a duplicate NPC id.
		npc_id = self.CheckForRedirectedRareIds(npc_id)
		
		if self.rare_ids_set[npc_id] then
			-- Update the current health of the entity.
			local percentage = self.GetTargetHealthPercentage()
			
			-- Does the entity have any health left?
			if percentage > 0 then
				-- Report the health of the entity to your peers.
				self:RegisterEntityHealth(self.current_shard_id, npc_id, spawn_uid, percentage)
			else
				-- Mark the entity has dead and report to your peers.
				self:RegisterEntityDeath(self.current_shard_id, npc_id, spawn_uid)
			end
		end
	end
end

-- The flag used to detect guardians or pets.
local flag_mask = bit.bor(COMBATLOG_OBJECT_TYPE_GUARDIAN, COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_TYPE_OBJECT)

-- We track a list of entities that might cause erroneous shard changes.
-- This list is updated dynamically.
RTMDB.banned_NPC_ids = {}

-- Called when a unit health update event is fired.
function RTM:OnCombatLogEvent()
	-- The event does not have a payload (8.0 change). Use CombatLogGetCurrentEventInfo() instead.
	-- timestamp, subevent, zero, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
	-- destGUID, destName, destFlags, destRaidFlags
	local _, subevent, _, sourceGUID, _, _, _, destGUID, _, destFlags, _ = CombatLogGetCurrentEventInfo()
	
	-- unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid
	local unittype, _, _, _, zone_uid, npc_id, spawn_uid = strsplit("-", destGUID)
	npc_id = tonumber(npc_id)
	
	-- It might occur that the NPC id is nil. Do not proceed in such a case.
	if not npc_id then return end
	
	-- Blacklist the entity.
	if not RTMDB.banned_NPC_ids[npc_id] and bit.band(destFlags, flag_mask) > 0 and not self.rare_ids_set[npc_id] then
		RTMDB.banned_NPC_ids[npc_id] = true
	end
	
	-- We can always check for a shard change.
	-- We only take fights between creatures, since they seem to be the only reliable option.
	-- We exclude all pets and guardians, since they might have retained their old shard change.
	if unittype == "Creature" and not self.banned_NPC_ids[npc_id]
		and not RTMDB.banned_NPC_ids[npc_id] and bit.band(destFlags, flag_mask) == 0 then
		
		if self:CheckForShardChange(zone_uid) then
			self.Debug("[OnCombatLogEvent]", sourceGUID, destGUID)
		end
	end
	
	--A special check for the future variant for Mecharantula, which for some reason has a duplicate NPC id.
	npc_id = self.CheckForRedirectedRareIds(npc_id)
		
    if unittype == "Creature" and self.rare_ids_set[npc_id] then
		if subevent == "UNIT_DIED" then
			-- Mark the entity has dead and report to your peers.
			self:RegisterEntityDeath(self.current_shard_id, npc_id, spawn_uid)
		elseif subevent ~= "PARTY_KILL" then
			-- Report the entity as alive to your peers, if it is not marked as alive already.
			if self.is_alive[npc_id] == nil then
				-- The combat log range is quite long, so no coordinates can be provided.
				self:RegisterEntityAlive(self.current_shard_id, npc_id, spawn_uid, nil, nil)
			end
		end
	end
end

-- Called when a vignette on the minimap is updated.
function RTM:OnVignetteMinimapUpdated(vignetteGUID, _)
	local vignetteInfo = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
	local vignetteLocation = C_VignetteInfo.GetVignettePosition(vignetteGUID, C_Map.GetBestMapForUnit("player"))

	if vignetteInfo then
		-- Report the entity.
		-- unittype, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid
		local unittype, _, _, _, zone_uid, npc_id, spawn_uid = strsplit("-", vignetteInfo.objectGUID)
		npc_id = tonumber(npc_id)
	
		-- It might occur that the NPC id is nil. Do not proceed in such a case.
		if not npc_id then return end
		
		if unittype == "Creature" then
			if not self.banned_NPC_ids[npc_id] and not RTMDB.banned_NPC_ids[npc_id] then
				if self:CheckForShardChange(zone_uid) then
					self.Debug("[OnVignette]", vignetteInfo.objectGUID)
				end
			end
			
			--A special check for the future variant for Mecharantula, which for some reason has a duplicate NPC id.
			npc_id = self.CheckForRedirectedRareIds(npc_id)
			
			if self.rare_ids_set[npc_id] and not self.reported_vignettes[vignetteGUID] then
				self.reported_vignettes[vignetteGUID] = {npc_id, spawn_uid}
				
				local x, y = 100 * vignetteLocation.x, 100 * vignetteLocation.y
				self:RegisterEntityAlive(self.current_shard_id, npc_id, spawn_uid, x, y)
			end
		end
	end
end

-- Called when a monster or entity does a self emote.
function RTM:OnChatMsgMonsterEmote(...)
    local text = select(1, ...)
    
    -- Check if any of the drill rig designations is contained in the broadcast text.
    for designation, npc_id in pairs(self.drill_announcing_rares) do
        if text:find(designation) then
            -- We found a match.
            self.is_alive[npc_id] = GetServerTime()
            self.current_coordinates[npc_id] = self.rare_coordinates[npc_id]
            self:PlaySoundNotification(npc_id, npc_id)
            return
        end
    end
end

-- Called when a monster or entity does a yell emote.
function RTM:OnChatMsgMonsterYell(...)
    local entity_name = select(2, ...)
    local npc_id = self.yell_announcing_rares[entity_name]
    
    if npc_id ~= nil then
        -- Mark the entity as alive.
		self.is_alive[npc_id] = GetServerTime()
        self.current_coordinates[npc_id] = self.rare_coordinates[npc_id]
        self:PlaySoundNotification(npc_id, npc_id)
    end
end

-- Called whenever an event occurs that could indicate a zone change.
function RTM:OnZoneTransition()
	-- The zone the player is in.
	local zone_id = C_Map.GetBestMapForUnit("player")
		
	if self.target_zones[zone_id] and not self.target_zones[self.last_zone_id] then
		self:StartInterface()
	elseif not self.target_zones[zone_id] then
		self:RegisterDeparture(self.current_shard_id)
		self:CloseInterface()
	end
	
	self.last_zone_id = zone_id
end

-- Called on every addon message received by the addon.
function RTM:OnChatMsgAddon(...)
	local addon_prefix, message, _, sender = ...

	if addon_prefix == "RTM" then
		local header, payload = strsplit(":", message)
		local prefix, shard_id, addon_version_str = strsplit("-", header)
		local addon_version = tonumber(addon_version_str)

		self:OnChatMessageReceived(sender, prefix, shard_id, addon_version, payload)
	end
end

-- A counter that tracks the time stamp on which the displayed data was updated last.
RTM.last_display_update = 0

-- The last time the icon changed.
RTM.last_icon_change = 0

-- Called on every addon message received by the addon.
function RTM:OnUpdate()
	if (self.last_display_update + 1 < GetTime()) then
		for i=1, #self.rare_ids do
			local npc_id = self.rare_ids[i]
			
			-- It might occur that the rare is marked as alive, but no health is known.
			-- If two minutes pass without a health value, the alive tag will be reset.
			if self.is_alive[npc_id] and GetServerTime() - self.is_alive[npc_id] > 120 then
				self.is_alive[npc_id] = nil
				self.current_health[npc_id] = nil
                self.reported_spawn_uids[npc_id] = nil
			end
			
			self:UpdateStatus(npc_id)
		end
		
		self.last_display_update = GetTime()
	end
	
	if self.last_icon_change + 2 < GetTime() then
		self.last_icon_change = GetTime()
		
		self.broadcast_icon.icon_state = not self.broadcast_icon.icon_state
		
		if self.broadcast_icon.icon_state then
			self.broadcast_icon.texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\Broadcast.tga")
		else
			self.broadcast_icon.texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\Waypoint.tga")
		end
	end
end

-- Called when the addon loaded event is fired.
function RTM:OnAddonLoaded()
	-- OnAddonLoaded might be called multiple times. We only want it to do so once.
	if not self.is_loaded then
		if RTMDB.show_window == nil then
			RTMDB.show_window = true
		end
		
		if not RTMDB.favorite_rares then
			RTMDB.favorite_rares = {}
		end
		
		if not RTMDB.previous_records then
			RTMDB.previous_records = {}
		end
		
		if not RTMDB.selected_sound_number then
			RTMDB.selected_sound_number = 552503
		end
		
		if RTMDB.minimap_icon_enabled == nil then
			RTMDB.minimap_icon_enabled = true
		end
		
		if RTMDB.debug_enabled == nil then
			RTMDB.debug_enabled = false
		end
		
		if not RTMDB.banned_NPC_ids then
			RTMDB.banned_NPC_ids = {}
		else
			-- As a precaution, we remove all rares from the blacklist.
			for i=1, #self.rare_ids do
				local npc_id = self.rare_ids[i]
				RTMDB.banned_NPC_ids[npc_id] = nil
			end
		end
		
		if not RTMDB.window_scale then
			RTMDB.window_scale = 1.0
		end
		
		if RTMDB.enable_raid_communication == nil then
			RTMDB.enable_raid_communication = true
		end
		
		if not RTMDB.ignore_rare then
			RTMDB.ignore_rare = {}
		end
		
		if not RTMDB.rare_ordering then
			RTMDB.rare_ordering = LinkedSet:New()
			for i=1, #self.rare_ids do
				local npc_id = self.rare_ids[i]
				RTMDB.rare_ordering:AddBack(npc_id)
			end
		else
			RTMDB.rare_ordering = LinkedSet:New(RTMDB.rare_ordering)
		end
		
		-- Initialize the frame.
		self:InitializeInterface()
		self:CorrectFavoriteMarks()
		
		-- Initialize the configuration menu.
		self:InitializeConfigMenu()
		
		self:RegisterMapIcon()
		
		-- Remove any data in the previous records that has expired.
		for key, _ in pairs(RTMDB.previous_records) do
			if GetServerTime() - RTMDB.previous_records[key].time_stamp > 900 then
				print(L["<RTM> Removing cached data for shard "]..(key + 42)..".")
				RTMDB.previous_records[key] = nil
			end
		end
		
		self.is_loaded = true
	end
end

-- Called when the player logs out, such that we can save the current time table for later use.
function RTM:OnPlayerLogout()
	if self.current_shard_id then
		-- Save the records, such that we can use them after a reload.
		RTMDB.previous_records[self.current_shard_id] = {}
		RTMDB.previous_records[self.current_shard_id].time_stamp = GetServerTime()
		RTMDB.previous_records[self.current_shard_id].time_table = self.last_recorded_death
	end
end

-- Register to the events required for the addon to function properly.
function RTM:RegisterEvents()
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("UNIT_HEALTH")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("CHAT_MSG_ADDON")
	self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
	self:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
	self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
end

-- Unregister from the events, to disable the tracking functionality.
function RTM:UnregisterEvents()
	self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	self:UnregisterEvent("UNIT_HEALTH")
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("CHAT_MSG_ADDON")
	self:UnregisterEvent("VIGNETTE_MINIMAP_UPDATED")
	self:UnregisterEvent("CHAT_MSG_MONSTER_EMOTE")
	self:UnregisterEvent("CHAT_MSG_MONSTER_YELL")
end

-- Create a frame that handles the frame updates of the addon.
RTM.updateHandler = CreateFrame("Frame", "RTM.updateHandler", RTM)
RTM.updateHandler:SetScript("OnUpdate",
	function()
		RTM:OnUpdate()
	end
)

-- Register the event handling of the frame.
RTM:SetScript("OnEvent",
	function(self, event, ...)
		self:OnEvent(event, ...)
	end
)

RTM:RegisterEvent("ZONE_CHANGED_NEW_AREA")
RTM:RegisterEvent("ZONE_CHANGED")
RTM:RegisterEvent("PLAYER_ENTERING_WORLD")
RTM:RegisterEvent("ADDON_LOADED")
RTM:RegisterEvent("PLAYER_LOGOUT")

-- ####################################################################
-- ##                      Daily Reset Handling                      ##
-- ####################################################################

local daily_reset_handling_frame = CreateFrame("Frame", "daily_reset_handling_frame", UIParent)

-- Which timestamp was the last hour?
local time_table = date("*t", GetServerTime())
time_table.sec = 0
time_table.min = 0

-- Check when the next hourly reset is going to be, by adding 3600 to the previous hour timestamp.
daily_reset_handling_frame.target_time = time(time_table) + 3600 + 60

-- Add an OnUpdate checker.
daily_reset_handling_frame:SetScript("OnUpdate",
	function(self)
		if GetServerTime() > self.target_time then
			self.target_time = self.target_time + 3600
            
            if RTM.entities_frame ~= nil then
                RTM:UpdateAllDailyKillMarks()
                RTM.Debug("<RTM> Updating daily kill marks.")
            end
		end
	end
)
daily_reset_handling_frame:Show()

-- ####################################################################
-- ##                       Channel Wait Frame                       ##
-- ####################################################################

-- One of the issues encountered is that the chat might be joined before the default channels.
-- In such a situation, the order of the channels changes, which is undesirable.
-- Thus, we block certain events until these chats have been loaded.
RTM.chat_frame_loaded = false

local message_delay_frame = CreateFrame("Frame", "RTM.message_delay_frame", UIParent)
message_delay_frame.start_time = GetServerTime()
message_delay_frame:SetScript("OnUpdate",
	function(self)
		if GetServerTime() - self.start_time > 0 then
			if #{GetChannelList()} == 0 then
				self.start_time = GetServerTime()
			else
				RTM.chat_frame_loaded = true
				self:SetScript("OnUpdate", nil)
				self:Hide()
			end
		end
	end
)
message_delay_frame:Show()