local Passives = {}
local eucharist = CollectibleType.COLLECTIBLE_EUCHARIST
-- These two subtypes identify old hunter wisps and the v103 starting items.
local goat, duality = CollectibleType.COLLECTIBLE_GOAT_HEAD, CollectibleType.COLLECTIBLE_DUALITY
local offscreen = Vector(-1000, -1000)
local owned, costume

-- Item wisps grant native collectible modifiers. Their coin/key fields survive a continue.
function Passives.isWisp(entity)
    if not entity or entity.Type ~= EntityType.ENTITY_FAMILIAR or entity.Variant ~= FamiliarVariant.ITEM_WISP
        or (entity.SubType ~= eucharist and entity.SubType ~= goat and entity.SubType ~= duality) then return false end
    local wisp = entity:ToFamiliar()
    return wisp.Coins == 76 and wisp.Keys == 83
end

local function hide(wisp)
    wisp.Visible = false
    wisp.Position, wisp.Velocity = offscreen, Vector.Zero
    wisp.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    wisp.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    wisp.FireCooldown = 60
end

local function claim(wisp)
    owned = wisp
    wisp.Coins, wisp.Keys = 76, 83
    wisp:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    wisp:AddEntityFlags(EntityFlag.FLAG_NO_QUERY | EntityFlag.FLAG_NO_REWARD)
    wisp:RemoveFromOrbit()
    hide(wisp)
end

local function alive(wisp)
    return wisp and wisp:Exists() and not wisp:IsDead()
end

function Passives.remove(wisp)
    wisp:Remove()
    wisp:Kill() -- Release the item's modifier as well as the familiar entity.
end

function Passives.visit(wisp)
    if not alive(wisp) then return end
    if wisp.SubType ~= eucharist then Passives.remove(wisp)
    elseif not alive(owned) then claim(wisp)
    elseif GetPtrHash(owned) == GetPtrHash(wisp) then hide(wisp)
    else Passives.remove(wisp) end
end

function Passives.update(player)
    if not player then
        if alive(owned) then Passives.remove(owned) end
        owned = nil
        return
    end
    if player:IsDead() then return end
    if not alive(owned) then
        -- FindByType omits FLAG_NO_QUERY familiars, including ones restored from a save.
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if Passives.isWisp(entity) then
                local wisp = entity:ToFamiliar()
                if wisp.Player and GetPtrHash(wisp.Player) == GetPtrHash(player) then Passives.visit(wisp) end
            end
        end
        if not alive(owned) then
            local wisp = player:AddItemWisp(eucharist, offscreen)
            if wisp then claim(wisp) end
        end
    end
    -- Native costume rebuilds can also reapply a wisp's outfit.
    player:RemoveCostume(costume)
end

function Passives.reset()
    owned = nil
end

function Passives.start(player, migrate)
    costume = Isaac.GetItemConfig():GetCollectible(eucharist)
    if migrate and player:HasCollectible(goat, true) and player:HasCollectible(duality, true) then
        player:RemoveCollectible(goat, true)
        player:RemoveCollectible(duality, true)
    end
    Passives.update(player)
end

return Passives
