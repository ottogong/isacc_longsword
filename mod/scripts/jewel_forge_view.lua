local Jewels = include("scripts.hunt_jewels")
local Damage = include("scripts.damage")
local Hunt = include("scripts.hunt")
local ItemText = include("scripts.item_text")
local Locale = include("scripts.locale")
local Button = include("scripts.workshop_button")
local Forge = { station = { key = "forge", rows = Jewels.keys } }

-- The two copy columns stay visible on both pages, even at 320x180.
local function layout()
    local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local w, h = math.min(438, sw - 28), math.min(206, sh - 10)
    local x, y = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    local list = x + math.floor(w * 0.25) + 8
    local right = x + w
    local cell = math.min(54, math.floor((right - list) * 0.205))
    return { left = x, right = right, top = y, bottom = y + h, width = w, height = h,
        list = list, rightPane = right - list, cell = cell, copies = right - 2 * cell,
        tabY = y + 20, tabWidth = math.floor((right - list) / 2),
        first = y + 50, row = math.min(20, math.floor((h - 106) / #Jewels.keys)) }
end

local function pointer(box, pos)
    if not pos or pos.X < box.left or pos.X > box.right or pos.Y < box.top or pos.Y > box.bottom then return end
    if pos.Y < box.top + 17 and pos.X >= box.right - 20 then return "back" end
    if Button.hit(box, pos) then return "confirm" end
    if pos.X < box.list then return end
    if pos.Y >= box.tabY and pos.Y < box.tabY + 15 then
        return pos.X < box.list + box.tabWidth and "craft" or "upgrade"
    end
    local row = 1 + math.floor((pos.Y - box.first) / box.row)
    if row >= 1 and row <= #Jewels.keys then
        local copy
        if pos.X >= box.copies then copy = pos.X < box.copies + box.cell and 1 or 2 end
        return row, copy
    end
end

function Forge.action(ui, run, buy, action, pos, text)
    local row, page, copy = ui.selection, ui.page, ui.copy
    if action == "click" then
        local target, column = pointer(layout(), pos)
        if type(target) == "number" then
            row = target
            ui.orderSelected = true
            if page == "upgrade" and column then copy = column end
        elseif target == "craft" or target == "upgrade" then
            if page ~= target then copy, ui.orderSelected = 1, false end
            page = target
        else
            if target == "confirm" and not ui.orderSelected then return end
            action = target
        end
    elseif action == "up" or action == "down" then
        row = (row - 1 + (action == "up" and -1 or 1)) % #Jewels.keys + 1
        ui.orderSelected = true
    elseif action == "left" or action == "right" then
        -- The three horizontal stops are Forge, Upgrade/first, Upgrade/second.
        local stop = (page == "craft" and 0 or copy) + (action == "right" and 1 or -1)
        stop = stop % 3
        page, copy = stop == 0 and "craft" or "upgrade", math.max(stop, 1)
        ui.orderSelected = true
    end
    if action == "back" then return "close" end
    if row ~= ui.selection or page ~= ui.page or copy ~= ui.copy then
        ui.selection, ui.page, ui.copy, ui.noticeTicks = row, page, copy, 0
    end
    if action ~= "confirm" then return end
    local key = Jewels.keys[row]
    local target = page == "upgrade" and copy or nil
    local price, index = Jewels.price(run, key, page, target)
    if not price or run.materials < price then return end
    local ok, reason = buy(key, page, target)
    if not ok then return "notice", reason == "space" and text.noSpace or nil end
    local t = text.forge
    local rank = Jewels.copyLevel(run, key, index)
    local name = Locale.isChinese() and ("%s Lv.%d"):format(t[key], rank) or ItemText.jewelEnglishName(key, rank)
    return "forged", t.receipt:format(name, index)
end

local statue, atlas, palette
function Forge.statue(x, y, scale)
    if not statue then
        statue = Sprite()
        statue:Load("gfx/1000.009_angelstatue.anm2", true)
        statue:SetFrame("Idle", 0)
    end
    statue.Scale = Vector(scale, scale)
    statue:RenderLayer(0, Vector(math.floor(x), math.floor(y)))
end

local function renderAtlas(frame, x, y, sx, sy, color)
    atlas:SetFrame(frame, 0)
    atlas.Scale, atlas.Color = Vector(sx, sy), color
    atlas:RenderLayer(0, Vector(math.floor(x), math.floor(y)))
end

local fill = Button.fill

local function loadArt()
    if atlas then return end
    atlas = Sprite()
    atlas:Load("gfx/isacc_longsword/guild_jewels.anm2", true)
    palette = {
        white = Color(1, 1, 1, 1), bronze = Color(0.73, 0.53, 0.29, 0.82),
        surface = Color(0.16, 0.15, 0.14, 0.98), portrait = Color(0.18, 0.22, 0.21, 1),
        tab = Color(0.40, 0.30, 0.17, 1), recess = Color(0.25, 0.23, 0.20, 1),
        band = Color(0.45, 0.33, 0.18, 0.68), highlight = Color(0.63, 0.43, 0.22, 0.8),
        ink = KColor(0.96, 0.92, 0.83, 1), muted = KColor(0.80, 0.76, 0.67, 1),
        accent = KColor(1, 0.80, 0.46, 1), ivory = KColor(1, 0.93, 0.75, 1),
    }
end

local function effect(t, key, current, nextLevel, player, run)
    local function preview(a, b)
        if a == b then return a end
        return t.transition:format(a, b)
    end
    if key == "attack" then
        -- The starting flat bonus is preserved when the last two ranks add a multiplier.
        local function bonus(level)
            local flat, multiplier = Jewels.attackFlat(level), Jewels.attackMultiplier(level)
            return multiplier == 1 and ("+%d"):format(flat) or ("+%d x%.2f"):format(flat, multiplier)
        end
        return t.power:format(preview(bonus(current), bonus(nextLevel)))
    elseif key == "reach" then
        return t.reachEffect:format(preview(("+%g"):format(Jewels.rangeBonus(current)),
            ("+%g"):format(Jewels.rangeBonus(nextLevel))))
    elseif key == "speed" then
        return t.speedEffect:format(preview(("+%g"):format(Jewels.tearsBonus(current)),
            ("+%g"):format(Jewels.tearsBonus(nextLevel))))
    elseif key == "critical" then
        return t.critEffect:format(preview(("x%.2f"):format(Jewels.critMultiplier(current)),
            ("x%.2f"):format(Jewels.critMultiplier(nextLevel))))
    end
    local function chance(level, moveBonus)
        return ("%.1f"):format(100 * Damage.critChance(player.Luck, Jewels.affinity(level), moveBonus)):gsub("%.0$", "") .. "%"
    end
    local boots = Hunt.greavesCritBonus(run.gear.boots)
    return t.affinity:format(preview(chance(current, 0), chance(nextLevel, 0)),
        preview(chance(current, boots), chance(nextLevel, boots)))
end

function Forge.render(ui, run, player, text, line, drawPaper)
    local b, t = layout(), text.forge
    loadArt()
    local p = palette
    drawPaper(b)
    fill(b.left - 3, b.top - 2, b.width + 6, b.height + 4, p.surface)
    local leftWidth = b.list - b.left - 7
    line(text.station.forge, b.left, b.top, p.ink, b.width * 0.55)
    line(text.materials:format(run.materials), b.right - 101, b.top, p.accent, 76)
    line("[X]", b.right - 18, b.top, p.ink, 18)
    fill(b.left, b.top + 16, b.width, 1, p.bronze)

    local displayTop, displayBottom = b.tabY, b.bottom - 20
    fill(b.left, displayTop, leftWidth, displayBottom - displayTop, p.portrait)
    local middle = b.left + leftWidth / 2
    local scale = math.min(1.42, (leftWidth - 10) / 72)
    Forge.statue(middle, displayTop + (displayBottom - displayTop - 14) / 2 + 28 * scale, scale)
    local owned = 0
    for _, key in ipairs(Jewels.keys) do
        for index = 1, Jewels.maxCopies do
            if Jewels.isHeld(run, key, index) then owned = owned + 1 end
        end
    end
    line(t.inventory:format(owned, #Jewels.keys * Jewels.maxCopies),
        b.left + 5, displayBottom - 14, p.ivory, leftWidth - 10)

    for index, mode in ipairs({ "craft", "upgrade" }) do
        local x = b.list + (index - 1) * b.tabWidth
        local active = mode == ui.page
        fill(x, b.tabY, b.tabWidth - 2, 14, active and p.tab or p.recess)
        if active then fill(x, b.tabY + 13, b.tabWidth - 2, 1, p.bronze) end
        line(t[mode], x + 5, b.tabY + 1, active and p.ivory or p.ink, b.tabWidth - 10)
    end
    line(t.jewel, b.list + 2, b.first - 13, p.muted, b.copies - b.list - 4)
    line(t.first, b.copies + 3, b.first - 13, p.muted, b.cell - 5)
    line(t.second, b.copies + b.cell + 3, b.first - 13, p.muted, b.cell - 5)
    for row, key in ipairs(Jewels.keys) do
        local y = b.first + (row - 1) * b.row
        local selected = row == ui.selection
        if selected then
            fill(b.list, y, b.rightPane, b.row - 1, p.band)
            fill(b.list, y, 2, b.row - 1, p.bronze)
        end
        local textY = y + math.floor((b.row - 12) / 2)
        local iconScale = math.min(1, b.row / 16)
        renderAtlas(key, b.list + 11, y + b.row / 2 - 1, iconScale, iconScale, p.white)
        line(t[key], b.list + 21, textY, selected and p.accent or p.ink, b.copies - b.list - 22)
        for index = 1, Jewels.maxCopies do
            local level = Jewels.copyLevel(run, key, index)
            local x = b.copies + (index - 1) * b.cell
            local active = selected and ui.page == "upgrade" and index == ui.copy
            if active then fill(x, y, b.cell - 1, b.row - 1, p.highlight) end
            local label = t.empty
            if Jewels.isPending(run, key, index) then label = t.pending:format(level)
            elseif level > 0 then label = ("Lv.%d"):format(level) end
            line(label, x + 3, textY, level > 0 and p.ink or p.muted, b.cell - 5)
        end
    end

    local key, mode = Jewels.keys[ui.selection], ui.page
    local price, index = Jewels.price(run, key, mode, mode == "upgrade" and ui.copy or nil)
    local current, cap = Jewels.level(run, key), Jewels.maxLevel[key]
    local after = price and math.min(cap, current + 1) or current
    local y = b.first + #Jewels.keys * b.row + 1
    fill(b.list, y, b.rightPane, 1, p.bronze)
    local progress = t.skill:format(current, cap)
    if price then
        local level = Jewels.copyLevel(run, key, index)
        progress = t.afterPickup:format(index == 1 and t.first or t.second, level, level + 1, current, after, cap)
    end
    line(progress, b.list + 2, y + 2, p.ink, b.rightPane - 4)
    line(effect(t, key, current, after, player, run), b.list + 2, y + 14, p.ink, b.rightPane - 4)
    local status
    if ui.noticeTicks > 0 and ui.noticeLanguage == text then status = ui.notice
    elseif not price then
        if mode == "craft" then status = t.full
        elseif Jewels.isPending(run, key, ui.copy) then status = t.pickup
        elseif not Jewels.isHeld(run, key, ui.copy) then status = t.missing
        else status = t.maxCopy end
    elseif run.materials < price then status = t.shortage
    elseif current == cap then status = t.capped end
    if status then line(status, b.list + 2, y + 26, p.accent, b.rightPane - 4) end

    line(t.controls, b.left, b.bottom - 14, p.muted, b.width - 100)
    if price then
        Button.draw(b, t.price:format(t[mode], price), ui.orderSelected and run.materials >= price, line)
    end
end

return Forge
