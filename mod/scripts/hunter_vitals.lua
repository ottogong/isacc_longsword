-- main.lua calls these functions only for the single-player Little Hunter.
local Vitals = {}
local HEART_LIMIT = 12 -- six red containers, measured in half-hearts
local BASE_DAMAGE = 1.5
local ISAAC_DAMAGE = 3.5
local SMITH_DAMAGE = 1
local SMITH_TEARS = 0.35
local SMITH_RANGE = 50

local function fixContainers(player)
    local delta = HEART_LIMIT - player:GetMaxHearts()
    if delta == 0 then return end
    local redHearts = player:GetHearts()
    player:AddMaxHearts(delta, false)
    local healthDelta = math.min(redHearts, player:GetEffectiveMaxHearts()) - player:GetHearts()
    if healthDelta ~= 0 then player:AddHearts(healthDelta) end
end

local function consumableCount(player)
    -- Ctrl can rotate a consumable behind the permanent pocket weapon.
    local count = 0
    for slot = 0, 3 do
        if player:GetPill(slot) ~= 0 or player:GetCard(slot) ~= 0 then count = count + 1 end
    end
    return count
end

local function fullHealthColor(game)
    local pool = game:GetItemPool()
    local color = pool:ForceAddPillEffect(PillEffect.PILLEFFECT_FULL_HEALTH)
    pool:IdentifyPill(color)
    return color
end

function Vitals.supply(game, player, key, origin)
    local variant, subtype
    if key == "pill" then
        variant, subtype = PickupVariant.PICKUP_PILL, fullHealthColor(game)
    elseif key == "devil" then
        variant, subtype = PickupVariant.PICKUP_TAROTCARD, Card.CARD_DEVIL
    elseif key == "key" then
        variant, subtype = PickupVariant.PICKUP_KEY, KeySubType.KEY_NORMAL
    elseif key == "bomb" then
        variant, subtype = PickupVariant.PICKUP_BOMB, BombSubType.BOMB_NORMAL
    else
        return false
    end
    local position = game:GetRoom():FindFreePickupSpawnPosition(origin or player.Position, 0, true)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, position, Vector.Zero, player)
    return true
end

function Vitals.damage(player, smithLevel, jewelFlat, jewelMultiplier)
    -- Preserve additive upgrades above base and keep low-damage items usable.
    local native = player.Damage
    local reduction = math.min(ISAAC_DAMAGE - BASE_DAMAGE, native * (1 - BASE_DAMAGE / ISAAC_DAMAGE))
    player.Damage = (native - reduction + SMITH_DAMAGE * smithLevel + (jewelFlat or 0)) * (jewelMultiplier or 1)
end

function Vitals.pounceDamage(player, spurRank)
    local bonus = math.max(0, player.Damage - BASE_DAMAGE)
    return 2 + bonus + (spurRank == 2 and 1 or 0)
end

function Vitals.tears(player, smithLevel, jewelBonus)
    local bonus = SMITH_TEARS * smithLevel + (jewelBonus or 0)
    if bonus == 0 then return end
    local tearsPerSecond = 30 / (player.MaxFireDelay + 1)
    player.MaxFireDelay = 30 / (tearsPerSecond + bonus) - 1
end

function Vitals.range(player, level, jewelTiles)
    player.TearRange = player.TearRange + SMITH_RANGE * level + 40 * (jewelTiles or 0)
end

function Vitals.refresh(player, flag)
    player:AddCacheFlags(flag or (CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_RANGE))
    player:EvaluateItems()
end

function Vitals.start(game, player, run, continued)
    fixContainers(player)
    if not continued then
        -- Keep native pocket cycling without Polydactyly's first-pickup payout.
        local pocketItem = CollectibleType.COLLECTIBLE_POLYDACTYLY
        if not player:HasCollectible(pocketItem, true) then player:AddCollectible(pocketItem, 0, false) end
    end
    Vitals.refresh(player)
end

function Vitals.update(game, player, run)
    if player:IsDead() then return false end
    fixContainers(player)
    -- Only pre-v85 saves can still have a Full Health pill waiting on the cat.
    if run.reservePill and consumableCount(player) == 0 then
        player:AddPill(fullHealthColor(game))
        run.reservePill = false
        return true
    end
    return false
end

return Vitals
