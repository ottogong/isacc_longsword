local EarlyHunts = {}

local function isDuke(entity)
    return entity and entity.Type == EntityType.ENTITY_DUKE and entity.Variant == 0
end

local function isGuardFly(target)
    local kind = target.Type
    return kind == EntityType.ENTITY_FLY or kind == EntityType.ENTITY_ATTACKFLY
        or kind == EntityType.ENTITY_MOTER or kind == EntityType.ENTITY_SUCKER
end

-- Read the target before TakeDamage: a lethal hit or phase change can replace
-- its animation or remove the fly. Only accepted observations reach onHit.
function EarlyHunts.observe(melee, player, target)
    if target.Type == EntityType.ENTITY_FAMINE and target.Variant == 0 then
        -- 063.000_famine.anm2: AttackDash loops on the horse; the windup and
        -- dismounted head have separate animations. Charges travel horizontally.
        if target:GetSprite():GetAnimation() ~= "AttackDash" then return end
        local dx = math.abs(player.Position.X - target.Position.X)
        local dy = math.abs(player.Position.Y - target.Position.Y)
        if dy >= 8 and dy >= dx then return { part = "spur", seed = target.InitSeed } end
    elseif melee.action == "ROUND_SLASH" then
        if isDuke(target) then return { part = "duke", seed = target.InitSeed } end
        if isGuardFly(target) then
            local owner = target.SpawnerEntity
            if not isDuke(owner) then owner = target.Parent end
            if isDuke(owner) then return { part = "fly", seed = owner.InitSeed } end
        end
    end
end

function EarlyHunts.onHit(melee, cue)
    if not cue then return end
    if cue.part == "spur" then return "spur" end
    local swing = melee.damageContext
    -- Melee.start allocates a fresh damage context for every individual slash.
    swing.dukeHits = swing.dukeHits or {}
    local first = swing.dukeHits[cue.seed]
    if not first then
        swing.dukeHits[cue.seed] = cue.part
    elseif first ~= cue.part and first ~= "broken" then
        swing.dukeHits[cue.seed] = "broken"
        return "flySuit"
    end
end

return EarlyHunts
