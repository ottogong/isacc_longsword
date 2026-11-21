-- Shared damage math and native settlement; hit timing/target dedup stay with each attack.
local Damage = {}

function Damage.snapshot(player, action, blade, profile, config, source)
    local multipliers = profile.bladeMultipliers or config.bladeMultipliers
    if profile.spiritCombo or (action == "ROUND_SLASH" and source == "SPIRIT_COMBO") then
        multipliers = config.spiritBladeMultipliers
    end
    return {
        player = player, action = action, blade = blade,
        baseDamage = player.Damage,
        moveMultiplier = profile.multiplier,
        hitCount = profile.hitCount or 1,
        bladeMultiplier = multipliers[blade + 1],
        damageFlags = config.damageFlags,
        damageCountdown = config.damageCountdown,
    }
end

function Damage.calculate(context, target, modifier)
    local amount = context.baseDamage * context.moveMultiplier * context.bladeMultiplier
    -- Future item effects can inspect the originating player/action/blade and this target here.
    if modifier then amount = modifier(context, target, amount) end
    return amount / context.hitCount
end

function Damage.critChance(luck, expertBonus, moveBonus)
    local base = math.max(0, math.min(0.5, (1 + luck) / 20))
    return math.min(1, base + (expertBonus or 0) + (moveBonus or 0))
end

function Damage.apply(context, target, modifier, eligibleEnemy, hitStage)
    local amount = Damage.calculate(context, target, modifier)
    local critical = false
    if eligibleEnemy and context.critItemId then
        -- Each Helm Breaker cut rolls once, shared by the enemies caught in that cut.
        local stage = context.action == "HELM_BREAKER" and hitStage or 1
        if context.criticalStage ~= stage then
            local finisher = context.action == "IAI" or context.action == "HELM_BREAKER"
            local chance = Damage.critChance(context.player.Luck, context.jewelAffinity, finisher and context.greavesCritBonus)
            context.critical = context.player:GetCollectibleRNG(context.critItemId):RandomFloat() < chance
            context.criticalStage = stage
        end
        critical = context.critical
        if critical then amount = amount * (context.jewelCritMultiplier or 1.25) end
    end
    local accepted = target:TakeDamage(amount, context.damageFlags,
        EntityRef(context.player), context.damageCountdown)
    return { target = target.InitSeed, damage = amount, accepted = not not accepted,
        critical = critical and not not accepted }
end

return Damage
