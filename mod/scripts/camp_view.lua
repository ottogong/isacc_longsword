local Button = include("scripts.workshop_button")
local Damage = include("scripts.damage")
local Hunt = include("scripts.hunt")
local Jewels = include("scripts.hunt_jewels")
local ItemText = include("scripts.item_text")
local Locale = include("scripts.locale")
local Camp = {}

local groups = { board = "hunt", braces = "gear", pill = "supplies", language = "options" }
local colors

function Camp.layout(ui)
    local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local w, h = math.min(438, sw - 28), math.min(238, sh - 14)
    local left, top = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    local count = #ui.station.rows
    local visible = math.min(count, math.max(1, math.floor((h - 77) / 12)))
    local row = math.min(18, math.floor((h - 77) / visible))
    local first = top + 20
    local start = math.max(1, math.min(ui.campFirst or 1, count - visible + 1, ui.selection))
    start = math.max(start, ui.selection - visible + 1)
    return { left = left, right = left + w, top = top, bottom = top + h, width = w, height = h,
        list = left + math.floor(w * 0.27) + 6, listRight = left + w - (visible < count and 16 or 0),
        row = row, first = first, detail = first + visible * row + 4, visible = visible, start = start, count = count }
end

function Camp.pointer(box, pos)
    if not pos or pos.X < box.left or pos.X >= box.right or pos.Y < box.top or pos.Y >= box.bottom then return end
    if pos.Y < box.top + 15 and pos.X >= box.right - 20 then return "back" end
    if Button.hit(box, pos) then return "confirm" end
    if pos.X < box.list then return end
    local row = math.floor((pos.Y - box.first) / box.row) + 1
    if row < 1 or row > box.visible then return end
    if pos.X >= box.listRight then
        if row == 1 and box.start > 1 then return "scrollUp" end
        if row == box.visible and box.start + box.visible <= box.count then return "scrollDown" end
        return
    end
    return box.start + row - 1
end

local function drawStatus(box, player, run, line)
    local x, y = box.left + 5, box.first
    local width = box.list - x - 8
    local statsY = box.detail - 39
    Button.fill(box.left, y, box.list - box.left - 6, box.detail - y - 3, colors.panel)
    line(Locale.text("Little Hunter", "小猎人"), x, y + 2, colors.accent, width)
    local origin = Vector(math.floor(x + width / 2), math.floor((y + 20 + statsY) / 2 + 12))
    player:RenderGlow(origin)
    player:RenderBody(origin)
    player:RenderHead(origin)
    player:RenderTop(origin)

    local redHealth = ("%g/%g"):format(player:GetHearts() / 2, player:GetEffectiveMaxHearts() / 2)
    local affinity = Damage.critChance(player.Luck, Jewels.affinity(Jewels.level(run, "expert")))
    local chance = ("%.1f"):format(100 * affinity):gsub("%.0$", "")
    line(Locale.text("Red HP ", "红心 ") .. redHealth, x, statsY, colors.ink, width)
    line(Locale.text("Attack ", "攻击 ") .. ("%.2f"):format(player.Damage), x, statsY + 12, colors.ink, width)
    line(Locale.text("Affinity ", "会心 ") .. chance .. "%", x, statsY + 24, colors.ink, width)
end

function Camp.render(ui, run, player, text, line, drawPaper, nameFor, orderState, getFont)
    if not colors then
        colors = { surface = Color(0.16, 0.15, 0.14, 0.98), panel = Color(0.17, 0.23, 0.20, 1),
            rule = Color(0.59, 0.48, 0.30, 1), band = Color(0.29, 0.35, 0.27, 1),
            accent = KColor(1, 0.84, 0.54, 1), ink = KColor(0.97, 0.94, 0.86, 1),
            muted = KColor(0.77, 0.75, 0.67, 1) }
    end
    local b = Camp.layout(ui)
    drawPaper(b)
    Button.fill(b.left - 3, b.top - 2, b.width + 6, b.height + 4, colors.surface)
    line(text.station.camp, b.left, b.top, colors.ink, b.width * 0.55)
    line(text.materials:format(run.materials), b.right - 101, b.top, colors.accent, 76)
    line("[X]", b.right - 18, b.top, colors.ink, 18)
    Button.fill(b.left, b.top + 16, b.width, 1, colors.rule)
    drawStatus(b, player, run, line)

    local languageFont = getFont("font/cjk/lanapixel.fnt")
    local rightWidth = b.listRight - b.list
    local nameX = b.list + math.floor(rightWidth * 0.20)
    local priceX = b.listRight - math.min(66, math.floor(rightWidth * 0.26))
    if b.visible < b.count then
        Button.fill(b.listRight + 1, b.first, 15, b.visible * b.row, colors.panel)
        line("^", b.listRight + 5, b.first, b.start > 1 and colors.accent or colors.muted, 10)
        local bottom = b.first + (b.visible - 1) * b.row
        line("v", b.listRight + 5, bottom, b.start + b.visible <= b.count and colors.accent or colors.muted, 10)
        local track = (b.visible - 2) * b.row
        local thumb = math.floor(track * b.visible / b.count)
        local offset = math.floor((track - thumb) * (b.start - 1) / (b.count - b.visible))
        Button.fill(b.listRight + 7, b.first + b.row + offset, 2, thumb, colors.rule)
    end
    for index = b.start, b.start + b.visible - 1 do
        local key = ui.station.rows[index]
        local y = b.first + (index - b.start) * b.row
        local selected = index == ui.selection
        if selected then
            Button.fill(b.list, y, rightWidth, b.row - 1, colors.band)
            Button.fill(b.list, y, 2, b.row - 1, colors.rule)
        end
        local ty = y + math.max(0, math.floor((b.row - 12) / 2))
        if groups[key] then line(text.groups[groups[key]], b.list + 4, ty, colors.muted, nameX - b.list - 6) end
        local name = key == "language" and "English / 中文" or nameFor(key, run.gear[key], text)
        line(name, nameX, ty, selected and colors.accent or colors.ink, priceX - nameX - 3,
            key == "language" and languageFont or nil)
        if key ~= "board" and key ~= "language" then
            local state, cost = orderState(run, key)
            local status = state == "ready" and text.ready or state == "maxed" and text.maxed or text.cost:format(cost)
            line(status, priceX, ty, state == "poor" and colors.muted or colors.ink, b.listRight - priceX - 2)
        end
    end

    local key = ui.station.rows[ui.selection]
    local detail, hint, note, button, enabled
    if key == "board" then
        local contract = ui.contract
        local reward = contract and contract.gear
        if reward == "spurPlus" and not run.spur then reward = "spur" end
        detail = text.contract:format(contract and text.contracts[contract.gear].title or text.ordinary)
        hint = contract and text.contracts[contract.gear].hint or text.ordinaryHint
        note = reward and text.reward:format(Hunt.bossMaterials, ItemText.name(reward))
            or text.ordinaryReward:format(Hunt.bossMaterials)
    elseif key == "language" then
        detail, hint, button, enabled = "English / 中文", text.languageHint, text.switch, true
    else
        local rank = run.gear[key]
        local state, cost = orderState(run, key)
        detail = rank and text.effects[key][math.min(2, rank + 1)] or text.effects[key]
        if state == "ready" then hint = text.pickup
        elseif state == "maxed" then hint = text.active
        else
            local verb = rank and (rank == 0 and "craft" or "upgrade") or "buy"
            button = text.forge.price:format(text.verbs[verb], cost)
            enabled = state == "available"
            hint = not enabled and text.needMaterials or rank and text.gearHint or text.supplyHint
        end
    end
    if key ~= "board" and ui.noticeTicks > 0 and ui.noticeLanguage == text then note = ui.notice end
    Button.fill(b.left, b.detail - 1, b.width, 1, colors.rule)
    line(detail, b.left + 2, b.detail + 1, colors.ink, b.width - 4, key == "language" and languageFont or nil)
    line(hint, b.left + 2, b.detail + 13, colors.muted, b.width - 4)
    if note then line(note, b.left + 2, b.detail + 25, colors.accent, b.width - 4) end
    line(text.controls, b.left, b.bottom - 14, colors.muted, b.width - 99)
    if button then Button.draw(b, button, enabled and ui.orderSelected, line) end
end

return Camp
