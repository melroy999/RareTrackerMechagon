-- Redefine often used functions locally.
local CreateFrame = CreateFrame
local IsLeftControlKeyDown = IsLeftControlKeyDown
local IsRightControlKeyDown = IsRightControlKeyDown
local UnitInRaid = UnitInRaid
local IsLeftAltKeyDown = IsLeftAltKeyDown
local IsRightAltKeyDown = IsRightAltKeyDown
local SendChatMessage = SendChatMessage
local GetServerTime = GetServerTime
local IsQuestFlaggedCompleted = IsQuestFlaggedCompleted
local UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth
local UIDropDownMenu_SetText = UIDropDownMenu_SetText
local PlaySoundFile = PlaySoundFile
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton = UIDropDownMenu_AddButton
local getglobal = getglobal
local InterfaceOptions_AddCategory = InterfaceOptions_AddCategory

-- Redefine global variables locally.
local UIParent = UIParent
local C_Map = C_Map

-- Width and height variables used to customize the window.
local entity_name_width = 208
local entity_status_width = 50
local frame_padding = 4
local favorite_rares_width = 10
local shard_id_frame_height = 16

-- Values for the opacity of the background and foreground.
local background_opacity = 0.4
local front_opacity = 0.6

--localization
local L = LibStub ("AceLocale-3.0"):GetLocale ("RareTrackerMechagon", true)

-- ####################################################################
-- ##                              GUI                               ##
-- ####################################################################

RTM.last_reload_time = 0

function RTM:InitializeShardNumberFrame()
	local f = CreateFrame("Frame", "RTM.shard_id_frame", self)
	f:SetSize(
      entity_name_width + entity_status_width + 3 * frame_padding + 2 * favorite_rares_width,
      shard_id_frame_height
  )
  
	local texture = f:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f)
	f.texture = texture
	
	f.status_text = f:CreateFontString(nil, nil, "GameFontNormal")
	f.status_text:SetPoint("TOPLEFT", 10 + 2 * favorite_rares_width + 2 * frame_padding, -3)
	f.status_text:SetText(L["Shard ID: Unknown"])
	f:SetPoint("TOPLEFT", self, frame_padding, -frame_padding)
	
	return f
end

function RTM:CreateRareTableEntry(npc_id, parent_frame)
	local f = CreateFrame("Frame", "RTM.entities_frame.entities["..npc_id.."]", parent_frame);
	f:SetSize(entity_name_width + entity_status_width + 3 * frame_padding + 2 * favorite_rares_width, 12)
	
	-- Add the favorite button.
	f.favorite = CreateFrame("CheckButton", "RTM.entities_frame.entities["..npc_id.."].favorite", f)
	f.favorite:SetSize(10, 10)
	local texture = f.favorite:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.favorite)
	f.favorite.texture = texture
	f.favorite:SetPoint("TOPLEFT", 1, 0)
	
	-- Add an action listener.
	f.favorite:SetScript("OnClick",
		function()
			if RTMDB.favorite_rares[npc_id] then
				RTMDB.favorite_rares[npc_id] = nil
				f.favorite.texture:SetColorTexture(0, 0, 0, front_opacity)
			else
				RTMDB.favorite_rares[npc_id] = true
				f.favorite.texture:SetColorTexture(0, 1, 0, 1)
			end
		end
	);
	
	-- Add the announce/waypoint button.
	f.announce = CreateFrame("Button", "RTM.entities_frame.entities["..npc_id.."].announce", f)
	f.announce:SetSize(10, 10)
	texture = f.announce:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.announce)
	f.announce.texture = texture
	f.announce:SetPoint("TOPLEFT", frame_padding + favorite_rares_width + 1, 0)
	f.announce:RegisterForClicks("LeftButtonDown", "RightButtonDown")
	
	-- Add an action listener.
	f.announce:SetScript("OnClick",
		function(_, button)
			local name = self.rare_names[npc_id]
			local health = self.current_health[npc_id]
			local last_death = self.last_recorded_death[npc_id]
			local loc = self.current_coordinates[npc_id]
			
			if button == "LeftButton" then
				local target = "CHANNEL"
				
				if IsLeftControlKeyDown() or IsRightControlKeyDown() then
					if UnitInRaid("player") then
						target = "RAID"
					else
						target = "PARTY"
					end
				elseif IsLeftAltKeyDown() or IsRightAltKeyDown() then
					target = "SAY"
				end
			
				if self.current_health[npc_id] then
					-- SendChatMessage
					if loc then
						SendChatMessage(
							string.format(L["<RTM> %s (%s%%) seen at ~(%.2f, %.2f)"], name, health, loc.x, loc.y),
							target,
							nil,
							1
						)
					else
						SendChatMessage(
							string.format(L["<RTM> %s (%s%%) seen at ~(N/A)"], name, health),
							target,
							nil,
							1
						)
					end
				elseif self.last_recorded_death[npc_id] ~= nil then
					if GetServerTime() - last_death < 60 then
						SendChatMessage(
							string.format(L["<RTM> %s has died"], name, GetServerTime() - last_death),
							target,
							nil,
							1
						)
					else
						SendChatMessage(
							string.format(
								L["<RTM> %s was last seen ~%s minutes ago"],
								name,
								math.floor((GetServerTime() - last_death) / 60)
							),
							target,
							nil,
							1
						)
					end
				elseif self.is_alive[npc_id] then
					if loc then
						SendChatMessage(
							string.format(L["<RTM> %s seen alive, vignette at ~(%.2f, %.2f)"], name, loc.x, loc.y),
							target,
							nil,
							1
						)
					else
						SendChatMessage(
							string.format(L["<RTM> %s seen alive (vignette)"], name),
							target,
							nil,
							1
						)
					end
				end
			else
				-- does the user have tom tom? if so, add a waypoint if it exists.
				if TomTom ~= nil and loc then
					self.waypoints[npc_id] = TomTom:AddWaypointToCurrentZone(loc.x, loc.y, name)
				end
			end
		end
	);
	
	-- Add the entities name.
	f.name = f:CreateFontString(nil, nil, "GameFontNormal")
	f.name:SetJustifyH("LEFT")
	f.name:SetJustifyV("TOP")
	f.name:SetPoint("TOPLEFT", 2 * frame_padding + 2 * favorite_rares_width + 10, 0)
	f.name:SetText(self.rare_names[npc_id])
	
	-- Add the timer/health entry.
	f.status = f:CreateFontString(nil, nil, "GameFontNormal")
	f.status:SetPoint("TOPRIGHT", 0, 0)
	f.status:SetText("--")
	f.status:SetJustifyH("MIDDLE")
	f.status:SetJustifyV("TOP")
	f.status:SetSize(entity_status_width, 12)
	
	return f
end

function RTM:InitializeRareTableEntries(parent_frame)
	-- Create a holder for all the entries.
	parent_frame.entities = {}
	
	-- Create a frame entry for all of the NPC ids, even the ignored ones.
	-- The ordering and hiding of rares will be done later.
	for i=1, #self.rare_ids do
		local npc_id = self.rare_ids[i]
		parent_frame.entities[npc_id] = self:CreateRareTableEntry(npc_id, parent_frame)
	end
end

function RTM:ReorganizeRareTableFrame(f)
	-- How many ignored rares do we have?
	local n = 0
	for _, _ in pairs(RTMDB.ignore_rare) do
		n = n + 1
	end
	
	-- Resize all the frames.
	self:SetSize(
		entity_name_width + entity_status_width + 2 * favorite_rares_width + 5 * frame_padding,
		shard_id_frame_height + 3 * frame_padding + (#self.rare_ids - n) * 12 + 8
	)
	f:SetSize(
		entity_name_width + entity_status_width + 2 * favorite_rares_width + 3 * frame_padding,
		(#self.rare_ids - n) * 12 + 8
	)
	f.entity_name_backdrop:SetSize(entity_name_width, f:GetHeight())
	f.entity_status_backdrop:SetSize(entity_status_width, f:GetHeight())
	
	-- Give all of the table entries their new positions.
	local i = 1
	RTMDB.rare_ordering:ForEach(
		function(npc_id, _)
			if RTMDB.ignore_rare[npc_id] then
				f.entities[npc_id]:Hide()
			else
				f.entities[npc_id]:SetPoint("TOPLEFT", f, 0, -(i - 1) * 12 - 5)
				f.entities[npc_id]:Show()
				i = i + 1
			end
		end
	)
end

function RTM:InitializeRareTableFrame(f)
	-- First, add the frames for the backdrop and make sure that the hierarchy is created.
	f:SetPoint("TOPLEFT", frame_padding, -(2 * frame_padding + shard_id_frame_height))
	
	f.entity_name_backdrop = CreateFrame("Frame", "RTM.entities_frame.entity_name_backdrop", f)
	local texture = f.entity_name_backdrop:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.entity_name_backdrop)
	f.entity_name_backdrop.texture = texture
	f.entity_name_backdrop:SetPoint("TOPLEFT", f, 2 * frame_padding + 2 * favorite_rares_width, 0)
	
	f.entity_status_backdrop = CreateFrame("Frame", "RTM.entities_frame.entity_status_backdrop", f)
	texture = f.entity_status_backdrop:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.entity_status_backdrop)
	f.entity_status_backdrop.texture = texture
	f.entity_status_backdrop:SetPoint("TOPRIGHT", f, 0, 0)
	
	-- Next, add all the rare entries to the table.
	self:InitializeRareTableEntries(f)
	
	-- Arrange the table such that it fits the user's wishes. Resize the frames appropriately.
	self:ReorganizeRareTableFrame(f)
end

function RTM:UpdateStatus(npc_id)
	local target = self.entities_frame.entities[npc_id]

	if self.current_health[npc_id] then
		target.status:SetText(self.current_health[npc_id].."%")
    target.status:SetFontObject("GameFontGreen")
		target.announce.texture:SetColorTexture(0, 1, 0, 1)
	elseif self.is_alive[npc_id] then
		target.status:SetText("N/A")
    target.status:SetFontObject("GameFontGreen")
		target.announce.texture:SetColorTexture(0, 1, 0, 1)
	elseif self.last_recorded_death[npc_id] ~= nil then
		local last_death = self.last_recorded_death[npc_id]
		target.status:SetText(math.floor((GetServerTime() - last_death) / 60).."m")
    target.status:SetFontObject("GameFontNormal")
		target.announce.texture:SetColorTexture(0, 0, 1, front_opacity)
	else
		target.status:SetText("--")
    target.status:SetFontObject("GameFontNormal")
		target.announce.texture:SetColorTexture(0, 0, 0, front_opacity)
	end
end

function RTM:UpdateShardNumber(shard_number)
	if shard_number then
		self.shard_id_frame.status_text:SetText(L["Shard ID: "]..(shard_number + 42))
	else
		self.shard_id_frame.status_text:SetText(L["Shard ID: Unknown"])
	end
end

function RTM:CorrectFavoriteMarks()
	for i=1, #self.rare_ids do
		local npc_id = self.rare_ids[i]
		
		if RTMDB.favorite_rares[npc_id] then
			self.entities_frame.entities[npc_id].favorite.texture:SetColorTexture(0, 1, 0, 1)
		else
			self.entities_frame.entities[npc_id].favorite.texture:SetColorTexture(0, 0, 0, front_opacity)
		end
	end
end

function RTM:UpdateDailyKillMark(npc_id)
	if not self.completion_quest_ids[npc_id] then
		return
	end
	
	-- Multiple NPCs might share the same quest id.
	local completion_quest_id = self.completion_quest_ids[npc_id]
	local npc_ids = self.completion_quest_inverse[completion_quest_id]
	
	for _, target_npc_id in pairs(npc_ids) do
		if self.completion_quest_ids[target_npc_id] and IsQuestFlaggedCompleted(self.completion_quest_ids[target_npc_id]) then
			self.entities_frame.entities[target_npc_id].name:SetText(self.rare_names[target_npc_id])
			self.entities_frame.entities[target_npc_id].name:SetFontObject("GameFontRed")
		else
			self.entities_frame.entities[target_npc_id].name:SetText(self.rare_names[target_npc_id])
			self.entities_frame.entities[target_npc_id].name:SetFontObject("GameFontNormal")
		end
	end
end

function RTM:UpdateAllDailyKillMarks()
	for i=1, #RTM.rare_ids do
		local npc_id = RTM.rare_ids[i]
		self:UpdateDailyKillMark(npc_id)
	end
end

function RTM.InitializeFavoriteIconFrame(f)
	f.favorite_icon = CreateFrame("Frame", "RTM.favorite_icon", f)
	f.favorite_icon:SetSize(10, 10)
	f.favorite_icon:SetPoint("TOPLEFT", f, frame_padding + 1, -(frame_padding + 3))

	f.favorite_icon.texture = f.favorite_icon:CreateTexture(nil, "OVERLAY")
	f.favorite_icon.texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\Favorite.tga")
	f.favorite_icon.texture:SetSize(10, 10)
	f.favorite_icon.texture:SetPoint("CENTER", f.favorite_icon)
	
	f.favorite_icon.tooltip = CreateFrame("Frame", nil, UIParent)
	f.favorite_icon.tooltip:SetSize(300, 18)
	
	local texture = f.favorite_icon.tooltip:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.favorite_icon.tooltip)
	f.favorite_icon.tooltip.texture = texture
	f.favorite_icon.tooltip:SetPoint("TOPLEFT", f, 0, 19)
	f.favorite_icon.tooltip:Hide()
	
	f.favorite_icon.tooltip.text = f.favorite_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.favorite_icon.tooltip.text:SetJustifyH("LEFT")
	f.favorite_icon.tooltip.text:SetJustifyV("TOP")
	f.favorite_icon.tooltip.text:SetPoint("TOPLEFT", f.favorite_icon.tooltip, 5, -3)
	f.favorite_icon.tooltip.text:SetText(L["Click on the squares to add rares to your favorites."])
	
	f.favorite_icon:SetScript("OnEnter",
		function(self)
			self.tooltip:Show()
		end
	);
	
	f.favorite_icon:SetScript("OnLeave",
		function(self)
			self.tooltip:Hide()
		end
	);
end

function RTM.InitializeAnnounceIconFrame(f)
	f.broadcast_icon = CreateFrame("Frame", "RTM.broadcast_icon", f)
	f.broadcast_icon:SetSize(10, 10)
	f.broadcast_icon:SetPoint("TOPLEFT", f, 2 * frame_padding + favorite_rares_width + 1, -(frame_padding + 3))

	f.broadcast_icon.texture = f.broadcast_icon:CreateTexture(nil, "OVERLAY")
	f.broadcast_icon.texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\Broadcast.tga")
	f.broadcast_icon.texture:SetSize(10, 10)
	f.broadcast_icon.texture:SetPoint("CENTER", f.broadcast_icon)
	f.broadcast_icon.icon_state = false
	
	f.broadcast_icon.tooltip = CreateFrame("Frame", nil, UIParent)
	f.broadcast_icon.tooltip:SetSize(273, 68)
	
	local texture = f.broadcast_icon.tooltip:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.broadcast_icon.tooltip)
	f.broadcast_icon.tooltip.texture = texture
	f.broadcast_icon.tooltip:SetPoint("TOPLEFT", f, 0, 69)
	f.broadcast_icon.tooltip:Hide()
	
	f.broadcast_icon.tooltip.text1 = f.broadcast_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.broadcast_icon.tooltip.text1:SetJustifyH("LEFT")
	f.broadcast_icon.tooltip.text1:SetJustifyV("TOP")
	f.broadcast_icon.tooltip.text1:SetPoint("TOPLEFT", f.broadcast_icon.tooltip, 5, -3)
	f.broadcast_icon.tooltip.text1:SetText(L["Click on the squares to announce rare timers."])
	
	f.broadcast_icon.tooltip.text2 = f.broadcast_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.broadcast_icon.tooltip.text2:SetJustifyH("LEFT")
	f.broadcast_icon.tooltip.text2:SetJustifyV("TOP")
	f.broadcast_icon.tooltip.text2:SetPoint("TOPLEFT", f.broadcast_icon.tooltip, 5, -15)
	f.broadcast_icon.tooltip.text2:SetText(L["Left click: report to general chat"])
	
	f.broadcast_icon.tooltip.text3 = f.broadcast_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.broadcast_icon.tooltip.text3:SetJustifyH("LEFT")
	f.broadcast_icon.tooltip.text3:SetJustifyV("TOP")
	f.broadcast_icon.tooltip.text3:SetPoint("TOPLEFT", f.broadcast_icon.tooltip, 5, -27)
	f.broadcast_icon.tooltip.text3:SetText(L["Control-left click: report to party/raid chat"])
	
	f.broadcast_icon.tooltip.text4 = f.broadcast_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.broadcast_icon.tooltip.text4:SetJustifyH("LEFT")
	f.broadcast_icon.tooltip.text4:SetJustifyV("TOP")
	f.broadcast_icon.tooltip.text4:SetPoint("TOPLEFT", f.broadcast_icon.tooltip, 5, -39)
	f.broadcast_icon.tooltip.text4:SetText(L["Alt-left click: report to say"])
	  
	f.broadcast_icon.tooltip.text5 = f.broadcast_icon.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.broadcast_icon.tooltip.text5:SetJustifyH("LEFT")
	f.broadcast_icon.tooltip.text5:SetJustifyV("TOP")
	f.broadcast_icon.tooltip.text5:SetPoint("TOPLEFT", f.broadcast_icon.tooltip, 5, -51)
	f.broadcast_icon.tooltip.text5:SetText(L["Right click: set waypoint if available"])
	
	f.broadcast_icon:SetScript("OnEnter",
		function(self)
			self.tooltip:Show()
		end
	);
	
	f.broadcast_icon:SetScript("OnLeave",
		function(self)
			self.tooltip:Hide()
		end
	);
end

function RTM:InitializeReloadButton(f)
	f.reload_button = CreateFrame("Button", "RTM.reload_button", f)
	f.reload_button:SetSize(10, 10)
	f.reload_button:SetPoint("TOPRIGHT", f, -2 * frame_padding, -(frame_padding + 3))

	f.reload_button.texture = f.reload_button:CreateTexture(nil, "OVERLAY")
	f.reload_button.texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\Reload.tga")
	f.reload_button.texture:SetSize(10, 10)
	f.reload_button.texture:SetPoint("CENTER", f.reload_button)
	
	-- Create a tooltip window.
	f.reload_button.tooltip = CreateFrame("Frame", nil, UIParent)
	f.reload_button.tooltip:SetSize(390, 34)
	
	local texture = f.reload_button.tooltip:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, front_opacity)
	texture:SetAllPoints(f.reload_button.tooltip)
	f.reload_button.tooltip.texture = texture
	f.reload_button.tooltip:SetPoint("TOPLEFT", f, 0, 35)
	f.reload_button.tooltip:Hide()
	
	f.reload_button.tooltip.text1 = f.reload_button.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.reload_button.tooltip.text1:SetJustifyH("LEFT")
	f.reload_button.tooltip.text1:SetJustifyV("TOP")
	f.reload_button.tooltip.text1:SetPoint("TOPLEFT", f.reload_button.tooltip, 5, -3)
	f.reload_button.tooltip.text1:SetText(L["Reset your data and replace it with the data of others."])
	
	f.reload_button.tooltip.text2 = f.reload_button.tooltip:CreateFontString(nil, nil, "GameFontNormal")
	f.reload_button.tooltip.text2:SetJustifyH("LEFT")
	f.reload_button.tooltip.text2:SetJustifyV("TOP")
	f.reload_button.tooltip.text2:SetPoint("TOPLEFT", f.reload_button.tooltip, 5, -15)
	f.reload_button.tooltip.text2:SetText(L["Note: you do not need to press this button to receive new timers."])
	
	-- Hide and show the tooltip on mouseover.
	f.reload_button:SetScript("OnEnter",
		function(self2)
			self2.tooltip:Show()
		end
	);
	
	f.reload_button:SetScript("OnLeave",
		function(self2)
			self2.tooltip:Hide()
		end
	);
	
	f.reload_button:SetScript("OnClick",
		function()
			if self.current_shard_id ~= nil and GetServerTime() - self.last_reload_time > 600 then
				print(L["<RTM> Resetting current rare timers and requesting up-to-date data."])
				self.is_alive = {}
				self.current_health = {}
				self.last_recorded_death = {}
				self.recorded_entity_death_ids = {}
				self.current_coordinates = {}
				self.reported_spawn_uids = {}
				self.reported_vignettes = {}
				self.last_reload_time = GetServerTime()
				
				-- Reset the cache.
				RTMDB.previous_records[self.current_shard_id] = nil
				
				-- Re-register your arrival in the shard.
				RTM:RegisterArrival(self.current_shard_id)
			elseif self.current_shard_id == nil then
				print(L["<RTM> Please target a non-player entity prior to resetting, "]..
						L["such that the addon can determine the current shard id."])
			else
				print(L["<RTM> The reset button is on cooldown. Please note that a reset is not needed "]..
					L["to receive new timers. If it is your intention to reset the data, "]..
					L["please do a /reload and click the reset button again."])
			end
		end
	);
end


function RTM:InitializeInterface()
	self:SetSize(
		entity_name_width + entity_status_width + 2 * favorite_rares_width + 5 * frame_padding,
		shard_id_frame_height + 3 * frame_padding + #self.rare_ids * 12 + 8
	)
	
	local texture = self:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, background_opacity)
	texture:SetAllPoints(self)
	self.texture = texture
	self:SetPoint("CENTER")
	
	-- Create a sub-frame for the entity names.
	self.shard_id_frame = self:InitializeShardNumberFrame()
	self.entities_frame = CreateFrame("Frame", "RTM.entities_frame", self)
	self:InitializeRareTableFrame(self.entities_frame)

	self:SetMovable(true)
	self:EnableMouse(true)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", self.StartMoving)
	self:SetScript("OnDragStop", self.StopMovingOrSizing)
	
	-- Add icons for the favorite and broadcast columns.
	self.InitializeFavoriteIconFrame(self)
	self.InitializeAnnounceIconFrame(self)
	
	-- Create a reset button.
	self:InitializeReloadButton(self)
	self:SetClampedToScreen(true)
	
	self:Hide()
end

-- ####################################################################
-- ##                       Options Interface                        ##
-- ####################################################################

-- The provided sound options.
local sound_options = {}
sound_options[''] = -1
sound_options["Rubber Ducky"] = 566121
sound_options["Cartoon FX"] = 566543
sound_options["Explosion"] = 566982
sound_options["Shing!"] = 566240
sound_options["Wham!"] = 566946
sound_options["Simon Chime"] = 566076
sound_options["War Drums"] = 567275
sound_options["Scourge Horn"] = 567386
sound_options["Pygmy Drums"] = 566508
sound_options["Cheer"] = 567283
sound_options["Humm"] = 569518
sound_options["Short Circuit"] = 568975
sound_options["Fel Portal"] = 569215
sound_options["Fel Nova"] = 568582
sound_options["PVP Flag"] = 569200
sound_options["Beware!"] = 543587
sound_options["Laugh"] = 564859
sound_options["Not Prepared"] = 552503
sound_options["I am Unleashed"] = 554554
sound_options["I see you"] = 554236

local sound_options_inverse = {}
for key, value in pairs(sound_options) do
	sound_options_inverse[value] = key
end

function RTM.IntializeSoundSelectionMenu(parent_frame)
	local f = CreateFrame("frame", "RTM.options_panel.sound_selection", parent_frame, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(f, 140)
	UIDropDownMenu_SetText(f, sound_options_inverse[RTMDB.selected_sound_number])
	
	f.onClick = function(_, sound_id, _, _)
		RTMDB.selected_sound_number = sound_id
		UIDropDownMenu_SetText(f, sound_options_inverse[RTMDB.selected_sound_number])
		PlaySoundFile(RTMDB.selected_sound_number)
	end
	
	f.initialize = function()
		local info = UIDropDownMenu_CreateInfo()
		
		for key, value in pairs(sound_options) do
			info.text = key
			info.arg1 = value
			info.func = f.onClick
			info.menuList = key
			info.checked = RTMDB.selected_sound_number == value
			UIDropDownMenu_AddButton(info)
		end
	end
	
	f.label = f:CreateFontString(nil, "BORDER", "GameFontNormal")
	f.label:SetJustifyH("LEFT")
	f.label:SetText(L["Favorite sound alert"])
	f.label:SetPoint("TOPLEFT", parent_frame)
	
	f:SetPoint("TOPLEFT", f.label, -20, -13)
	
	return f
end

function RTM:IntializeMinimapCheckbox(parent_frame)
	local f = CreateFrame(
		"CheckButton", "RTM.options_panel.minimap_checkbox", parent_frame, "ChatConfigCheckButtonTemplate"
	)
	
	getglobal(f:GetName() .. 'Text'):SetText(L[" Show minimap icon"]);
	f.tooltip = L["Show or hide the minimap button."];
	f:SetScript("OnClick",
		function()
			RTMDB.minimap_icon_enabled = not RTMDB.minimap_icon_enabled
			if not RTMDB.minimap_icon_enabled then
				self.icon:Hide("RTM_icon")
			elseif RTM.target_zones[C_Map.GetBestMapForUnit("player")] then
				self.icon:Show("RTM_icon")
			end
		end
	);
	f:SetChecked(RTMDB.minimap_icon_enabled)
	f:SetPoint("TOPLEFT", parent_frame, 0, -53)
end

function RTM.IntializeRaidCommunicationCheckbox(parent_frame)
	local f = CreateFrame(
		"CheckButton", "RTM.options_panel.raid_comms_checkbox", parent_frame, "ChatConfigCheckButtonTemplate"
	)
	
	getglobal(f:GetName() .. 'Text'):SetText(L[" Enable communication over part/raid channel"])
	f.tooltip = L["Enable communication over party/raid channel, "]..
					L["to support CRZ functionality while in a party or raid group."]

	f:SetScript("OnClick",
		function()
			RTMDB.enable_raid_communication = not RTMDB.enable_raid_communication
		end
	);
	f:SetChecked(RTMDB.enable_raid_communication)
	f:SetPoint("TOPLEFT", parent_frame, 0, -75)
end

function RTM.IntializeDebugCheckbox(parent_frame)
	local f = CreateFrame("CheckButton", "RTM.options_panel.debug_checkbox", parent_frame, "ChatConfigCheckButtonTemplate")
	getglobal(f:GetName() .. 'Text'):SetText(L[" Enable debug mode"]);
	f.tooltip = L["Show or hide the minimap button."];
	f:SetScript("OnClick",
		function()
			RTMDB.debug_enabled = not RTMDB.debug_enabled
		end
	);
	f:SetChecked(RTMDB.debug_enabled)
	f:SetPoint("TOPLEFT", parent_frame, 0, -97)
end

function RTM:IntializeScaleSlider(parent_frame)
	local f = CreateFrame("Slider", "RTM.options_panel.scale_slider", parent_frame, "OptionsSliderTemplate")
	f.tooltip = L["Set the scale of the rare window."];
	f:SetMinMaxValues(0.5, 2)
	f:SetValueStep(0.05)
	f:SetValue(RTMDB.window_scale)
	self:SetScale(RTMDB.window_scale)
	f:Enable()
	
	f:SetScript("OnValueChanged",
		function(self2, value)
			-- Round the value to the nearest step value.
			value = math.floor(value * 20) / 20
		
			RTMDB.window_scale = value
			self2.label:SetText(L["Rare window scale "]..string.format("(%.2f)", RTMDB.window_scale))
			RTM:SetScale(RTMDB.window_scale)
		end
	);
	
	f.label = f:CreateFontString(nil, "BORDER", "GameFontNormal")
	f.label:SetJustifyH("LEFT")
	f.label:SetText(L["Rare window scale "]..string.format("(%.2f)", RTMDB.window_scale))
	f.label:SetPoint("TOPLEFT", parent_frame, 0, -125)
	
	f:SetPoint("TOPLEFT", f.label, 5, -15)
end

function RTM:InitializeButtons(parent_frame)
	parent_frame.reset_favorites_button = CreateFrame(
		"Button", "RTM.options_panel.reset_favorites_button", parent_frame, 'UIPanelButtonTemplate'
	)
	
	parent_frame.reset_favorites_button:SetText(L["Reset Favorites"])
	parent_frame.reset_favorites_button:SetSize(150, 25)
	parent_frame.reset_favorites_button:SetPoint("TOPLEFT", parent_frame, 0, -175)
	parent_frame.reset_favorites_button:SetScript("OnClick",
		function()
			RTMDB.favorite_rares = {}
			self:CorrectFavoriteMarks()
		end
	)
	
	parent_frame.reset_blacklist_button = CreateFrame(
		"Button", "RTM.options_panel.reset_blacklist_button", parent_frame, 'UIPanelButtonTemplate'
	)
	
	parent_frame.reset_blacklist_button:SetText(L["Reset Blacklist"])
	parent_frame.reset_blacklist_button:SetSize(150, 25)
	parent_frame.reset_blacklist_button:SetPoint("TOPRIGHT", parent_frame.reset_favorites_button, 155, 0)
	parent_frame.reset_blacklist_button:SetScript("OnClick",
		function()
			RTMDB.banned_NPC_ids = {}
		end
	)
end

function RTM:CreateRareSelectionEntry(npc_id, parent_frame, entry_data)
	local f = CreateFrame("Frame", "RTM.options_panel.rare_selection.frame.list["..npc_id.."]", parent_frame);
	f:SetSize(500, 12)
	
	f.enable = CreateFrame("Button", "RTM.options_panel.rare_selection.frame.list["..npc_id.."].enable", f);
	f.enable:SetSize(10, 10)
	local texture = f.enable:CreateTexture(nil, "BACKGROUND")
	
	if not RTMDB.ignore_rare[npc_id] then
		texture:SetColorTexture(0, 1, 0, 1)
	else
		texture:SetColorTexture(1, 0, 0, 1)
	end
	
	texture:SetAllPoints(f.enable)
	f.enable.texture = texture
	f.enable:SetPoint("TOPLEFT", f, 0, 0)
	f.enable:SetScript("OnClick",
		function()
			if not RTMDB.ignore_rare[npc_id] then
				if RTMDB.favorite_rares[npc_id] then
					print(L["<RTM> Favorites cannot be hidden."])
				else
					RTMDB.ignore_rare[npc_id] = true
					f.enable.texture:SetColorTexture(1, 0, 0, 1)
					RTM:ReorganizeRareTableFrame(RTM.entities_frame)
				end
			else
				RTMDB.ignore_rare[npc_id] = nil
				f.enable.texture:SetColorTexture(0, 1, 0, 1)
				RTM:ReorganizeRareTableFrame(RTM.entities_frame)
			end
		end
	)
	
	f.up = CreateFrame("Button", "RTM.options_panel.rare_selection.frame.list["..npc_id.."].up", f);
	f.up:SetSize(10, 10)
	texture = f.up:CreateTexture(nil, "OVERLAY")
	texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\UpArrow.tga")
	texture:SetSize(10, 10)
	texture:SetPoint("CENTER", f.up)
	texture:SetAllPoints(f.up)
	
	f.up.texture = texture
	f.up:SetPoint("TOPLEFT", f, 13, 0)
	
	f.up:SetScript("OnClick",
		function()
      -- Here, we use the most up-to-date entry data, instead of the one passed as an argument.
      local previous_entry = RTMDB.rare_ordering.__raw_data_table[npc_id].__previous
			RTMDB.rare_ordering:SwapNeighbors(previous_entry, npc_id)
			self.ReorderRareSelectionEntryItems(parent_frame)
			self:ReorganizeRareTableFrame(self.entities_frame)
		end
	)
		
	if entry_data.__previous == nil then
		f.up:Hide()
	end
	
	f.down = CreateFrame("Button", "RTM.options_panel.rare_selection.frame.list["..npc_id.."].down", f);
	f.down:SetSize(10, 10)
	texture = f.down:CreateTexture(nil, "OVERLAY")
	texture:SetTexture("Interface\\AddOns\\RareTrackerMechagon\\Icons\\DownArrow.tga")
	texture:SetSize(10, 10)
	texture:SetPoint("CENTER", f.down)
	texture:SetAllPoints(f.down)
	f.down.texture = texture
	f.down:SetPoint("TOPLEFT", f, 26, 0)
	
	f.down:SetScript("OnClick",
		function()
      -- Here, we use the most up-to-date entry data, instead of the one passed as an argument.
      local next_entry = RTMDB.rare_ordering.__raw_data_table[npc_id].__next
			RTMDB.rare_ordering:SwapNeighbors(npc_id, next_entry)
			self.ReorderRareSelectionEntryItems(parent_frame)
			self:ReorganizeRareTableFrame(self.entities_frame)
		end
	)

	if entry_data.__next == nil then
		f.down:Hide()
	end
	
	f.text = f:CreateFontString(nil, "BORDER", "GameFontNormal")
	f.text:SetJustifyH("LEFT")
	f.text:SetText(self.rare_names[npc_id])
	f.text:SetPoint("TOPLEFT", f, 42, 0)
	
	return f
end

function RTM.ReorderRareSelectionEntryItems(parent_frame)
	local i = 1
	RTMDB.rare_ordering:ForEach(
		function(npc_id, entry_data)
			local f = parent_frame.list_item[npc_id]
			if entry_data.__previous == nil then
				f.up:Hide()
			else
				f.up:Show()
			end
			
			if entry_data.__next == nil then
				f.down:Hide()
			else
				f.down:Show()
			end
				
			f:SetPoint("TOPLEFT", parent_frame, 1, -(i - 1) * 12 - 5)
			i = i + 1
		end
	)
end

function RTM:DisableAllRaresButton(parent_frame)
  parent_frame.reset_all_button = CreateFrame(
		"Button", "RTM.options_panel.rare_selection.reset_all_button", parent_frame, 'UIPanelButtonTemplate'
	)
	
	parent_frame.reset_all_button:SetText(L["Disable All"])
	parent_frame.reset_all_button:SetSize(150, 25)
	parent_frame.reset_all_button:SetPoint("TOPRIGHT", parent_frame, 0, 0)
	parent_frame.reset_all_button:SetScript("OnClick",
		function()
			for i=1, #self.rare_ids do
        local npc_id = self.rare_ids[i]
        if RTMDB.favorite_rares[npc_id] ~= true then
          RTMDB.ignore_rare[npc_id] = true
          parent_frame.list_item[npc_id].enable.texture:SetColorTexture(1, 0, 0, 1)
        end
      end
      self:ReorganizeRareTableFrame(self.entities_frame)
		end
	)
end

function RTM:EnableAllRaresButton(parent_frame)
  parent_frame.enable_all_button = CreateFrame(
		"Button", "RTM.options_panel.rare_selection.enable_all_button", parent_frame, 'UIPanelButtonTemplate'
	)
	
	parent_frame.enable_all_button:SetText(L["Enable All"])
	parent_frame.enable_all_button:SetSize(150, 25)
	parent_frame.enable_all_button:SetPoint("TOPRIGHT", parent_frame, 0, -25)
	parent_frame.enable_all_button:SetScript("OnClick",
		function()
      for i=1, #self.rare_ids do
        local npc_id = self.rare_ids[i]
        RTMDB.ignore_rare[npc_id] = nil
        parent_frame.list_item[npc_id].enable.texture:SetColorTexture(0, 1, 0, 1)
      end
      self:ReorganizeRareTableFrame(self.entities_frame)
		end
	)
end

function RTM:ResetRareOrderButton(parent_frame)
  parent_frame.reset_order_button = CreateFrame(
		"Button", "RTM.options_panel.rare_selection.reset_order_button", parent_frame, 'UIPanelButtonTemplate'
	)
	
	parent_frame.reset_order_button:SetText(L["Reset Order"])
	parent_frame.reset_order_button:SetSize(150, 25)
	parent_frame.reset_order_button:SetPoint("TOPRIGHT", parent_frame, 0, -50)
	parent_frame.reset_order_button:SetScript("OnClick",
		function()
			RTMDB.rare_ordering:Clear()
      for i=1, #self.rare_ids do
        local npc_id = self.rare_ids[i]
        RTMDB.rare_ordering:AddBack(npc_id)
      end
      self:ReorganizeRareTableFrame(self.entities_frame)
      self.ReorderRareSelectionEntryItems(parent_frame)
		end
	)
end

function RTM:InitializeRareSelectionChildMenu(parent_frame)
	parent_frame.rare_selection = CreateFrame("Frame", "RTM.options_panel.rare_selection", parent_frame)
	parent_frame.rare_selection.name = L["Rare ordering/selection"]
	parent_frame.rare_selection.parent = parent_frame.name
	InterfaceOptions_AddCategory(parent_frame.rare_selection)
	
	parent_frame.rare_selection.frame = CreateFrame(
      "Frame",
      "RTM.options_panel.rare_selection.frame",
      parent_frame.rare_selection
  )
  
	parent_frame.rare_selection.frame:SetPoint("LEFT", parent_frame.rare_selection, 101, 0)
	parent_frame.rare_selection.frame:SetSize(400, 500)
	
	local f = parent_frame.rare_selection.frame
	local i = 1
	f.list_item = {}
	
	RTMDB.rare_ordering:ForEach(
		function(npc_id, entry_data)
			f.list_item[npc_id] = self:CreateRareSelectionEntry(npc_id, f, entry_data)
			f.list_item[npc_id]:SetPoint("TOPLEFT", f, 1, -(i - 1) * 12 - 5)
			i = i + 1
		end
	)
  
  -- Add utility buttons.
  RTM:DisableAllRaresButton(f)
  RTM:EnableAllRaresButton(f)
  RTM:ResetRareOrderButton(f)
end

function RTM:InitializeConfigMenu()
	self.options_panel = CreateFrame("Frame", "RTM.options_panel", UIParent)
	self.options_panel.name = "RareTrackerMechagon"
	InterfaceOptions_AddCategory(self.options_panel)
	
	self.options_panel.frame = CreateFrame("Frame", "RTM.options_panel.frame", self.options_panel)
	self.options_panel.frame:SetPoint("TOPLEFT", self.options_panel, 11, -14)
	self.options_panel.frame:SetSize(500, 500)

	self.options_panel.sound_selector = self.IntializeSoundSelectionMenu(self.options_panel.frame)
	self.options_panel.minimap_checkbox = self:IntializeMinimapCheckbox(self.options_panel.frame)
	self.options_panel.raid_comms_checkbox = self.IntializeRaidCommunicationCheckbox(self.options_panel.frame)
	self.options_panel.debug_checkbox = self.IntializeDebugCheckbox(self.options_panel.frame)
	self.options_panel.scale_slider = self:IntializeScaleSlider(self.options_panel.frame)
	self:InitializeButtons(self.options_panel.frame)
	self:InitializeRareSelectionChildMenu(self.options_panel)
end