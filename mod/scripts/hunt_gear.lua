local Gear = {}
local ItemText = include("scripts.item_text")
local Jewels = include("scripts.hunt_jewels")
local campGear = { "braces", "boots", "kit" }
local rewards = { "tooth", "flySuit", "spur", "spurPlus" }
local ids = {}
for _, key in ipairs(rewards) do ids[key] = { Isaac.GetItemIdByName(ItemText.englishName(key)) } end
for _, key in ipairs(campGear) do
    ids[key] = { Isaac.GetItemIdByName(ItemText.englishName(key)), Isaac.GetItemIdByName(ItemText.englishName(key, 2)) }
end

local jewelIds, jewelById = {}, {}
for _, key in ipairs(Jewels.keys) do
    jewelIds[key] = {}
    for rank = 1, Jewels.maxJewelLevel do
        local id = Isaac.GetItemIdByName(ItemText.jewelEnglishName(key, rank))
        jewelIds[key][rank] = id
        if id and id > 0 then jewelById[id] = true end
    end
end

function Gear.isJewelPedestal(pickup)
    return pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.Price == 0 and jewelById[pickup.SubType]
end

local ownedByRank = {}
function Gear.syncJewel(run, player, key)
    for rank, id in ipairs(jewelIds[key]) do
        ownedByRank[rank] = player:GetCollectibleNum(id, true)
    end
    return Jewels.syncOwned(run, key, ownedByRank)
end

-- Read the actual passives so a pedestal, a queued pickup, or a rerolled item
-- cannot grant a bonus the hunter does not currently own.
function Gear.sync(run, player)
    local changed = false
    for _, key in ipairs(rewards) do
        local held = player:HasCollectible(ids[key][1], true)
        if run[key] ~= held then run[key], changed = held, true end
    end
    for _, key in ipairs(campGear) do
        local ranks = ids[key]
        local rank = player:HasCollectible(ranks[2], true) and 2
            or player:HasCollectible(ranks[1], true) and 1 or 0
        if rank ~= run.gear[key] then
            run.gear[key], changed = rank, true
        end
    end
    return changed
end

function Gear.migrate(run, player)
    -- Before v83 these were hunt-save fields only. Restore each earned item once.
    local function restore(id)
        if not player:HasCollectible(id, true) then player:AddCollectible(id, 0, false) end
    end
    for _, key in ipairs(campGear) do
        for rank = 1, run.gear[key] do restore(ids[key][rank]) end
    end
    if run.tooth then restore(ids.tooth[1]) end
end

function Gear.waiting(key, rank)
    local id = ids[key][rank]
    return #Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, false, false) > 0
end

local function spawnPedestal(room, player, id, anchor)
    -- Prefer the tile just below the workstation. At a wall or another pickup,
    -- try the other sides so standing still at the forge won't collect the item.
    for _, offset in ipairs({ Vector(0, 48), Vector(48, 0), Vector(-48, 0), Vector(0, -48) }) do
        local target = room:GetClampedPosition(anchor + offset, 20)
        local position = room:FindFreePickupSpawnPosition(target, 0, true, false)
        if position:DistanceSquared(player.Position) >= 36 * 36 then
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id,
                position, Vector.Zero, player)
            return true
        end
    end
    return false, "space"
end

function Gear.spawn(room, player, key, rank)
    if Gear.waiting(key, rank) then return false, "waiting" end
    return spawnPedestal(room, player, ids[key][rank], player.Position)
end

function Gear.placeJewel(room, player, anchor, key, rank, oldRank)
    local ranks = jewelIds[key]
    if oldRank > 0 and player:GetCollectibleNum(ranks[oldRank], true) == 0 then return false, "unavailable" end
    local placed, reason = spawnPedestal(room, player, ranks[rank], anchor or player.Position)
    if not placed then return false, reason end
    if oldRank > 0 then player:RemoveCollectible(ranks[oldRank]) end
    return true
end

return Gear
