local MonstroHunt = {}

-- Frame of the native Land event in 020.000_monstro.anm2.
local landingFrame = { JumpDown = 32, Walk = 22 }

local function landingSource(source)
    local entity = source and source.Entity
    if not entity then return end
    local projectile = entity.Type == EntityType.ENTITY_PROJECTILE
    local boss = entity
    if projectile then
        boss = entity.SpawnerEntity
        if not boss or entity.FrameCount > 5 then return end
    end
    if boss.Type ~= EntityType.ENTITY_MONSTRO or boss.Variant ~= 0 then return end
    local sprite = boss:GetSprite()
    local animation, frame = sprite:GetAnimation(), sprite:GetFrame()
    local land = landingFrame[animation]
    -- JumpDown also emits a burst two animation frames after impact. Ordinary spit is Taunt.
    if projectile and (animation ~= "JumpDown" or frame < 34) then return end
    if land and frame >= land - 1 and frame <= land + 8 then return boss end
end

-- Called once for the first real guard of the action. The sweep's damage snapshot
-- is discarded when another action starts, including a cancelled Foresight.
function MonstroHunt.onGuard(run, player, combat, melee, source)
    if not run then return end
    if combat.action == "FORESIGHT" and not run.tooth then
        local boss = landingSource(source)
        if boss and melee.action == "FORESIGHT" then
            melee.damageContext.landingMonstroSeed = boss.InitSeed
            melee.damageContext.landingPosition = boss.Position
            return "landing_guard"
        end
    elseif combat.action == "IAI" and run.tooth then
        for _, angle in ipairs({ -15, 0, 15 }) do
            local velocity = melee.direction:Rotated(angle) * 10
            local tear = Isaac.Spawn(EntityType.ENTITY_TEAR, TearVariant.BLOOD, 0,
                player.Position, velocity, player):ToTear()
            tear.CollisionDamage = player.Damage
        end
        return "tooth_volley"
    end
end

function MonstroHunt.brokeTooth(run, melee, hit)
    if not run or run.tooth or melee.action ~= "FORESIGHT" or not hit.accepted then return false end
    local swing = melee.damageContext
    if hit.target ~= swing.landingMonstroSeed then return false end
    swing.landingMonstroSeed = nil
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.TOOTH_PARTICLE, 0, swing.landingPosition,
        melee.direction * 4, nil)
    return true
end

return MonstroHunt
