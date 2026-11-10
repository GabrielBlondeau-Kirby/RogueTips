-- RoguePLZ : aides perso pour voleur.
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
}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end

local function Print(msg)
    print("|cff33ff99RoguePLZ|r : " .. msg)
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
    }
end

-- overwrite = true : réécrit aussi les macros existantes (commande /rogueplz macros).
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
                CreateMacro(name, "INV_MISC_QUESTIONMARK", m.body, true)
                created = created + 1
            end
        elseif overwrite then
            EditMacro(index, name, "INV_MISC_QUESTIONMARK", m.body)
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

local scanTip = CreateFrame("GameTooltip", "RoguePLZScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function IsLockedBox(bag, slot)
    local lockedText = LOCKED or "Locked"
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        for _, line in ipairs(data and data.lines or {}) do
            if line.leftText == lockedText then return true end
        end
        return false
    end
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    for i = 2, scanTip:NumLines() do
        local fs = _G["RoguePLZScanTipTextLeft" .. i]
        if fs and fs:GetText() == lockedText then return true end
    end
    return false
end

local overlay = CreateFrame("Button", "RoguePLZLockpickButton", UIParent, "SecureActionButtonTemplate")
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
overlay:SetScript("PostClick", function() C_Timer.After(0.2, HideOverlay) end)

local function ButtonBagSlot(btn)
    local bag = btn.GetBagID and btn:GetBagID() or (btn:GetParent() and btn:GetParent():GetID())
    local slot = btn.GetID and btn:GetID()
    return bag, slot
end

local function OnItemEnter(btn)
    if overlay.reentering or InCombatLockdown() then return end
    if not IsSpellKnown(SPELL.LOCKPICK) then return end
    local bag, slot = ButtonBagSlot(btn)
    if not bag or not slot or not IsLockedBox(bag, slot) then return end

    overlay:SetAttribute("macrotext2",
        "/cast " .. SpellName(SPELL.LOCKPICK) .. "\n/use " .. bag .. " " .. slot)
    overlay.target = btn
    overlay:SetParent(btn)       -- se cache avec le sac
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 5)
    overlay:Show()
end

local hooked = {}
local function HookBagButtons()
    for f = 1, (NUM_CONTAINER_FRAMES or 13) do
        for i = 1, (MAX_CONTAINER_ITEMS or 36) do
            local btn = _G["ContainerFrame" .. f .. "Item" .. i]
            if btn and not hooked[btn] then
                btn:HookScript("OnEnter", OnItemEnter)
                hooked[btn] = true
            end
        end
    end
end

---------------------------------------------------------------------------
-- Événements et commande
---------------------------------------------------------------------------

local pendingMacros = true
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("BAG_OPEN")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "BAG_OPEN" then
        HookBagButtons()
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideOverlay()  -- encore possible à l'entrée en combat
    end
    if pendingMacros and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED") then
        -- Petit délai : la liste des macros n'est pas toujours prête au login.
        C_Timer.After(2, function()
            if pendingMacros and SetupMacros(false) then pendingMacros = false end
        end)
    end
end)

SLASH_ROGUEPLZ1 = "/rogueplz"
SlashCmdList.ROGUEPLZ = function(msg)
    msg = (msg or ""):lower()
    if msg == "macros" then
        SetupMacros(true)
    else
        Print("/rogueplz macros : recrée et remet à jour les macros.")
    end
end
