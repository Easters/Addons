-- ============================================================================
-- ilvl MODULE WITH CONFIGURATION PANEL
-- ============================================================================

local addonName, ns = ...
ns = ns or {}

ilvlDB = ilvlDB or {}
ns.db = ilvlDB

local ilvlMod = {
    initialized = false,
    applied = false,
    hooks = {},
    texts = {},
}

local isAscension = _G.PathToAscensionMicroButton ~= nil

local defaultConfig = {
    enabled = true,
    font_family = "expressway",
    font_size = 14,
    font_outline = "THICKOUTLINE",
    position = "BOTTOM",
    tooltip_cvar = true,
    bags = true,
    bank = true,
    guildbank = true,
    character = true,
    inspect = true,
    merchant = true,
    trade = true,
    loot = true,
    lootroll = true,
    mail = true,
    auction = true,
}

local function GetModuleConfig()
    if not ilvlDB then
        ilvlDB = {}
    end
    for k, v in pairs(defaultConfig) do
        if ilvlDB[k] == nil then
            ilvlDB[k] = v
        end
    end
    return ilvlDB
end

local function IsModuleEnabled()
    local config = GetModuleConfig()
    return config.enabled ~= false
end

local function IsContextEnabled(context)
    if not IsModuleEnabled() then return false end
    local config = GetModuleConfig()
    return config[context] ~= false
end

local Fonts = {
    ACTIONBAR = "Fonts\\FRIZQT__.TTF",
    PRIMARY = "Fonts\\FRIZQT__.TTF",
    NARROW = "Fonts\\ARIALN.TTF",
}

local function DelayedCall(delay, callback)
    C_Timer.After(delay, callback)
end

-- ============================================================================
-- ITEM LEVEL LOOKUP
-- ============================================================================

local NON_GEAR_SLOTS = {
    [""] = true,
    ["INVTYPE_NON_EQUIP"] = true,
    ["INVTYPE_BAG"] = true,
    ["INVTYPE_QUIVER"] = true,
    ["INVTYPE_AMMO"] = true,
    ["INVTYPE_BODY"] = true,
    ["INVTYPE_TABARD"] = true,
}

local levelCache = {}
local UpdateAll
local RefreshAllFonts, RefreshAllPositions, ApplyItemLevelSystem, RestoreItemLevelSystem
local retryScheduled = false
local retryBudget = 0

local function ScheduleRetry()
    if retryScheduled or retryBudget <= 0 then return end
    retryScheduled = true
    retryBudget = retryBudget - 1
    DelayedCall(0.5, function()
        retryScheduled = false
        if UpdateAll then UpdateAll() end
    end)
end

local function RefillRetryBudget()
    retryBudget = 3
end

local pendingUpdates = {}

local function Debounce(key, delay, callback)
    if pendingUpdates[key] then return end
    pendingUpdates[key] = true
    DelayedCall(delay, function()
        pendingUpdates[key] = nil
        callback()
    end)
end

local function GetLevelInfo(link)
    if not link then return nil end
    local itemID = link:match("item:(%d+)")
    if itemID then
        local cached = levelCache[itemID]
        if cached == false then return nil end
        if cached then return math.floor(cached / 10), cached % 10 end
    end

    local _, _, quality, ilvl, _, _, _, _, equipSlot = GetItemInfo(link)
    if not ilvl then return nil, nil, true end

    if ilvl <= 0 or NON_GEAR_SLOTS[equipSlot or ""] then
        if itemID then levelCache[itemID] = false end
        return nil
    end

    if itemID then levelCache[itemID] = (ilvl * 10) + (quality or 1) end
    return ilvl, quality
end

-- ============================================================================
-- TEXT OVERLAY
-- ============================================================================

local function ResolveFontPath()
    return Fonts.ACTIONBAR or "Fonts\\FRIZQT__.TTF"
end

local function ApplyFont(fontString, sizeDelta)
    local config = GetModuleConfig()
    local size = ((config and config.font_size) or 14) + (sizeDelta or 0)
    local path = ResolveFontPath()
    local outline = "THICKOUTLINE"

    fontString:SetFont(path, size, outline)
end

local TEXT_POSITIONS = {
    BOTTOM = { "BOTTOM", "BOTTOM", 0, 2 },
    CENTER = { "CENTER", "CENTER", 0, 0 },
    TOP = { "TOP", "TOP", 0, -2 },
}

local function ResolveTextPosition()
    local config = GetModuleConfig()
    local pos = config and config.position
    if pos and TEXT_POSITIONS[pos] then return pos end
    return "BOTTOM"
end

local function ApplyTextPosition(fontString, anchor)
    local pos = ResolveTextPosition()
    local p = TEXT_POSITIONS[pos]
    fontString:ClearAllPoints()
    fontString:SetPoint(p[1], anchor, p[2], p[3], p[4])
    fontString.__ilvlPos = pos
    fontString.__ilvlAnchor = anchor
end

function RefreshAllPositions()
    for button, fontString in pairs(ilvlMod.texts) do
        if fontString then
            ApplyTextPosition(fontString, fontString.__ilvlAnchor or button)
        end
    end
end

local function GetOrCreateText(button, anchorTo)
    local anchor = anchorTo or button
    local fontString = button.__ilvlText
    if not fontString then
        fontString = button:CreateFontString(nil, "OVERLAY")
        fontString:SetDrawLayer("OVERLAY", 7)
        fontString:SetJustifyH("CENTER")
        ApplyFont(fontString)
        button.__ilvlText = fontString
        ilvlMod.texts[button] = fontString
    end
    ApplyTextPosition(fontString, anchor)
    return fontString
end

local function HideButtonItemLevel(button)
    local fontString = button and button.__ilvlText
    if fontString then fontString:Hide() end
end

local function DrawItemLevel(button, ilvl, r, g, b, anchorTo)
    if not ilvl then
        HideButtonItemLevel(button)
        return
    end
    local fontString = GetOrCreateText(button, anchorTo)
    fontString:SetText(ilvl)
    fontString:SetTextColor(r or 1, g or 1, b or 1)
    fontString:Show()
end

local function SetButtonItemLevel(button, link, anchorTo, context)
    if not button then return end
    if not IsModuleEnabled() or (context and not IsContextEnabled(context)) then
        HideButtonItemLevel(button)
        return
    end
    if not link then
        HideButtonItemLevel(button)
        return
    end

    local ilvlVal, quality, needsRetry = GetLevelInfo(link)
    if needsRetry then ScheduleRetry() end

    if not ilvlVal then
        HideButtonItemLevel(button)
        return
    end

    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if color then
        DrawItemLevel(button, ilvlVal, color.r, color.g, color.b, anchorTo)
    else
        DrawItemLevel(button, ilvlVal, 1, 1, 1, anchorTo)
    end
end

_G.UpdateItemLevelSlot = SetButtonItemLevel

local function HideAllTexts()
    for _, fontString in pairs(ilvlMod.texts) do
        if fontString then fontString:Hide() end
    end
end

function RefreshAllFonts()
    for _, fontString in pairs(ilvlMod.texts) do
        if fontString then ApplyFont(fontString) end
    end
end

-- ============================================================================
-- FRAME UPDATE LOGIC
-- ============================================================================

local function UpdateContainerFrame(frame)
    if not frame or not IsModuleEnabled() then return end
    local bag = frame:GetID()
    local ctx = (bag >= 5 and bag <= 11) and "bank" or "bags"
    if not IsContextEnabled(ctx) then return end

    local frameName = frame:GetName()
    local size = frame.size or GetContainerNumSlots(bag)
    for i = 1, size do
        local button = _G[frameName .. "Item" .. i]
        if button then
            SetButtonItemLevel(button, GetContainerItemLink(bag, button:GetID()))
        end
    end
end

local function UpdateAllContainerFrames()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            UpdateContainerFrame(frame)
        end
    end
end

local function UpdateBankSlots()
    if not IsContextEnabled("bank") or not BankFrame or not BankFrame:IsShown() then return end
    for i = 1, 28 do
        local button = _G["BankFrameItem" .. i]
        if button then
            SetButtonItemLevel(button, GetContainerItemLink(-1, button:GetID()))
        end
    end
end

local function UpdateGuildBankSlots()
    if not IsContextEnabled("guildbank") or not IsAddOnLoaded("Blizzard_GuildBankUI") or not GuildBankFrame or not GuildBankFrame:IsShown() then return end
    local tab = GetCurrentGuildBankTab()
    for i = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local index = math.fmod(i, 14)
        if index == 0 then index = 14 end
        local column = math.ceil((i - 0.5) / 14)
        local button = _G["GuildBankColumn" .. column .. "Button" .. index]
        if button then
            SetButtonItemLevel(button, GetGuildBankItemLink(tab, i))
        end
    end
end

local EQUIP_SLOT_FRAMES = {
    "CharacterAmmoSlot", "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
    "CharacterShirtSlot", "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot",
    "CharacterFeetSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterFinger0Slot",
    "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterBackSlot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterTabardSlot",
}

local INSPECT_SLOT_FRAMES = {
    "InspectHeadSlot", "InspectNeckSlot", "InspectShoulderSlot", "InspectShirtSlot",
    "InspectChestSlot", "InspectWaistSlot", "InspectLegsSlot", "InspectFeetSlot",
    "InspectWristSlot", "InspectHandsSlot", "InspectFinger0Slot", "InspectFinger1Slot",
    "InspectTrinket0Slot", "InspectTrinket1Slot", "InspectBackSlot",
    "InspectMainHandSlot", "InspectSecondaryHandSlot", "InspectRangedSlot", "InspectTabardSlot",
}

local function ResolveSlotFrame(frameName)
    local ascensionName = "Ascension" .. frameName
    if _G[ascensionName] then return ascensionName end
    return frameName
end

local SKIPPED_SLOT_IDS = { [0] = true, [4] = true, [19] = true, [20] = true, [21] = true, [22] = true, [23] = true }

local function UpdateCharacterSlot(button)
    if not button or not IsContextEnabled("character") then return end
    local slotID = button:GetID()
    if not slotID or slotID < 0 or SKIPPED_SLOT_IDS[slotID] then
        HideButtonItemLevel(button)
        return
    end
    SetButtonItemLevel(button, GetInventoryItemLink("player", slotID))
end

local ITEM_LEVEL_PREFIX = string.gsub(ITEM_LEVEL or "Item Level %d", "%%d.*", "")
local scanTip, scanTipName
local inspectDataReady = false

local function ScanInspectSlot(unit, slotID)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ilvlScanTip", nil, "GameTooltipTemplate")
        scanTipName = scanTip:GetName()
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetInventoryItem(unit, slotID)

    local ilvlVal
    for i = 2, (scanTip:NumLines() or 0) do
        local line = _G[scanTipName .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and string.find(text, ITEM_LEVEL_PREFIX, 1, true) then
            ilvlVal = tonumber(string.match(text, "(%d+)"))
            if ilvlVal then break end
        end
    end
    local r, g, b
    local nameLine = _G[scanTipName .. "TextLeft1"]
    if nameLine then r, g, b = nameLine:GetTextColor() end
    local _, link = scanTip:GetItem()
    scanTip:Hide()
    return ilvlVal, link, r, g, b
end

local function GetInspectFrame()
    return _G.AscensionInspectFrame or InspectFrame
end

local function UpdateInspectSlot(button)
    if not button or not IsContextEnabled("inspect") then return end
    local inspectFrame = GetInspectFrame()
    if not inspectFrame or not inspectFrame.unit then return end
    local slotID = button:GetID()
    if not slotID or slotID < 0 or SKIPPED_SLOT_IDS[slotID] then
        HideButtonItemLevel(button)
        return
    end
    local unit = inspectFrame.unit
    if not inspectDataReady or not GetInventoryItemTexture(unit, slotID) then
        HideButtonItemLevel(button)
        return
    end
    local ilvlVal, link, r, g, b = ScanInspectSlot(unit, slotID)
    if ilvlVal then
        DrawItemLevel(button, ilvlVal, r, g, b)
        return
    end
    SetButtonItemLevel(button, link or GetInventoryItemLink(unit, slotID))
end

local function HideInspectTexts()
    for _, frameName in ipairs(INSPECT_SLOT_FRAMES) do
        local button = _G[ResolveSlotFrame(frameName)]
        if button then HideButtonItemLevel(button) end
    end
end

local function UpdateAllCharacterSlots()
    if not IsContextEnabled("character") then return end
    for _, frameName in ipairs(EQUIP_SLOT_FRAMES) do
        local button = _G[ResolveSlotFrame(frameName)]
        if button then UpdateCharacterSlot(button) end
    end
end

local function UpdateAllInspectSlots()
    if not IsContextEnabled("inspect") then return end
    local inspectFrame = GetInspectFrame()
    if not inspectFrame or not inspectFrame:IsShown() then return end
    for _, frameName in ipairs(INSPECT_SLOT_FRAMES) do
        local button = _G[ResolveSlotFrame(frameName)]
        if button then UpdateInspectSlot(button) end
    end
end

local function UpdateMerchantItems()
    if not IsContextEnabled("merchant") or not MerchantFrame or not MerchantFrame:IsShown() then return end
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    for i = 1, perPage do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then SetButtonItemLevel(button, GetMerchantItemLink(((page - 1) * perPage) + i)) end
    end
end

local function UpdateBuybackItems()
    if not IsContextEnabled("merchant") or not MerchantFrame or not MerchantFrame:IsShown() then return end
    for i = 1, (BUYBACK_ITEMS_PER_PAGE or 12) do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button then SetButtonItemLevel(button, GetBuybackItemLink(i)) end
    end
end

local function UpdateMerchantActiveTab()
    if MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 2 then
        UpdateBuybackItems()
    else
        UpdateMerchantItems()
    end
end

local function UpdateTradeItems()
    if not IsContextEnabled("trade") or not TradeFrame or not TradeFrame:IsShown() then return end
    for i = 1, 7 do
        local pb = _G["TradePlayerItem" .. i .. "ItemButton"]
        if pb then SetButtonItemLevel(pb, GetTradePlayerItemLink(i)) end
        local tb = _G["TradeRecipientItem" .. i .. "ItemButton"]
        if tb then SetButtonItemLevel(tb, GetTradeTargetItemLink(i)) end
    end
end

local function UpdateLootButton(index)
    if not IsContextEnabled("loot") then return end
    local button = _G["LootButton" .. index]
    if not button then return end
    local icon = _G["LootButton" .. index .. "IconTexture"]
    local link = button.slot and GetLootSlotLink(button.slot) or nil
    SetButtonItemLevel(button, button:IsShown() and link or nil, icon)
end

local function UpdateAllLootButtons()
    if not IsContextEnabled("loot") or not LootFrame or not LootFrame:IsShown() then return end
    for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do UpdateLootButton(i) end
end

local function UpdateLootRollFrame(frame)
    if not frame or not IsContextEnabled("lootroll") then return end
    local id = frame:GetID()
    local iconFrame = _G["GroupLootFrame" .. id .. "IconFrame"]
    if iconFrame then
        SetButtonItemLevel(iconFrame, frame.rollID and GetLootRollItemLink(frame.rollID) or nil)
    end
end

local function UpdateOpenMailAttachments()
    if not IsContextEnabled("mail") or not OpenMailFrame or not OpenMailFrame:IsShown() then return end
    local mailID = InboxFrame and InboxFrame.openMailID
    for i = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
        local button = _G["OpenMailAttachmentButton" .. i]
        if button then SetButtonItemLevel(button, mailID and GetInboxItemLink(mailID, i) or nil) end
    end
end

local function UpdateSendMailAttachments()
    if not IsContextEnabled("mail") or not SendMailFrame or not SendMailFrame:IsShown() then return end
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local button = _G["SendMailAttachment" .. i]
        if button then SetButtonItemLevel(button, GetSendMailItemLink and GetSendMailItemLink(i) or nil) end
    end
end

local function UpdateAuctionItems()
    if not IsContextEnabled("auction") or not IsAddOnLoaded("Blizzard_AuctionUI") or not AuctionFrame or not AuctionFrame:IsShown() then return end
    local lists = {
        { prefix = "Browse", list = "list", scroll = "BrowseScrollFrame", count = "NUM_BROWSE_TO_DISPLAY" },
        { prefix = "Bid", list = "bidder", scroll = "BidScrollFrame", count = "NUM_BIDS_TO_DISPLAY" },
        { prefix = "Auctions", list = "owner", scroll = "AuctionsScrollFrame", count = "NUM_AUCTIONS_TO_DISPLAY" },
    }
    for _, entry in ipairs(lists) do
        local scroll = _G[entry.scroll]
        if scroll then
            local offset = FauxScrollFrame_GetOffset(scroll) or 0
            for i = 1, (_G[entry.count] or 8) do
                local button = _G[entry.prefix .. "Button" .. i .. "Item"]
                if button then
                    local link = button:GetParent() and button:GetParent():IsShown() and GetAuctionItemLink(entry.list, offset + i) or nil
                    SetButtonItemLevel(button, link)
                end
            end
        end
    end
end

function UpdateAll()
    if not IsModuleEnabled() then return end
    UpdateAllContainerFrames()
    UpdateBankSlots()
    UpdateGuildBankSlots()
    UpdateAllCharacterSlots()
    UpdateAllInspectSlots()
    UpdateMerchantActiveTab()
    UpdateTradeItems()
    UpdateAllLootButtons()
    UpdateOpenMailAttachments()
    UpdateSendMailAttachments()
    UpdateAuctionItems()
end

local function ApplyTooltipCVar()
    local config = GetModuleConfig()
    if config and config.tooltip_cvar and IsModuleEnabled() then
        SetCVar("showItemLevel", 1)
    end
end

-- ============================================================================
-- HOOK INSTALLATIONS & REFRESHERS
-- ============================================================================

local function InstallInspectHooks()
    if ilvlMod.hooks["Inspect"] then return end
    if isAscension then
        if not _G.AscensionInspectFrame then return end
        hooksecurefunc(AscensionInspectFrame, "UpdateCharacterInfo", function()
            inspectDataReady = true
            UpdateAllInspectSlots()
        end)
        AscensionInspectFrame:HookScript("OnShow", function()
            RefillRetryBudget()
            inspectDataReady = false
            HideInspectTexts()
            Debounce("inspectfallback", 1.5, function()
                if not inspectDataReady then
                    inspectDataReady = true
                    UpdateAllInspectSlots()
                end
            end)
        end)
    else
        if not InspectPaperDollItemSlotButton_Update then return end
        hooksecurefunc("InspectPaperDollItemSlotButton_Update", UpdateInspectSlot)
    end
    ilvlMod.hooks["Inspect"] = true
end

local function InstallGuildBankHooks()
    if ilvlMod.hooks["GuildBank"] or not GuildBankFrame_Update then return end
    hooksecurefunc("GuildBankFrame_Update", UpdateGuildBankSlots)
    ilvlMod.hooks["GuildBank"] = true
end

local function InstallAuctionHooks()
    if ilvlMod.hooks["Auction"] or not AuctionFrameBrowse_Update then return end
    hooksecurefunc("AuctionFrameBrowse_Update", UpdateAuctionItems)
    if AuctionFrameBid_Update then hooksecurefunc("AuctionFrameBid_Update", UpdateAuctionItems) end
    if AuctionFrameAuctions_Update then hooksecurefunc("AuctionFrameAuctions_Update", UpdateAuctionItems) end
    ilvlMod.hooks["Auction"] = true
end

function ApplyItemLevelSystem()
    if ilvlMod.applied then return end
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", UpdateContainerFrame) end
    if BankFrameItemButton_Update then
        hooksecurefunc("BankFrameItemButton_Update", function(button)
            if not IsContextEnabled("bank") or not BankFrame or not BankFrame:IsShown() or button.isBag then return end
            SetButtonItemLevel(button, GetContainerItemLink(-1, button:GetID()))
        end)
    end
    if PaperDollItemSlotButton_Update then hooksecurefunc("PaperDollItemSlotButton_Update", UpdateCharacterSlot) end
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function() DelayedCall(0.05, UpdateAllCharacterSlots) end)
    end
    if isAscension and _G.AscensionCharacterFrame then
        AscensionCharacterFrame:HookScript("OnShow", function()
            RefillRetryBudget()
            DelayedCall(0.05, UpdateAllCharacterSlots)
        end)
    end
    if MerchantFrame_UpdateMerchantInfo then hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchantItems) end
    if MerchantFrame_UpdateBuybackInfo then hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateBuybackItems) end
    if TradeFrame_UpdatePlayerItem then
        hooksecurefunc("TradeFrame_UpdatePlayerItem", function(id)
            if not IsContextEnabled("trade") then return end
            local b = _G["TradePlayerItem" .. id .. "ItemButton"]
            if b then SetButtonItemLevel(b, GetTradePlayerItemLink(id)) end
        end)
        hooksecurefunc("TradeFrame_UpdateTargetItem", function(id)
            if not IsContextEnabled("trade") then return end
            local b = _G["TradeRecipientItem" .. id .. "ItemButton"]
            if b then SetButtonItemLevel(b, GetTradeTargetItemLink(id)) end
        end)
    end
    if LootFrame_UpdateButton then hooksecurefunc("LootFrame_UpdateButton", UpdateLootButton) end
    if GroupLootFrame_OnShow then hooksecurefunc("GroupLootFrame_OnShow", UpdateLootRollFrame) end
    if OpenMail_Update then hooksecurefunc("OpenMail_Update", UpdateOpenMailAttachments) end
    if SendMailFrame_Update then hooksecurefunc("SendMailFrame_Update", SendMailFrame_Update) end

    InstallInspectHooks()
    InstallGuildBankHooks()
    InstallAuctionHooks()
    ApplyTooltipCVar()
    RefillRetryBudget()
    DelayedCall(0.5, UpdateAll)
    ilvlMod.applied = true
    ilvlMod.initialized = true
end

function RestoreItemLevelSystem()
    if not ilvlMod.applied then return end
    HideAllTexts()
    ilvlMod.applied = false
end

local function RefreshModuleState()
    if IsModuleEnabled() then
        ApplyItemLevelSystem()
        RefillRetryBudget()
        UpdateAll()
        RefreshAllFonts()
        RefreshAllPositions()
    else
        RestoreItemLevelSystem()
    end
end

-- ============================================================================
-- CUSTOM OPTIONS PANEL
-- ============================================================================

local function CreateCustomDropdown(name, parent, width, items, getFunc, setFunc)
    local dropdown = CreateFrame("Button", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)

    dropdown.RefreshValue = function()
        local currentVal = getFunc()
        for _, item in ipairs(items) do
            if item.value == currentVal then
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                break
            end
        end
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local currentVal = getFunc()
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.func = function(btn)
                setFunc(btn.value)
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                RefreshModuleState()
            end
            info.checked = (currentVal == item.value)
            UIDropDownMenu_AddButton(info)
        end
    end)
    dropdown:RefreshValue()
    return dropdown
end

local function CreateSettingsPanel()
    if _G["ilvlOptionsPanel"] then return end

    local panel = CreateFrame("Frame", "ilvlOptionsPanel", UIParent)
    panel.name = "ilvl"

    -- Header Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ilvl")

    -- Font Size Slider
    local sizeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
    sizeLabel:SetText("Font Size")

    local slider = CreateFrame("Slider", "ilvlFontSizeSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 6, -8)
    slider:SetWidth(150)
    slider:SetMinMaxValues(8, 18)
    slider:SetValueStep(1)
    slider:SetValue(GetModuleConfig().font_size or 14)
    _G[slider:GetName() .. "Low"]:SetText("8")
    _G[slider:GetName() .. "High"]:SetText("18")
    
    local sliderText = _G[slider:GetName() .. "Text"]
    if sliderText then
        sliderText:SetText("")
    end

    local valueDisplay = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueDisplay:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    valueDisplay:SetText(tostring(GetModuleConfig().font_size or 14))

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        GetModuleConfig().font_size = value
        if valueDisplay then
            valueDisplay:SetText(tostring(value))
        end
        RefreshAllFonts()
    end)

    -- Position Dropdown
    local posLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    posLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 220, -20)
    posLabel:SetText("Position")

    local posDropdown = CreateCustomDropdown("ilvlPosDropdown", panel, 130, {
        { text = "Bottom", value = "BOTTOM" },
        { text = "Center", value = "CENTER" },
        { text = "Top", value = "TOP" },
    }, function()
        return GetModuleConfig().position
    end, function(val)
        GetModuleConfig().position = val
        RefreshAllPositions()
    end)
    posDropdown:SetPoint("TOPLEFT", posLabel, "BOTTOMLEFT", -18, -4)

    panel.refresh = function()
        local config = GetModuleConfig()
        if slider and slider.SetValue then
            slider:SetValue(config.font_size or 14)
            if valueDisplay then
                valueDisplay:SetText(tostring(config.font_size or 14))
            end
        end
        if posDropdown and posDropdown.RefreshValue then posDropdown:RefreshValue() end
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end

    return panel
end

-- ============================================================================
-- EVENT HANDLER
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
eventFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_UPDATE")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
eventFrame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("MAIL_SEND_INFO_UPDATE")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
eventFrame:RegisterEvent("INSPECT_TALENT_READY")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "ilvl" then
            print("|cff00ff00ilvl by Easters loaded successfully!|r")
        end
        GetModuleConfig()
        CreateSettingsPanel()
        if arg1 == "Blizzard_InspectUI" or arg1 == "Ascension_InspectUI" then
            InstallInspectHooks()
        elseif arg1 == "Blizzard_GuildBankUI" then
            InstallGuildBankHooks()
        elseif arg1 == "Blizzard_AuctionUI" then
            InstallAuctionHooks()
        end
        return
    end

    if not IsModuleEnabled() then return end

    if event == "PLAYER_ENTERING_WORLD" then
        DelayedCall(1.0, ApplyItemLevelSystem)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Debounce("character", 0.2, UpdateAllCharacterSlots)
    elseif event == "BAG_UPDATE" then
        Debounce("bags", 0.2, UpdateAllContainerFrames)
    elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        RefillRetryBudget()
        Debounce("bank", 0.2, UpdateBankSlots)
    elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKBAGSLOTS_CHANGED" then
        RefillRetryBudget()
        InstallGuildBankHooks()
        Debounce("guildbank", 0.2, UpdateGuildBankSlots)
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        RefillRetryBudget()
        Debounce("merchant", 0.2, UpdateMerchantActiveTab)
    elseif event == "TRADE_SHOW" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then
        Debounce("trade", 0.1, UpdateTradeItems)
    elseif event == "LOOT_OPENED" or event == "LOOT_SLOT_CLEARED" then
        RefillRetryBudget()
        Debounce("loot", 0.1, UpdateAllLootButtons)
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        RefillRetryBudget()
        Debounce("openmail", 0.2, UpdateOpenMailAttachments)
    elseif event == "MAIL_SEND_INFO_UPDATE" then
        Debounce("sendmail", 0.1, UpdateSendMailAttachments)
    elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_ITEM_LIST_UPDATE" then
        RefillRetryBudget()
        InstallAuctionHooks()
    elseif event == "INSPECT_TALENT_READY" then
        RefillRetryBudget()
        InstallInspectHooks()
        inspectDataReady = true
        Debounce("inspect", 0.1, UpdateAllInspectSlots)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local inspectFrame = GetInspectFrame()
        if inspectFrame and inspectFrame:IsShown() and inspectFrame.unit and arg1 == inspectFrame.unit then
            Debounce("inspect", 0.2, UpdateAllInspectSlots)
        end
    end
end)

-- Force enable features on startup
ilvlDB.enabled = true
ilvlDB.character = true
ilvlDB.inspect = true
ilvlDB.bags = true
ilvlDB.bank = true
ilvlDB.guildbank = true
ilvlDB.trade = true
ilvlDB.loot = true
ilvlDB.lootroll = true
ilvlDB.mail = true
ilvlDB.auction = true
ilvlDB.merchant = true
ilvlDB.tooltip = true