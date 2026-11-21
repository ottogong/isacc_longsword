local Wave = {}
local flightTicks = 6

function Wave.emit(waves, player, origin, direction, bladeReach)
    local dir = direction:Normalized()
    waves[#waves + 1] = {
        player = player, origin = Vector(origin.X, origin.Y), direction = dir,
        position = origin + dir * bladeReach, reach = bladeReach,
        halfWidth = math.min(14, math.max(6, bladeReach * 0.16)),
        damage = player.Damage * 0.7, hits = {}, age = 0, duration = flightTicks,
    }
end

-- Check the whole cast, including the blade itself, so the wave cannot start
-- on the far side of a rock. Pits are open to the flying edge.
local function farthestClearPoint(room, wave)
    local finish = wave.reach * 1.5
    local steps = math.ceil(finish / 5)
    for step = 1, steps do
        local pos = wave.origin + wave.direction * (finish * step / steps)
        if not room:IsPositionInRoom(pos, 0) or room:GetGridCollisionAtPos(pos) >= GridCollisionClass.COLLISION_OBJECT then
            return finish * (step - 1) / steps, true
        end
    end
    return finish, false
end

local function isEnemy(target)
    return target.Type ~= EntityType.ENTITY_FIREPLACE and target.Type ~= EntityType.ENTITY_MOVABLE_TNT
        and target:IsVulnerableEnemy() and not target:IsDead()
        and not target:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

local function sweep(wave, targets, from, to, accepted)
    for _, target in ipairs(targets) do
        if not wave.hits[target.InitSeed] and isEnemy(target) then
            local offset = target.Position - wave.origin
            local along = offset.X * wave.direction.X + offset.Y * wave.direction.Y
            local across = offset.Y * wave.direction.X - offset.X * wave.direction.Y
            local nearEdge = along - target.Size
            -- Leave the original blade's reach to the blade itself, including
            -- a boss whose center is outside the reach but whose body overlaps it.
            if nearEdge > wave.reach and nearEdge <= to and along + target.Size >= from
                and math.abs(across) <= wave.halfWidth + target.Size
                and (not wave.blocked or along <= wave.limit) then
                wave.hits[target.InitSeed] = true
                local pos = target.Position
                if target:TakeDamage(wave.damage, 0, EntityRef(wave.player), 0) then
                    accepted[#accepted + 1] = pos
                end
            end
        end
    end
end

function Wave.update(waves, room)
    local accepted = {}
    if #waves == 0 then return accepted end
    local targets = Isaac.GetRoomEntities()
    for i = #waves, 1, -1 do
        local wave = waves[i]
        if wave.age == 0 then wave.limit, wave.blocked = farthestClearPoint(room, wave) end
        local from = wave.reach + wave.age * wave.reach * 0.5 / wave.duration
        if wave.age >= wave.duration or from >= wave.limit then
            table.remove(waves, i)
        else
            wave.age = wave.age + 1
            local to = math.min(wave.limit, wave.reach + wave.age * wave.reach * 0.5 / wave.duration)
            wave.position = wave.origin + wave.direction * to
            sweep(wave, targets, from, to, accepted)
        end
    end
    return accepted
end

return Wave
