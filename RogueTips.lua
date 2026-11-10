-- RogueTips : aides perso pour voleur.
--  1. Crée les macros d'ouverture (noms de sorts dans la langue du client).
--  2. Clic droit sur un coffre verrouillé du sac = Crochetage dessus.

local ADDON = ...
local _, class = UnitClass("player")
if class ~= "ROGUE" then return end

-- IDs de sorts (rang 1) : le client renvoie le nom dans sa propre langue.
local SPELL = {
    AMBUSH   = 8676,
    GARROTE  = 703,
    CHEAP    = 1833,
    SINISTER = 1752,
    SAP      = 6770,
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

    return {
        { name = n.AMBUSH,   body = opener(n.AMBUSH) },
        { name = n.GARROTE,  body = opener(n.GARROTE) },
        { name = n.CHEAP,    body = opener(n.CHEAP) },
        { name = n.SINISTER, body = opener(n.SINISTER) },
        { name = n.SAP, body = "#showtooltip " .. n.SAP .. "\n"
            .. "/cleartarget [dead][help]\n"
            .. "/targetenemy [noexists]\n"
            .. "/cast " .. n.PICK .. "\n"
            .. "/cast [@mouseover,harm,exists,nodead] " .. n.SAP .. "; " .. n.SAP .. "\n"
            .. "/cast [nostealth] " .. n.STEALTH },
        { name = n.PICK, body = "#showtooltip\n"
            .. "/cleartarget [dead][help]\n"
            .. "/targetenemy [noexists]\n"
            .. "/cast [@mouseover,harm,exists,nodead] " .. n.PICK .. "; " .. n.PICK .. "\n"
            .. "/cast [nostealth] " .. n.STEALTH },
        -- Tir à distance : choisit le bon sort selon l'arme équipée.
        { name = GetLocale() == "frFR" and "Tir à distance" or "Ranged",
          icon = "Ability_Marksmanship",
          body = "/cast [equipped:" .. WeaponType("BOW") .. "] " .. n.BOW
            .. "; [equipped:" .. WeaponType("GUN") .. "] " .. n.GUN
            .. "; [equipped:" .. WeaponType("CROSSBOW") .. "] " .. n.CROSSBOW
            .. "; [equipped:" .. WeaponType("THROWN") .. "] " .. n.THROW },
    }
end

-- overwrite = true : réécrit aussi les macros existantes (commande /roguetips macros).
local function SetupMacros(overwrite)
    if InCombatLockdown() then
        Print("en combat, macros créées à la sortie du combat.")
        return false
    end
    local list = BuildMacros()
    if not list then return false end

    local created, updated, full = 0, 0, false
    for _, m in ipairs(list) do
        local name = MacroName(m.name)
        local index = GetMacroIndexByName(name)
        if index == 0 then
            local _, numChar = GetNumMacros()
            if numChar >= (MAX_CHARACTER_MACROS or 18) then
                full = true
            else
                -- Icône « ? » : #showtooltip affiche alors l'icône du sort.
                CreateMacro(name, m.icon or "INV_MISC_QUESTIONMARK", m.body, true)
                created = created + 1
            end
        elseif overwrite then
            EditMacro(index, name, m.icon or "INV_MISC_QUESTIONMARK", m.body)
            updated = updated + 1
        end
    end

    if created > 0 then Print(created .. " macro(s) créée(s) (onglet macros du personnage).") end
    if updated > 0 then Print(updated .. " macro(s) mise(s) à jour.") end
    if full then Print("plus de place dans les macros du personnage, certaines n'ont pas été créées.") end
    return true
end

---------------------------------------------------------------------------
-- 2. Crochetage au clic droit sur les coffres du sac
---------------------------------------------------------------------------
-- Lancer un sort sur un objet est une action protégée : on pose un bouton
-- sécurisé par-dessus la case du coffre survolé. Son clic droit exécute
-- « /cast Crochetage » + « /use sac case ». Le clic gauche traverse.

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
    if overlay.reentering or InCombatLockdown() then return end
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
-- Événements et commande
---------------------------------------------------------------------------

local pendingMacros = true
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        HideOverlay()  -- encore possible à l'entrée en combat
    end
    if pendingMacros and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED") then
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
        Print("debug " .. (debug and "activé" or "désactivé") .. ".")
    else
        Print("/roguetips macros : recrée et remet à jour les macros.")
        Print("/roguetips debug : affiche ce que l'addon voit au survol des objets.")
    end
end
