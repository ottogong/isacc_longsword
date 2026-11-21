local Field = {}
local ItemText = include("scripts.item_text")
local material = Isaac.GetEntityVariantByName("Longsword Hunt Material")
local remains = Isaac.GetEntityVariantByName("Longsword Hunt Remains")
local shopBundles = { Isaac.GetItemIdByName(ItemText.englishName("material")),
    Isaac.GetItemIdByName(ItemText.englishName("materialBundle")) }
local materialArt = "gfx/longsword_hunt_material.anm2"
local TEMPORARY = 1
local LIFETIME = 120
local CARVE_TICKS = 30
local EXIT_CLEARANCE = 60 -- Leave room for the 31-unit carve radius outside the entrance.
local MOM_BOSS_ID = 6 -- Native entities2.xml bossID, not entity type 45.

function Field.materialVariant()
    return material
end

-- Called for a floor boss room's clear award, after all parts of Mom are defeated.
function Field.isMomClear(room)
    return room:GetBossID() == MOM_BOSS_ID
end

-- Only older hunt saves lack the exact kill flag. Womb and a recorded final clear
-- on the regular Mom floor provide the progression evidence available to those saves.
function Field.legacyPostMom(game, run)
    if game:IsGreedMode() then return false end
    local level = game:GetLevel()
    local stage = level:GetStage()
    if stage >= LevelStage.STAGE4_1 then return true end
    local momFloor = stage == LevelStage.STAGE3_2 or (stage == LevelStage.STAGE3_1 and
        (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0)
    return momFloor and run.rewarded == true and run.floor ==
        stage .. ":" .. level:GetStageType() .. ":" .. level:GetDungeonPlacementSeed()
end

function Field.drop(npc, postMom)
    if npc:IsBoss() or npc.SpawnerType ~= 0 or not npc:IsEnemy()
        or npc.Type == EntityType.ENTITY_FIREPLACE or npc.Type == EntityType.ENTITY_MOVABLE_TNT
        or npc:HasEntityFlags(EntityFlag.FLAG_NO_REWARD) or npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
    local rng = RNG()
    rng:SetSeed(npc.InitSeed, 35)
    local champion = npc:IsChampion()
    if not champion and rng:RandomInt(postMom and 3 or 5) ~= 0 then return end
    local velocity = Vector.FromAngle(rng:RandomInt(360)) * 2
    if champion then
        return Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_HEART,
            HeartSubType.HEART_SOUL, npc.Position, velocity, nil):ToPickup()
    end
    local pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, material, TEMPORARY, npc.Position, velocity, nil):ToPickup()
    pickup.Timeout = LIFETIME
    return pickup
end

local function heartMaterials(subtype)
    if subtype == HeartSubType.HEART_HALF_SOUL then return 1 end
    if subtype == HeartSubType.HEART_SOUL or subtype == HeartSubType.HEART_BLACK then return 2 end
end

function Field.updatePickup(pickup)
    if pickup.Variant == material then
        if pickup.SubType == TEMPORARY then
            if pickup.FrameCount >= LIFETIME then pickup:Remove()
            elseif pickup.FrameCount >= 90 then pickup.Visible = pickup.FrameCount % 8 < 5 end
        end
    elseif pickup.Variant == PickupVariant.PICKUP_HEART then
        local amount = heartMaterials(pickup.SubType)
        if not amount then return end
        if pickup:IsShopItem() then
            -- Keep the heart's live shop price, including mid-room discounts, until checkout.
            local sprite = pickup:GetSprite()
            if sprite:GetFilename() ~= materialArt then
                sprite:Load(materialArt, true)
                sprite:Play("Idle", true)
            end
        else
            local option = pickup.OptionsPickupIndex
            pickup:Morph(EntityType.ENTITY_PICKUP, material, amount == 2 and 2 or 0, true, true, true)
            pickup.OptionsPickupIndex = option
        end
    end
end

function Field.offerShopBundle(pickup, player)
    local amount = heartMaterials(pickup.SubType)
    if not amount then return end
    -- An overlap can precede the first pickup update. Wait for the ground material morph in that case.
    if not pickup:IsShopItem() or pickup.Wait > 0 or player:IsDead() or not player.ControlsEnabled
        or player:GetNumCoins() < pickup.Price then return true end
    local price, slot, options = pickup.Price, pickup.ShopItemId, pickup.OptionsPickupIndex
    -- A native collectible can be bought at full health. Isaac settles the sale on the next collision.
    pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, shopBundles[amount], true, true, true)
    pickup.ShopItemId, pickup.OptionsPickupIndex = slot, options
    pickup.AutoUpdatePrice, pickup.Price = false, price
    return true
end

function Field.redeemShopBundles(player)
    local total = 0
    for amount, id in ipairs(shopBundles) do
        if player:HasCollectible(id, true) then
            local count = player:GetCollectibleNum(id, true)
            for _ = 1, count do player:RemoveCollectible(id) end
            total = total + count * amount
        end
    end
    return total
end

function Field.collect(pickup, player)
    if pickup.Wait > 0 or pickup.Touched or player:IsDead() then return end
    pickup.Touched = true
    if pickup.OptionsPickupIndex > 0 then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
            local other = entity:ToPickup()
            if other.Index ~= pickup.Index and other.OptionsPickupIndex == pickup.OptionsPickupIndex then other:Remove() end
        end
    end
    local amount = pickup.SubType == 2 and 2 or 1
    pickup:Remove()
    return amount
end

function Field.clear(ui)
    if ui.body and ui.body:Exists() then ui.body:Remove() end
    ui.body, ui.carveTicks, ui.carveNearby = nil, 0, false
end

function Field.site(room, deathPosition)
    local center = room:GetCenterPos()
    local pos = room:GetClampedPosition(deathPosition or center, 24)
    -- Leave space for the usual boss pedestal even before the clear award spawns.
    if pos:DistanceSquared(center) < 32 * 32 then pos = center + Vector(40, 0) end
    return room:FindFreePickupSpawnPosition(pos, 10, true, false)
end

local function nearExit(room, position, entities)
    -- Floor entrances occupy 40-unit grid tiles and can appear after the award callback.
    for x = -1, 1 do
        for y = -1, 1 do
            local grid = room:GetGridEntityFromPos(position + Vector(x * 40, y * 40))
            if grid then
                local kind = grid:GetType()
                if (kind == GridEntityType.GRID_TRAPDOOR or kind == GridEntityType.GRID_STAIRS)
                    and grid.Position:DistanceSquared(position) < EXIT_CLEARANCE ^ 2 then return true end
            end
        end
    end
    for _, entity in ipairs(entities) do
        if (entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == EffectVariant.HEAVEN_LIGHT_DOOR
            or entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_BIGCHEST)
            and entity:Exists() and entity.Position:DistanceSquared(position) < EXIT_CLEARANCE ^ 2 then return true end
    end
    return false
end

local function carvePosition(room, origin, player)
    local entities = Isaac.GetRoomEntities()
    if not nearExit(room, origin, entities) then return origin end
    local best, bestDistance, bestPlayerDistance = nil, math.huge, math.huge
    for i = 0, room:GetGridSize() - 1 do
        local tile = room:GetGridPosition(i)
        local distance, playerDistance = tile:DistanceSquared(origin), tile:DistanceSquared(player.Position)
        if (distance < bestDistance or distance == bestDistance and playerDistance < bestPlayerDistance)
            and room:IsPositionInRoom(tile, 20) and not room:GetGridEntity(i)
            and room:GetGridCollisionAtPos(tile) == GridCollisionClass.COLLISION_NONE
            and not nearExit(room, tile, entities) and room:CheckLine(player.Position, tile, 0)
            and room:FindFreePickupSpawnPosition(tile, 0, true, false):DistanceSquared(tile) < 1 then
            best, bestDistance, bestPlayerDistance = tile, distance, playerDistance
        end
    end
    return best
end

function Field.updateCarve(ui, run, room, player, busy, sendCat)
    local seed = room:GetSpawnSeed()
    local reward = run.remains[seed]
    if not reward or reward.carved or not room:IsClear() then
        ui.carveTicks, ui.carveNearby = 0, false
        return
    end
    local pos = carvePosition(room, Vector(reward.x, reward.y), player)
    if not pos then Field.clear(ui); return end
    local moved = pos.X ~= reward.x or pos.Y ~= reward.y
    if not ui.body or not ui.body:Exists() then
        ui.body = Isaac.Spawn(EntityType.ENTITY_EFFECT, remains, 0, pos, Vector.Zero, nil)
        ui.body:GetSprite():Play("Idle", true)
    elseif moved then
        ui.body.Position = pos
    end
    ui.carveNearby = player.Position:DistanceSquared(ui.body.Position) <= 31 * 31
    if moved then
        reward.x, reward.y = math.floor(pos.X), math.floor(pos.Y)
        ui.carveTicks = 0
        return nil, true
    end
    if not ui.carveNearby or busy or player:IsDead() or not player.ControlsEnabled
        or player:GetMovementInput():LengthSquared() > 0.04 or player.Velocity:LengthSquared() > 1 then
        ui.carveTicks = 0
        return
    end
    if ui.carveTicks == 0 then sendCat(ui.body.Position + Vector(-10, 0), CARVE_TICKS) end
    ui.carveTicks = ui.carveTicks + 1
    if ui.carveTicks >= CARVE_TICKS then
        Field.clear(ui)
        return seed
    end
end

return Field
