local CritSlash = {}

local normalStyles = { "Thin", "Split", "Twin" }
local critStyles = { "Original", "Burst" }
local normalBag, critBag, waveBag
local normalColor

function CritSlash.reset()
    normalBag, critBag, waveBag = {}, {}, {}
end
CritSlash.reset()

local function drawStyle(bag, styles, seed, used)
    if not bag.remaining or #bag.remaining == 0 then
        bag.remaining = { table.unpack(styles) }
    end
    local eligible = {}
    for i, style in ipairs(bag.remaining) do
        if style ~= bag.last and not (used and used[style]) then
            eligible[#eligible + 1] = i
        end
    end
    -- The low part of the effect seed already supplies the cut angle.
    local index = eligible[1 + (seed // 360) % #eligible]
    bag.last = table.remove(bag.remaining, index)
    return bag.last
end

local function playClip(flash, clip)
    local sprite = flash:GetSprite()
    sprite:Load("gfx/longsword_hit_slash.anm2", true)
    sprite:Play(clip, true)
    flash.SpriteScale = Vector(1, 1)
end

function CritSlash.spawn(position, direction)
    local flash = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.TEAR_POOF_A, 23,
        position, Vector.Zero, nil):ToEffect()
    local seed = flash.InitSeed
    if drawStyle(critBag, critStyles, seed) == "Original" then
        flash.SpriteScale = Vector(3.6, 0.6)
        flash:GetSprite().PlaybackSpeed = 1
    else
        playClip(flash, "Burst")
    end
    flash.SpriteRotation = direction:GetAngleDegrees() - 28 + (seed % 25 - 12)
    flash.DepthOffset = 40
    flash:SetTimeout(8)
end

local function spawnNormal(position, bag, spiritContext, stage)
    local flash = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.TEAR_POOF_A, 22,
        position, Vector.Zero, nil):ToEffect()
    local style
    if spiritContext then
        -- All targets struck by one Spirit III cut see its style. When the
        -- global bag refills mid-move, finish the triple with still-unseen cuts.
        local cuts = spiritContext.normalCuts or { used = {} }
        spiritContext.normalCuts = cuts
        if not cuts[stage] then
            cuts[stage] = drawStyle(bag, normalStyles, flash.InitSeed, cuts.used)
            cuts.used[cuts[stage]] = true
        end
        style = cuts[stage]
    else
        style = drawStyle(bag, normalStyles, flash.InitSeed)
    end
    playClip(flash, style)
    if not normalColor then
        normalColor = Color(1, 1, 1, 0.72)
        normalColor:SetColorize(1, 1, 1, 1)
    end
    flash.Color = normalColor
    flash.SpriteRotation = flash.InitSeed % 360
    flash.DepthOffset = 39
    flash:SetTimeout(6)
end

function CritSlash.spawnNormal(position, spiritContext, stage)
    spawnNormal(position, normalBag, spiritContext, stage)
end

function CritSlash.spawnWave(position)
    spawnNormal(position, waveBag)
end

return CritSlash
