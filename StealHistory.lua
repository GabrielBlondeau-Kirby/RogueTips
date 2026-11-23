-- StealHistory (module de RogueTips) : historique de ce qui a été volé avec Vol à la tire.
--  1. Repère le butin ouvert juste après un Vol à la tire et l'enregistre.
--  2. Remplace dans le chat « Vous recevez le butin : x » par « Vol le butin : x ».
--  3. Fenêtre façon cadre de butin avec les N derniers vols (5 par défaut).

local ADDON, ns = ...
ns.modules = ns.modules or {}  -- exécutés par Init.lua, une fois la langue choisie connue
ns.onLoad = ns.onLoad or {}
ns.modules[#ns.modules + 1] = function()
local L = ns.L
local _, class = UnitClass("player")
if class ~= "ROGUE" then return end

local PICK_POCKET = 921
local ICON = "Interface\\AddOns\\RogueTips\\Media\\icon"
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"


local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- visibility : "always" (tout le temps) ou "nocombat" (cachée en combat).
-- combatReduce : avec "always", en combat la fenêtre passe à combatAlpha
-- et combatScale.
-- Réglages : rangés dans un profil partagé entre personnages (RogueTipsDB.stealProfiles).
-- Les données (historique, total, stats) restent propres au personnage (StealHistoryDB).
local PROFILE_DEFAULTS = {
    max = 5, replaceChat = true, autoShow = false,
    alpha = 100, visibility = "always", combatReduce = false, combatAlpha = 40, combatScale = 70,
    minimap = { angle = 200, hide = false },
    scale = 100, bgAlpha = 100, locked = false, compact = false,
    hoverFade = false, hoverAlpha = 25, autoClose = 0,
    titleX = 0, titleY = 0,
    show = { logo = true, title = true, amount = true, time = true, target = true,
             nameFrame = true, tabs = true, book = true, compactBtn = true, close = true },
}
local PROFILE_KEYS = { "max", "replaceChat", "autoShow", "alpha", "visibility", "combatReduce",
    "combatAlpha", "combatScale", "minimap", "pos" }  -- anciens réglages par personnage

local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
end
-- Complète un profil avec les valeurs par défaut manquantes (nouvelles options).
local function Fill(p, d)
    for k, v in pairs(d) do
        if p[k] == nil then p[k] = Copy(v)
        elseif type(v) == "table" and type(p[k]) == "table" then Fill(p[k], v) end
    end
    return p
end

local db = { history = {}, stats = nil }
local cfg = Copy(PROFILE_DEFAULTS)
local profiles  -- RogueTipsDB.stealProfiles
ns.steal = {}  -- partagé avec StealJournal.lua (grande fenêtre)

-- Valeurs « secrètes » des clients récents (noms d'unités en instance,
-- en combat…) : on ne peut ni les comparer ni les sauvegarder. On les ignore.
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end
local function Readable(v)
    if Secret(v) or v == nil or v == "" then return nil end  -- Secret d'abord : comparer une valeur secrète plante
    return v
end

local function Print(msg)
    print("|cff33ff99RogueTips|r : " .. msg)
end

---------------------------------------------------------------------------
-- 1. Détection du vol
---------------------------------------------------------------------------
-- Vol à la tire ouvre une fenêtre de butin, comme un cadavre. On considère
-- que c'est un vol si elle s'ouvre moins de 2 s après l'envoi du sort.

local castAt, castTarget = 0, nil
local stealing = false     -- fenêtre de butin du vol ouverte
local windowEnd = 0        -- fin de la période où les messages du chat sont « volés »
local moneyBefore = 0      -- argent au moment du sort
local HISTORY_KEEP = 20  -- maximum du curseur « Vols gardés »
local lastCast, countedCast = 0, nil  -- un vol = un sort, même s'il donne pièces + objet
local stealMoney = 0       -- pièces du vol en cours (pour le meilleur vol)

local Refresh, ScheduleAutoClose  -- fenêtre, définis plus bas
local debug = false  -- /sh debug

---------------------------------------------------------------------------
-- Statistiques : un « seau » par session, un pour le total, un par mois archivé.
-- Au-delà de MAX_SESSIONS, la plus ancienne session est fusionnée dans
-- l'archive de son mois : on garde les totaux, on perd seulement le découpage.
---------------------------------------------------------------------------

local MAX_SESSIONS = 100

local function NewBucket(start)
    start = start or time()
    return { money = 0, steals = 0, nitems = 0, best = 0, start = start, stop = start,
             items = {}, targets = {}, zones = {} }
end

local function Duration(b) return b.time or math.max(0, b.stop - b.start) end

local function Merge(into, b)
    into.money = into.money + b.money
    into.steals = into.steals + b.steals
    into.nitems = into.nitems + b.nitems
    into.best = math.max(into.best, b.best)
    into.start = math.min(into.start, b.start)
    into.stop = math.max(into.stop, b.stop)
    into.time = (into.time or 0) + Duration(b)
    for id, it in pairs(b.items) do
        local t = into.items[id]
        if t then t.n = t.n + it.n else into.items[id] = { n = it.n, link = it.link } end
    end
    for name, t in pairs(b.targets) do
        local u = into.targets[name] or { m = 0, n = 0 }
        u.m, u.n = u.m + t.m, u.n + t.n
        into.targets[name] = u
    end
    for zone, n in pairs(b.zones) do into.zones[zone] = (into.zones[zone] or 0) + n end
end

local function Archive(b)
    local key, list = date("%Y-%m", b.start), db.stats.archives
    local arch
    for _, a in ipairs(list) do if a.key == key then arch = a break end end
    if not arch then
        arch = NewBucket(b.start)
        arch.key, arch.time = key, 0
        list[#list + 1] = arch
        table.sort(list, function(x, y) return x.key > y.key end)
    end
    Merge(arch, b)
end

-- Nouvelle session à la connexion (pas au /reload). Une session sans vol est jetée.
local function StartSession()
    local s = db.stats.sessions
    if s[1] and s[1].steals == 0 then table.remove(s, 1) end
    table.insert(s, 1, NewBucket())
    while #s > MAX_SESSIONS do Archive(table.remove(s)) end
end

local function Bump(b, entry, newSteal, zone)
    b.stop = time()
    local t = castTarget and b.targets[castTarget]
    if newSteal then
        b.steals = b.steals + 1
        if zone then b.zones[zone] = (b.zones[zone] or 0) + 1 end
        if castTarget then
            t = t or { m = 0, n = 0 }
            t.n = t.n + 1
            b.targets[castTarget] = t
        end
    end
    if entry.money then
        b.money = b.money + entry.money
        if t then t.m = t.m + entry.money end
        b.best = math.max(b.best, stealMoney)
    end
    if entry.link then
        local id = entry.link:match("item:(%d+)")
        local n = entry.count or 1
        if id then
            local it = b.items[id] or { n = 0 }
            it.n, it.link = it.n + n, entry.link
            b.items[id] = it
        end
        b.nitems = b.nitems + n
    end
end

local function Record(entry)
    local newSteal = lastCast ~= countedCast
    if newSteal then countedCast, stealMoney = lastCast, 0 end
    if entry.money then stealMoney = stealMoney + entry.money end
    local zone = Readable(GetRealZoneText and GetRealZoneText())
    if not db.stats.sessions[1] then StartSession() end
    Bump(db.stats.all, entry, newSteal, zone)
    Bump(db.stats.sessions[1], entry, newSteal, zone)
end

local function Add(entry)
    entry.target = castTarget
    entry.time = time()
    table.insert(db.history, 1, entry)
    for i = #db.history, HISTORY_KEEP + 1, -1 do db.history[i] = nil end  -- on n'en affiche que cfg.max
    if entry.money then db.total = (db.total or 0) + entry.money end
    Record(entry)
    if ns.steal.OnSteal then ns.steal.OnSteal() end
    -- On ouvre d'abord : OnShow remplit la liste, et une erreur dans la mise
    -- à jour ne peut plus empêcher l'ouverture.
    local f = StealHistoryFrame
    if cfg.autoShow and not f:IsShown() then
        ns.steal.AutoOpened()
        f:Show()
    else
        Refresh()
    end
    ScheduleAutoClose()
    if debug then
        Print(("vol enregistré (%s) | autoShow=%s, fenêtre=%s, visible=%s, alpha=%.2f, combat=%s"):format(
            entry.link or (entry.money .. " cuivre"), tostring(cfg.autoShow), tostring(f:IsShown()),
            tostring(f:IsVisible()), f:GetEffectiveAlpha(), tostring(InCombatLockdown())))
    end
end

-- Vol en cours : sort lancé il y a moins de 2 s, fenêtre de butin ouverte,
-- ou fermée depuis moins de 2 s (le chat et l'argent arrivent parfois après).
local function InWindow()
    return stealing or GetTime() < windowEnd or GetTime() - castAt < 2
end

-- LOOT_READY (ramassage auto) puis LOOT_OPENED : le premier des deux suffit.
local function OnLootOpened()
    if stealing or GetTime() - castAt > 2 then return end
    castAt = 0
    stealing = true
end

---------------------------------------------------------------------------
-- 2. Chat : « Vol le butin : x »
---------------------------------------------------------------------------
-- Les messages du jeu sont des formats localisés (« Vous recevez le butin : %s. ») :
-- on les transforme en motifs Lua pour récupérer l'objet ou la somme.

local function Pattern(fmt)
    if not fmt then return nil end
    -- %s / %d (ou %1$s) -> repères, échappement des caractères magiques, puis captures.
    fmt = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    fmt = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. fmt .. "$"
end

local PATTERNS = {
    CHAT_MSG_LOOT  = { Pattern(LOOT_ITEM_SELF_MULTIPLE), Pattern(LOOT_ITEM_SELF) },
    CHAT_MSG_MONEY = { Pattern(YOU_LOOT_MONEY), Pattern(LOOT_MONEY_SPLIT) },
}

-- Les objets sont enregistrés depuis le message « Vous recevez le butin » :
-- avec le ramassage auto, la fenêtre de butin est souvent déjà vide quand
-- l'addon la lit, alors que le message arrive toujours.
local function RecordLoot(msg)
    if Secret(msg) then return end
    for _, pat in ipairs(PATTERNS.CHAT_MSG_LOOT) do
        local link, count = msg:match(pat)
        if link and link:find("|Hitem:") then
            Add({ link = link, count = tonumber(count) or 1 })
            return
        end
    end
end

local function ChatFilter(_, event, msg, ...)
    if not cfg.replaceChat or not InWindow() or Secret(msg) then return false end
    for _, pat in ipairs(PATTERNS[event]) do
        local what, count = msg:match(pat)
        if what then
            if count then what = what .. " x" .. count end
            return false, L.STOLE:format(what), ...
        end
    end
    return false
end

local addFilter = ChatFrame_AddMessageEventFilter
    or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
addFilter("CHAT_MSG_LOOT", ChatFilter)
addFilter("CHAT_MSG_MONEY", ChatFilter)

---------------------------------------------------------------------------
-- 3. Fenêtre façon cadre de butin
---------------------------------------------------------------------------

local ROW_H, WIDTH = 44, 290  -- 3 colonnes : icône, nom + cible, heure

-- Somme en pièces avec icônes. GetCoinTextureString n'existe plus sur les
-- clients récents (déplacée dans C_CurrencyInfo) : on prend ce qui existe.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function Coins(c)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if f then return f(c) end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. COIN:format("Gold") end
    if s > 0 then out[#out + 1] = s .. COIN:format("Silver") end
    if k > 0 or #out == 0 then out[#out + 1] = k .. COIN:format("Copper") end
    return table.concat(out, " ")
end


-- Le conteneur porte la visibilité / transparence ; la fenêtre, elle, garde
-- son état ouvert / fermé choisi par le joueur.
local holder = CreateFrame("Frame", nil, UIParent)
holder:SetAllPoints(UIParent)

local frame = CreateFrame("Frame", "StealHistoryFrame", holder, BACKDROP_TEMPLATE)

-- La position est sauvée en unités d'UIParent : on la divise par l'échelle
-- pour que la fenêtre réduite reste au même endroit.
local function Place()
    local p, s = cfg.pos or { "CENTER", "CENTER", 0, 0 }, frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3] / s, p[4] / s)
end

local inCombat = false
local hovered = false  -- souris sur la fenêtre (option « nette au survol »)
local function ApplyVisibility()
    holder:SetShown(not (inCombat and cfg.visibility == "nocombat"))
    local reduced = inCombat and cfg.visibility == "always" and cfg.combatReduce
    local faded = cfg.hoverFade and not hovered
    local a = (reduced and cfg.combatAlpha or cfg.alpha) / 100
    if faded then a = a * cfg.hoverAlpha / 100 end
    holder:SetAlpha(a)
    frame:SetScale(cfg.scale / 100 * (reduced and cfg.combatScale / 100 or 1))
    if frame.SetBackdropColor then frame:SetBackdropColor(1, 1, 1, cfg.bgAlpha / 100) end
    -- Le cadre du titre reste opaque, comme celui du journal (sauf réduction en combat ou survol).
    if ns.steal.headerFrame and ns.steal.headerFrame.SetIgnoreParentAlpha then
        ns.steal.headerFrame:SetIgnoreParentAlpha(not reduced and not faded)
    end
    Place()
end
frame:SetSize(WIDTH, 120)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) if not cfg.locked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    local s = self:GetScale()
    cfg.pos = { point, rel, x * s, y * s }
end)
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()
tinsert(UISpecialFrames, "StealHistoryFrame")  -- Échap ferme la fenêtre

-- Bandeau du titre en trois morceaux (bouts fixes, milieu étiré) : il
-- s'élargit avec le texte sans déformer ses extrémités.
local HEADER_TEX = "Interface\\DialogFrame\\UI-DialogBox-Header"
local headerFrame = CreateFrame("Frame", nil, frame)  -- au-dessus de la bordure de la fenêtre
headerFrame:SetAllPoints()
headerFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
ns.steal.headerFrame = headerFrame
-- Icône en haut à gauche, comme le cadre de butin.
local portrait = headerFrame:CreateTexture(nil, "OVERLAY")
portrait:SetSize(46, 46)
portrait:SetPoint("TOPLEFT", -14, 14)
portrait:SetTexture(ICON)  -- icône carrée telle quelle, sans cercle

local header = headerFrame:CreateTexture(nil, "ARTWORK")
header:SetTexture(HEADER_TEX)
header:SetTexCoord(0.31, 0.67, 0, 0.63)
header:SetSize(100, 40)
header:SetPoint("TOP", 12, 12)
local headerL = headerFrame:CreateTexture(nil, "ARTWORK")
headerL:SetTexture(HEADER_TEX)
headerL:SetTexCoord(0.21, 0.31, 0, 0.63)
headerL:SetSize(30, 40)
headerL:SetPoint("RIGHT", header, "LEFT")
local headerR = headerFrame:CreateTexture(nil, "ARTWORK")
headerR:SetTexture(HEADER_TEX)
headerR:SetTexCoord(0.67, 0.77, 0, 0.63)
headerR:SetSize(30, 40)
headerR:SetPoint("LEFT", header, "RIGHT")
local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
local TITLE = L.TITLE

-- Titre + pièces volées pendant la session ; le bandeau suit la largeur.
-- Au survol du titre : session et total.
local function SessionMoney()
    local cur = db.stats and db.stats.sessions[1]
    return cur and cur.money or 0
end
local function UpdateTitle()
    local money = SessionMoney()
    local show = cfg.show.amount and money > 0
    title:SetText(show and (TITLE .. "   |cffffffff" .. Coins(money) .. "|r") or TITLE)
    header:SetWidth(math.max(60, title:GetStringWidth() + 16))
end

local titleHit = CreateFrame("Button", nil, headerFrame)
titleHit:SetPoint("TOPLEFT", headerL, "TOPLEFT", 8, -8)
titleHit:SetPoint("BOTTOMRIGHT", headerR, "BOTTOMRIGHT", -8, 14)
titleHit:RegisterForDrag("LeftButton")
titleHit:SetScript("OnDragStart", function() if not cfg.locked then frame:StartMoving() end end)
titleHit:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
titleHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddDoubleLine(L.TIP_SESSION, Coins(SessionMoney()), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TIP_TOTAL, Coins(db.total or 0), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:Show()
end)
titleHit:SetScript("OnLeave", GameTooltip_Hide)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("TOP", 0, -50)
empty:SetText(L.EMPTY)

local rows = {}

local function RowEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.link then
        GameTooltip:SetHyperlink(e.link)
    else
        GameTooltip:AddLine(Coins(e.money), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(e.target or "?", date("%d/%m %H:%M", e.time), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function RowClick(self)
    local e = self.entry
    if e and e.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(e.link) end
end

-- Même construction qu'un bouton de butin : icône + cadre de nom doré.
-- Mode compact : une ligne de 22 px, petite icône, ni cadre doré ni cible.
local ROW_C = 22
local function RowHeight() return cfg.compact and ROW_C or ROW_H end

local function LayoutRow(r, i)
    local compact, sh = cfg.compact, cfg.show
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 22, -34 - (i - 1) * RowHeight())
    r:SetSize(WIDTH - 40, RowHeight() - (compact and 2 or 4))
    r.icon:SetSize(compact and 18 or 37, compact and 18 or 37)
    r.border:SetShown(not compact)
    r.nameFrame:SetShown(not compact and sh.nameFrame)
    r.name:ClearAllPoints()
    if compact then
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetFontObject("GameFontNormalSmall")
    else
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -3)
        r.name:SetFontObject("GameFontNormal")
    end
    r.name:SetWidth(WIDTH - (compact and 110 or 145))
    r.sub:SetShown(not compact and sh.target)
    r.time:SetShown(sh.time)
    r.count:SetFontObject(compact and "NumberFontNormalSmall" or "NumberFontNormal")
end

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, frame)

    r.icon = r:CreateTexture(nil, "BORDER")
    r.icon:SetPoint("LEFT")
    r.border = r:CreateTexture(nil, "ARTWORK")
    r.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    r.border:SetSize(64, 64)
    r.border:SetPoint("CENTER", r.icon, "CENTER")

    r.nameFrame = r:CreateTexture(nil, "BACKGROUND")
    r.nameFrame:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame")
    r.nameFrame:SetSize(WIDTH - 120, 64)
    r.nameFrame:SetPoint("LEFT", r.icon, "RIGHT", -10, 0)

    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetWidth(WIDTH - 145)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)

    r.time = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    r.time:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.time:SetJustifyH("RIGHT")

    r.count = r:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    r.count:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", -2, 2)

    r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    r:GetHighlightTexture():SetAllPoints(r.icon)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", RowClick)
    rows[i] = r
    LayoutRow(r, i)
    return r
end

-- Nom coloré (qualité) et icône tirés d'un lien « |cffffffff|Hitem:…|h[Nom]|h|r ».
local function ItemLook(link)
    local color = link:match("|c(%x%x%x%x%x%x%x%x)") or "ffffffff"
    local name = link:match("%[(.-)%]") or link
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(link))
        or (GetItemIcon and GetItemIcon(link))
    return "|c" .. color .. name .. "|r", icon or ICON
end

-- Objets d'un seau, du plus volé au moins volé.
local function SortedItems(b)
    local list = {}
    for _, it in pairs(b.items) do list[#list + 1] = it end
    table.sort(list, function(x, y)
        if x.n ~= y.n then return x.n > y.n end
        return (x.link:match("%[(.-)%]") or "") < (y.link:match("%[(.-)%]") or "")
    end)
    return list
end

local function ItemEnter(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
end
local function ItemClick(self)
    if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
end

-- Onglets : Récents / Stats / Butin --------------------------------------

local TAB_H = 26
local tab = "recent"
local panes = {}

local function RefreshRecent()
    local n = math.min(#db.history, cfg.max)
    for i = 1, n do
        local e, r = db.history[i], Row(i)
        r.entry = e
        if e.link then
            local name, icon = ItemLook(e.link)
            r.icon:SetTexture(icon)
            r.name:SetText(name)
            r.count:SetText((e.count or 1) > 1 and e.count or "")
        else
            r.icon:SetTexture(COIN_ICON)
            r.name:SetText(Coins(e.money))
            r.name:SetTextColor(1, 1, 1)
            r.count:SetText("")
        end
        r.sub:SetText(e.target or "?")
        r.time:SetText(date("%H:%M", e.time))
        r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    empty:ClearAllPoints()
    empty:SetPoint("TOP", 0, -50)
    empty:SetText(L.EMPTY)
    empty:SetShown(n == 0)
    return math.max(n, 1) * RowHeight() + 50
end

-- Stats : deux encadrés (session, total) puis moyenne et meilleur vol.
local stats = CreateFrame("Frame", nil, frame)
stats:SetPoint("TOPLEFT", 22, -32)
stats:SetPoint("RIGHT", -22, 0)
stats:SetHeight(170)
panes.stats = stats

local function Box(parent, y)
    local b = CreateFrame("Frame", nil, parent, BACKDROP_TEMPLATE)
    b:SetPoint("TOPLEFT", 0, y)
    b:SetPoint("RIGHT")
    b:SetHeight(58)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        b:SetBackdropColor(0, 0, 0, 0.5)
        b:SetBackdropBorderColor(0.55, 0.45, 0.25)
    end
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.label:SetPoint("TOPLEFT", 8, -7)
    b.value = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    b.value:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -3)
    b.sub = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.sub:SetPoint("TOPLEFT", b.value, "BOTTOMLEFT", 0, -2)
    return b
end
local boxSession, boxTotal = Box(stats, 0), Box(stats, -64)

local function StatLine(y, label)
    local l = stats:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    l:SetPoint("TOPLEFT", 4, y)
    l:SetText(label)
    local v = stats:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    v:SetPoint("TOPRIGHT", -4, y)
    return v
end
local avgValue = StatLine(-132, L.AVG)
local bestValue = StatLine(-150, L.BEST)

local function RefreshStats()
    local st, cur = db.stats, db.stats.sessions[1] or NewBucket()
    boxSession.label:SetText(L.SESSION:format(date("%H:%M", cur.start)))
    boxSession.value:SetText(Coins(cur.money))
    boxSession.sub:SetText(L.COUNTS:format(cur.steals, cur.nitems))
    boxTotal.label:SetText(L.TOTAL)
    boxTotal.value:SetText(Coins(db.total or 0))
    boxTotal.sub:SetText(L.COUNTS:format(st.all.steals, st.all.nitems))
    avgValue:SetText(st.all.steals > 0 and Coins(math.floor(st.all.money / st.all.steals)) or "-")
    bestValue:SetText(st.all.best > 0 and Coins(st.all.best) or "-")
    return 180 + 44
end

-- Butin : récapitulatif des objets, session ou total.
local LOOT_ROWS, LOOT_H = 10, 22
local loot = CreateFrame("Frame", nil, frame)
loot:SetPoint("TOPLEFT", 22, -32)
loot:SetPoint("RIGHT", -22, 0)
loot:SetHeight(30)
panes.loot = loot
local lootPeriod = "session"

local periodBtns = {}
local function PeriodButton(key, label, x)
    local b = CreateFrame("Button", nil, loot, "UIPanelButtonTemplate")
    b:SetSize(80, 20)
    b:SetPoint("TOPLEFT", x, 0)
    b:SetText(label)
    b:SetScript("OnClick", function() lootPeriod = key; Refresh() end)
    periodBtns[key] = b
end
PeriodButton("session", L.P_SESSION, 0)
PeriodButton("total", L.P_TOTAL, 84)

local lootRows = {}
for i = 1, LOOT_ROWS do
    local r = CreateFrame("Button", nil, loot)
    r:SetHeight(LOOT_H - 2)
    r:SetPoint("TOPLEFT", 0, -26 - (i - 1) * LOOT_H)
    r:SetPoint("RIGHT")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT")
    r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", -40, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.count = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.count:SetPoint("RIGHT", -2, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r:SetScript("OnEnter", ItemEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", ItemClick)
    lootRows[i] = r
end
local lootMore = loot:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")

local function RefreshLoot()
    for key, b in pairs(periodBtns) do
        if key == lootPeriod then b:LockHighlight() else b:UnlockHighlight() end
    end
    local b = lootPeriod == "total" and db.stats.all or db.stats.sessions[1] or NewBucket()
    local list = SortedItems(b)
    local n = math.min(#list, LOOT_ROWS)
    for i = 1, LOOT_ROWS do
        local r, it = lootRows[i], list[i]
        if i <= n then
            local name, icon = ItemLook(it.link)
            r.link = it.link
            r.icon:SetTexture(icon)
            r.name:SetText(name)
            r.count:SetText("×" .. it.n)
            r:Show()
        else
            r:Hide()
        end
    end
    lootMore:ClearAllPoints()
    lootMore:SetPoint("TOPLEFT", 0, -28 - n * LOOT_H)
    lootMore:SetText(#list > n and L.MORE:format(#list - n) or "")
    empty:ClearAllPoints()
    empty:SetPoint("TOP", 0, -66)
    empty:SetText(L.NO_LOOT)
    empty:SetShown(n == 0)
    return 26 + math.max(n, 1) * LOOT_H + (#list > n and 16 or 0) + 50 + 8
end

local tabBtns = {}
local function SelectTab(key)
    tab = key
    Refresh()
end
local TABS = { { "recent", L.TAB_RECENT }, { "stats", L.TAB_STATS }, { "loot", L.TAB_LOOT } }
for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize((WIDTH - 44) / 3 - 2, 22)
    b:SetPoint("BOTTOMLEFT", 22 + (i - 1) * ((WIDTH - 44) / 3), 14)
    b:SetText(t[2])
    b:SetScript("OnClick", function() SelectTab(t[1]) end)
    tabBtns[t[1]] = b
end

-- Livre dans le coin : ouvre le Journal du voleur (StealJournal.lua).
local book = CreateFrame("Button", nil, frame)
book:SetSize(20, 20)
book:SetPoint("RIGHT", close, "LEFT", 0, 0)
book:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
book:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
book:SetScript("OnClick", function() if ns.steal.ToggleJournal then ns.steal.ToggleJournal() end end)
book:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.JOURNAL)
    GameTooltip:Show()
end)
book:SetScript("OnLeave", GameTooltip_Hide)

-- Parchemin à côté du livre : passe en mode compact et en revient (coloré = compact).
local ApplyLayout
local compactBtn = CreateFrame("Button", nil, frame)
compactBtn:SetSize(20, 20)
compactBtn:SetPoint("RIGHT", book, "LEFT", -2, 0)
compactBtn:SetNormalTexture("Interface\\Icons\\INV_Scroll_03")
compactBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
compactBtn:SetScript("OnClick", function(self)
    cfg.compact = not cfg.compact
    ApplyLayout()
    if ns.steal.RefreshOptions then ns.steal.RefreshOptions() end
    self:GetScript("OnEnter")(self)
end)
compactBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.COMPACT_BTN)
    GameTooltip:AddLine(cfg.compact and L.COMPACT_ON or L.COMPACT_OFF, 1, 1, 1)
    GameTooltip:Show()
end)
compactBtn:SetScript("OnLeave", GameTooltip_Hide)

Refresh = function()
    if tab ~= "recent" then
        for i = 1, #rows do rows[i]:Hide() end
    end
    stats:SetShown(tab == "stats")
    loot:SetShown(tab == "loot")
    empty:Hide()
    local h
    if tab == "stats" then h = RefreshStats()
    elseif tab == "loot" then h = RefreshLoot()
    else h = RefreshRecent() end
    for key, b in pairs(tabBtns) do
        if key == tab then b:LockHighlight() else b:UnlockHighlight() end
    end
    UpdateTitle()
    frame:SetHeight(h + (cfg.show.tabs and TAB_H or 0))
end

-- Éléments affichés et mode compact (profil).
ApplyLayout = function()
    local sh = cfg.show
    header:ClearAllPoints()
    header:SetPoint("TOP", 12 + cfg.titleX, 12 + cfg.titleY)
    portrait:SetShown(sh.logo)
    for _, t in ipairs({ header, headerL, headerR, title }) do t:SetShown(sh.title) end
    titleHit:SetShown(sh.title)
    close:SetShown(sh.close)
    book:SetShown(sh.book)
    compactBtn:SetShown(sh.compactBtn)
    local tex = compactBtn:GetNormalTexture()
    if tex and tex.SetDesaturated then tex:SetDesaturated(not cfg.compact) end
    for _, b in pairs(tabBtns) do b:SetShown(sh.tabs) end
    for i, r in ipairs(rows) do LayoutRow(r, i) end
    if frame:IsShown() then Refresh() end
end

-- Nette au survol : on regarde la souris dix fois par seconde.
local hoverWatch, hoverAcc = CreateFrame("Frame"), 0
hoverWatch:SetScript("OnUpdate", function(_, elapsed)
    if not cfg.hoverFade then
        if hovered then hovered = false end
        return
    end
    hoverAcc = hoverAcc + elapsed
    if hoverAcc < 0.1 then return end
    hoverAcc = 0
    local over = frame:IsVisible() and frame:IsMouseOver() or false
    if over ~= hovered then
        hovered = over
        ApplyVisibility()
    end
end)

-- Fermeture automatique : seulement si la fenêtre s'est ouverte toute seule après un vol.
local autoOpened, closeToken, previewing = false, 0, false
ns.steal.AutoOpened = function() autoOpened = true end
ScheduleAutoClose = function()
    if not autoOpened or cfg.autoClose <= 0 or not C_Timer then return end
    closeToken = closeToken + 1
    local token = closeToken
    C_Timer.After(cfg.autoClose, function()
        if token ~= closeToken or not autoOpened or previewing then return end
        if frame:IsMouseOver() then ScheduleAutoClose() return end  -- on attend que la souris parte
        autoOpened = false
        frame:Hide()
    end)
end

frame:SetScript("OnShow", Refresh)
frame:SetScript("OnHide", function()
    autoOpened = false
    if debug then Print("fenêtre fermée par :\n" .. debugstack(2, 4, 0)) end
end)

local function Toggle()
    autoOpened = false
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- 4. Panneau d'options (page de la fenêtre de réglages, Options.lua), dans un cadre qui défile
---------------------------------------------------------------------------

local SetProfile, DeleteProfile, ProfileNames, ApplyAll  -- définis avec les profils, plus bas

local panel = CreateFrame("Frame")
panel.name = "StealHistory"

local pscroll = CreateFrame("ScrollFrame", "StealHistoryOptionsScroll", panel, "UIPanelScrollFrameTemplate")
pscroll:SetPoint("TOPLEFT", 0, -6)
pscroll:SetPoint("BOTTOMRIGHT", -28, 6)
local opts = CreateFrame("Frame", nil, pscroll)
opts:SetSize(620, 1420)
pscroll:SetScrollChild(opts)

local ptitle = opts:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
ptitle:SetPoint("TOPLEFT", 16, -10)
ptitle:SetText("StealHistory")

local psub = opts:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
psub:SetPoint("TOPLEFT", ptitle, "BOTTOMLEFT", 0, -8)
psub:SetText(L.SUBTITLE)

local refreshers = {}

local function Section(anchor, y, text)
    local h = opts:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    h:SetText(text)
    local line = opts:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", h, "RIGHT", 8, 0)
    line:SetWidth(560 - h:GetStringWidth())
    return h
end

local sliderCount = 0
local function Slider(anchor, x, y, min, max, step, label, key, onChange)
    sliderCount = sliderCount + 1
    local name = "StealHistorySlider" .. sliderCount
    local s = CreateFrame("Slider", name, opts, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    s:SetWidth(220)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[name .. "Low"]:SetText(min)
    _G[name .. "High"]:SetText(max)
    local function Label(v) _G[name .. "Text"]:SetText(label(v)) end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        Label(v)
        if v == cfg[key] then return end
        cfg[key] = v
        onChange(v)
    end)
    refreshers[#refreshers + 1] = function() s:SetValue(cfg[key]); Label(cfg[key]) end
    return s
end

local function CheckBox(anchor, x, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, opts, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb
end
local function Option(key, after)
    return function() return cfg[key] end,
           function(v) cfg[key] = v; if after then after() end end
end

local function Button(anchor, point, x, y, w, label, onClick)
    local b = CreateFrame("Button", nil, opts, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", anchor, point, x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Profil -------------------------------------------------------------------

local hProfile = Section(psub, -18, L.PROFILE)
local profileBtn = CreateFrame("Button", nil, opts, "UIPanelButtonTemplate")
profileBtn:SetSize(200, 24)
profileBtn:SetPoint("TOPLEFT", hProfile, "BOTTOMLEFT", 0, -8)
profileBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
profileBtn:SetScript("OnClick", function(_, button)
    local names, cur = ProfileNames(), db.profile
    if #names < 2 then return end
    for i, n in ipairs(names) do
        if n == cur then
            local step = button == "RightButton" and -1 or 1
            SetProfile(names[(i - 1 + step) % #names + 1])
            return
        end
    end
    SetProfile(names[1])
end)
profileBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.PROFILE)
    GameTooltip:AddLine(L.PROFILE_CYCLE, 1, 1, 1, true)
    GameTooltip:Show()
end)
profileBtn:SetScript("OnLeave", GameTooltip_Hide)
refreshers[#refreshers + 1] = function() profileBtn:SetText(db.profile or "?") end

StaticPopupDialogs.ROGUETIPS_NEW_PROFILE = {
    text = L.PROFILE_NEW_PROMPT, button1 = ACCEPT, button2 = CANCEL, hasEditBox = true,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        local name = box and strtrim(box:GetText() or "") or ""
        if name ~= "" then
            if not profiles[name] then profiles[name] = Copy(cfg) end
            SetProfile(name)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs.ROGUETIPS_NEW_PROFILE.OnAccept(parent)
        parent:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs.ROGUETIPS_DELETE_PROFILE = {
    text = L.PROFILE_DELETE_CONFIRM, button1 = YES, button2 = NO,
    OnAccept = function() DeleteProfile(db.profile) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local newBtn = Button(profileBtn, "TOPRIGHT", 8, 0, 120, L.PROFILE_NEW,
    function() StaticPopup_Show("ROGUETIPS_NEW_PROFILE") end)
local delBtn = Button(newBtn, "TOPRIGHT", 8, 0, 120, L.PROFILE_DELETE, function()
    if #ProfileNames() < 2 then Print(L.PROFILE_LAST) return end
    StaticPopup_Show("ROGUETIPS_DELETE_PROFILE", db.profile)
end)
local profileHint = opts:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
profileHint:SetPoint("TOPLEFT", profileBtn, "BOTTOMLEFT", 2, -6)
profileHint:SetText(L.PROFILE_HINT)

-- Général ------------------------------------------------------------------

local hGeneral = Section(profileHint, -20, L.GENERAL)
local sCount = Slider(hGeneral, 4, -26, 1, 20, 1,
    function(v) return L.KEPT:format(v) end, "max",
    function(v)
        Refresh()
    end)
local cbChat = CheckBox(sCount, -4, -26, L.CHAT_OPT:format(L.STOLE:format("x")), Option("replaceChat"))
local cbShow = CheckBox(cbChat, 0, -4, L.AUTOSHOW, Option("autoShow"))
local sClose = Slider(cbShow, 32, -22, 0, 30, 1,
    function(v) return v == 0 and L.AUTOCLOSE_OFF or L.AUTOCLOSE:format(v) end, "autoClose",
    function() end)
local SetMinimapShown  -- défini avec le bouton de la minimap
local cbMinimap = CheckBox(sClose, -32, -24, L.MINIMAP,
    function() return not cfg.minimap.hide end,
    function(v) SetMinimapShown(v) end)

-- Apparence ----------------------------------------------------------------

local hLook = Section(cbMinimap, -20, L.APPEARANCE)
local sScale = Slider(hLook, 4, -26, 70, 150, 5,
    function(v) return L.SCALE:format(v) end, "scale", ApplyVisibility)
local sAlpha = Slider(sScale, 0, -36, 10, 100, 5,
    function(v) return L.OPACITY:format(v) end, "alpha", ApplyVisibility)
local sBg = Slider(sAlpha, 0, -36, 0, 100, 5,
    function(v) return L.BG_OPACITY:format(v) end, "bgAlpha", ApplyVisibility)
local sTitleX = Slider(sBg, 0, -36, -80, 80, 1,
    function(v) return L.TITLE_X:format(v) end, "titleX", ApplyLayout)
local sTitleY = Slider(sTitleX, 0, -36, -20, 30, 1,
    function(v) return L.TITLE_Y:format(v) end, "titleY", ApplyLayout)
local cbCompact = CheckBox(sTitleY, -4, -26, L.COMPACT, Option("compact", ApplyLayout))
local cbLock = CheckBox(cbCompact, 0, -4, L.LOCK, Option("locked"))
local hoverWidgets = {}
local function UpdateHoverOptions()
    for _, w in ipairs(hoverWidgets) do
        w:SetAlpha(cfg.hoverFade and 1 or 0.4)
        w:EnableMouse(cfg.hoverFade)
    end
end
local cbHover = CheckBox(cbLock, 0, -4, L.HOVER, Option("hoverFade", function()
    UpdateHoverOptions()
    ApplyVisibility()
end))
local sHover = Slider(cbHover, 32, -22, 0, 100, 5,
    function(v) return L.HOVER_ALPHA:format(v) end, "hoverAlpha", ApplyVisibility)
hoverWidgets = { sHover }
refreshers[#refreshers + 1] = UpdateHoverOptions

local hShow = opts:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
hShow:SetPoint("TOPLEFT", sHover, "BOTTOMLEFT", -32, -26)
hShow:SetText(L.ELEMENTS)
local ELEMENTS = { "logo", "title", "amount", "time", "target", "nameFrame", "tabs", "book", "compactBtn", "close" }
local lastShow
for i, key in ipairs(ELEMENTS) do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local cb = CheckBox(hShow, col * 190 - 4, -4 - row * 26, L["SHOW_" .. key:upper()],
        function() return cfg.show[key] end,
        function(v) cfg.show[key] = v; ApplyLayout() end)
    if col == 0 then lastShow = cb end
end

-- Visibilité : « Tout le temps » / « Hors combat » s'excluent ; sous « Tout le temps »,
-- la réduction en combat et ses deux réglages (grisés sinon).
local visTitle = Section(lastShow, -20, L.VISIBILITY)
visTitle:ClearAllPoints()
visTitle:SetPoint("TOPLEFT", lastShow, "BOTTOMLEFT", 4, -20)

local visBoxes, reduceWidgets = {}, {}
local function UpdateVisibilityOptions()
    for _, b in ipairs(visBoxes) do b:SetChecked(b.mode == cfg.visibility) end
    local on = cfg.visibility == "always"
    for _, w in ipairs(reduceWidgets) do
        w:SetAlpha(on and 1 or 0.4)
        w:EnableMouse(on)
    end
end
local function VisBox(anchor, x, y, mode, label)
    local cb = CheckBox(anchor, x, y, label,
        function() return cfg.visibility == mode end,
        function()
            cfg.visibility = mode
            UpdateVisibilityOptions()
            ApplyVisibility()
        end)
    cb.mode = mode
    visBoxes[#visBoxes + 1] = cb
    return cb
end

local cbAlways = VisBox(visTitle, -4, -6, "always", L.VIS_ALWAYS)
local cbReduce = CheckBox(cbAlways, 24, -2, L.VIS_FADE,
    function() return cfg.combatReduce end,
    function(v) cfg.combatReduce = v; ApplyVisibility() end)
local sCombat = Slider(cbReduce, 8, -24, 0, 100, 5,
    function(v) return L.COMBAT_OPACITY:format(v) end, "combatAlpha", ApplyVisibility)
local sCScale = Slider(sCombat, 0, -36, 50, 100, 5,
    function(v) return L.COMBAT_SIZE:format(v) end, "combatScale", ApplyVisibility)
reduceWidgets = { cbReduce, sCombat, sCScale }
local cbNoCombat = VisBox(sCScale, -32, -24, "nocombat", L.VIS_NOCOMBAT)
refreshers[#refreshers + 1] = UpdateVisibilityOptions

-- Boutons ------------------------------------------------------------------

local clear = Button(cbNoCombat, "BOTTOMLEFT", 4, -24, 180, L.CLEAR,
    function() wipe(db.history); Refresh() end)
local show = Button(clear, "TOPRIGHT", 10, 0, 180, L.SHOW, Toggle)

local function ResetStats()
    db.total = 0
    db.stats = { all = NewBucket(), sessions = {}, archives = {} }
    StartSession()
    Refresh()
    if ns.steal.OnSteal then ns.steal.OnSteal() end
    Print(L.STATS_RESET)
end
StaticPopupDialogs.ROGUETIPS_RESET_STATS = {
    text = L.RESET_CONFIRM, button1 = YES, button2 = NO,
    OnAccept = ResetStats, timeout = 0, whileDead = true, hideOnEscape = true,
}
local journalBtn = Button(clear, "BOTTOMLEFT", 0, -8, 180, L.OPEN_JOURNAL,
    function() if ns.steal.ToggleJournal then ns.steal.ToggleJournal() end end)
Button(journalBtn, "TOPRIGHT", 10, 0, 180, L.RESET_STATS,
    function() StaticPopup_Show("ROGUETIPS_RESET_STATS") end)

ns.steal.RefreshOptions = function()
    if panel:IsVisible() then for _, f in ipairs(refreshers) do f() end end
end

-- Aperçu en direct : la fenêtre reste affichée tant que les options sont ouvertes.
local shownBeforePreview = false
panel:SetScript("OnShow", function()
    for _, f in ipairs(refreshers) do f() end
    shownBeforePreview = frame:IsShown()
    previewing = true
    autoOpened = false
    frame:Show()
end)
panel:SetScript("OnHide", function()
    previewing = false
    if not shownBeforePreview then frame:Hide() end
end)

-- Page de la fenêtre de réglages de RogueTips (Options.lua).
local function RegisterPanel()
    ns.Options.AddPage(panel, L.TITLE, "Interface\\Icons\\INV_Misc_Bag_11", 2)
end

local function OpenPanel() ns.Options.Toggle(panel) end

---------------------------------------------------------------------------
-- 5. Icône autour de la minimap
-- Clic gauche : fenêtre. Clic droit : options. Glisser : tourner autour.
---------------------------------------------------------------------------

local mm = CreateFrame("Button", "StealHistoryMinimapButton", Minimap)
mm:SetSize(31, 31)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
mmBg:SetSize(20, 20)
mmBg:SetPoint("TOPLEFT", 7, -5)

local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", 7, -6)
if SetPortraitToTexture then SetPortraitToTexture(mmIcon, ICON) else mmIcon:SetTexture(ICON) end

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT")

local function PlaceMinimapButton()
    local a = math.rad(cfg.minimap.angle)
    local r = Minimap:GetWidth() / 2 + 5
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

SetMinimapShown = function(shown)
    cfg.minimap.hide = not shown
    mm:SetShown(shown)
end

mm:SetScript("OnClick", function(_, button)
    if IsShiftKeyDown() then OpenPanel()
    elseif button == "RightButton" then
        if ns.steal.ToggleJournal then ns.steal.ToggleJournal() end
    else Toggle() end
end)
mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cfg.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
        PlaceMinimapButton()
    end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("StealHistory", 0.2, 1, 0.6)
    GameTooltip:AddLine(L.MM_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.MM_RIGHT, 1, 1, 1)
    GameTooltip:AddLine(L.MM_SHIFT, 1, 1, 1)
    GameTooltip:AddLine(L.MM_DRAG, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- 6. Profils partagés entre personnages
---------------------------------------------------------------------------

ApplyAll = function()
    ApplyLayout()
    ApplyVisibility()
    PlaceMinimapButton()
    mm:SetShown(not cfg.minimap.hide)
    if frame:IsShown() then Refresh() end
    if panel:IsVisible() then for _, f in ipairs(refreshers) do f() end end
end

ProfileNames = function()
    local list = {}
    for name in pairs(profiles) do list[#list + 1] = name end
    table.sort(list)
    return list
end

SetProfile = function(name)
    if not profiles[name] then profiles[name] = Copy(PROFILE_DEFAULTS) end
    cfg = Fill(profiles[name], PROFILE_DEFAULTS)
    db.profile = name
    ApplyAll()
    Print(L.PROFILE_ACTIVE:format(name))
end

DeleteProfile = function(name)
    local names = ProfileNames()
    if #names < 2 then return end
    profiles[name] = nil
    local nextName = names[1] == name and names[2] or names[1]
    SetProfile(nextName)
end

-- Pour StealJournal.lua.
ns.steal.DB = function() return db end
ns.steal.Coins, ns.steal.ItemLook, ns.steal.SortedItems = Coins, ItemLook, SortedItems
ns.steal.Duration, ns.steal.ItemEnter, ns.steal.ItemClick = Duration, ItemEnter, ItemClick
ns.steal.Backdrop, ns.steal.Refresh = BACKDROP_TEMPLATE, function() if frame:IsShown() then Refresh() end end

---------------------------------------------------------------------------
-- Événements et commande
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local didLoad = false
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
ev:RegisterEvent("LOOT_READY")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("LOOT_CLOSED")
ev:RegisterEvent("PLAYER_MONEY")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        ApplyVisibility()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        local isLogin = ...
        if isLogin or not db.stats.sessions[1] then StartSession() end
        return
    elseif event == "PLAYER_LOGOUT" then
        if db.stats.sessions[1] then db.stats.sessions[1].stop = time() end
        return
    end
    if event == "ADDON_LOADED" then
        if ... ~= ADDON or didLoad then return end
        didLoad = true
        StealHistoryDB = StealHistoryDB or {}
        db = StealHistoryDB
        db.history = db.history or {}
        RogueTipsDB = RogueTipsDB or {}
        RogueTipsDB.stealProfiles = RogueTipsDB.stealProfiles or {}
        profiles = RogueTipsDB.stealProfiles
        local name = db.profile or L.DEFAULT_PROFILE
        if not profiles[name] then
            -- 1re fois : les anciens réglages de ce personnage deviennent le profil.
            local p = {}
            for _, k in ipairs(PROFILE_KEYS) do if db[k] ~= nil then p[k] = db[k] end end
            profiles[name] = p
        end
        for _, k in ipairs(PROFILE_KEYS) do db[k] = nil end
        cfg = Fill(profiles[name], PROFILE_DEFAULTS)
        db.profile = name
        if cfg.visibility == "fade" then  -- ancien 3e mode -> case à part
            cfg.visibility, cfg.combatReduce = "always", true
        end
        if not db.total then  -- première fois : total des pièces déjà dans l'historique
            db.total = 0
            for _, e in ipairs(db.history) do db.total = db.total + (e.money or 0) end
        end
        db.stats = db.stats or { all = NewBucket(), sessions = {}, archives = {} }
        RegisterPanel()
        ApplyAll()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, target, _, spellID = ...
        if spellID == PICK_POCKET then
            castAt = GetTime()
            lastCast = castAt
            moneyBefore = GetMoney()
            castTarget = Readable(target) or Readable((UnitName("target")))
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local _, _, spellID = ...
        if spellID == PICK_POCKET then castAt = 0 end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "CHAT_MSG_LOOT" then
        if InWindow() then RecordLoot(...) end
    elseif event == "PLAYER_MONEY" then
        if InWindow() then
            local gained = GetMoney() - moneyBefore
            moneyBefore = GetMoney()
            if gained > 0 then
                Add({ money = gained })
            end
        end
    elseif event == "LOOT_CLOSED" then
        if stealing then
            stealing = false
            windowEnd = GetTime() + 2  -- les messages du chat arrivent parfois après
        end
    end
end)

SLASH_STEALHISTORY1 = "/stealhistory"
SLASH_STEALHISTORY2 = "/sh"
SlashCmdList.STEALHISTORY = function(msg)
    msg = (msg or ""):lower()
    if msg == "options" or msg == "config" then
        OpenPanel()
    elseif msg == "clear" then
        wipe(db.history); Refresh()
        Print(L.CLEARED)
    elseif msg == "journal" or msg == "stats" then
        if ns.steal.ToggleJournal then ns.steal.ToggleJournal() end
    elseif msg == "debug" then
        debug = not debug
        Print("debug " .. (debug and "on" or "off"))
    elseif msg == "minimap" then
        SetMinimapShown(cfg.minimap.hide)
    elseif msg == "reset" then
        cfg.pos = nil
        Place()
    else
        Toggle()
    end
end

-- Les SavedVariables sont chargées : Init.lua rejoue ADDON_LOADED pour ce module.
ns.onLoad[#ns.onLoad + 1] = function() ev:GetScript("OnEvent")(ev, "ADDON_LOADED", ADDON) end
end
