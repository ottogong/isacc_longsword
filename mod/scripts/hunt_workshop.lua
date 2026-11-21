local Workshop = {}
local Hunt = include("scripts.hunt")
local Gear = include("scripts.hunt_gear")
local ItemText = include("scripts.item_text")
local workshopText = include("scripts.workshop_text")
local Forge = include("scripts.jewel_forge_view")
local Camp = include("scripts.camp_view")
local counterVariant = Isaac.GetEntityVariantByName("Longsword Guild Counter")

local STAND_TICKS = 24
local camp = { key = "camp", rows = { "board", "braces", "boots", "kit", "pill", "devil", "key", "bomb", "language" } }
local forge = Forge.station

function Workshop.new()
    return { hold = 0, noticeTicks = 0 }
end

function Workshop.announce(ui, message)
    ui.notice, ui.noticeLanguage, ui.noticeTicks = message, workshopText(), 75
end

function Workshop.isOpen(ui)
    return ui ~= nil and ui.selection ~= nil
end

function Workshop.close(ui)
    if ui then ui.selection, ui.hold, ui.blocked = nil, 0, true end
end

local contracts = {
    { boss = EntityType.ENTITY_MONSTRO, gear = "tooth" },
    { boss = EntityType.ENTITY_DUKE, gear = "flySuit" },
    { boss = EntityType.ENTITY_FAMINE, gear = "spurPlus" },
}

-- Advertise only targets explicitly placed in the floor boss room.
local function floorContract(level, run)
    local rooms = level:GetRooms()
    local last = level:GetLastBossRoomListIndex()
    if last < 0 or last >= rooms.Size then return end
    local desc = rooms:Get(last)
    if not desc or not desc.Data or desc.Data.Type ~= RoomType.ROOM_BOSS then return end
    local spawns = desc.Data.Spawns
    for i = 0, spawns.Size - 1 do
        local spawn = spawns:Get(i)
        if spawn.EntryCount == 1 then
            local enemy = spawn:PickEntry(0)
            if enemy.Variant == 0 then
                for _, contract in ipairs(contracts) do
                    if enemy.Type == contract.boss and not run[contract.gear] then return contract end
                end
            end
        end
    end
end

-- The counter is a single non-blocking effect, restored when re-entering a room.
local function placeCounter(room, station)
    local desired = room:GetCenterPos() + Vector(-80, -64)
    local best, distance
    for i = 0, room:GetGridSize() - 1 do
        local position = room:GetGridPosition(i)
        if room:IsPositionInRoom(position, 20) and not room:GetGridEntity(i)
            and room:GetGridCollision(i) == GridCollisionClass.COLLISION_NONE then
            local d = position:DistanceSquared(desired)
            if not distance or d < distance then best, distance = position, d end
        end
    end
    if not best then return end
    local existing = Isaac.FindByType(EntityType.ENTITY_EFFECT, counterVariant, -1, false, false)
    local counter = existing[1] or Isaac.Spawn(EntityType.ENTITY_EFFECT, counterVariant, 0, best, Vector.Zero, nil)
    for i = 2, #existing do existing[i]:Remove() end
    counter.Position = best
    local sprite = counter:GetSprite()
    local art = station == camp and "gfx/isacc_longsword/camp_tent.anm2" or "gfx/005.056_wooden chest.anm2"
    if sprite:GetFilename() ~= art then sprite:Load(art, true) end
    sprite:SetFrame("Idle", 0)
    return best
end

function Workshop.enterRoom(ui, game, player, run, isGuild)
    ui.station, ui.position, ui.selection, ui.inspectBoss = nil, nil, nil, nil
    ui.blocked, ui.nearCamp, ui.hold = false, false, 0
    ui.carveNearby, ui.carveTicks = false, 0
    local level, room = game:GetLevel(), game:GetRoom()
    if isGuild or level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() then
        ui.station = isGuild and forge or camp
        ui.position = placeCounter(room, ui.station)
        ui.arrival = player.Position
        ui.contract = not isGuild and floorContract(level, run)
        return ui.position
    elseif room:GetType() == RoomType.ROOM_BOSS and not room:IsClear() then
        ui.inspectBoss = 15
    end
end

local function nameFor(key, rank, text)
    return text.names[key] or ItemText.name(key, rank and math.min(2, rank + 1))
end

local function orderState(run, key)
    local rank = run.gear[key]
    local price = Hunt.price(run, key)
    if rank and rank < 2 and Gear.waiting(key, rank + 1) then return "ready", price end
    if not price then return "maxed" end
    if run.materials < price then return "poor", price end
    return "available", price
end

local function menuAction(ui, run, craft, changeLanguage, action, pos)
    if not action or action == "point" then return end
    if ui.station == forge then
        local result, receipt = Forge.action(ui, run, craft, action, pos, workshopText())
        if result == "close" or result == "forged" then Workshop.close(ui) end
        if result == "forged" then SFXManager():Play(SoundEffect.SOUND_SLOTSPAWN, 0.7) end
        if receipt then Workshop.announce(ui, receipt) end
        return
    end
    if action == "click" then
        local box = Camp.layout(ui)
        ui.campFirst = box.start
        local target = Camp.pointer(box, pos)
        if target == "scrollUp" or target == "scrollDown" then
            ui.campFirst = box.start + (target == "scrollUp" and -1 or 1)
            local selected = math.max(ui.campFirst, math.min(ui.selection, ui.campFirst + box.visible - 1))
            if selected ~= ui.selection then ui.selection, ui.orderSelected, ui.noticeTicks = selected, false, 0 end
            return
        end
        if type(target) == "number" then
            if target ~= ui.selection then ui.noticeTicks = 0 end
            ui.selection, ui.orderSelected = target, true
            return
        end
        if target == "confirm" and not ui.orderSelected then return end
        action = target
    end
    local rows = ui.station.rows
    if action == "back" then Workshop.close(ui); return end
    if action == "up" or action == "down" then
        ui.selection = (ui.selection - 1 + (action == "up" and -1 or 1)) % #rows + 1
        ui.campFirst = Camp.layout(ui).start
        ui.orderSelected, ui.noticeTicks = true, 0
        return
    end
    if action ~= "confirm" then return end
    local key, text = rows[ui.selection], workshopText()
    if key == "board" then return end
    if key == "language" then
        local mode = changeLanguage()
        Workshop.announce(ui, workshopText().languageModes[mode])
        return
    end
    local state, price = orderState(run, key)
    if state ~= "available" then return end
    local rank = run.gear[key]
    local name = nameFor(key, rank, text)
    local ok, reason = craft(key)
    if ok then
        SFXManager():Play(SoundEffect.SOUND_SLOTSPAWN, 0.7)
        local verb = rank and (rank == 0 and "craft" or "upgrade") or "buy"
        Workshop.announce(ui, text.receipt:format(text.past[verb], name, price) .. (rank and text.collect or ""))
        if rank then Workshop.close(ui) end
    elseif reason == "space" then
        Workshop.announce(ui, text.noSpace)
    end
end

function Workshop.update(ui, game, player, run, craft, changeLanguage, action, mousePos, canOpen)
    ui.noticeTicks = math.max(0, ui.noticeTicks - 1)
    if ui.inspectBoss then
        ui.inspectBoss = ui.inspectBoss > 1 and ui.inspectBoss - 1 or nil
        for _, contract in ipairs(contracts) do
            if not run[contract.gear] and #Isaac.FindByType(contract.boss, 0, -1, false, true) > 0 then
                local text = workshopText()
                local target = text.contracts[contract.gear]
                Workshop.announce(ui, text.bossHint:format(target.name, target.hint))
                ui.inspectBoss = nil
                break
            end
        end
    end
    if not ui.position or not game:GetRoom():IsClear() then
        if Workshop.isOpen(ui) then Workshop.close(ui) end
        ui.nearCamp, ui.hold = false, 0
        return
    end
    if Workshop.isOpen(ui) then
        menuAction(ui, run, craft, changeLanguage, action, mousePos)
        return
    end
    local distance = player.Position:DistanceSquared(ui.position)
    ui.nearCamp = distance <= 68 * 68
    if ui.arrival and player.Position:DistanceSquared(ui.arrival) > 28 * 28 then ui.arrival = nil end
    if distance > 24 * 24 then
        ui.hold, ui.blocked = 0, false
    elseif ui.carveNearby then
        ui.hold, ui.blocked = 0, true
    elseif canOpen == false or ui.blocked or ui.arrival or player:GetMovementInput():LengthSquared() > 0.04 then
        ui.hold = 0
    else
        ui.hold = ui.hold + 1
        if ui.hold >= STAND_TICKS then
            ui.selection, ui.hold, ui.noticeTicks, ui.orderSelected = 1, 0, 0, false
            if ui.station == forge then ui.page, ui.copy = "craft", 1 else ui.campFirst = 1 end
        end
    end
end

local font, ink, gold, shadow, paper
local fonts = {}
local function getFont(path)
    if not fonts[path] then
        local face = Font()
        face:Load(path)
        fonts[path] = face
    end
    return fonts[path]
end

local function centered(text, x, y, color, face)
    face = face or font
    x = math.floor(x - face:GetStringWidthUTF8(text) * 0.5)
    y = math.floor(y)
    face:DrawStringUTF8(text, x + 1, y + 1, shadow)
    face:DrawStringUTF8(text, x, y, color)
end

local function line(message, x, y, color, maxWidth, face)
    face = face or font
    local width = face:GetStringWidthUTF8(message)
    local scale = math.min(1, maxWidth / math.max(1, width))
    if scale == 1 then
        face:DrawStringUTF8(message, x, y, color)
    else
        face:DrawStringScaledUTF8(message, x, y, scale, scale, color, 0, false)
    end
end

local function drawPaper(box)
    if not paper then
        paper = Sprite()
        paper:Load("gfx/ui/genericpopup.anm2", true)
        paper:SetFrame("Idle", 0)
    end
    local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    -- Native popup layer 0 is a 720x500 shade beginning at (-100,-50).
    paper.Scale = Vector(sw / 720, sh / 500)
    paper:RenderLayer(0, Vector(100 * sw / 720, 50 * sh / 500))
    -- Layer 1 is the empty paper; the original dialog text is on layer 2.
    local sx, sy = (box.width + 28) / 222, (box.height + 18) / 115
    paper.Scale = Vector(sx, sy)
    paper:RenderLayer(1, Vector(sw / 2 - 235 * sx, sh / 2 - 130 * sy))
end

function Workshop.render(ui, game, player, run, palicoNoticePosition)
    local atStation = ui.position and game:GetRoom():IsClear()
    local hud = game:GetHUD():IsVisible()
    if not atStation and not hud and not ui.carveNearby and ui.noticeTicks == 0 and not palicoNoticePosition then return end
    local text = workshopText()
    if not ink then
        ink, gold, shadow = KColor(1, 0.96, 0.87, 1), KColor(1, 0.84, 0.45, 1), KColor(0.12, 0.07, 0.06, 1)
    end
    font = getFont(text.font)
    local middle = Isaac.GetScreenWidth() * 0.5
    if palicoNoticePosition and not Workshop.isOpen(ui) then
        local screen = Isaac.WorldToScreen(palicoNoticePosition)
        local margin = math.min(middle, font:GetStringWidthUTF8(text.bladeWaveUnlock) * 0.5 + 4)
        local x = math.max(margin, math.min(2 * middle - margin, screen.X))
        centered(text.bladeWaveUnlock, x, math.max(5, screen.Y - 30), gold)
    end
    if hud and not Workshop.isOpen(ui) then
        local inset = Options.HUDOffset
        centered(text.materials:format(run.materials), 75 + 20 * inset, 57 + 12 * inset, gold)
    end
    if ui.carveNearby then
        local progress = math.min(100, math.floor((ui.carveTicks or 0) * 100 / 30))
        centered(text.carving:format(progress), middle, Isaac.GetScreenHeight() - 43, gold)
    end
    if atStation then
        local screen = Isaac.WorldToScreen(ui.position)
        if not Workshop.isOpen(ui) then
            if ui.station == forge then Forge.statue(screen.X, screen.Y, 0.68) end
            centered(text.station[ui.station.key], screen.X, screen.Y + 5, gold)
        end
        if Workshop.isOpen(ui) then
            if ui.station == forge then Forge.render(ui, run, player, text, line, drawPaper)
            else Camp.render(ui, run, player, text, line, drawPaper, nameFor, orderState, getFont) end
        elseif ui.nearCamp and not ui.carveNearby then
            local hint = ui.blocked and text.stepAway or text.openMenu:format(math.floor(ui.hold * 100 / STAND_TICKS))
            centered(hint, middle, Isaac.GetScreenHeight() - 38, ink)
        end
    end
    if ui.noticeTicks > 0 and ui.noticeLanguage == text and not Workshop.isOpen(ui) then
        centered(ui.notice, middle, 28, gold)
    end
end

return Workshop
