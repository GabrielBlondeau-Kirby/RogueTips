-- Fenêtre de réglages de RogueTips : une fenêtre à elle, déplaçable, fermée par
-- sa croix ou Échap, avec un onglet d'icône par module sur le côté (façon Lueur).
-- Chaque module y range son panneau avec ns.Options.AddPage. Le panneau
-- Options → AddOns → RogueTips n'a plus qu'un bouton qui ouvre cette fenêtre.

local ADDON, ns = ...
ns.modules = ns.modules or {}  -- exécutés par Init.lua, une fois la langue choisie connue
ns.modules[#ns.modules + 1] = function()

local FR = (ns.lang or GetLocale()) == "frFR"
local function T(fr, en) return FR and fr or en end

local WIDTH, HEIGHT = 760, 620
local Options = { pages = {} }
ns.Options = Options

local function FromTemplate(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    return ok and frame or nil
end

local window, card, current

-- Fenêtre à portrait du jeu ; à défaut, un simple fond sombre.
local function BuildWindow()
    window = FromTemplate("Frame", "RogueTipsOptions", UIParent, "PortraitFrameTemplate")
    if window then
        window.title = window.TitleContainer and window.TitleContainer.TitleText or window.TitleText
        window.close = window.CloseButton
        local portrait = window.PortraitContainer and window.PortraitContainer.portrait or window.portrait
        if portrait then portrait:SetTexture("Interface\\Icons\\Ability_Stealth") end
    else
        window = CreateFrame("Frame", "RogueTipsOptions", UIParent)
        local back = window:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0.07, 0.06, 0.05, 0.95)
    end
    if not window.title then
        window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        window.title:SetPoint("TOP", 0, -6)
    end
    if not window.close then
        window.close = FromTemplate("Button", nil, window, "UIPanelCloseButton") or CreateFrame("Button", nil, window)
        window.close:SetSize(24, 24)
        window.close:SetPoint("TOPRIGHT", -2, -2)
    end
    window.close:SetScript("OnClick", function() window:Hide() end)

    window:Hide()
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    tinsert(UISpecialFrames, "RogueTipsOptions")  -- se ferme avec Échap

    -- Panneau sombre au filet arrondi qui reçoit la page choisie.
    card = FromTemplate("Frame", nil, window, "BackdropTemplate") or CreateFrame("Frame", nil, window)
    if card.SetBackdrop then
        card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        card:SetBackdropColor(0.03, 0.03, 0.03, 0.72)
        card:SetBackdropBorderColor(0.62, 0.56, 0.46, 0.9)
    else
        local back = card:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0, 0, 0, 0.55)
    end
    card:SetPoint("TOPLEFT", 12, -62)
    card:SetPoint("BOTTOMRIGHT", -10, 10)
end

local function ShowPage(page)
    current = page
    for _, p in ipairs(Options.pages) do
        p.panel:SetShown(p == page)
        if p.tab and p.tab.SetChecked then p.tab:SetChecked(p == page) end
    end
    window.title:SetText("RogueTips — " .. page.label)
end

-- Onglet d'icône sur le bord droit de la fenêtre, sous `previous`.
local function SideTab(previous, page)
    local tab = FromTemplate("Frame", nil, window, "LargeSideTabButtonTemplate")
    if tab and tab.Icon and tab.SetChecked and tab.SetCustomOnMouseUpHandler then
        tab.Icon:SetTexture(page.icon)
        if tab.SetFillToInterior then tab:SetFillToInterior(true) end
        tab:SetCustomOnMouseUpHandler(function(_, button, inside)
            if button == "LeftButton" and inside then ShowPage(page) end
        end)
        tab.tooltipText = page.label
        tab:SetPoint("TOPLEFT", previous or window, previous and "BOTTOMLEFT" or "TOPRIGHT", 0, previous and -2 or -60)
        return tab
    end
    if tab then tab:Hide() end
    -- À défaut : un bouton d'icône simple.
    tab = CreateFrame("CheckButton", nil, window)
    tab:SetSize(36, 36)
    local face = tab:CreateTexture(nil, "ARTWORK")
    face:SetAllPoints()
    face:SetTexture(page.icon)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    tab:GetCheckedTexture():SetBlendMode("ADD")
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        ShowPage(page)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(page.label)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    tab:SetPoint("TOPLEFT", previous or window, previous and "BOTTOMLEFT" or "TOPRIGHT", previous and 0 or 2,
        previous and -12 or -66)
    return tab
end

local function Layout()
    table.sort(Options.pages, function(a, b) return a.order < b.order end)
    local previous
    for _, p in ipairs(Options.pages) do
        if p.tab then p.tab:Hide() end
        p.tab = SideTab(previous, p)
        previous = p.tab
    end
end

-- Range le panneau d'un module dans la fenêtre. order : place de son onglet.
function Options.AddPage(panel, label, icon, order)
    if not window then BuildWindow() end
    panel:SetParent(card)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 4, -4)
    panel:SetPoint("BOTTOMRIGHT", -4, 4)
    panel:Hide()
    Options.pages[#Options.pages + 1] = { panel = panel, label = label, icon = icon, order = order or 99 }
    Layout()
end

-- Ouvre la fenêtre sur la page de ce panneau (ou la dernière vue).
function Options.Open(panel)
    if not window then return end
    local page = current or Options.pages[1]
    for _, p in ipairs(Options.pages) do
        if p.panel == panel then page = p end
    end
    if not page then return end
    ShowPage(page)
    window:Show()
end

function Options.Toggle(panel)
    if window and window:IsShown() and (not panel or (current and current.panel == panel)) then
        window:Hide()
    else
        Options.Open(panel)
    end
end

-- Options → AddOns → RogueTips : un bouton qui ouvre la fenêtre.
local stub = CreateFrame("Frame")
stub.name = "RogueTips"
local stubTitle = stub:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
stubTitle:SetPoint("TOPLEFT", 16, -16)
stubTitle:SetText("RogueTips")
local stubButton = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
stubButton:SetSize(220, 26)
stubButton:SetPoint("TOPLEFT", stubTitle, "BOTTOMLEFT", 0, -16)
stubButton:SetText(T("Ouvrir les réglages", "Open settings"))
stubButton:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
    Options.Open()
end)
local stubNote = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
stubNote:SetPoint("TOPLEFT", stubButton, "BOTTOMLEFT", 0, -10)
stubNote:SetText(T("Ou tapez /roguetips.", "Or type /roguetips."))

if Settings and Settings.RegisterCanvasLayoutCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(stub, stub.name))
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(stub)
end

end
