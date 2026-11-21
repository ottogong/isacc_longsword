local Loot = {}
local sampling = false

-- Initial pool weights (sum of Item.Weight x 10 in the local Repentance+
-- itempools.xml). GetCollectible handles the actual unlocked items and their
-- current weights. Normal Lua does not expose the remaining weight of a pool.
local normalPools = {
    {0, 3923}, {1, 888}, {2, 580}, {3, 876}, {4, 639}, {5, 610}, -- treasure through secret
    {6, 134}, {7, 60}, {8, 217}, {9, 119}, {10, 260}, {11, 308}, -- library through demon beggar
    {12, 317}, {13, 252}, {14, 82}, {15, 186}, -- curse through Mom's chest
    {23, 960}, {24, 930}, {25, 186}, {26, 110}, -- crane game through planetarium
    {27, 234}, {28, 890}, {29, 110}, {30, 80}, -- old chest through rotten beggar
}
local greedPools = {
    {16, 3702}, {17, 639}, {18, 819}, {19, 799}, {20, 594}, {21, 282}, {22, 565},
}
for _, pools in ipairs({ normalPools, greedPools }) do
    pools.total = 0
    for _, entry in ipairs(pools) do pools.total = pools.total + entry[2] end
end

local function pickPool(pools, rng)
    local ticket = rng:RandomInt(pools.total)
    for _, entry in ipairs(pools) do
        if ticket < entry[2] then return entry[1] end
        ticket = ticket - entry[2]
    end
end

local function eligible(config, id)
    local item = id > 0 and config:GetCollectible(id)
    return item and (item:HasTags(ItemConfig.TAG_OFFENSIVE) or item:HasTags(ItemConfig.TAG_QUEST))
end

local function resolve(game, player, requested, decrease, seed)
    local pool, config = game:GetItemPool(), Isaac.GetItemConfig()
    local nativeChaos = player:HasCollectible(CollectibleType.COLLECTIBLE_CHAOS)
    local rng = RNG()
    rng:SetSeed(seed == 0 and 1 or seed, 35)
    local pools = game:IsGreedMode() and greedPools or normalPools
    local fallback = CollectibleType.COLLECTIBLE_BROTHER_BOBBY

    -- Scripted drops never reach this hook. Preserve quest items returned by
    -- the original pool as well, before the hunter makes a different choice.
    local poolType, rollSeed = requested, seed
    local defaultItem = CollectibleType.COLLECTIBLE_NULL
    local id = pool:GetCollectible(poolType, false, rollSeed, defaultItem)
    local item = id > 0 and config:GetCollectible(id)
    local keepOriginal = item and (item:HasTags(ItemConfig.TAG_QUEST)
        or nativeChaos and item:HasTags(ItemConfig.TAG_OFFENSIVE))
    if not keepOriginal then
        defaultItem = CollectibleType.COLLECTIBLE_BREAKFAST
        for _ = 1, 16 do
            -- If the player owns Chaos, Isaac already mixes this native roll.
            poolType = nativeChaos and requested or pickPool(pools, rng)
            rollSeed = rng:Next()
            id = pool:GetCollectible(poolType, false, rollSeed, defaultItem)
            if eligible(config, id) then break end
        end
    end
    if not eligible(config, id) then return fallback end
    if not decrease then return id end
    local committed = pool:GetCollectible(poolType, true, rollSeed, defaultItem)
    if eligible(config, committed) then return committed end
    return fallback
end

function Loot.draw(game, player, requested, decrease, seed)
    if sampling or requested < 0 then return end
    sampling = true
    local ok, item = pcall(resolve, game, player, requested, decrease, seed)
    sampling = false
    if not ok then error(item, 0) end
    return item
end

return Loot
