local HunterCharacter = {}
local Vitals = include("scripts.hunter_vitals")
local hunterType = Isaac.GetPlayerTypeByName("Little Hunter", false)
local helmetCostume = Isaac.GetCostumeIdByPath("gfx/characters/rathalos_helmet.anm2")
local catVariant = Isaac.GetEntityVariantByName("Longsword Palico")
local cat, destination, workTicks
local markedSeed, cooldown, glance, glanceTicks = nil, 0, nil, 0
local loggedPounce = false
local spurPounces = {}
local waveNoticeTicks = 0

function HunterCharacter.isHunter(game, player)
    return player ~= nil and game:GetNumPlayers() == 1 and player:GetPlayerType() == hunterType
end

function HunterCharacter.syncHelmet(game, player)
    if not player then return end
    local effects = player:GetEffects()
    local equipped = effects:HasNullEffect(helmetCostume)
    if HunterCharacter.isHunter(game, player) then
        if not equipped then effects:AddNullEffect(helmetCostume, true) end
    elseif equipped then
        effects:RemoveNullEffect(helmetCostume, -1)
    end
end

function HunterCharacter.enterRoom()
    if cat and cat:Exists() then cat:Remove() end
    cat, destination, workTicks = nil, nil, 0
    markedSeed, cooldown, glance, glanceTicks = nil, 0, nil, 0
    spurPounces = {}
    loggedPounce = false
end

function HunterCharacter.start(game, player, itemId, continued, native)
    HunterCharacter.enterRoom()
    waveNoticeTicks = 0
    if not continued and HunterCharacter.isHunter(game, player) then
        return native.equip(game, player, itemId)
    end
end

function HunterCharacter.sendCat(position, ticks)
    destination, workTicks = position, ticks
end

function HunterCharacter.announceBladeWave()
    waveNoticeTicks = 120
end

function HunterCharacter.bladeWaveNoticePosition()
    if waveNoticeTicks > 0 and cat and cat:Exists() then return cat.Position end
end

function HunterCharacter.markEnemy(seed)
    markedSeed = seed
end

function HunterCharacter.noticeDrop(position)
    glance, glanceTicks = position, 7
end

function HunterCharacter.rollFly(player, swing, itemId)
    if swing.flySuitRolled then return false end
    swing.flySuitRolled = true
    if player:GetCollectibleRNG(itemId):RandomInt(5) ~= 0 then return false end
    local origin = cat and cat:Exists() and cat.Position or player.Position
    player:AddBlueFlies(1, origin, nil)
    return true
end

local function isPrey(npc)
    return npc.Type ~= EntityType.ENTITY_FIREPLACE and npc.Type ~= EntityType.ENTITY_MOVABLE_TNT
        and npc:IsActiveEnemy(false) and npc:IsVulnerableEnemy() and not npc:IsDead()
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function prey(origin, preferred)
    local nearest, best
    for _, npc in ipairs(Isaac.GetRoomEntities()) do
        if isPrey(npc) then
            if npc.InitSeed == preferred then return npc end
            local d = origin:DistanceSquared(npc.Position)
            if not best or d < best then nearest, best = npc, d end
        end
    end
    return nearest
end

function HunterCharacter.spurPounce(player, rank)
    local enemy = prey(player.Position)
    if not enemy then return false end
    spurPounces[#spurPounces + 1] = { enemy = enemy, rank = rank }
    return true
end

function HunterCharacter.updateCat(game, player)
    if not HunterCharacter.isHunter(game, player) or player:IsDead() then
        if cat then HunterCharacter.enterRoom() end
        return
    end
    if waveNoticeTicks > 0 then waveNoticeTicks = waveNoticeTicks - 1 end
    if not cat or not cat:Exists() then
        cat = Isaac.Spawn(EntityType.ENTITY_EFFECT, catVariant, 0, player.Position, Vector.Zero, player)
        local sprite = cat:GetSprite()
        sprite:ReplaceSpritesheet(0, "gfx/characters/player2/102_baby_guppy.png")
        sprite:LoadGraphics()
        sprite:Play("HeadDown", true)
    end

    local room = game:GetRoom()
    cooldown = math.max(0, cooldown - 1)
    local spur = spurPounces[1]
    while spur and (not spur.enemy:Exists() or not isPrey(spur.enemy)) do
        table.remove(spurPounces, 1)
        spur = spurPounces[1]
    end
    local enemy = player.ControlsEnabled and (spur and spur.enemy or prey(cat.Position, markedSeed))
    local lunging = enemy and (spur or cooldown <= 4)
    local target = destination or room:GetClampedPosition(player.Position + Vector(-20, 10), 10)
    if lunging then
        target = enemy.Position
    elseif enemy then
        local side = player.Position.X < enemy.Position.X and -1 or 1
        target = room:GetClampedPosition(enemy.Position + Vector(side * (enemy.Size + 22), 8), 10)
    end
    local delta = target - cat.Position
    local distance = delta:Length()
    -- This custom Effect owns its movement. Advance its world position exactly once per game tick.
    cat.Position = cat.Position + delta * math.min(1, (lunging and 10 or 7) / math.max(1, distance))
    local facing = delta
    if enemy and distance <= 3 then facing = enemy.Position - cat.Position end
    if glanceTicks > 0 then
        glanceTicks = glanceTicks - 1
        if not enemy then facing = glance - cat.Position end
    end
    local sprite = cat:GetSprite()
    local direction = sprite:GetAnimation()
    if facing:Length() > 3 then
        if math.abs(facing.X) > math.abs(facing.Y) then
            direction = facing.X > 0 and "HeadRight" or "HeadLeft"
        else
            direction = facing.Y > 0 and "HeadDown" or "HeadUp"
        end
    end
    -- The native baby head clips do not loop. Their two drawn poses start at frames 0 and 2.
    sprite:SetFrame(direction, distance > 3 and math.floor(cat.FrameCount / 4) % 2 * 2 or 0)
    -- A short work animation starts when the cat reaches the material or workbench.
    if lunging then
        cat.SpriteOffset = Vector(0, -3 - 4 * math.abs(math.sin(cat.FrameCount * 0.35)))
        if (spur or cooldown == 0) and cat.Position:DistanceSquared(enemy.Position) <= (enemy.Size + 10) ^ 2 then
            if spur then table.remove(spurPounces, 1) else cooldown = 45 end
            local damage = Vitals.pounceDamage(player, spur and spur.rank)
            if enemy:TakeDamage(damage, 0, EntityRef(cat), 0) and not loggedPounce then
                loggedPounce = true
                Isaac.DebugString("[LS_M0] event=hunter_cat_hit target=" .. enemy.Type .. "." .. enemy.Variant .. " damage=" .. damage)
            end
        end
    elseif not enemy and destination and distance <= 3 then
        cat.SpriteOffset = Vector(0, -math.abs(math.sin(workTicks * 0.40)) * 4)
        workTicks = workTicks - 1
        if workTicks <= 0 then destination = nil end
    elseif distance > 3 then
        cat.SpriteOffset = Vector(0, -3 * math.abs(math.sin(cat.FrameCount * 0.35)))
    else
        cat.SpriteOffset = Vector.Zero
    end
end

return HunterCharacter
