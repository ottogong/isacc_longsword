-- One native damage call per target per cut; the sprite is display-only.
local Damage = include("scripts.damage")
local WeaponSize = include("scripts.weapon_size")
local Melee = {}
local baseSize = { x = 1, y = 1, body = 1, reach = 1, width = 1 }

function Melee.new(config)
    return { action = "NONE", hits = {}, config = config }
end

function Melee.clear(state)
    state.action, state.profile, state.direction, state.facing = "NONE", nil, nil, nil
    state.damageContext, state.hits, state.observeHit = nil, {}, nil
    state.landingPosition, state.thrustTarget = nil, nil
    state.gridTargets, state.lastHitStage = nil, nil
end

local function directionName(direction)
    if direction.X > 0 then return "Right" end
    if direction.X < 0 then return "Left" end
    return direction.Y < 0 and "Up" or "Down"
end

function Melee.setDirection(state, direction)
    state.direction = Vector(direction.X, direction.Y)
    state.facing = directionName(direction)
end

function Melee.start(state, player, id, direction, blade, config, source)
    -- Only the Helm Breaker derived from this thrust inherits its target.
    local thrustTarget = id == "HELM_BREAKER" and state.action == "SPIRIT_THRUST" and state.thrustTarget
    Melee.clear(state)
    if thrustTarget then state.thrustTarget = thrustTarget end
    state.action, state.profile = id, config.profiles[id]
    if not state.profile then return end
    Melee.setDirection(state, direction)
    state.damageContext = Damage.snapshot(player, id, blade, state.profile, config, source)
end

local function targetKind(target)
    if target.Type == EntityType.ENTITY_FIREPLACE then
        -- 10 is movable orange fire. Blue, purple, white and coal have other native interactions.
        if (target.Variant == 0 or target.Variant == 1 or target.Variant == 10)
            and target.HitPoints > 0 and not target:IsDead() then return "prop" end
    elseif target.Type == EntityType.ENTITY_MOVABLE_TNT then
        if (target.Variant == 0 or target.Variant == 1)
            and target.HitPoints > 0 and not target:IsDead() then return "prop" end
    elseif target:IsVulnerableEnemy() and not target:IsDead() and not target:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return "enemy"
    end
end

local function hitEntity(state, target, modifier, hitStage, enemy)
    hitStage = hitStage or 1
    if state.hits[target.InitSeed] == hitStage then return end
    -- Mark before TakeDamage: damage callbacks must not produce a second attempt on this target.
    state.hits[target.InitSeed] = hitStage
    local pos = target.Position
    local cue = enemy and state.observeHit and state.observeHit(state, state.damageContext.player, target)
    local event = Damage.apply(state.damageContext, target, modifier, enemy, hitStage)
    event.hitStage = hitStage
    event.huntCue = cue or nil
    if enemy and event.accepted then
        event.position = pos
        if state.action == "SPIRIT_THRUST" then
            state.thrustTarget = { seed = event.target, hash = GetPtrHash(target) }
        end
    end
    return event
end

function Melee.contact(state, player, target, config, hitStage)
    if state.profile and targetKind(target) == "enemy" then
        return hitEntity(state, target, config.damageModifier, hitStage, true)
    end
end

-- Fractions of the move during which a target lies between the two edges on one axis.
local function overlapTimes(offset, travel, low, high)
    if travel == 0 then
        if offset >= low and offset <= high then return 0, 1 end
        return 1, 0
    end
    local first, last = (offset - high) / travel, (offset - low) / travel
    return math.min(first, last), math.max(first, last)
end

local function inRange(state, player, position, targetRadius, length, halfWidth, landingRadius, thrustFrom)
    local profile = state.profile
    local origin = thrustFrom or state.landingPosition or player.Position
    local x, y = position.X - origin.X, position.Y - origin.Y
    if landingRadius then
        local radius = landingRadius + targetRadius
        if x * x + y * y <= radius * radius then return true end
    end
    local forward = x * state.direction.X + y * state.direction.Y
    if profile.mode == "line" then
        local sideways = x * state.direction.Y - y * state.direction.X
        local tip, edge = length + targetRadius, halfWidth + targetRadius
        if forward >= 0 and forward <= tip and math.abs(sideways) <= edge then return true end
        if not thrustFrom then return false end
        -- Sweep the same forward box along actual travel, including sideways pushes by native physics.
        local dx, dy = player.Position.X - origin.X, player.Position.Y - origin.Y
        local along = dx * state.direction.X + dy * state.direction.Y
        local across = dx * state.direction.Y - dy * state.direction.X
        local enterX, leaveX = overlapTimes(forward, along, 0, tip)
        local enterY, leaveY = overlapTimes(sideways, across, -edge, edge)
        return math.max(0, enterX, enterY) <= math.min(1, leaveX, leaveY)
    end
    local radius = length + targetRadius
    return x * x + y * y <= radius * radius
        and (profile.mode == "radial" or forward >= 0)
end

local function activeRange(state, combat, size)
    if not state.profile or combat.action ~= state.action or combat.phase ~= "ACTIVE" then return end
    if state.profile.firstHitFrame and combat.phaseFrame < state.profile.firstHitFrame then return end
    if state.profile.lastHitFrame and combat.phaseFrame > state.profile.lastHitFrame then return end
    size = size or baseSize
    -- Scale the blade first; enemy collision radii stay in world units.
    local scale = state.config.hitAreaScale
    local reach = WeaponSize.bladeScale(size) * scale
    return state.profile.range * reach, (state.profile.width or 0) * size.body * size.width * scale,
        state.profile.landingRadius and state.profile.landingRadius * reach
end

local function gridTargets(room)
    local targets = {}
    -- Grid objects do not appear in GetRoomEntities. Scan the room once per swing.
    for i = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(i)
        local kind = grid and grid:GetType()
        if kind == GridEntityType.GRID_POOP or kind == GridEntityType.GRID_TNT then
            targets[#targets + 1] = { index = i, kind = kind }
        end
    end
    return targets
end

local function damageGridProps(state, player, stage, length, halfWidth, landingRadius, thrustFrom)
    local room = Game():GetRoom()
    state.gridTargets = state.gridTargets or gridTargets(room)
    for _, target in ipairs(state.gridTargets) do
        if target.stage ~= stage then
            local grid = room:GetGridEntity(target.index)
            if grid and grid:GetType() == target.kind
                and grid.State < (target.kind == GridEntityType.GRID_TNT and 4 or 1000) and
                inRange(state, player, grid.Position, 20, length, halfWidth, landingRadius, thrustFrom) then
                target.stage = stage
                -- Native Hurt takes tear-sized damage steps; each grid class applies its own state scale.
                grid:Hurt(1)
            end
        end
    end
end

local function settleCut(state, player, stage, config, events, length, halfWidth, landingRadius, thrustFrom)
    damageGridProps(state, player, stage, length, halfWidth, landingRadius, thrustFrom)
    local thrustLanded = false
    local locked = state.action == "HELM_BREAKER" and state.thrustTarget
    for _, target in ipairs(Isaac.GetRoomEntities()) do
        local kind = targetKind(target)
        local pierced = kind == "enemy" and locked and target.InitSeed == locked.seed and GetPtrHash(target) == locked.hash
        if kind and (kind == "prop" or not thrustLanded) and
            (pierced or inRange(state, player, target.Position, target.Size, length, halfWidth, landingRadius, thrustFrom)) then
            local event = hitEntity(state, target, kind == "enemy" and config.damageModifier or nil, stage, kind == "enemy")
            if event and kind == "enemy" then
                events[#events + 1] = event
                if thrustFrom and event.accepted then thrustLanded = true end
            end
        end
    end
end

function Melee.update(state, player, combat, config, size, thrustFrom)
    local events = {}
    -- An exploding barrel can invoke the player's damage callback inside this very thrust.
    if state.resolving then return events end
    -- Spirit thrust is settled on its movement callback, including its last active segment.
    if state.action == "SPIRIT_THRUST" and not thrustFrom then return events end
    local length, halfWidth, landingRadius = activeRange(state, combat, size)
    if not length then return events end
    if landingRadius and not state.landingPosition then
        state.landingPosition = Vector(player.Position.X, player.Position.Y)
    end
    state.resolving = true
    local last = combat.hitStage or 1
    -- Two or more Helm cuts can fall on this tick. On later ticks only the current cut stays open.
    local first = last
    if combat.helmCuts then
        first = math.min((state.lastHitStage or 0) + 1, last)
        state.lastHitStage = last
    end
    for stage = first, last do
        settleCut(state, player, stage, config, events, length, halfWidth, landingRadius, thrustFrom)
    end
    state.resolving = nil
    return events, length, halfWidth
end

-- The three debug masks are centered 64-pixel squares. The half disc faces right.
local hitAreaSprite
local function drawArea(mask, center, direction, length, width)
    if not hitAreaSprite then
        hitAreaSprite = Sprite()
        hitAreaSprite:Load("gfx/isacc_longsword/hit_area.anm2", true)
    end
    local position = Isaac.WorldToScreen(center)
    local along = Isaac.WorldToScreen(center + direction * length) - position
    local across = Isaac.WorldToScreen(center + Vector(-direction.Y, direction.X) * width) - position
    hitAreaSprite:SetFrame(mask, 0)
    hitAreaSprite.Rotation = math.deg(math.atan(along.Y, along.X))
    hitAreaSprite.Scale = Vector(math.sqrt(along:LengthSquared()) / 64, math.sqrt(across:LengthSquared()) / 64)
    hitAreaSprite:Render(position)
end

local function drawBox(origin, direction, length, halfWidth)
    drawArea("Box", origin + direction * (length / 2), direction, length, 2 * halfWidth)
end

function Melee.renderHitArea(state, player, combat, size, thrustBox)
    if thrustBox then
        drawBox(thrustBox.origin, thrustBox.direction, thrustBox.length, thrustBox.halfWidth)
        if state.action == "SPIRIT_THRUST" then return end
    end
    local length, halfWidth, landingRadius = activeRange(state, combat, size)
    if not length then return end
    local direction = state.direction
    if state.profile.mode == "line" then
        local origin = state.landingPosition or player.Position
        drawBox(origin, direction, length, halfWidth)
        if landingRadius then drawArea("Disc", origin, direction, 2 * landingRadius, 2 * landingRadius) end
    else
        local mask = state.profile.mode == "radial" and "Disc" or "HalfDisc"
        drawArea(mask, player.Position, direction, 2 * length, 2 * length)
    end
end

function Melee.render(state, player, combat, actionFrames, config, size)
    if not state.profile or combat.action ~= state.action or combat.phase ~= "ACTIVE" then return end
    local visual = config.visual
    if not state.sprite then
        state.sprite = Sprite()
        state.sprite:Load(visual.path, true)
    end
    local spin = state.action == "ROUND_SLASH" or state.action == "HELM_BREAKER"
    local animation = spin and visual.spinAnimation or visual.attackAnimation
    local count = spin and visual.spinFrames or visual.attackFrames
    local duration = actionFrames[state.action].active
    local frame = math.min(count - 1, math.floor(combat.phaseFrame * (count - 1) / math.max(1, duration - 1)))
    size = size or baseSize
    -- AttackDown has its length along local Y before rotation; SpinDown sweeps a circle.
    local length = WeaponSize.bladeScale(size)
    local width = spin and length or size.body * size.width
    local previousScale = state.sprite.Scale
    state.sprite.Scale = Vector(visual.scale * width, visual.scale * length)
    state.sprite.Rotation = visual.rotationByFacing[state.facing]
    state.sprite:SetFrame(animation, frame)
    state.sprite:Render(Isaac.WorldToScreen(player.Position) + Vector(visual.offsetX * size.x, visual.offsetY * size.y))
    state.sprite.Scale = previousScale
end

return Melee
