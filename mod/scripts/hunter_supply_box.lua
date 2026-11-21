local Vitals = include("scripts.hunter_vitals")
local SupplyBox = { variant = Isaac.GetEntityVariantByName("Longsword Hunter Supply Box") }
local neighbors = { Vector(40, 0), Vector(-40, 0), Vector(0, 40), Vector(0, -40) }
local boxDistance = 80
local current

local function positionByBoard(room, board, player)
    local function freeFrom(origin, target)
        if not room:IsPositionInRoom(target, 14) then return end
        local free = room:FindFreePickupSpawnPosition(target, 0, true, false)
        if room:IsPositionInRoom(free, 14) and free:DistanceSquared(board) >= boxDistance^2
            and free:DistanceSquared(player.Position) >= 28^2 and room:CheckLine(origin, free, 0) then
            return free
        end
    end
    -- Prefer two tiles due right; try the other cardinal directions before accepting a nudge.
    local nearest, deviation
    for _, step in ipairs(neighbors) do
        local target = board + step + step
        local free = freeFrom(board, target)
        if free then
            local d = free:DistanceSquared(target)
            if d < 1 then return free end
            if not deviation or d < deviation then nearest, deviation = free, d end
        end
    end
    if nearest then return nearest end

    -- A wall can put the nearest reachable floor tile around a corner.
    local queue, seen, index = { board }, { [room:GetGridIndex(board)] = true }, 1
    while index <= #queue do
        local origin = queue[index]
        index = index + 1
        for _, step in ipairs(neighbors) do
            local target = origin + step
            if room:IsPositionInRoom(target, 14) then
                local cell = room:GetGridIndex(target)
                if not seen[cell] and room:CheckLine(origin, target, 0) then
                    seen[cell] = true
                    queue[#queue + 1] = target
                    if target:DistanceSquared(board) >= boxDistance^2 then
                        local free = freeFrom(target, target)
                        if free then return free end
                    end
                end
            end
        end
    end
end

function SupplyBox.enter(room, board, run, player)
    current = nil
    if not board or not run.supplyBox then return end
    local existing = Isaac.FindByType(EntityType.ENTITY_PICKUP, SupplyBox.variant, -1, false, false)
    local entity = existing[1]
    for i = 2, #existing do existing[i]:Remove() end
    if not entity or entity.Position:DistanceSquared(board) < boxDistance^2 then
        local pos = positionByBoard(room, board, player)
        if pos then
            if entity then entity.Position = pos
            else entity = Isaac.Spawn(EntityType.ENTITY_PICKUP, SupplyBox.variant, 0, pos, Vector.Zero, nil) end
        elseif not entity then
            return
        end
    end
    current = entity:ToPickup()
    local closed = run.supplyBox == "closed"
    current.EntityCollisionClass = closed and EntityCollisionClass.ENTCOLL_PLAYERONLY or EntityCollisionClass.ENTCOLL_NONE
    current:GetSprite():SetFrame(closed and "Idle" or "Opened", 0)
end

function SupplyBox.open(game, pickup, player, run)
    if run.supplyBox ~= "closed" or not current or GetPtrHash(current) ~= GetPtrHash(pickup) then return false end
    run.supplyBox = "opened"
    pickup.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    pickup:GetSprite():Play("Open", true)
    Vitals.supply(game, player, "pill", pickup.Position + Vector(-22, 20))
    Vitals.supply(game, player, "devil", pickup.Position + Vector(22, 20))
    return true
end

function SupplyBox.update(pickup)
    local sprite = pickup:GetSprite()
    if sprite:IsFinished("Open") then sprite:SetFrame("Opened", 0) end
end

return SupplyBox
