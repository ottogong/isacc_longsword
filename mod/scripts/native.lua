local Native = {}

function Native.inputDevice(player)
    local index = player.ControllerIndex
    -- J510 exposes the engine's signed keyboard ID (-2) to Lua as a uint32.
    if index >= 0x80000000 then index = index - 0x100000000 end
    if index == -2 or index == 0 then return "keyboard" end
    if index > 0 then return "gamepad" end
    return "unknown"
end

function Native.attackRate(player, baseFireRate)
    return math.max(1, (30 / (player.MaxFireDelay + 1)) / baseFireRate)
end

local shootingActions = {
    [ButtonAction.ACTION_SHOOTLEFT] = true, [ButtonAction.ACTION_SHOOTRIGHT] = true,
    [ButtonAction.ACTION_SHOOTUP] = true, [ButtonAction.ACTION_SHOOTDOWN] = true,
}
local movementActions = {
    [ButtonAction.ACTION_LEFT] = true, [ButtonAction.ACTION_RIGHT] = true,
    [ButtonAction.ACTION_UP] = true, [ButtonAction.ACTION_DOWN] = true,
}
function Native.filterInput(game, entity, hook, action, itemId, walkingLocked, aimConfig, motion, mouseConfig, lockedHead)
    if not (shootingActions[action] or (walkingLocked and movementActions[action]))
        or not entity then return nil end
    local player = entity:ToPlayer()
    if not Native.guard(game, player, itemId, true) then return nil end
    local device = Native.inputDevice(player)
    local mouseMode = device == "keyboard" and mouseConfig and mouseConfig.enabled
    if shootingActions[action] and ((device == "gamepad" and aimConfig) or mouseMode) then
        -- Feed native head direction while blindfold still prevents player tears.
        -- Raw Input reads below do not read back this callback's replacement values.
        local facing = lockedHead or (mouseMode and motion.facing or Native.controllerFacing(player, motion))
        local values = {
            [ButtonAction.ACTION_SHOOTLEFT] = math.max(0, -facing.X),
            [ButtonAction.ACTION_SHOOTRIGHT] = math.max(0, facing.X),
            [ButtonAction.ACTION_SHOOTUP] = math.max(0, -facing.Y),
            [ButtonAction.ACTION_SHOOTDOWN] = math.max(0, facing.Y),
        }
        if hook == InputHook.GET_ACTION_VALUE then return values[action] end
        if hook == InputHook.IS_ACTION_PRESSED then return values[action] > 0 end
        return false
    end
    -- MC_INPUT_ACTION alters engine input only; Input reads still feed our move buttons.
    if hook == InputHook.GET_ACTION_VALUE then return 0 end
    return false
end

function Native.readMovementIntent(player)
    local controller = player.ControllerIndex
    -- Read raw actions: engine movement is locked in sheathe, but step selection is not.
    return Vector(Input.GetActionValue(ButtonAction.ACTION_RIGHT, controller)
            - Input.GetActionValue(ButtonAction.ACTION_LEFT, controller),
        Input.GetActionValue(ButtonAction.ACTION_DOWN, controller)
            - Input.GetActionValue(ButtonAction.ACTION_UP, controller))
end

function Native.newMotion()
    return { facing = Vector(0, 1), movementFacing = Vector(0, 1),
        movement = Vector(0, 0), aim = Vector(0, 0),
        stepDirection = nil, stepFacing = "NONE" }
end

function Native.mouseScreenPosition()
    -- Native false coordinates do not reliably match Sprite.Render's coordinate space.
    return Isaac.WorldToScreen(Input.GetMousePosition(true))
end

function Native.readAimIntent(player, config, mouseConfig)
    local device = Native.inputDevice(player)
    if device == "keyboard" and mouseConfig and mouseConfig.enabled then
        local position = Native.mouseScreenPosition()
        local origin = Isaac.WorldToScreen(player.Position)
        -- Both points share the cursor's display space; movement buttons never choose aim.
        local offset = Vector(position.X - origin.X, position.Y - origin.Y)
        local sample = { source = "mouse_relative", mouseX = position.X, mouseY = position.Y,
            playerScreenX = origin.X, playerScreenY = origin.Y,
            mouseOffsetX = offset.X, mouseOffsetY = offset.Y }
        if offset:LengthSquared() <= mouseConfig.minDistance * mouseConfig.minDistance then
            return Vector(0, 0), sample
        end
        return offset, sample
    end
    if device ~= "gamepad" or not config then return Vector(0, 0), nil end
    local controller = player.ControllerIndex
    -- Physical axis reads stay independent when a face button saturates/cancels SHOOT.
    local sample = {
        axisLeft = Input.GetButtonValue(config.axes.left, controller),
        axisRight = Input.GetButtonValue(config.axes.right, controller),
        axisUp = Input.GetButtonValue(config.axes.up, controller),
        axisDown = Input.GetButtonValue(config.axes.down, controller),
        -- Aggregates are diagnostic only; they must never choose the weapon's facing.
        aggregateX = Input.GetActionValue(ButtonAction.ACTION_SHOOTRIGHT, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTLEFT, controller),
        aggregateY = Input.GetActionValue(ButtonAction.ACTION_SHOOTDOWN, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTUP, controller),
    }
    local aim = Vector(sample.axisRight - sample.axisLeft, sample.axisDown - sample.axisUp)
    if aim:LengthSquared() <= config.deadzone * config.deadzone then
        return Vector(0, 0), sample
    end
    return aim, sample
end

local mouseCursorSprite
function Native.renderMouseCursor(player, config)
    if not config.enabled or Native.inputDevice(player) ~= "keyboard" then return end
    if not mouseCursorSprite then
        mouseCursorSprite = Sprite()
        mouseCursorSprite:Load(config.path, true)
    end
    mouseCursorSprite.Scale = Vector(config.scale, config.scale)
    mouseCursorSprite:SetFrame(config.animation, config.frame)
    mouseCursorSprite:Render(Native.mouseScreenPosition())
end

local chargeIndicatorSprite
function Native.renderChargeIndicator(player, combat, actionConfig, config)
    if not config.enabled or combat.action ~= "CHARGE" or combat.phase ~= "HOLD" then return end
    if not chargeIndicatorSprite then
        chargeIndicatorSprite = Sprite()
        chargeIndicatorSprite:Load(config.path, true)
    end
    -- Display the action's actual progress; rendering never advances charge or its own timer.
    if combat.chargeFrames >= actionConfig.chargeFrames then
        chargeIndicatorSprite:SetFrame(config.readyAnimation, combat.tick % config.readyFrames)
    else
        chargeIndicatorSprite:SetFrame(config.chargingAnimation,
            math.floor(combat.chargeFrames / actionConfig.chargeFrames * config.chargingLastFrame))
    end
    chargeIndicatorSprite.Scale = Vector(config.scale, config.scale)
    local position = Isaac.WorldToScreen(player.Position)
    chargeIndicatorSprite:Render(Vector(position.X + config.offsetX, position.Y + config.offsetY))
end

function Native.pocketBladePosition(player, config)
    -- Cards/pills ahead of the sword move its HUD icon up the pocket stack.
    -- This visual index never authorizes a pocket action.
    local row = 1
    while row < #config.rowRise and (player:GetCard(row - 1) ~= 0 or player:GetPill(row - 1) ~= 0) do
        row = row + 1
    end
    local offset = Options.HUDOffset
    local position = Vector(Isaac.GetScreenWidth() - config.right - offset * config.insetX,
        Isaac.GetScreenHeight() - config.bottom - offset * config.insetY - config.rowRise[row])
    return position, row == 1
end

local bladeBarSprite, bladeColors
function Native.renderBladeBar(position, blade, config)
    if not bladeBarSprite then
        bladeBarSprite = Sprite()
        bladeBarSprite:Load(config.path, true)
        bladeColors = { [0] = Color(1, 1, 1, 1, 0, 0, 0) }
        for level, rgb in ipairs(config.colors) do
            local color = Color(1, 1, 1, 1, 0, 0, 0)
            color:SetColorize(rgb[1], rgb[2], rgb[3], 1)
            bladeColors[level] = color
        end
    end
    bladeBarSprite.Color = bladeColors[0]
    bladeBarSprite:SetFrame("BarEmpty", 0)
    bladeBarSprite:Render(position)
    if blade > 0 then
        bladeBarSprite.Color = bladeColors[blade]
        bladeBarSprite:SetFrame("BarFull", 0)
        bladeBarSprite:Render(position)
        bladeBarSprite.Color = bladeColors[0]
    end
    bladeBarSprite:SetFrame("BarOverlay1", 0)
    bladeBarSprite:Render(position)
end

local function cardinalDirection(movement, previous)
    local x, y = movement.X, movement.Y
    if x == 0 and y == 0 then return previous end
    -- Equal axes keep the held facing instead of flickering between two directions.
    if math.abs(x) == math.abs(y) and (previous.X * x > 0 or previous.Y * y > 0) then
        return previous
    end
    if math.abs(x) > math.abs(y) then return Vector(x > 0 and 1 or -1, 0) end
    return Vector(0, y > 0 and 1 or -1)
end

local function directionName(direction)
    if direction.X < 0 then return "LEFT" end
    if direction.X > 0 then return "RIGHT" end
    return direction.Y < 0 and "UP" or "DOWN"
end

Native.directionName = directionName

function Native.controllerFacing(player, motion)
    -- POST_UPDATE samples the physical stick; engine callbacks consume its last sample.
    local aim = motion.aim
    local intent = (aim.X ~= 0 or aim.Y ~= 0) and aim or Native.readMovementIntent(player)
    return cardinalDirection(intent, motion.facing)
end

function Native.stopStep(player, motion)
    if motion.stepDirection and player then player.Velocity = Vector(0, 0) end
    motion.stepDirection = nil
end

function Native.updateMotion(player, motion, stepping, started, distance, frames, walkingLocked, aimConfig, mouseConfig, attackDirection)
    local movement = walkingLocked and Native.readMovementIntent(player) or player:GetMovementInput()
    local aim, aimSample = Native.readAimIntent(player, aimConfig, mouseConfig)
    motion.aimSample = aimSample
    motion.movement, motion.aim = movement, aim
    motion.movementFacing = cardinalDirection(movement, motion.movementFacing)
    local mouseMode = Native.inputDevice(player) == "keyboard" and mouseConfig and mouseConfig.enabled
    -- A cursor near the player's center keeps facing without a WASD fallback.
    local facingIntent = (mouseMode or aim.X ~= 0 or aim.Y ~= 0) and aim or movement
    motion.facing = cardinalDirection(facingIntent, motion.facing)
    if attackDirection then
        motion.stepDirection = attackDirection
    elseif started then
        -- Aiming must not redirect a movement-selected sheathed step.
        motion.stepDirection = motion.movementFacing
        motion.stepFacing = directionName(motion.stepDirection)
    end
    if stepping then
        -- Use velocity, not teleportation: native wall/grid collision remains in charge.
        player.Velocity = motion.stepDirection * (distance / frames)
    else
        Native.stopStep(player, motion)
        -- Remove the entering momentum as well as ongoing native walking input.
        if walkingLocked then player.Velocity = Vector(0, 0) end
    end
    return movement
end

function Native.stopThrust(player, motion)
    if motion.thrustMoving and player then player.Velocity = Vector(0, 0) end
    motion.thrustMoving, motion.thrustDirection, motion.thrustPosition = false, nil, nil
end

function Native.settleHelmPosition(player, flight, radius)
    local position = player.Position
    -- Accept the step the engine actually resolved. At rest, keep the last reachable spot.
    if flight.moving and (position - flight.origin):LengthSquared() <= radius ^ 2 + 0.001 then
        flight.ground = position
    elseif (position - flight.ground):LengthSquared() > 0 then
        player.Position = flight.ground
    end
end

function Native.updateHelm(player, motion, phase, config, previousFacing)
    local flight = motion.helm
    if flight.landed then return end

    local velocity = Vector(0, 0)
    if phase == "ACTIVE" then
        flight.landed = true
    elseif motion.movement:LengthSquared() > 0 then
        local input = motion.movement
        if input:LengthSquared() > 1 then input = input:Normalized() end
        local offset = flight.ground - flight.origin + input * (config.radius / config.framesToEdge)
        if offset:LengthSquared() > config.radius ^ 2 then offset = offset:Normalized() * config.radius end
        velocity = flight.origin + offset - flight.ground
    end
    player.Velocity = velocity
    flight.moving = velocity:LengthSquared() > 0
    -- Sample the landing tick as well. A centered stick keeps the cut facing even while moving.
    return cardinalDirection(motion.aim, previousFacing)
end

function Native.updateThrust(player, motion, combat, started, config, activeFrames)
    if started then
        -- A fresh thrust can cancel the previous lunge on its first recovery tick.
        Native.stopThrust(player, motion)
        motion.thrustDirection = motion.facing
    end
    if combat.action ~= "SPIRIT_THRUST" then
        Native.stopThrust(player, motion)
        return nil
    end
    if combat.phase ~= "ACTIVE" then
        if motion.thrustMoving then Native.stopThrust(player, motion) end
        return nil
    end
    local position = player.Position
    local enteringActive = not motion.thrustMoving
    motion.thrustPosition, motion.thrustMoving = position, true
    player.Velocity = motion.thrustDirection * (config.distance / activeFrames)
    return enteringActive
end

function Native.guard(game, player, itemId, requireHeld)
    if not REPENTANCE then return false, "REPENTANCE_REQUIRED" end
    if not player then return false, "NO_PLAYER" end
    -- This rejects multiple player entities; it is not a proven online detector.
    if game:GetNumPlayers() ~= 1 then return false, "SINGLE_ENTITY_ONLY" end
    if type(itemId) ~= "number" or itemId <= 0 then
        return false, "ITEM_NOT_REGISTERED"
    end
    if requireHeld and player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= itemId then
        return false, "NOT_HELD_IN_PERMANENT_POCKET"
    end
    return true, "OK"
end

function Native.canGuardDamage(game, player, itemId, flags)
    -- Keep native invincibility-bypassing costs and fake damage effect triggers intact.
    return flags & (DamageFlag.DAMAGE_INVINCIBLE | DamageFlag.DAMAGE_FAKE) == 0
        and Native.guard(game, player, itemId, true)
end

function Native.isLostGuardContact(collider)
    if collider:IsDead() or collider.Type == EntityType.ENTITY_FIREPLACE then return false end
    local projectile = collider:ToProjectile()
    if projectile then
        -- Ordinary enemy projectiles have CollisionDamage 0 in entities2.xml.
        return not projectile:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER)
    end
    local npc = collider:ToNPC()
    if not npc or not npc:IsEnemy() or npc.CollisionDamage <= 0 then return false end
    local class = npc.EntityCollisionClass
    return class ~= EntityCollisionClass.ENTCOLL_NONE and class ~= EntityCollisionClass.ENTCOLL_ENEMIES
        and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and not npc:HasEntityFlags(EntityFlag.FLAG_CHARM)
end

function Native.inActionGuardWindow(combat, windows)
    local phases = windows[combat.action]
    return phases ~= nil and phases[combat.phase] == true
        and (not phases.lastFrame or combat.phaseFrame <= phases.lastFrame)
end

function Native.inspect(game, player, itemId)
    local data = {
        players = game:GetNumPlayers(), challenge = game.Challenge,
        itemId = itemId, selected = "UNKNOWN", held = false,
    }
    if not player then return data end
    data.playerType = player:GetPlayerType()
    data.canShoot = player:CanShoot()
    data.hearts = player:GetHearts()
    data.maxHearts = player:GetMaxHearts()
    data.soulHearts = player:GetSoulHearts()
    data.boneHearts = player:GetBoneHearts()
    data.brokenHearts = player:GetBrokenHearts()
    data.coins = player:GetNumCoins()
    data.bombs = player:GetNumBombs()
    data.keys = player:GetNumKeys()
    data.collectibles = player:GetCollectibleCount()
    data.active, data.charge, data.cards, data.pills = {}, {}, {}, {}
    for slot = 0, 3 do
        data.active[slot + 1] = player:GetActiveItem(slot)
        data.charge[slot + 1] = player:GetActiveCharge(slot)
        data.cards[slot + 1] = player:GetCard(slot)
        data.pills[slot + 1] = player:GetPill(slot)
    end
    data.held = type(itemId) == "number" and itemId > 0
        and data.active[ActiveSlot.SLOT_POCKET + 1] == itemId
    -- Card/Pill slot values are observations, not proof of the selected active.
    return data
end

function Native.equip(game, player, itemId)
    local allowed, reason = Native.guard(game, player, itemId, false)
    if not allowed then return { ok = false, reason = reason } end
    local current = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
    if current ~= 0 and current ~= itemId then
        return { ok = false, reason = "POCKET_OCCUPIED", occupant = current }
    end
    if current == itemId then return { ok = true, reason = "ALREADY_EQUIPPED" } end
    local before = Native.inspect(game, player, itemId)
    local ok, err = pcall(function()
        player:SetPocketActiveItem(itemId, ActiveSlot.SLOT_POCKET, true)
    end)
    local after = Native.inspect(game, player, itemId)
    return {
        ok = ok and after.held,
        reason = not ok and tostring(err) or (after.held and "EQUIPPED" or "EQUIP_NOT_OBSERVED"),
        before = before, after = after,
    }
end

local function applyBlindfold(game, player, itemId)
    local before = Native.inspect(game, player, itemId)
    local previousChallenge = game.Challenge
    -- Recompute native blindfold for the same character, then restore this run's challenge.
    local ok, err = pcall(function()
        game.Challenge = Challenge.CHALLENGE_SOLAR_SYSTEM
        player:ChangePlayerType(before.playerType)
    end)
    game.Challenge = previousChallenge
    local after = Native.inspect(game, player, itemId)
    return {
        ok = ok and not after.canShoot,
        reason = not ok and tostring(err) or (after.canShoot and "BLINDFOLD_NOT_OBSERVED" or "BLINDFOLD_OBSERVED"),
        before = before, after = after,
    }
end

function Native.ensureBlindfold(game, player, itemId)
    local allowed, reason = Native.guard(game, player, itemId, true)
    if not allowed then return { ok = false, reason = reason } end
    if not player:CanShoot() then return { ok = true, reason = "ALREADY_CANNOT_SHOOT" } end
    return applyBlindfold(game, player, itemId)
end

-- Retained explicit M0 command; automatic mode uses ensureBlindfold without probe restrictions.
function Native.blindfold(game, player, itemId, session)
    local allowed, reason = Native.guard(game, player, itemId, true)
    if not allowed then return { ok = false, reason = reason } end
    if session.blindfoldAttempted then return { ok = false, reason = "ALREADY_ATTEMPTED" } end
    if player:GetPlayerType() ~= PlayerType.PLAYER_ISAAC then
        return { ok = false, reason = "BLINDFOLD_PROBE_ISAAC_ONLY" }
    end
    if game.Challenge ~= Challenge.CHALLENGE_NULL then
        return { ok = false, reason = "BLINDFOLD_PROBE_NO_CHALLENGE" }
    end
    if not player:CanShoot() then return { ok = false, reason = "ALREADY_CANNOT_SHOOT" } end
    session.blindfoldAttempted = true
    return applyBlindfold(game, player, itemId)
end

function Native.readPocketInput(player, pocket)
    local down = Input.IsActionPressed(ButtonAction.ACTION_PILLCARD, player.ControllerIndex)
    -- Switching the selected pocket item ends the old sword hold without swallowing Ctrl.
    if Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex) then
        pocket.armed, pocket.pending, pocket.blocked = false, false, true
    end
    local active = not pocket.blocked and (pocket.pending or (pocket.armed and down))
    local cancelled = pocket.blocked
    pocket.pending = false
    if not down then pocket.armed, pocket.blocked = false, false end
    return not not active, cancelled, down
end

function Native.readCombatInput(player, bindings, pocketActive)
    local values = {}
    local device = Native.inputDevice(player)
    for source, binding in pairs(bindings) do
        if binding.pocket then
            -- Only the sword's native use callback may arm this input, never raw Q alone.
            values[source] = not not pocketActive
        elseif device == "gamepad" and binding.button then
            -- Physical face buttons choose moves, independently of native shooting actions.
            values[source] = Input.IsButtonPressed(binding.button, player.ControllerIndex)
        elseif binding.action then
            -- A shooting action alone is never a controller move binding: it also includes the stick.
            values[source] = not (device == "gamepad" and shootingActions[binding.action])
                and Input.IsActionPressed(binding.action, player.ControllerIndex) or false
        elseif binding.key then
            values[source] = Input.IsButtonPressed(binding.key, 0)
        else
            values[source] = false
        end
        if not binding.pocket and device == "keyboard" and binding.mouse ~= nil then
            -- Merge the same intent so releasing one device cannot release the other held button.
            values[source] = values[source] or Input.IsMouseBtnPressed(binding.mouse)
        end
    end
    return values
end

function Native.bindingLabel(binding)
    if binding.pocket then return "Pocket" end
    local label
    if binding.key then
        for name, value in pairs(Keyboard) do
            if value == binding.key then label = name:gsub("^KEY_", ""); break end
        end
    elseif binding.action then
        for name, value in pairs(ButtonAction) do
            if value == binding.action then label = name:gsub("^ACTION_", ""); break end
        end
    end
    if binding.mouse ~= nil then
        local mouseLabel = "Mouse" .. binding.mouse
        return label and (label .. "+" .. mouseLabel) or mouseLabel
    end
    return label or "-"
end

function Native.readDirections(player, directions)
    local values = {}
    for _, direction in ipairs(directions) do
        values[direction.name] = Input.IsActionPressed(direction.action, player.ControllerIndex)
    end
    return values
end

return Native
