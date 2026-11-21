local Size = {}
local Slot = include("scripts.slot_data")
local MAX_BLADE_SCALE = 2

function Size.bladeScale(size)
    -- Cap the combined reach so a body-size bonus cannot push the blade past the limit.
    return math.min(size.body * size.reach, MAX_BLADE_SCALE)
end

function Size.new()
    return { x = 1, y = 1, body = 1, reach = 1, width = 1 }
end

function Size.readBody(size, player)
    local s = player.SpriteScale
    size.x, size.y = s.X, s.Y
    size.body = math.sqrt(math.abs(s.X * s.Y))
end

function Size.reach(player, config)
    return 1 + (player.TearRange / config.baseRange - 1) / config.rangeDivisor
end

function Size.tearParams(player)
    return player:GetTearHitParams(WeaponType.WEAPON_TEARS, 1, 1, nil)
end

-- One clean reference per save slot, independent of who first equips the sword.
function Size.reference(mod, game, player, continued, config)
    local slot = Slot.read(mod)
    local saved = tonumber(slot.isaacTearScale)
    if saved and saved > 0 then return saved end
    if continued or not player or game:GetNumPlayers() ~= 1 or game.Challenge ~= Challenge.CHALLENGE_NULL
        or player:GetPlayerType() ~= PlayerType.PLAYER_ISAAC or player.Damage ~= config.isaacDamage
        or player.TearRange ~= config.baseRange or player:GetTrinket(0) ~= 0
        or player:GetTrinket(1) ~= 0 then return nil end
    local count = player:GetCollectibleCount()
    if count ~= 0 and not (count == 1 and player:HasCollectible(CollectibleType.COLLECTIBLE_D6)) then return nil end
    local scale = Size.tearParams(player).TearScale
    if scale > 0 then
        slot.isaacTearScale = scale
        Slot.write(mod, slot)
        return scale
    end
end

return Size
