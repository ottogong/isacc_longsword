local Locale = {}
local Slot = include("scripts.slot_data")

-- Native include re-executes modules. Keep the preference shared by every text renderer.
function Locale.mode()
    return IsaccLongswordLanguageMode or "auto"
end

function Locale.load(mod)
    local saved = Slot.read(mod).longswordLanguage
    IsaccLongswordLanguageMode = (saved == "en" or saved == "zh") and saved or "auto"
end

function Locale.isChinese()
    local mode = Locale.mode()
    return mode == "zh" or (mode == "auto" and Options.Language == "zh")
end

function Locale.text(english, chinese)
    return Locale.isChinese() and chinese or english
end

function Locale.set(mod, mode)
    if mode ~= "auto" and mode ~= "en" and mode ~= "zh" then return nil end
    local fields = Slot.read(mod)
    fields.longswordLanguage = mode ~= "auto" and mode or nil
    Slot.write(mod, fields)
    IsaccLongswordLanguageMode = mode
    return mode
end

function Locale.toggle(mod)
    local wantChinese = not Locale.isChinese()
    if wantChinese == (Options.Language == "zh") then return Locale.set(mod, "auto") end
    return Locale.set(mod, wantChinese and "zh" or "en")
end

return Locale
