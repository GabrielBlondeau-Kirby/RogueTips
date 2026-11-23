-- DamageText (module de RogueTips) : chiffres de dégâts au-dessus de la cible,
-- stylés selon la nature des dégâts (UNIT_COMBAT). Le montant est une valeur
-- secrète : on ne peut que le faire afficher par une FontString, pas le lire.
-- Réglages : /roguetips (ou /rtdmg options) → onglet Chiffres de dégâts.
-- /rtdmg : active / coupe ; /rtdmg options : ouvre les réglages.

local ADDON, ns = ...
ns.modules = ns.modules or {}  -- exécutés par Init.lua, une fois la langue choisie connue
ns.onLoad = ns.onLoad or {}
ns.modules[#ns.modules + 1] = function()

local FR = ns.lang == "frFR"  -- langue choisie dans les options
local function T(fr, en) return FR and fr or en end
local function Print(msg) print("|cff33ff99RogueTips|r " .. msg) end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local MEDIA = "Interface\\AddOns\\RogueTips\\Media\\dmg_"
local FONT = DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DUR = 1.2

local ICONS = { "aucune", "poison", "parade", "esquive", "bloque", "rate" }
local ANIMS = { "haut", "arc-gauche", "arc-droite", "pop" }
local ANIM_NAMES = { haut = T("Vers le haut", "Up"), ["arc-gauche"] = T("Arc gauche", "Arc left"),
                     ["arc-droite"] = T("Arc droite", "Arc right"), pop = "Pop" }

-- Types dans l'ordre du panneau. { id, libellé, exemple d'aperçu } ; { header = ... } = titre de groupe.
local TYPES = {
    { header = T("Dégâts infligés", "Damage dealt") },
    { "phys", T("Physique", "Physical"), "89" },
    { "phys_crit", T("Physique critique", "Physical crit"), "178" },
    { "nature", T("Nature (poisons)", "Nature (poisons)"), "19" },
    { "nature_crit", T("Nature critique", "Nature crit"), "38" },
    { "fire", T("Feu", "Fire"), "24" },
    { "fire_crit", T("Feu critique", "Fire crit"), "48" },
    { "frost", T("Givre", "Frost"), "24" },
    { "frost_crit", T("Givre critique", "Frost crit"), "48" },
    { "shadow", T("Ombre", "Shadow"), "24" },
    { "shadow_crit", T("Ombre critique", "Shadow crit"), "48" },
    { "arcane", T("Arcane", "Arcane"), "24" },
    { "arcane_crit", T("Arcane critique", "Arcane crit"), "48" },
    { "holy", T("Sacré", "Holy"), "24" },
    { "holy_crit", T("Sacré critique", "Holy crit"), "48" },
    { "mixed", T("Mixte", "Mixed"), "24" },
    { "mixed_crit", T("Mixte critique", "Mixed crit"), "48" },
    { header = T("Précisions", "Modifiers") },
    { "glancing", T("Érafle", "Glancing"), T("Érafle", "Glancing") },
    { "block_reduced", T("Bloqué en partie", "Partial block"), T("Bloqué", "Blocked") },
    { "resist_reduced", T("Résisté en partie", "Partial resist"), T("Résisté", "Resisted") },
    { "absorb_partial", T("Absorbé en partie", "Partial absorb"), T("Absorbé", "Absorbed") },
    { "crushing", T("Écrasant", "Crushing"), T("Écrasant", "Crushing") },
    { header = T("Coups évités", "Avoided") },
    { "miss", T("Raté", "Miss"), T("Raté", "Miss") },
    { "dodge", T("Esquive", "Dodge"), T("Esquive", "Dodge") },
    { "parry", T("Parade", "Parry"), T("Parade", "Parry") },
    { "block", T("Bloqué", "Block"), T("Bloqué", "Block") },
    { "resist", T("Résisté", "Resist"), T("Résisté", "Resist") },
    { "absorb", T("Absorbé", "Absorb"), T("Absorbé", "Absorb") },
    { "immune", T("Insensible", "Immune"), T("Insensible", "Immune") },
    { "evade", T("Évite", "Evade"), T("Évite", "Evade") },
    { "deflect", T("Dévié", "Deflect"), T("Dévié", "Deflect") },
    { "reflect", T("Renvoyé", "Reflect"), T("Renvoyé", "Reflect") },
    { header = T("Autres", "Other") },
    { "heal", T("Soin sur la cible", "Heal on target"), "120" },
    { "heal_crit", T("Soin critique", "Heal crit"), "240" },
    { "taken", T("Dégâts reçus", "Damage taken"), "56" },
}
local WORD = {}   -- texte affiché pour les types sans montant (évités, précisions)
for _, t in ipairs(TYPES) do if t[1] then WORD[t[1]] = t[3] end end

-- Valeurs par défaut (choisies dans la page « Dégâts réglables »).
local function S(color, size, bold, icon, anim, on)
    return { color = color, size = size, bold = bold, icon = icon, anim = anim, on = on }
end
local DEFAULTS = {
    phys = S("cfcece", 22, false, "aucune", "arc-droite", true),
    phys_crit = S("f36868", 32, true, "aucune", "haut", true),
    nature = S("9853c1", 22, false, "poison", "arc-gauche", true),
    nature_crit = S("b133ff", 30, true, "poison", "haut", true),
    fire = S("ff8000", 22, false, "aucune", "haut", true),
    fire_crit = S("ff8000", 30, false, "aucune", "haut", true),
    frost = S("80ffff", 22, false, "aucune", "haut", true),
    frost_crit = S("80ffff", 30, false, "aucune", "haut", true),
    shadow = S("8080ff", 22, false, "aucune", "haut", true),
    shadow_crit = S("8080ff", 30, false, "aucune", "haut", true),
    arcane = S("ff80ff", 22, false, "aucune", "haut", true),
    arcane_crit = S("ff80ff", 30, false, "aucune", "haut", true),
    holy = S("ffe680", 22, false, "aucune", "haut", true),
    holy_crit = S("ffe680", 30, false, "aucune", "haut", true),
    mixed = S("ffffff", 22, false, "aucune", "haut", true),
    mixed_crit = S("ffffff", 30, false, "aucune", "haut", true),
    glancing = S("b0b0b0", 14, false, "aucune", "haut", true),
    block_reduced = S("cccccc", 14, false, "aucune", "haut", true),
    resist_reduced = S("cccccc", 14, false, "aucune", "haut", true),
    absorb_partial = S("cccccc", 14, false, "aucune", "haut", true),
    crushing = S("ff4040", 16, false, "aucune", "haut", true),
    miss = S("b0b0b0", 18, false, "rate", "pop", true),
    dodge = S("b0b0b0", 18, false, "esquive", "pop", true),
    parry = S("b0b0b0", 18, false, "parade", "pop", true),
    block = S("b0b0b0", 18, false, "bloque", "pop", true),
    resist = S("b0b0b0", 18, false, "aucune", "haut", true),
    absorb = S("b0b0b0", 18, false, "aucune", "haut", true),
    immune = S("b0b0b0", 18, false, "aucune", "haut", true),
    evade = S("b0b0b0", 18, false, "aucune", "haut", true),
    deflect = S("b0b0b0", 18, false, "aucune", "haut", true),
    reflect = S("b0b0b0", 18, false, "aucune", "haut", true),
    heal = S("33ff66", 22, false, "aucune", "haut", false),
    heal_crit = S("33ff66", 30, false, "aucune", "haut", false),
    taken = S("ff4040", 20, false, "aucune", "haut", false),
}

local db   -- RogueTipsDB.dmg

local function Style(id) return db.styles[id] end
local function RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local function Hex(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function ResetStyles()
    db.styles = {}
    for id, d in pairs(DEFAULTS) do
        local s = {}
        for k, v in pairs(d) do s[k] = v end
        db.styles[id] = s
    end
end

-- Chiffres ------------------------------------------------------------------

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetAllPoints()
holder:SetFrameStrata("TOOLTIP")   -- au-dessus du panneau d'options pour l'aperçu

local pool, live = {}, {}

local function NewPop()
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(1, 1)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetPoint("RIGHT", f.text, "LEFT", -3, 0)
    f.tag = f:CreateFontString(nil, "OVERLAY")
    f.tag:SetPoint("TOP", f.text, "BOTTOM", 0, -1)
    return f
end

local function Dress(fs, s)
    fs:SetFont(FONT, s.size, s.bold and "THICKOUTLINE" or "OUTLINE")
    fs:SetTextColor(RGB(s.color))
end

local function SetAmount(fs, value)
    if pcall(fs.SetText, fs, value) then return end
    if pcall(fs.SetFormattedText, fs, "%s", value) then return end
    fs:SetText("?")
end

-- Fait apparaître un chiffre (ou un mot) du type `id`, accroché à `anchor`.
local function Pop(id, value, anchor, point, y0, tagId)
    local s = Style(id)
    if not s or not s.on then return end
    local f = table.remove(pool) or NewPop()
    Dress(f.text, s)
    SetAmount(f.text, value)
    if s.icon ~= "aucune" then
        f.icon:SetTexture(MEDIA .. s.icon)
        f.icon:SetSize(s.size, s.size)
        f.icon:Show()
    else
        f.icon:Hide()
    end
    local ts = tagId and Style(tagId)
    if ts and ts.on then
        Dress(f.tag, ts)
        f.tag:SetText(WORD[tagId])
        f.tag:Show()
    else
        f.tag:Hide()
    end
    f.anim, f.anchor, f.point = s.anim, anchor, point
    f.x0 = s.anim == "haut" and math.random(-25, 25) or 0
    f.y0, f.t = y0, 0
    f:SetScale(1)
    f:SetAlpha(1)
    f:Show()
    live[#live + 1] = f
end

local function Move(f, p)
    local dx, dy, scale = 0, 0, 1
    if f.anim == "arc-gauche" or f.anim == "arc-droite" then
        dx = (f.anim == "arc-gauche" and -90 or 90) * p
        dy = math.sin(p * math.pi) * 55 - p * 25
    elseif f.anim == "pop" then
        if p < 0.12 then scale = 0.6 + p / 0.12 * 0.9
        elseif p < 0.25 then scale = 1.5 - (p - 0.12) / 0.13 * 0.5 end
    else
        dy = p * 70
    end
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("CENTER", f.anchor, f.point, (f.x0 + dx) / scale, (f.y0 + dy) / scale)
    f:SetAlpha(p < 0.6 and 1 or 1 - (p - 0.6) / 0.4)
end

holder:SetScript("OnUpdate", function(_, elapsed)
    for i = #live, 1, -1 do
        local f = live[i]
        f.t = f.t + elapsed
        local p = f.t / DUR
        if p >= 1 then
            f:Hide()
            table.remove(live, i)
            pool[#pool + 1] = f
        else
            Move(f, p)
        end
    end
end)

-- Au-dessus de la barre de nom de la cible, sinon au-dessus du centre de l'écran.
local function TargetAnchor()
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok and plate and plate:IsShown() then return plate, "TOP", 10 end
    end
    return UIParent, "CENTER", 120
end

-- UNIT_COMBAT ----------------------------------------------------------------

local SCHOOL = { [1] = "phys", [2] = "holy", [4] = "fire", [8] = "nature", [16] = "frost", [32] = "shadow", [64] = "arcane" }
local AVOID = { MISS = "miss", DODGE = "dodge", PARRY = "parry", BLOCK = "block", RESIST = "resist",
                ABSORB = "absorb", IMMUNE = "immune", EVADE = "evade", DEFLECT = "deflect", REFLECT = "reflect" }
local FLAGS = { GLANCING = "glancing", BLOCK_REDUCED = "block_reduced", RESIST_REDUCED = "resist_reduced",
                ABSORB = "absorb_partial", CRUSHING = "crushing" }

local function OnUnitCombat(unit, action, flag, amount, school)
    if Secret(action) then return end
    if Secret(flag) then flag = nil end
    if Secret(school) then school = 1 end
    if unit == "player" then
        if action == "WOUND" then Pop("taken", amount, UIParent, "CENTER", 40, FLAGS[flag]) end
        return
    end
    if unit ~= "target" then return end
    local anchor, point, y0 = TargetAnchor()
    if action == "WOUND" then
        local base = SCHOOL[school] or "mixed"
        Pop(flag == "CRITICAL" and base .. "_crit" or base, amount, anchor, point, y0, FLAGS[flag])
    elseif action == "HEAL" then
        Pop(flag == "CRITICAL" and "heal_crit" or "heal", amount, anchor, point, y0)
    elseif AVOID[action] then
        Pop(AVOID[action], WORD[AVOID[action]], anchor, point, y0)
    end
end

local ev = CreateFrame("Frame")

-- Chiffres de Blizzard : masqués tant que les nôtres sont actifs (hors combat seulement).
local SetCV = (C_CVar and C_CVar.SetCVar) or SetCVar
local function ApplyBlizzard()
    if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    local hide = db.enabled and db.hideBlizzard
    pcall(SetCV, "floatingCombatTextCombatDamage", hide and "0" or "1")
end

local function ApplyEnabled()
    if db.enabled then ev:RegisterEvent("UNIT_COMBAT") else ev:UnregisterEvent("UNIT_COMBAT") end
    ApplyBlizzard()
end

-- Panneau d'options ------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = T("Chiffres de dégâts", "Damage numbers")
panel:Hide()

local refreshers = {}
local function RefreshAll() for _, fn in ipairs(refreshers) do fn() end end

local function Preview(id, sample, button)
    local s = Style(id)
    if not s then return end
    local was = s.on
    s.on = true
    Pop(id, sample, button, "TOP", 8)
    s.on = was
end

local function PickColor(s, onChange)
    local r, g, b = RGB(s.color)
    local function apply(nr, ng, nb) s.color = Hex(nr, ng, nb); onChange() end
    local function changed() apply(ColorPickerFrame:GetColorRGB()) end
    local function cancel() apply(r, g, b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = changed, cancelFunc = cancel })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = changed, cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ShowUIPanel(ColorPickerFrame)
    end
end

local function Cycle(list, current, step)
    for i, v in ipairs(list) do
        if v == current then return list[(i - 1 + step) % #list + 1] end
    end
    return list[1]
end

local ROW = 28
local COL = { on = 0, name = 28, color = 182, size = 214, bold = 254, icon = 290, anim = 324, preview = 428, sample = 510 }

local function BuildRow(content, t, y)
    local id, label, sample = t[1], t[2], t[3]
    local row = CreateFrame("Frame", nil, content)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(620, ROW)

    local on = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    on:SetSize(24, 24)
    on:SetPoint("LEFT", COL.on, 0)
    on:SetScript("OnClick", function(b) Style(id).on = b:GetChecked() and true or false end)

    local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("LEFT", COL.name, 0)
    name:SetWidth(150)
    name:SetJustifyH("LEFT")
    name:SetText(label)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetPoint("LEFT", COL.color, 0)
    swatch:SetSize(20, 20)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)

    local size = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    size:SetPoint("LEFT", COL.size + 6, 0)
    size:SetSize(28, 20)
    size:SetAutoFocus(false)
    size:SetNumeric(true)
    size:SetMaxLetters(2)

    local bold = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    bold:SetSize(24, 24)
    bold:SetPoint("LEFT", COL.bold, 0)
    bold:SetScript("OnClick", function(b) Style(id).bold = b:GetChecked() and true or false; RefreshAll() end)

    local icon = CreateFrame("Button", nil, row)
    icon:SetPoint("LEFT", COL.icon, 0)
    icon:SetSize(24, 24)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local iconTex = icon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    local iconNone = icon:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    iconNone:SetPoint("CENTER")
    iconNone:SetText("—")
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local anim = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    anim:SetPoint("LEFT", COL.anim, 0)
    anim:SetSize(98, 22)
    anim:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local prev = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    prev:SetPoint("LEFT", COL.preview, 0)
    prev:SetSize(76, 22)
    prev:SetText(T("Aperçu", "Preview"))

    local sampleFs = row:CreateFontString(nil, "OVERLAY")
    sampleFs:SetPoint("LEFT", COL.sample + 22, 0)
    local sampleIcon = row:CreateTexture(nil, "OVERLAY")
    sampleIcon:SetPoint("RIGHT", sampleFs, "LEFT", -3, 0)

    local function Refresh()
        local s = Style(id)
        on:SetChecked(s.on)
        fill:SetColorTexture(RGB(s.color))
        size:SetText(tostring(s.size))
        bold:SetChecked(s.bold)
        if s.icon == "aucune" then
            iconTex:Hide(); iconNone:Show()
        else
            iconTex:SetTexture(MEDIA .. s.icon); iconTex:Show(); iconNone:Hide()
        end
        anim:SetText(ANIM_NAMES[s.anim] or s.anim)
        -- aperçu fixe, taille plafonnée pour tenir dans la ligne
        sampleFs:SetFont(FONT, math.min(s.size, 20), s.bold and "THICKOUTLINE" or "OUTLINE")
        sampleFs:SetTextColor(RGB(s.color))
        sampleFs:SetText(sample)
        if s.icon ~= "aucune" then
            sampleIcon:SetTexture(MEDIA .. s.icon)
            sampleIcon:SetSize(math.min(s.size, 20), math.min(s.size, 20))
            sampleIcon:Show()
        else
            sampleIcon:Hide()
        end
    end
    refreshers[#refreshers + 1] = Refresh

    swatch:SetScript("OnClick", function() PickColor(Style(id), Refresh) end)
    local function SaveSize(box)
        local v = tonumber(box:GetText())
        if v then Style(id).size = math.max(8, math.min(64, v)) end
        box:ClearFocus()
        Refresh()
    end
    size:SetScript("OnEnterPressed", SaveSize)
    size:SetScript("OnEditFocusLost", SaveSize)
    size:SetScript("OnEscapePressed", function(box) box:ClearFocus(); Refresh() end)
    icon:SetScript("OnClick", function(_, button)
        local s = Style(id)
        s.icon = Cycle(ICONS, s.icon, button == "RightButton" and -1 or 1)
        Refresh()
    end)
    anim:SetScript("OnClick", function(_, button)
        local s = Style(id)
        s.anim = Cycle(ANIMS, s.anim, button == "RightButton" and -1 or 1)
        Refresh()
        Preview(id, sample, prev)
    end)
    prev:SetScript("OnClick", function(b) Preview(id, sample, b) end)
    icon:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("Clic : icône suivante\nClic droit : précédente", "Click: next icon\nRight-click: previous"))
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", GameTooltip_Hide)
end

local function BuildPanel()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(panel.name)

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(600)
    sub:SetJustifyH("LEFT")
    sub:SetText(T("Physique = coups blancs, techniques et saignements. Nature = tous les poisons. Le jeu ne distingue pas mieux.",
                  "Physical = white hits, abilities and bleeds. Nature = all poisons. The game tells nothing finer."))

    local enable = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -4, -6)
    enable:SetSize(26, 26)
    enable.label = enable:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enable.label:SetPoint("LEFT", enable, "RIGHT", 4, 1)
    enable.label:SetText(T("Afficher les chiffres de RogueTips", "Show RogueTips numbers"))
    enable:SetScript("OnClick", function(b) db.enabled = b:GetChecked() and true or false; ApplyEnabled() end)

    local blizz = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    blizz:SetPoint("LEFT", enable, "RIGHT", 240, 0)
    blizz:SetSize(26, 26)
    blizz.label = blizz:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    blizz.label:SetPoint("LEFT", blizz, "RIGHT", 4, 1)
    blizz.label:SetText(T("Masquer les chiffres de Blizzard", "Hide Blizzard numbers"))
    blizz:SetScript("OnClick", function(b) db.hideBlizzard = b:GetChecked() and true or false; ApplyBlizzard() end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPRIGHT", -24, -16)
    reset:SetSize(130, 22)
    reset:SetText(T("Réinitialiser", "Reset"))
    reset:SetScript("OnClick", function() ResetStyles(); RefreshAll() end)

    local heads = { { COL.on, T("Aff.", "On") }, { COL.name, T("Type", "Type") }, { COL.color, T("Coul.", "Color") },
                    { COL.size, T("Taille", "Size") }, { COL.bold, T("Gras", "Bold") }, { COL.icon, T("Icône", "Icon") },
                    { COL.anim, T("Animation", "Animation") }, { COL.sample, T("Rendu", "Look") } }
    for _, h in ipairs(heads) do
        local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", h[1] + 4, -8)
        fs:SetText(h[2])
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -24)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(640, 10)
    scroll:SetScrollChild(content)

    local y = 0
    for _, t in ipairs(TYPES) do
        if t.header then
            local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            h:SetPoint("TOPLEFT", 4, y - 8)
            h:SetText(t.header)
            y = y - 28
        else
            BuildRow(content, t, y)
            y = y - ROW
        end
    end
    content:SetHeight(-y + 10)

    panel:SetScript("OnShow", function()
        enable:SetChecked(db.enabled)
        blizz:SetChecked(db.hideBlizzard)
        RefreshAll()
    end)
end

-- Page de la fenêtre de réglages (Options.lua).
local function RegisterPanel()
    BuildPanel()
    ns.Options.AddPage(panel, panel.name, "Interface\\Icons\\Ability_Rogue_Eviscerate", 3)
end

local function OpenPanel() ns.Options.Toggle(panel) end

-- Démarrage --------------------------------------------------------------------

local didLoad = false
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "ADDON_LOADED" then
        if ... ~= ADDON or didLoad then return end
        didLoad = true
        RogueTipsDB = RogueTipsDB or {}
        RogueTipsDB.dmg = RogueTipsDB.dmg or { enabled = true, hideBlizzard = true }
        db = RogueTipsDB.dmg
        if not db.styles then ResetStyles() end
        for id, d in pairs(DEFAULTS) do          -- types ajoutés dans une version plus récente
            if not db.styles[id] then
                local s = {}
                for k, v in pairs(d) do s[k] = v end
                db.styles[id] = s
            end
        end
        RegisterPanel()
        ApplyEnabled()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if db then ApplyBlizzard() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ApplyBlizzard()
    end
end)

SLASH_RTDMG1 = "/rtdmg"
SlashCmdList.RTDMG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" or msg == "config" then OpenPanel(); return end
    db.enabled = not db.enabled
    ApplyEnabled()
    Print(T("chiffres de dégâts : ", "damage numbers: ") .. (db.enabled and T("activés", "on") or T("coupés", "off")))
end

-- Les SavedVariables sont chargées : Init.lua rejoue ADDON_LOADED pour ce module.
ns.onLoad[#ns.onLoad + 1] = function() ev:GetScript("OnEvent")(ev, "ADDON_LOADED", ADDON) end
end
