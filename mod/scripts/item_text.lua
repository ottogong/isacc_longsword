local Locale = include("scripts.locale")
local ItemText = {}

-- The English names match the registrations in content/items.xml in every language.
local items = {
    sword = { en = "Hellish Slasher", zh = "天上天下天地无双刀", "挥出气刃斩，纳刀后可用居合反击" },
    material = { en = "Hunting Material", zh = "狩猎素材", "素材 +1" },
    materialBundle = { en = "Hunting Materials Bundle", zh = "狩猎素材包", "素材 +2" },
    braces = { en = "Quick Sheathe Braces", zh = "快纳护腕", "特殊纳刀起手缩短 15%", "特殊纳刀起手缩短 25%" },
    boots = { en = "Leaping Greaves", zh = "居合护腿", "大居合和登龙每段的会心率提高 15 个百分点", "大居合和登龙每段的会心率提高 30 个百分点" },
    kit = { en = "First Aid Pouch", zh = "急救腰包", "每层首次进入首领房时回复半颗红心", "每层首次进入首领房时回复一颗红心" },
    tooth = { en = "Fang Charm", zh = "大牙挂饰", "大居合成功时散射三颗血泪" },
    flySuit = { en = "Fly Sac Palico Suit", zh = "虫囊小猫套", "太刀命中有 20% 概率让艾露猫放出一只蓝苍蝇" },
    spur = { en = "Knight's Spur", zh = "骑士马刺", "纳刀闪身时，艾露猫会追扑附近的敌人" },
    spurPlus = { en = "Knight's Spur+", zh = "骑士马刺+", "纳刀闪身时，艾露猫的追扑比普通扑击多 1 点伤害" },
}
ItemText.chineseSwordName = items.sword.zh

local function suffix(rank)
    return rank == 2 and "+" or ""
end

function ItemText.englishName(key, rank)
    return items[key].en .. suffix(rank)
end

function ItemText.name(key, rank)
    local entry = items[key]
    return Locale.text(entry.en, entry.zh) .. suffix(rank)
end

local pickupText = {}
for key, entry in pairs(items) do
    for rank, description in ipairs(entry) do
        pickupText[ItemText.englishName(key, rank)] = { name = entry.zh .. suffix(rank), description = description }
    end
end

local jewelNames = {
    attack = { "ATT", "攻击珠", "攻击" }, expert = { "Expert", "达人珠", "达人" },
    critical = { "Crit Boost", "超会心珠", "超会心" }, reach = { "Reach", "延刃珠", "攻击范围" },
    speed = { "Attack Speed", "攻速珠", "攻速" },
}
function ItemText.jewelEnglishName(key, rank)
    return jewelNames[key][1] .. " Lv." .. rank
end
for key, names in pairs(jewelNames) do
    for rank = 1, 4 do
        local description = key == "critical" and rank >= 3 and "超会心满级，会心伤害 ×1.40"
            or names[3] .. "技能 +" .. rank .. " 级"
        pickupText[ItemText.jewelEnglishName(key, rank)] = {
            name = names[2] .. " Lv." .. rank, description = description,
        }
    end
end

-- The queue stays populated throughout the pickup animation. Translate its native
-- banner once, after the engine has processed the pickup, without modifying the queue.
function ItemText.localizePickup(player, hud)
    local queue = player.QueuedItem
    local item = queue.Item
    local text = item and pickupText[item.Name]
    local data = player:GetData()
    local previous = data.longswordPickupBanner
    data.longswordPickupBanner = text and item.ID
    local caption = data.longswordPickupCaption
    if caption and (player.FrameCount >= caption.expires or not Locale.isChinese()
        or Options.Language == "zh" or (item and text ~= caption.text)) then
        data.longswordPickupCaption = nil
    end
    if text and item.ID ~= previous and not queue.Touched and Locale.isChinese()
        and item:IsCollectible() and item.ID == Isaac.GetItemIdByName(item.Name) then
        if Options.Language == "zh" then
            hud:ShowItemText(text.name, text.description, false, true)
        else
            -- The game's non-Chinese banner font may lack CJK glyphs.
            data.longswordPickupCaption = { text = text, expires = player.FrameCount + 75 }
        end
    end
end

local font, ink, gold, shadow
local function loadFont()
    if font then return end
    font = Font()
    font:Load("font/cjk/lanapixel.fnt")
    ink, gold, shadow = KColor(1, 0.96, 0.87, 1), KColor(1, 0.84, 0.45, 1), KColor(0.12, 0.07, 0.06, 1)
end

local function draw(text, x, y, color)
    x, y = math.floor(x), math.floor(y)
    font:DrawStringUTF8(text, x + 1, y + 1, shadow)
    font:DrawStringUTF8(text, x, y, color)
end

local function captionLines(caption, width)
    local lines = { caption.text.name }
    local description = caption.text.description
    if font:GetStringWidthUTF8(description) <= width then
        lines[2] = description
    else
        local line = ""
        for glyph in description:gmatch(utf8.charpattern) do
            if line ~= "" and font:GetStringWidthUTF8(line .. glyph) > width then
                lines[#lines + 1], line = line, ""
            end
            line = line .. glyph
        end
        lines[#lines + 1] = line
    end
    return lines
end

function ItemText.renderPickup(player)
    local caption = player:GetData().longswordPickupCaption
    if not caption or not Locale.isChinese() or Options.Language == "zh" then return end
    loadFont()
    local width = Isaac.GetScreenWidth()
    if caption.width ~= width then
        caption.lines, caption.width = captionLines(caption, width - 24), width
    end
    -- The camp details begin 53 pixels from the bottom. Keep even a wrapped caption above them.
    local y = Isaac.GetScreenHeight() - 77 - (#caption.lines - 1) * 13
    for index, line in ipairs(caption.lines) do
        draw(line, (width - font:GetStringWidthUTF8(line)) / 2, y, index == 1 and gold or ink)
        y = y + 13
    end
end

-- Called for the front pocket sword only. The native name stays on the line below.
function ItemText.renderPocketName(position)
    loadFont()
    local name = ItemText.chineseSwordName
    local width = font:GetStringWidthUTF8(name)
    local x = math.max(2, math.min(position.X - 40 - width, Isaac.GetScreenWidth() - width - 2))
    local y = math.max(2, math.min(position.Y - 22, Isaac.GetScreenHeight() - 15))
    draw(name, x, y, ink)
end

return ItemText
