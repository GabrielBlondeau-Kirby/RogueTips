-- Démarrage de RogueTips : les modules attendent les SavedVariables pour
-- connaître la langue choisie (/roguetips → Général → Langue), puis se construisent.

local ADDON, ns = ...

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    RogueTipsDB = RogueTipsDB or {}
    local lang = RogueTipsDB.lang or "auto"
    ns.lang = (lang == "auto") and GetLocale() or lang
    ns.SetLocale(ns.lang)
    for _, build in ipairs(ns.modules or {}) do build() end
    for _, loaded in ipairs(ns.onLoad or {}) do loaded() end
end)
