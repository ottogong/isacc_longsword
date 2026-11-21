-- Pure action state and blade settlement; native movement/damage lives outside this module.
local Actions = {}
local priority = {
    CHARGE = 1, FORESIGHT = 1, SPIRIT_THRUST = 1, SPECIAL_SHEATHE = 2,
    NORMAL = 4, THRUST_CYCLE = 4, SPIRIT = 4, IAI = 4, SHEATHED_STEP = 4,
}
local sheatheCancelsRecovery = { NORMAL = true, THRUST = true, RISING = true }

local function emit(events, kind, id, reason, phase)
    events[#events + 1] = { kind = kind, id = id, reason = reason, phase = phase }
    return events[#events]
end

function Actions.new()
    return {
        posture = "SHEATHED_FREE", action = "NONE", phase = "IDLE", phaseFrame = 0,
        chargeFrames = 0, blade = 0, lastRequest = "NONE", reason = "IDLE",
        tick = 0, pending = nil, nextThrust = "THRUST", source = nil,
        attackRate = 1, nextAttackRate = 1, elapsed = 0,
        lastAttackTick = nil, sheatheRemaining = 0, sheathed = true, repeatHeld = {},
        hitAwarded = false,
    }
end

function Actions.interrupt(state, reason, sheathe)
    state.action, state.phase, state.phaseFrame = "NONE", "IDLE", 0
    state.chargeFrames, state.pending, state.source, state.mouseHold = 0, nil, nil, nil
    state.nextThrust, state.lastRequest, state.reason = "THRUST", "NONE", reason
    state.lastAttackTick, state.sheatheRemaining, state.repeatHeld = nil, 0, {}
    state.lastAttackWindow = nil
    state.guardedAction = nil
    state.attackRate, state.elapsed, state.activeTicks = 1, 0, nil
    if sheathe then state.sheathed = true end
    state.posture = state.sheathed and "SHEATHED_FREE" or "DRAWN_FREE"
end

function Actions.enterRoom(state)
    local preserved = state.posture == "SPECIAL_SHEATHE"
    local remaining = state.sheatheRemaining
    local chargePreserved = state.action == "CHARGE" and state.phase == "HOLD"
    local chargeFrames, source, sheathed, mouseHold = state.chargeFrames, state.source, state.sheathed, state.mouseHold
    local attackRate, elapsed = state.attackRate, state.elapsed
    Actions.interrupt(state, "ROOM_CHANGED", true)
    if chargePreserved then
        -- Carry the charge itself, not old buffered attacks or recent-attack qualifications.
        state.action, state.phase, state.chargeFrames = "CHARGE", "HOLD", chargeFrames
        state.source, state.sheathed = source, sheathed
        state.mouseHold = mouseHold
        state.attackRate, state.elapsed = attackRate, elapsed
        state.posture = sheathed and "SHEATHED_FREE" or "DRAWN_FREE"
        state.reason = "ROOM_CHARGE_PRESERVED"
    elseif preserved then
        -- Passing a door ends the step, not the stance or its existing countdown.
        state.posture, state.sheatheRemaining = "SPECIAL_SHEATHE", remaining
        state.reason = "ROOM_SHEATHE_PRESERVED"
    end
    return preserved, chargePreserved
end

local function specialPosture(state)
    return state.posture == "SHEATHE_STARTUP" or state.posture == "SPECIAL_SHEATHE"
end

local function invalidReason(state, id, config)
    if not priority[id] then return "NOT_IMPLEMENTED" end
    if id == "IAI" or id == "SHEATHED_STEP" then
        if not specialPosture(state) then return "SPECIAL_STANCE_ONLY" end
    elseif specialPosture(state) then
        return "SPECIAL_STANCE_LOCKED"
    end
    if id == "SPIRIT_THRUST" and state.blade < 1 then return "BLADE_REQUIRED" end
    if id == "FORESIGHT" or id == "SPECIAL_SHEATHE" then
        if not state.lastAttackTick or state.tick - state.lastAttackTick >= (state.lastAttackWindow or config.recentAttackFrames) then
            return "NO_RECENT_ATTACK"
        end
    end
end

local function setAttackTiming(state, timing, recentAttackFrames)
    local rate = state.attackRate
    local activeEnd = timing.startup + timing.active
    local total = activeEnd + timing.recovery
    -- Round cumulative authored boundaries once; even a very fast hit gets a game update.
    state.activeAt = math.ceil(timing.startup / rate)
    if timing.takeoffTicks then
        -- Even a very fast jump must show a falling pose before it can land.
        state.activeAt = math.max(state.activeAt, math.ceil(timing.takeoffTicks / rate) + 1)
    end
    local hitAt = timing.firstHitFrame and math.ceil(timing.firstHitFrame / rate) or state.activeAt
    if timing.hitStarts then
        for i = 2, #timing.hitStarts do
            hitAt = math.max(hitAt + 1, math.ceil(timing.hitStarts[i] / rate))
        end
        if timing.bonusHitsPerRate then
            local extra = math.floor(math.max(0, state.nextAttackRate - 1) * timing.bonusHitsPerRate + 0.5)
            state.helmCuts = { count = math.min(#timing.hitStarts + extra, timing.maxHits), lastTick = hitAt }
        end
    end
    state.recoveryAt = math.max(hitAt + 1, math.ceil(activeEnd / rate))
    state.finishAt = math.max(state.recoveryAt + 1, math.ceil(total / rate))
    state.activeTicks = state.recoveryAt - state.activeAt
    -- Preserve the real-time input grace left after the move's natural ending.
    state.lastAttackWindow = state.finishAt + (timing.recentAttackFrames or recentAttackFrames) - total
end

local function start(state, id, source, config, events)
    local wasSheathed = state.sheathed
    state.guardedAction = nil
    state.hitAwarded = false
    state.hitStage, state.poseStage, state.helmCuts = nil, nil, nil
    state.mouseHold = nil
    state.action, state.source, state.phaseFrame = id, source, 0
    state.attackRate, state.elapsed, state.activeTicks = 1, 0, nil
    state.chargeFrames, state.sheatheRemaining, state.reason = 0, 0, "STARTED"
    if id == "SPECIAL_SHEATHE" then
        -- Clip 306 starts drawn; seating the blade precedes opening the iai window.
        state.sheathed = false
        state.phase, state.posture, state.repeatHeld = "STARTUP", "SHEATHE_STARTUP", {}
    elseif id == "SHEATHED_STEP" then
        -- Only an actual step renews the stance; requests and movement keys do not.
        state.phase, state.posture, state.sheathed = "MOVE", "SPECIAL_SHEATHE", true
        state.sheatheRemaining = config.sheatheTimeout
    else
        state.sheathed, state.posture = false, "DRAWN_FREE"
        if id == "CHARGE" then
            state.attackRate = state.nextAttackRate
            state.phase = "HOLD"
        else
            local timing = config.frames[id]
            state.attackRate = state.nextAttackRate * (timing.speed or 1)
            state.phase = timing.startup == 0 and "ACTIVE" or "STARTUP"
            state.lastAttackTick = state.tick
            setAttackTiming(state, timing, config.recentAttackFrames)
        end
    end
    if id == "NORMAL" then state.nextThrust = "THRUST" end
    if id == "HELM_BREAKER" then
        -- Experimental settlement: spend on the confirmed hit's automatic follow-up.
        state.blade = state.blade - 1
        emit(events, "blade", id, "HELM_BREAKER_SPEND", state.phase)
    end
    local event = emit(events, "start", id, source, state.phase)
    event.speed = state.attackRate
    if wasSheathed and not state.sheathed and id ~= "SPECIAL_SHEATHE" then event.drewBlade = true end
end

local function raiseBlade(state)
    state.blade = math.min(3, state.blade + 1)
end

-- Called only for damage actually stopped by the native guard callback.
function Actions.confirmCounterGuard(state)
    if state.guardedAction or (state.action ~= "FORESIGHT" and state.action ~= "IAI") then return false end
    state.guardedAction = state.action
    if state.action == "IAI" then raiseBlade(state) end
    return true
end

function Actions.hit(state, config)
    local events = {}
    if state.phase ~= "ACTIVE" then return events end
    if state.action == "ROUND_SLASH" then
        -- One sweep can hit several enemies; its blade award belongs to the move, not each target.
        if not state.hitAwarded then
            state.hitAwarded = true
            raiseBlade(state)
            emit(events, "blade", "ROUND_SLASH", "ROUND_SLASH_HIT", state.phase)
        end
    elseif state.action == "SPIRIT_THRUST" then
        emit(events, "derive", "SPIRIT_THRUST", "HIT_HELM_BREAKER", state.phase)
        start(state, "HELM_BREAKER", "SPIRIT_THRUST_HIT", config, events)
    end
    return events
end

local function spiritSuccessor(state)
    if state.action == "SPIRIT_I" then return "SPIRIT_II"
    elseif state.action == "SPIRIT_II" then return "SPIRIT_III"
    elseif state.action == "SPIRIT_III" then
        -- The red-blade exclusion belongs only to the combo's exit edge.
        return state.blade == 3 and "SPIRIT_I" or "ROUND_SLASH"
    elseif state.action == "ROUND_SLASH" and state.source == "SPIRIT_COMBO" then return "SPIRIT_I" end
end

local function finish(state, config, events)
    local id, nextSpirit = state.action, spiritSuccessor(state)
    state.guardedAction = nil
    if id == "SPECIAL_SHEATHE" or id == "SHEATHED_STEP" then
        state.sheathed, state.posture = true, "SPECIAL_SHEATHE"
        state.sheatheRemaining = config.sheatheTimeout
    else
        state.sheathed = id == "ROUND_SLASH"
        state.posture = state.sheathed and "SHEATHED_FREE" or "DRAWN_FREE"
    end
    state.action, state.phase, state.phaseFrame = "NONE", "IDLE", 0
    state.attackRate, state.elapsed, state.activeTicks = 1, 0, nil
    state.chargeFrames, state.source, state.reason, state.mouseHold = 0, nil, "FINISHED", nil
    emit(events, "end", id, "FINISHED", "IDLE")
    return nextSpirit
end

local function advance(state, held, config, events)
    if state.action == "NONE" then
        if state.posture == "SPECIAL_SHEATHE" then
            state.sheatheRemaining = state.sheatheRemaining - 1
            if state.sheatheRemaining == 0 then
                state.posture, state.reason = "SHEATHED_FREE", "SHEATHE_TIMEOUT"
                emit(events, "timeout", "SPECIAL_SHEATHE", state.reason, "IDLE")
            end
        end
        return nil
    end
    state.elapsed = state.elapsed + 1
    if state.action == "CHARGE" then
        local progress = math.floor(state.elapsed * state.attackRate)
        if state.phase == "RECOVERY" then
            if state.elapsed >= config.chargeRecovery / state.attackRate then return finish(state, config, events) end
            state.phaseFrame = progress
            return nil
        end
        local charging = state.mouseHold and held.MOUSE_PRIMARY == state.mouseHold
            or (not state.mouseHold and held.CHARGE)
        if charging then
            if state.elapsed >= config.chargeFrames / state.attackRate then
                state.chargeFrames, state.reason = config.chargeFrames, "CHARGE_READY"
            else
                state.chargeFrames = math.min(progress, config.chargeFrames - 1)
            end
        elseif state.chargeFrames >= config.chargeFrames then
            start(state, "ROUND_SLASH", "CHARGE_RELEASE", config, events)
        else
            -- Keep the last held pose, including fractional attack speed, for the return animation.
            state.chargeReleaseTime = (state.elapsed - 1) * state.attackRate
            state.phase, state.phaseFrame, state.elapsed, state.reason = "RECOVERY", 0, 0, "CHARGE_EARLY_RELEASE"
            emit(events, "phase", "CHARGE", state.reason, "RECOVERY")
        end
        return nil
    end
    if state.action == "SPECIAL_SHEATHE" or state.action == "SHEATHED_STEP" then
        state.phaseFrame = state.elapsed
        if state.action == "SPECIAL_SHEATHE" and state.phaseFrame == config.sheatheSeatFrame then
            state.sheathed = true
        end
        local duration = state.action == "SPECIAL_SHEATHE" and config.sheatheStartup or config.stepFrames
        if state.elapsed >= duration then return finish(state, config, events) end
        return nil
    end
    if state.elapsed >= state.finishAt then return finish(state, config, events) end
    local frames = config.frames[state.action]
    local phase, first, count
    if state.elapsed < state.activeAt then phase, first, count = "STARTUP", 0, frames.startup
    elseif state.elapsed < state.recoveryAt then phase, first, count = "ACTIVE", frames.startup, frames.active
    else phase, first, count = "RECOVERY", frames.startup + frames.active, frames.recovery end
    if phase ~= state.phase then emit(events, "phase", state.action, "PHASE_COMPLETE", phase) end
    state.phase = phase
    state.phaseFrame = math.max(0, math.min(count - 1, math.floor(state.elapsed * state.attackRate) - first))
    if frames.takeoffTicks and phase == "ACTIVE" and state.elapsed == state.activeAt then
        state.phaseFrame = 0
    end
    if phase == "ACTIVE" and frames.hitStarts then
        -- Preserve the authored poses, including at least one update per original cut.
        local nextStage = (state.poseStage or 0) + 1
        if frames.hitStarts[nextStage] and state.elapsed >= math.ceil(frames.hitStarts[nextStage] / state.attackRate) then
            state.poseStage = nextStage
        end
        local nextStart = frames.hitStarts[state.poseStage + 1]
        if nextStart then state.phaseFrame = math.min(state.phaseFrame, nextStart - first - 1) end
        state.hitStage = state.poseStage
        if state.helmCuts and state.helmCuts.count > #frames.hitStarts then
            -- Fit the extra damage stages between touchdown and the original final cut.
            local span = state.helmCuts.lastTick - state.activeAt
            local age = math.min(state.elapsed - state.activeAt, span)
            state.hitStage = 1 + math.floor(age * (state.helmCuts.count - 1) / span + 0.5)
        end
    end
    -- If one update would skip the entire damaging cut, sample its last hittable pose.
    if phase == "ACTIVE" and state.elapsed == state.activeAt and frames.lastHitFrame then
        state.phaseFrame = math.min(state.phaseFrame, frames.lastHitFrame)
    end
end

local function reject(state, events, id, reason)
    state.reason = reason
    emit(events, "reject", id, reason, state.phase)
end

local function needsHold(id)
    return id == "CHARGE" or id == "SPIRIT"
end

local function canStart(state, id)
    if id == "IAI" or id == "SHEATHED_STEP" then
        return state.action == "NONE" and state.posture == "SPECIAL_SHEATHE"
    end
    if state.action == "NONE" then return true end
    if state.phase ~= "RECOVERY" then return false end
    if state.action == "FORESIGHT" or id == "SPIRIT_THRUST" then return true end
    if id == "SPECIAL_SHEATHE" then return sheatheCancelsRecovery[state.action] == true end
    if id == "SPIRIT" then return state.source == "SPIRIT_COMBO" end
    if id == "THRUST_CYCLE" then
        return (state.action == "THRUST" and state.nextThrust == "RISING")
            or (state.action == "RISING" and state.nextThrust == "THRUST")
    end
    return priority[id] == 1 and state.action ~= id
end

local function startIntent(state, request, nextSpirit, held, config, events)
    if state.action ~= "NONE" then
        local reason = state.action == "FORESIGHT" and "FORESIGHT_RECOVERY_LINK"
            or request.id == "SPECIAL_SHEATHE" and "SHEATHE_RECOVERY_LINK"
            or request.id == "THRUST_CYCLE" and "THRUST_CYCLE_LINK"
            or request.id == "SPIRIT" and "SPIRIT_COMBO_LINK" or "P1_" .. request.id
        emit(events, "cancel", state.action, reason, state.phase)
    end
    local id, source = request.id, request.source
    if id == "THRUST_CYCLE" then
        id = state.nextThrust
        state.nextThrust = id == "THRUST" and "RISING" or "THRUST"
    elseif id == "SPIRIT" then
        id, source = nextSpirit or spiritSuccessor(state) or "SPIRIT_I", "SPIRIT_COMBO"
    end
    start(state, id, source, config, events)
    if id == "NORMAL" then state.mouseHold = request.mouseHold end
    if (id == "CHARGE" or id == "FORESIGHT" or request.id == "THRUST_CYCLE") and held[request.id] then
        state.repeatHeld[request.id] = true
    end
end

function Actions.update(state, packet, config, thrustContact)
    local events, held = {}, packet.held or {}
    -- Keep buffer/derivation deadlines on the same clock as the held contact pose.
    if not packet.hitstop then state.tick = state.tick + 1 end
    state.nextAttackRate = packet.attackRate or 1
    if thrustContact then events = Actions.hit(state, config) end
    for id in pairs(state.repeatHeld) do
        if not held[id] then state.repeatHeld[id] = nil end
    end
    -- Input is sampled on the displayed pose, including the last recovery pose.
    if state.guardedAction == "FORESIGHT" and held.SPIRIT then
        for _, request in ipairs(packet.pressed or {}) do
            if request.id == "SPIRIT" and request.foresightCounter
                and not (request.fromPocket and packet.cancelPocket) then
                state.pending, state.lastRequest = nil, "SPIRIT"
                emit(events, "derive", "FORESIGHT", "GUARD_ROUND_SLASH", state.phase)
                start(state, "ROUND_SLASH", "FORESIGHT_COUNTER", config, events)
                return events
            end
        end
    end
    local nextSpirit
    -- Settle the last travelled active segment before advancing; a new helm keeps its full startup.
    if #events == 0 and not packet.keepOpeningPose and not packet.hitstop then
        nextSpirit = advance(state, held, config, events)
    end

    local pending = state.pending
    if pending then
        -- A middle-button takeover keeps the shared request when native pocket use is revoked.
        if packet.independentIntents and packet.independentIntents[pending.id] then
            pending.fromPocket = false
        end
        local reason = invalidReason(state, pending.id, config)
        -- A fresh tap queues one ordinary spirit link. Consuming a hold as a modifier
        -- drops the intent without a physical release and cannot create this tap.
        if pending.id == "SPIRIT" and (state.source == "SPIRIT_COMBO" or state.action == "FORESIGHT") and not held.SPIRIT then
            for _, release in ipairs(packet.released or {}) do
                if release.id == "SPIRIT" then pending.spiritTap = true end
            end
        end
        if packet.cancelPocket and pending.fromPocket then reason = "POCKET_CANCELLED"
        elseif state.tick > pending.expires then reason = "BUFFER_EXPIRED"
        elseif needsHold(pending.id) and not held[pending.id] and not pending.spiritTap then reason = "HOLD_RELEASED" end
        if reason then
            reject(state, events, pending.id, reason)
            state.pending = nil
        end
    end

    -- Check eligibility before priority: an illegal P1 must not hide a legal iai.
    -- One slot remains: higher priority wins; the latest equal-priority press wins.
    for _, request in ipairs(packet.pressed or {}) do
        state.lastRequest = request.id
        local reason = invalidReason(state, request.id, config)
        if reason then
            reject(state, events, request.id, reason)
        elseif needsHold(request.id) and not held[request.id] then
            reject(state, events, request.id, "HOLD_RELEASED")
        elseif state.pending and priority[request.id] > priority[state.pending.id] then
            reject(state, events, request.id, "HIGHER_PRIORITY_BUFFER")
        else
            local expiry = state.tick + config.bufferFrames
            local timing = config.frames[state.action]
            if timing and (timing.bufferThrough or state.attackRate < 1) then
                -- Keep a new press until its first legal link on a long authored clip.
                local link = priority[request.id] == 1 and state.recoveryAt or state.finishAt
                expiry = math.max(expiry, state.lastAttackTick + link)
            end
            state.pending = { id = request.id, source = request.source, fromPocket = request.fromPocket,
                mouseHold = request.mouseHold,
                expires = expiry }
            state.reason = "BUFFERED"
            emit(events, "buffer", request.id, "BUFFERED", state.phase)
        end
    end

    local candidate
    pending = state.pending
    if pending and canStart(state, pending.id) then candidate = pending end
    -- A hold renews only after this physical hold actually started its move.
    -- Thus an expired first charge press cannot spring back to life later.
    for _, id in ipairs({ "CHARGE", "FORESIGHT", "THRUST_CYCLE" }) do
        -- An automatic cut must leave room for a buffered move that needs normal recovery to finish.
        local deferCycle = id == "THRUST_CYCLE" and pending and state.action ~= "NONE"
        if state.repeatHeld[id] and held[id] and not invalidReason(state, id, config)
            and not deferCycle and canStart(state, id)
            and (not candidate or state.action ~= "FORESIGHT" and priority[id] < priority[candidate.id]) then
            candidate = { id = id, source = "HELD_REPEAT" }
        end
    end
    if candidate then
        if candidate == pending then state.pending = nil end
        state.lastRequest = candidate.id
        startIntent(state, candidate, nextSpirit, held, config, events)
    elseif not pending and state.action == "NORMAL" and state.phase == "RECOVERY"
        and state.mouseHold and held.MOUSE_PRIMARY == state.mouseHold then
        -- Only the hold that started this slash may cut its recovery; deliberate inputs win.
        local mouseCharge = state.mouseHold
        emit(events, "cancel", "NORMAL", "HELD_PRIMARY_CHARGE", state.phase)
        start(state, "CHARGE", "MOUSE_PRIMARY", config, events)
        state.mouseHold = mouseCharge
    elseif not pending and held.SPIRIT and canStart(state, "SPIRIT") and not invalidReason(state, "SPIRIT", config) then
        state.lastRequest = "SPIRIT"
        startIntent(state, { id = "SPIRIT", source = "HELD" }, nextSpirit, held, config, events)
    end
    return events
end

return Actions
