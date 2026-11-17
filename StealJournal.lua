-- Journal du voleur (module de RogueTips) : grande fenêtre de statistiques de vol.
--  En haut : chiffres clés de tous les temps.
--  À gauche : « Toutes les sessions », les sessions, puis les archives mensuelles.
--  À droite : détail de la ligne choisie (or par session, meilleures cibles, butin).
-- Données et fonctions partagées : ns.steal (StealHistory.lua).

local ADDON, ns = ...
local S = ns.steal
if not S then return end  -- pas voleur : StealHistory.lua ne s'est pas chargé
local L = ns.L

local W, H = 680, 470
local LIST_W, ENTRY_H = 214, 38
local BARS, TOP_N = 24, 7
local ARCHIVE_ICON = "Interface\\Icons\\INV_Box_01"

local frame = CreateFrame("Frame", "RogueTipsStealJournal", UIParent, S.Backdrop)
frame:SetSize(W, H)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()
tinsert(UISpecialFrames, "RogueTipsStealJournal")

-- Bandeau du titre en trois morceaux, comme la petite fenêtre.
local HEADER_TEX = "Interface\\DialogFrame\\UI-DialogBox-Header"
local headerFrame = CreateFrame("Frame", nil, frame)
headerFrame:SetAllPoints()
headerFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
local header = headerFrame:CreateTexture(nil, "ARTWORK")
header:SetTexture(HEADER_TEX)
header:SetTexCoord(0.31, 0.67, 0, 0.63)
header:SetSize(100, 40)
header:SetPoint("TOP", 0, 12)
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
title:SetText(L.JOURNAL)
header:SetWidth(math.max(60, title:GetStringWidth() + 16))

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local function Panel(parent)
    local p = CreateFrame("Frame", nil, parent, S.Backdrop)
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        p:SetBackdropColor(0, 0, 0, 0.5)
        p:SetBackdropBorderColor(0.55, 0.45, 0.25)
    end
    return p
end

-- Chiffres clés -----------------------------------------------------------

local KPI_W = (W - 44 - 18) / 4
local kpis = {}
for i, label in ipairs({ L.K_TOTAL, L.K_STEALS, L.K_ITEMS, L.AVG }) do
    local k = Panel(frame)
    k:SetSize(KPI_W, 44)
    k:SetPoint("TOPLEFT", 22 + (i - 1) * (KPI_W + 6), -32)
    local l = k:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 8, -7)
    l:SetText(label)
    k.value = k:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    k.value:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -4)
    kpis[i] = k
end

-- Liste des sessions --------------------------------------------------------

local listBg = Panel(frame)
listBg:SetPoint("TOPLEFT", 22, -84)
listBg:SetPoint("BOTTOMLEFT", 22, 20)
listBg:SetWidth(LIST_W + 26)

local scroll = CreateFrame("ScrollFrame", nil, listBg, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 5, -5)
scroll:SetPoint("BOTTOMRIGHT", -27, 5)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(LIST_W, 10)
scroll:SetScrollChild(content)

local entries, buttons = {}, {}
local selected = 1   -- index dans entries
local Refresh

local function Label(e)
    if e.kind == "all" then return "|cffffd100" .. L.ALL_SESSIONS .. "|r" end
    local b = e.b
    if e.kind == "archive" then
        local y, m = b.key:match("(%d+)-(%d+)")
        return (L.MONTHS[tonumber(m)] or m) .. " " .. y
    end
    local day, today = date("%Y%m%d", b.start), date("%Y%m%d")
    local yesterday = date("%Y%m%d", time() - 86400)
    if day == today then return L.TODAY .. " " .. date("%H:%M", b.start)
    elseif day == yesterday then return L.YESTERDAY .. " " .. date("%H:%M", b.start) end
    return date("%d/%m %H:%M", b.start)
end

local function DurationText(b)
    local secs = S.Duration(b)
    if secs < 3600 then return L.MINUTES:format(math.floor(secs / 60)) end
    return L.HOURS:format(math.floor(secs / 3600), math.floor(secs / 60) % 60)
end

local function MainZone(b)
    local best, n = nil, 0
    for zone, c in pairs(b.zones) do if c > n then best, n = zone, c end end
    return best or ""
end

local function EntryButton(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", nil, content)
    b:SetSize(LIST_W, ENTRY_H - 2)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * ENTRY_H)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.15)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("TOPLEFT", 4, -3)
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.label:SetJustifyH("LEFT")
    b.money = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.money:SetPoint("TOPRIGHT", -4, -4)
    b.info = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.info:SetPoint("BOTTOMLEFT", 6, 4)
    b.zone = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    b.zone:SetPoint("BOTTOMRIGHT", -4, 4)
    b.zone:SetWidth(90)
    b.zone:SetJustifyH("RIGHT")
    b.zone:SetWordWrap(false)
    b:SetScript("OnClick", function(self) selected = self.index; Refresh() end)
    buttons[i] = b
    return b
end

-- Détail ---------------------------------------------------------------------

local DX = 22 + LIST_W + 26 + 12
local DW = W - DX - 22

local dTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", DX, -88)
local dSummary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
dSummary:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)
dSummary:SetWidth(DW)
dSummary:SetJustifyH("LEFT")

local chartLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
chartLabel:SetPoint("TOPLEFT", DX, -134)

local chart = Panel(frame)
chart:SetPoint("TOPLEFT", DX, -148)
chart:SetSize(DW, 84)
local bars = {}
local BAR_W = (DW - 12) / BARS
for i = 1, BARS do
    local b = CreateFrame("Button", nil, chart)
    b:SetWidth(BAR_W - 2)
    b:SetPoint("BOTTOMLEFT", 6 + (i - 1) * BAR_W, 6)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b:SetScript("OnClick", function(self) selected = self.index; Refresh() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Label(entries[self.index]))
        GameTooltip:AddLine(S.Coins(entries[self.index].b.money), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    bars[i] = b
end
local chartEmpty = chart:CreateFontString(nil, "ARTWORK", "GameFontDisable")
chartEmpty:SetPoint("CENTER")
chartEmpty:SetText(L.NO_SESSIONS)

local COL_W = (DW - 12) / 2
local function Column(x, label)
    local t = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", DX + x, -246)
    t:SetText(label)
    local rows = {}
    for i = 1, TOP_N do
        local r = CreateFrame("Button", nil, frame)
        r:SetSize(COL_W, 20)
        r:SetPoint("TOPLEFT", DX + x, -262 - (i - 1) * 22)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.value = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.value:SetPoint("RIGHT")
        r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
        rows[i] = r
    end
    local none = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    none:SetPoint("TOPLEFT", DX + x, -264)
    rows.none = none
    return rows
end
local targetRows = Column(0, L.TARGETS)
local lootRows = Column(COL_W + 12, L.LOOT)
for i = 1, TOP_N do
    local r = lootRows[i]
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r:SetScript("OnEnter", S.ItemEnter)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", S.ItemClick)
end

local function FillTargets(b)
    local list = {}
    for name, t in pairs(b.targets) do list[#list + 1] = { name = name, m = t.m, n = t.n } end
    table.sort(list, function(x, y) if x.m ~= y.m then return x.m > y.m end return x.n > y.n end)
    for i = 1, TOP_N do
        local r, t = targetRows[i], list[i]
        if t then
            r.icon:Hide()
            r.name:SetPoint("LEFT", 0, 0)
            r.name:SetText(t.name .. " |cff888888×" .. t.n .. "|r")
            r.value:SetText(t.m > 0 and S.Coins(t.m) or "")
            r:Show()
        else
            r:Hide()
        end
    end
    targetRows.none:SetText(#list == 0 and L.NONE or "")
end

local function FillLoot(b)
    local list = S.SortedItems(b)
    for i = 1, TOP_N do
        local r, it = lootRows[i], list[i]
        if it then
            local name, icon = S.ItemLook(it.link)
            r.link = it.link
            r.icon:SetTexture(icon)
            r.icon:Show()
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
            r.name:SetText(name)
            r.value:SetText("×" .. it.n)
            r:Show()
        else
            r:Hide()
        end
    end
    lootRows.none:SetText(#list == 0 and L.NONE or (#list > TOP_N and L.MORE:format(#list - TOP_N) or ""))
    lootRows.none:ClearAllPoints()
    lootRows.none:SetPoint("TOPLEFT", DX + COL_W + 12, #list == 0 and -264 or -264 - math.min(#list, TOP_N) * 22)
end

-- Rafraîchissement --------------------------------------------------------------

Refresh = function()
    local db = S.DB()
    local st = db.stats
    wipe(entries)
    entries[1] = { kind = "all", b = st.all }
    for _, b in ipairs(st.sessions) do
        if b.steals > 0 then entries[#entries + 1] = { kind = "session", b = b } end
    end
    local firstArchive = #entries + 1
    for _, b in ipairs(st.archives) do entries[#entries + 1] = { kind = "archive", b = b } end
    if selected > #entries then selected = 1 end

    -- chiffres clés
    local all = st.all
    kpis[1].value:SetText(S.Coins(db.total or 0))
    kpis[2].value:SetText(all.steals)
    kpis[3].value:SetText(all.nitems)
    kpis[4].value:SetText(all.steals > 0 and S.Coins(math.floor(all.money / all.steals)) or "-")

    -- liste
    for i, e in ipairs(entries) do
        local btn = EntryButton(i)
        btn.index = i
        btn.sel:SetShown(i == selected)
        btn.label:ClearAllPoints()
        if e.kind == "archive" then
            btn.icon:SetTexture(ARCHIVE_ICON)
            btn.icon:Show()
            btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
        else
            btn.icon:Hide()
            btn.label:SetPoint("TOPLEFT", 6, -4)
        end
        btn.label:SetText(Label(e))
        btn.money:SetText(S.Coins(e.b.money))
        if e.kind == "all" then
            btn.info:SetText(L.N_SESSIONS:format(#entries - 1))
            btn.zone:SetText("")
        else
            btn.info:SetText(DurationText(e.b) .. " · " .. L.N_STEALS:format(e.b.steals))
            btn.zone:SetText(MainZone(e.b))
        end
        btn:Show()
    end
    for i = #entries + 1, #buttons do buttons[i]:Hide() end
    content:SetHeight(#entries * ENTRY_H)

    -- détail
    local e = entries[selected]
    local b = e.b
    dTitle:SetText(Label(e))
    local parts = { S.Coins(b.money), L.N_STEALS:format(b.steals), L.N_ITEMS:format(b.nitems) }
    if e.kind ~= "all" then parts[#parts + 1] = DurationText(b) end
    if b.steals > 0 then parts[#parts + 1] = L.AVG_SHORT:format(S.Coins(math.floor(b.money / b.steals))) end
    if b.best > 0 then parts[#parts + 1] = L.BEST_SHORT:format(S.Coins(b.best)) end
    dSummary:SetText(table.concat(parts, "  ·  "))

    -- graphique : sessions récentes, la plus ancienne à gauche
    local first = 2
    local last = math.min(firstArchive - 1, first + BARS - 1)
    local n = math.max(0, last - first + 1)
    chartLabel:SetText(L.CHART:format(n))
    local max = 1
    for i = first, last do max = math.max(max, entries[i].b.money) end
    for i = 1, BARS do
        local bar = bars[i]
        local idx = first + (n - i)   -- barre 1 = plus ancienne affichée
        if i <= n then
            bar.index = idx
            bar:SetHeight(math.max(2, entries[idx].b.money / max * 70))
            if idx == selected then bar.tex:SetColorTexture(1, 0.82, 0, 1)
            else bar.tex:SetColorTexture(0.55, 0.43, 0.23, 1) end
            bar:Show()
        else
            bar:Hide()
        end
    end
    chartEmpty:SetShown(n == 0)

    FillTargets(b)
    FillLoot(b)
end

frame:SetScript("OnShow", Refresh)

S.ToggleJournal = function() frame:SetShown(not frame:IsShown()) end
S.OnSteal = function()
    S.Refresh()
    if frame:IsShown() then Refresh() end
end
