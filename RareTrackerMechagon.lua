-- Redefine often used functions locally.
local CreateFrame = CreateFrame
local InterfaceOptionsFrame_Show = InterfaceOptionsFrame_Show
local InterfaceOptionsFrame_OpenToCategory = InterfaceOptionsFrame_OpenToCategory
local LibStub = LibStub
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax

-- Redefine global variables locally.
local UIParent = UIParent
local C_ChatInfo = C_ChatInfo

-- ####################################################################
-- ##                      Localization Support                      ##
-- ####################################################################

-- Get an object we can use for the localization of the addon.
local L = LibStub("AceLocale-3.0"):GetLocale("RareTrackerMechagon", true)

-- ####################################################################
-- ##                              Core                              ##
-- ####################################################################

local RTM = CreateFrame("Frame", "RTM", UIParent);

-- The current data we have of the rares.
RTM.is_alive = {}
RTM.current_health = {}
RTM.last_recorded_death = {}
RTM.current_coordinates = {}

-- The zone_uid can be used to distinguish different shards of the zone.
RTM.current_shard_id = nil

-- A table containing all UID deaths reported by the player.
RTM.recorded_entity_death_ids = {}

-- A table containing all vignette UIDs reported by the player.
RTM.reported_vignettes = {}

-- A table containing all spawn UIDs that have been reported through a sound warning.
RTM.reported_spawn_uids = {}

-- The version of the addon.
RTM.version = 6
-- Version 2: changed the order of the rares.
-- Version 3: death messages now send the spawn id.
-- Version 4: changed the interface of the alive message to include coordinates.
-- Version 5: added a future version of Mechtarantula.
-- Version 6: the time stamp that was used to generate the compressed table is now included in group messages.

-- The last zone the user was in.
RTM.last_zone_id = nil

-- Check whether the addon has loaded.
RTM.is_loaded = false

-- ####################################################################
-- ##                         Saved Variables                        ##
-- ####################################################################

-- Setting saved in the saved variables.
RTMDB = {}

-- The rares marked as RTMDB.favorite_rares by the player.
RTMDB.favorite_rares = {}

-- Remember whether the user wants to see the window or not.
RTMDB.show_window = nil

-- Keep a cache of previous data, that we can restore if appropriate.
RTMDB.previous_records = {}

-- ####################################################################
-- ##                        Helper functions                        ##
-- ####################################################################

-- Get the current health of the entity, rounded down to an integer.
function RTM.GetTargetHealthPercentage()
	-- Find the current and maximum health of the current target.
	local max_hp = UnitHealthMax("target")
	
	-- Check for division by zero.
	if max_hp == 0 then
		return -1
	end
	
	return math.floor((100 * UnitHealth("target")) / UnitHealthMax("target"))
end

-- A print function used for debug purposes.
function RTM.Debug(...)
	if RTMDB.debug_enabled then
		print(...)
	end
end

-- Open and start the RTM interface and subscribe to all the required events.
function RTM:StartInterface()
	-- Reset the data, since we cannot guarantee its correctness.
	self.is_alive = {}
	self.current_health = {}
	self.last_recorded_death = {}
	self.current_coordinates = {}
	self.reported_spawn_uids = {}
	self.reported_vignettes = {}
	self.waypoints = {}
	self.current_shard_id = nil
	self:UpdateShardNumber(nil)
	self:UpdateAllDailyKillMarks()
	
	self:RegisterEvents()
	
	if RTMDB.minimap_icon_enabled then
		self.icon:Show("RTM_icon")
        if Bazooka then
            local plugin = Bazooka.plugins["RTM"]
            plugin.db.enabled = true
            plugin:applySettings()
        end
	else
		self.icon:Hide("RTM_icon")
        if Bazooka then
            Bazooka:disablePlugin(Bazooka.plugins["RTM"])
        end
	end
	
	if C_ChatInfo.RegisterAddonMessagePrefix("RTM") ~= true then
		print(L["<RTM> Failed to register AddonPrefix 'RTM'. RTM will not function properly."])
	end
	
	if RTMDB.show_window then
		self:Show()
	end
end

-- Open and start the RTM interface and unsubscribe to all the required events.
function RTM:CloseInterface()
	-- Reset the data.
	self.is_alive = {}
	self.current_health = {}
	self.last_recorded_death = {}
	self.current_coordinates = {}
	self.reported_spawn_uids = {}
	self.reported_vignettes = {}
	self.current_shard_id = nil
	self:UpdateShardNumber(nil)
	
	-- Register the user's departure and disable event listeners.
	self:RegisterDeparture(self.current_shard_id)
	self:UnregisterEvents()
	self.icon:Hide("RTM_icon")
    if Bazooka then
        Bazooka:disablePlugin(Bazooka.plugins["RTM"])
    end
	
	-- Hide the interface.
	self:Hide()
end

-- ####################################################################
-- ##                          Minimap Icon                          ##
-- ####################################################################

local RTM_LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RTM", {
	type = "data source",
	text = "RTM",
	icon = "Interface\\AddOns\\RareTrackerMechagon\\Icons\\RareTrackerIcon",
	OnClick = function(_, button)
		if button == "LeftButton" then
			if RTM.last_zone_id and RTM.target_zones[RTM.last_zone_id] then
				if RTM:IsShown() then
					RTM:Hide()
					RTMDB.show_window = false
				else
					RTM:Show()
					RTMDB.show_window = true
				end
			end
		else
			InterfaceOptionsFrame_Show()
			InterfaceOptionsFrame_OpenToCategory(RTM.options_panel)
		end
	end,
	OnTooltipShow = function(tooltip)
		tooltip:SetText("RTM")
		tooltip:AddLine(L["Left-click: hide/show RTM"], 1, 1, 1)
		tooltip:AddLine(L["Right-click: show options"], 1, 1, 1)
		tooltip:Show()
	end
})

RTM.icon = LibStub("LibDBIcon-1.0")
RTM.icon:Hide("RTM_icon")

function RTM:RegisterMapIcon()
	self.ace_db = LibStub("AceDB-3.0"):New("RTM_ace_db", {
		profile = {
			minimap = {
				hide = false,
			},
		},
	})
	RTM.icon:Register("RTM_icon", RTM_LDB, self.ace_db.profile.minimap)
end


