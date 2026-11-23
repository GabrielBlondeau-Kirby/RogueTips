-- RogueTips : aides perso pour voleur.
--  1. Crée les macros d'ouverture (noms de sorts dans la langue du client).
--  2. Clic droit sur un coffre verrouillé du sac = Crochetage dessus.

local ADDON, ns = ...
ns.modules = ns.modules or {}  -- exécutés par Init.lua, une fois la langue choisie connue
ns.onLoad = ns.onLoad or {}
ns.modules[#ns.modules + 1] = function()
local _, class = UnitClass("player")
if class ~= "ROGUE" then return end

-- IDs de sorts (rang 1) : le client renvoie le nom dans sa propre langue.
local SPELL = {
    AMBUSH   = 8676,
    GARROTE  = 703,
    CHEAP    = 1833,
    SINISTER = 1752,
    SAP      = 6770,
    BLIND    = 2094,  -- Cécité
    PICK     = 921,   -- Vol à la tire
    STEALTH  = 1784,  -- Camouflage
    LOCKPICK = 1804,  -- Crochetage
    BOW      = 2480,  -- Tir à l'arc
    GUN      = 7918,  -- Tir au fusil
    CROSSBOW = 7919,  -- Tir à l'arbalète
    THROW    = 2764,  -- Lancer
}

-- Sous-classes d'armes (classe 2) : leur nom localisé sert dans [equipped:…].
local WEAPON = { BOW = 2, GUN = 3, THROWN = 16, CROSSBOW = 18 }
local WEAPON_EN = { BOW = "Bows", GUN = "Guns", THROWN = "Thrown", CROSSBOW = "Crossbows" }

local function WeaponType(key)
    local f = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    return (f and f(2, WEAPON[key])) or WEAPON_EN[key]
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local function Print(msg)
    print("|cff33ff99RogueTips|r : " .. msg)
end

local FR = ns.lang == "frFR"  -- langue choisie dans les options
local function T(fr, en) return FR and fr or en end

---------------------------------------------------------------------------
-- 1. Macros
---------------------------------------------------------------------------

-- Nom de macro limité à 16 octets : on coupe sans casser un caractère UTF-8.
local function MacroName(s)
    if #s <= 16 then return s end
    local cut = 16
    while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 0x80 and s:byte(cut + 1) < 0xC0 do
        cut = cut - 1
    end
    return s:sub(1, cut)
end

local function BuildMacros()
    local n = {}
    for k, id in pairs(SPELL) do
        n[k] = SpellName(id)
        if not n[k] then return nil end  -- données de sort pas encore chargées
    end

    local function opener(spell)
        return "#showtooltip " .. spell .. "\n"
            .. "/cast " .. n.PICK .. "\n"
            .. "/cast " .. spell .. "\n"
            .. "/cast [nostealth] " .. n.STEALTH
    end
    -- Vol à la tire puis le sort sur l'ennemi survolé (sinon la cible), comme Assommer.
    local function onMouseover(spell)
        return "#showtooltip " .. spell .. "\n"
            .. "/cleartarget [dead][help]\n"
            .. "/targetenemy [noexists]\n"
            .. "/cast " .. n.PICK .. "\n"
            .. "/cast [@mouseover,harm,exists,nodead] " .. spell .. "; " .. spell .. "\n"
            .. "/cast [nostealth] " .. n.STEALTH
    end

    return {
        { name = n.AMBUSH,   spell = SPELL.AMBUSH,   body = opener(n.AMBUSH) },
        { name = n.GARROTE,  spell = SPELL.GARROTE,  body = opener(n.GARROTE) },
        { name = n.CHEAP,    spell = SPELL.CHEAP,    body = opener(n.CHEAP) },
        { name = n.SINISTER, spell = SPELL.SINISTER, body = opener(n.SINISTER) },
        { name = n.SAP,      spell = SPELL.SAP,      body = onMouseover(n.SAP) },
        { name = n.BLIND,    spell = SPELL.BLIND,    body = onMouseover(n.BLIND) },
        { name = n.PICK, spell = SPELL.PICK, body = "#showtooltip\n"
            .. "/cleartarget [dead][help]\n"
            .. "/targetenemy [noexists]\n"
            .. "/cast [@mouseover,harm,exists,nodead] " .. n.PICK .. "; " .. n.PICK .. "\n"
            .. "/cast [nostealth] " .. n.STEALTH },
        -- Tir à distance : choisit le bon sort selon l'arme équipée.
        { name = GetLocale() == "frFR" and "Tir à distance" or "Ranged",
          icon = "Ability_Marksmanship", iconPath = "Interface\\Icons\\Ability_Marksmanship",
          body = "/cast [equipped:" .. WeaponType("BOW") .. "] " .. n.BOW
            .. "; [equipped:" .. WeaponType("GUN") .. "] " .. n.GUN
            .. "; [equipped:" .. WeaponType("CROSSBOW") .. "] " .. n.CROSSBOW
            .. "; [equipped:" .. WeaponType("THROWN") .. "] " .. n.THROW },
    }
end

-- Crée la macro si elle manque ; la réécrit si overwrite. Renvoie ce qui a été fait.
local function WriteMacro(m, overwrite)
    local name = MacroName(m.name)
    local index = GetMacroIndexByName(name)
    if index == 0 then
        local _, numChar = GetNumMacros()
        if numChar >= (MAX_CHARACTER_MACROS or 18) then return "full" end
        -- Icône « ? » : #showtooltip affiche alors l'icône du sort.
        CreateMacro(name, m.icon or "INV_MISC_QUESTIONMARK", m.body, true)
        return "created"
    elseif overwrite then
        EditMacro(index, name, m.icon or "INV_MISC_QUESTIONMARK", m.body)
        return "updated"
    end
end

-- État d'une macro dans l'onglet du personnage : absente, à jour ou modifiée.
local function MacroState(m)
    local index = GetMacroIndexByName(MacroName(m.name))
    if index == 0 then return "missing" end
    local body = GetMacroBody(index) or ""
    return strtrim(body) == strtrim(m.body) and "ok" or "edited"
end

-- overwrite = true : réécrit aussi les macros existantes (commande /roguetips macros).
local function SetupMacros(overwrite)
    if InCombatLockdown() then
        Print(T("en combat, macros créées à la sortie du combat.", "in combat, macros will be created after combat."))
        return false
    end
    local list = BuildMacros()
    if not list then return false end

    local created, updated, full = 0, 0, false
    for _, m in ipairs(list) do
        local r = WriteMacro(m, overwrite)
        if r == "created" then created = created + 1
        elseif r == "updated" then updated = updated + 1
        elseif r == "full" then full = true end
    end

    if created > 0 then Print(created .. T(" macro(s) créée(s) (onglet macros du personnage).", " macro(s) created (character macros tab).")) end
    if updated > 0 then Print(updated .. T(" macro(s) mise(s) à jour.", " macro(s) updated.")) end
    if full then Print(T("plus de place dans les macros du personnage, certaines n'ont pas été créées.", "no room left in character macros, some were not created.")) end
    return true
end

---------------------------------------------------------------------------
-- 2. Crochetage au clic droit sur les coffres du sac
---------------------------------------------------------------------------
-- Lancer un sort sur un objet est une action protégée : on pose un bouton
-- sécurisé par-dessus la case du coffre survolé. Son clic droit exécute
-- « /cast Crochetage » + « /use sac case ». Le clic gauche traverse.

-- Réglages (remplacés par RogueTipsDB au chargement).
local DEFAULTS = { lockpick = true, autoMacros = true }
local db = { lockpick = true, autoMacros = true }

local debug = false
local function Debug(msg) if debug then Print("|cffaaaaaa" .. msg .. "|r") end end

-- Le coffre est verrouillé si l'info-bulle affichée contient la ligne LOCKED.
local function TooltipSaysLocked(tt)
    local lockedText = LOCKED or "Locked"
    local name = tt:GetName()
    for i = 2, tt:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and strtrim(text) == lockedText then return true end
    end
    return false
end

local overlay = CreateFrame("Button", "RogueTipsLockpickButton", UIParent, "SecureActionButtonTemplate")
overlay:Hide()
overlay:RegisterForClicks("RightButtonUp")
overlay:SetAttribute("useOnKeyDown", false)  -- clients récents : agir au relâchement
overlay:SetAttribute("type2", "macro")
if overlay.SetPassThroughButtons then
    overlay:SetPassThroughButtons("LeftButton")
end
overlay:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local function HideOverlay()
    if InCombatLockdown() then return end
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetParent(UIParent)
    overlay.target = nil
end

overlay:SetScript("OnEnter", function(self)
    local btn = self.target
    if btn and btn:GetScript("OnEnter") then
        self.reentering = true
        btn:GetScript("OnEnter")(btn)
        self.reentering = nil
    end
end)
overlay:SetScript("OnLeave", function()
    GameTooltip:Hide()
    HideOverlay()
end)
-- Après le crochetage le coffre n'est plus verrouillé : on retire le bouton.
overlay:SetScript("PostClick", function(_, button)
    Debug("clic " .. tostring(button) .. " sur le bouton Crochetage")
    C_Timer.After(0.2, HideOverlay)
end)

-- On s'accroche à GameTooltip:SetBagItem plutôt qu'aux boutons du sac :
-- ça marche quel que soit le nom des cases (sacs séparés, sac combiné…),
-- et on lit directement l'info-bulle que le jeu vient de remplir.
local function OnSetBagItem(tt, bag, slot)
    if not db.lockpick or overlay.reentering or InCombatLockdown() then return end
    local btn = tt:GetOwner()
    local locked = TooltipSaysLocked(tt)
    Debug(("survol sac %s case %s, bouton %s, verrouillé : %s"):format(
        tostring(bag), tostring(slot), btn and (btn:GetName() or "sans nom") or "aucun", tostring(locked)))
    if not locked or not btn or btn == UIParent or btn == WorldFrame then return end

    local spell = SpellName(SPELL.LOCKPICK)
    overlay:SetAttribute("macrotext2", "/cast " .. spell .. "\n/use " .. bag .. " " .. slot)
    overlay.target = btn
    overlay:SetParent(btn)       -- se cache avec le sac
    overlay:ClearAllPoints()
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 5)
    overlay:Show()
    Debug("bouton Crochetage posé : /cast " .. spell .. " + /use " .. bag .. " " .. slot)
end
hooksecurefunc(GameTooltip, "SetBagItem", OnSetBagItem)

---------------------------------------------------------------------------
-- 3. Panneau d'options (page « Général » de la fenêtre de réglages, Options.lua)
---------------------------------------------------------------------------


local panel = CreateFrame("Frame")
panel.name = "RogueTips"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("RogueTips")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText(T("Aides pour voleur : macros d'ouverture et Crochetage au clic droit.",
                   "Rogue helpers: opener macros and right-click Pick Lock."))

local checkboxes = {}
local function CheckBox(anchor, label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)
    local note = cb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
    note:SetText(tip)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function(self) self:SetChecked(get()) end
    checkboxes[#checkboxes + 1] = cb
    return cb
end

local cbLock = CheckBox(subtitle,
    T("Crochetage au clic droit", "Right-click Pick Lock"),
    T("Clic droit sur un coffre verrouillé du sac pour le crocheter.",
      "Right-click a locked lockbox in your bags to pick it."),
    function() return db.lockpick end,
    function(v) db.lockpick = v; if not v then HideOverlay() end end)

local cbMacros = CheckBox(cbLock,
    T("Créer les macros manquantes à la connexion", "Create missing macros at login"),
    T("Ne touche jamais aux macros déjà présentes.", "Never changes existing macros."),
    function() return db.autoMacros end,
    function(v) db.autoMacros = v end)
cbMacros:SetPoint("TOPLEFT", cbLock, "BOTTOMLEFT", 0, -22)

local cbDebug = CheckBox(cbMacros,
    T("Mode debug", "Debug mode"),
    T("Affiche dans le chat ce que l'addon voit au survol des objets (non sauvegardé).",
      "Prints what the addon sees when hovering items (not saved)."),
    function() return debug end,
    function(v) debug = v end)
cbDebug:SetPoint("TOPLEFT", cbMacros, "BOTTOMLEFT", 0, -22)

local SetMinimapShown  -- défini avec l'icône de la minimap, plus bas
local cbMinimap = CheckBox(cbDebug,
    T("Icône autour de la minimap", "Minimap icon"),
    T("Clic : réglages. Glisser : la déplacer.", "Click: settings. Drag: move it."),
    function() return not db.minimap.hide end,
    function(v) SetMinimapShown(v) end)
cbMinimap:ClearAllPoints()
cbMinimap:SetPoint("LEFT", cbDebug, "LEFT", 330, 0)

local rebuild = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
rebuild:SetSize(200, 24)
rebuild:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 4, -32)
rebuild:SetText(T("Recréer les macros", "Rebuild macros"))
rebuild:SetScript("OnClick", function() SetupMacros(true) end)

local rebuildNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
rebuildNote:SetPoint("LEFT", rebuild, "RIGHT", 10, 0)

-- Aperçu des macros : liste à gauche, contenu de la macro choisie à droite.
local pvTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
pvTitle:SetPoint("TOPLEFT", rebuild, "BOTTOMLEFT", -4, -24)
pvTitle:SetText(T("Aperçu des macros", "Macro preview"))

local box = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
box:SetPoint("TOPLEFT", pvTitle, "BOTTOMLEFT", 0, -8)
box:SetSize(610, 230)
if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.55, 0.45, 0.25)
end

local LIST_W, ITEM_H = 190, 27
local divider = box:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.55, 0.45, 0.25, 0.6)
divider:SetWidth(1)
divider:SetPoint("TOPLEFT", LIST_W + 10, -8)
divider:SetPoint("BOTTOMLEFT", LIST_W + 10, 8)

local STATES = {
    missing = { T("Absente", "Missing"), 1, 0.35, 0.35 },
    ok      = { T("À jour", "Up to date"), 0.3, 1, 0.3 },
    edited  = { T("Modifiée par vous", "Edited by you"), 1, 0.65, 0.2 },
}

local function MacroIcon(m)
    if m.iconPath then return m.iconPath end
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    return (f and m.spell and f(m.spell)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local macroList, items, selectedMacro = nil, {}, 1
local RefreshPreview

local dIcon = box:CreateTexture(nil, "ARTWORK")
dIcon:SetSize(36, 36)
dIcon:SetPoint("TOPLEFT", LIST_W + 22, -12)
local dName = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
dName:SetPoint("TOPLEFT", dIcon, "TOPRIGHT", 8, -2)
local dState = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
dState:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -4)
local dBody = box:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
dBody:SetPoint("TOPLEFT", dIcon, "BOTTOMLEFT", 0, -12)
dBody:SetWidth(610 - LIST_W - 44)
dBody:SetJustifyH("LEFT")
dBody:SetJustifyV("TOP")
dBody:SetSpacing(2)
local dWrite = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
dWrite:SetSize(200, 22)
dWrite:SetPoint("BOTTOMRIGHT", -12, 12)
dWrite:SetScript("OnClick", function()
    local m = macroList and macroList[selectedMacro]
    if not m then return end
    if InCombatLockdown() then Print(T("impossible en combat.", "not in combat.")) return end
    local r = WriteMacro(m, true)
    if r == "full" then Print(T("plus de place dans les macros du personnage.", "no room left in character macros."))
    elseif r then Print(MacroName(m.name) .. T(" : macro écrite.", ": macro written.")) end
    RefreshPreview()
end)

local function Item(i)
    if items[i] then return items[i] end
    local b = CreateFrame("Button", nil, box)
    b:SetSize(LIST_W, ITEM_H - 2)
    b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ITEM_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.15)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("LEFT", 3, 0)
    b.name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", -16, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function(self) selectedMacro = self.index; RefreshPreview() end)
    items[i] = b
    return b
end

RefreshPreview = function()
    macroList = BuildMacros()
    if not macroList then
        dName:SetText(T("Chargement des sorts…", "Loading spells…"))
        return
    end
    rebuildNote:SetText((T("Réécrit les %d macros, même si vous les avez modifiées.",
        "Rewrites all %d macros, even if you edited them.")):format(#macroList))
    if selectedMacro > #macroList then selectedMacro = 1 end
    for i, m in ipairs(macroList) do
        local b, st = Item(i), STATES[MacroState(m)]
        b.index = i
        b.icon:SetTexture(MacroIcon(m))
        b.name:SetText(MacroName(m.name))
        b.dot:SetColorTexture(st[2], st[3], st[4])
        b.sel:SetShown(i == selectedMacro)
        b:Show()
    end
    for i = #macroList + 1, #items do items[i]:Hide() end
    local m = macroList[selectedMacro]
    local state = MacroState(m)
    local st = STATES[state]
    dIcon:SetTexture(MacroIcon(m))
    dName:SetText(MacroName(m.name))
    dState:SetText(st[1])
    dState:SetTextColor(st[2], st[3], st[4])
    dBody:SetText(m.body)
    dWrite:SetText(state == "missing" and T("Créer cette macro", "Create this macro")
        or T("Réécrire cette macro", "Rewrite this macro"))
end

rebuild:SetScript("OnClick", function() SetupMacros(true); RefreshPreview() end)

-- Langue de l'addon : celle du jeu, anglais ou français. Prise en compte au rechargement
-- (les textes sont posés à la construction des fenêtres).
StaticPopupDialogs.ROGUETIPS_RELOAD = {
    text = T("La nouvelle langue s'applique après un rechargement de l'interface. Recharger maintenant ?",
             "The new language applies after a UI reload. Reload now?"),
    button1 = T("Recharger", "Reload"), button2 = T("Plus tard", "Later"),
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local langTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
langTitle:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
langTitle:SetText(T("Langue de l'addon", "Addon language"))

local LANGS = { { "auto", T("Langue du jeu", "Game language") }, { "enUS", "English" }, { "frFR", "Français" } }
local langBoxes = {}
for i, l in ipairs(LANGS) do
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", langTitle, "BOTTOMLEFT", -4 + (i - 1) * 170, -4)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(l[2])
    cb:SetScript("OnClick", function()
        local before = db.lang or "auto"
        db.lang = l[1]
        for _, b in ipairs(langBoxes) do b:SetChecked(b.code == db.lang) end
        if l[1] ~= before then StaticPopup_Show("ROGUETIPS_RELOAD") end
    end)
    cb.code = l[1]
    cb.Refresh = function(self) self:SetChecked(self.code == (db.lang or "auto")) end
    langBoxes[i] = cb
    checkboxes[#checkboxes + 1] = cb
end
local langNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
langNote:SetPoint("TOPLEFT", langTitle, "BOTTOMLEFT", 0, -34)
langNote:SetText(T("Les noms de sorts des macros restent ceux du jeu.",
                   "Spell names in macros stay in the game's language."))

panel:SetScript("OnShow", function()
    for _, cb in ipairs(checkboxes) do cb:Refresh() end
    RefreshPreview()
end)

-- Première page de la fenêtre de réglages (Options.lua).
local function RegisterPanel()
    ns.Options.AddPage(panel, T("Général", "General"), "Interface\\Icons\\Ability_Stealth", 1)
end

local function OpenPanel() ns.Options.Toggle(panel) end

-- Icône autour de la minimap. Clic : réglages. Glisser : tourner autour.
local mm = CreateFrame("Button", "RogueTipsMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mm:Hide()

local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20)
mmBg:SetPoint("TOPLEFT", 7, -5)

local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", 7, -6)
if SetPortraitToTexture then SetPortraitToTexture(mmIcon, "Interface\\Icons\\Ability_Stealth")
else mmIcon:SetTexture("Interface\\Icons\\Ability_Stealth") end

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")

local function PlaceMinimapButton()
    local a = math.rad(db.minimap.angle)
    local r = Minimap:GetWidth() / 2 + 5
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

SetMinimapShown = function(shown)
    db.minimap.hide = not shown
    mm:SetShown(shown)
end

mm:SetScript("OnClick", function(_, button)
    if button == "RightButton" and ns.steal and ns.steal.ToggleJournal then ns.steal.ToggleJournal()
    else OpenPanel() end
end)
mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
    end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("RogueTips", 0.2, 1, 0.6)
    GameTooltip:AddLine(T("Clic gauche : réglages", "Left-click: settings"), 1, 1, 1)
    GameTooltip:AddLine(T("Clic droit : journal du voleur", "Right-click: thief's journal"), 1, 1, 1)
    GameTooltip:AddLine(T("Glisser : déplacer autour de la minimap", "Drag: move around the minimap"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- Événements et commande
---------------------------------------------------------------------------

local pendingMacros = true
local ev = CreateFrame("Frame")
local didLoad = false
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON or didLoad then return end
        didLoad = true
        RogueTipsDB = RogueTipsDB or {}
        for k, v in pairs(DEFAULTS) do
            if RogueTipsDB[k] == nil then RogueTipsDB[k] = v end
        end
        db = RogueTipsDB
        db.minimap = db.minimap or { angle = 160, hide = false }
        PlaceMinimapButton()
        mm:SetShown(not db.minimap.hide)
        RegisterPanel()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        HideOverlay()  -- encore possible à l'entrée en combat
    end
    if pendingMacros and db.autoMacros
        and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED") then
        -- Petit délai : la liste des macros n'est pas toujours prête au login.
        C_Timer.After(2, function()
            if pendingMacros and SetupMacros(false) then pendingMacros = false end
        end)
    end
end)

SLASH_ROGUETIPS1 = "/roguetips"
SlashCmdList.ROGUETIPS = function(msg)
    msg = (msg or ""):lower()
    if msg == "macros" then
        SetupMacros(true)
    elseif msg == "debug" then
        debug = not debug
        Print("debug " .. (debug and T("activé", "on") or T("désactivé", "off")) .. ".")
    else
        OpenPanel()
    end
end

-- Les SavedVariables sont chargées : Init.lua rejoue ADDON_LOADED pour ce module.
ns.onLoad[#ns.onLoad + 1] = function() ev:GetScript("OnEvent")(ev, "ADDON_LOADED", ADDON) end
end
