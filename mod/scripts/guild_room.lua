local Guild = {}
local watchBoss, entranceHandled, fieldForge = false, false, false

local function dealRoom(kind)
    return kind == RoomType.ROOM_DEVIL or kind == RoomType.ROOM_ANGEL
end

local function eligibleFloor(level)
    return level:GetStage() >= 2 or (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0
end

function Guild.isHall(game, run)
    return fieldForge or (dealRoom(game:GetRoom():GetType()) and run.rewarded and eligibleFloor(game:GetLevel()))
end

local function fixedProgression(pickup)
    local variant = pickup.Variant
    if variant == PickupVariant.PICKUP_BIGCHEST or variant == PickupVariant.PICKUP_TROPHY
        or variant == PickupVariant.PICKUP_MOMSCHEST then return true end
    if variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.SubType > 0 then
        local item = Isaac.GetItemConfig():GetCollectible(pickup.SubType)
        return item and item:HasTags(ItemConfig.TAG_QUEST)
    end
    return false
end

local function prepareHall(room, preservePickup)
    local firstVisit = room:IsFirstVisit()
    room:SetClear(true)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = entity:ToPickup()
        if pickup then
            local stock = firstVisit or pickup.Price ~= 0 or (pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and not pickup.Touched)
            if stock and not entity.SpawnerEntity and not fixedProgression(pickup)
                and not (preservePickup and preservePickup(pickup)) then
                pickup:Remove()
            end
        elseif entity.Type == EntityType.ENTITY_EFFECT then
            if entity.Variant == EffectVariant.DEVIL or entity.Variant == EffectVariant.ANGEL then entity:Remove() end
        elseif entity.Type == EntityType.ENTITY_SLOT or entity.Type == EntityType.ENTITY_SHOPKEEPER
            or (entity:ToNPC() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)) then
            entity:Remove()
        end
    end
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid then
            local kind = grid:GetType()
            if kind == GridEntityType.GRID_STATUE or kind == GridEntityType.GRID_SPIKES
                or kind == GridEntityType.GRID_SPIKES_ONOFF then
                room:RemoveGridEntity(index, 0, false)
            end
        end
    end
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door and not door:IsLocked() then door:Open() end
    end
end

function Guild.enterRoom(game, run, preservePickup)
    local room, level = game:GetRoom(), game:GetLevel()
    local kind = room:GetType()
    fieldForge, watchBoss, entranceHandled = false, false, false
    if dealRoom(kind) then
        prepareHall(room, preservePickup)
        return Guild.isHall(game, run)
    end
    if kind == RoomType.ROOM_BOSS and eligibleFloor(level) then
        local last = level:GetLastBossRoomListIndex()
        watchBoss = last < 0 or level:GetCurrentRoomDesc().ListIndex == last
    end
    return false
end

local function keepPreferredDealDoor(room)
    local devilSlot, hasAngel
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then
            if door.TargetRoomType == RoomType.ROOM_DEVIL then devilSlot = slot end
            if door.TargetRoomType == RoomType.ROOM_ANGEL then hasAngel = true end
        end
    end
    if hasAngel and devilSlot then room:RemoveDoor(devilSlot) end
    return hasAngel or devilSlot ~= nil
end

-- Run after native clear rewards have finished placing their exits. A field
-- counter covers layouts without a spare door and preserves all story exits.
function Guild.update(game, run)
    if not watchBoss or not run.rewarded then return false end
    local room = game:GetRoom()
    if not room:IsClear() then return false end
    -- Duality can place the second door later. Keep checking both slots but
    -- only ask the engine to create an entrance once per visit.
    local hasDoor = keepPreferredDealDoor(room)
    if entranceHandled then return false end
    entranceHandled = true
    if hasDoor then return false end
    if room:TrySpawnDevilRoomDoor(true, true) then
        keepPreferredDealDoor(room)
        return false
    end
    fieldForge = true
    return true
end

return Guild
