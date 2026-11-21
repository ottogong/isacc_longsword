local InputIntents = {}

-- Experimental stable emission order; action arbitration owns gameplay priority.
local SOURCES = { "UP", "MOUSE_PRIMARY", "RIGHT", "DOWN", "LEFT", "SPIRIT", "FORESIGHT", "SPECIAL_SHEATHE", "SPIRIT_THRUST" }
local SINGLE = {
    UP = "NORMAL", MOUSE_PRIMARY = "NORMAL", RIGHT = "THRUST_CYCLE", DOWN = "SHEATHED_STEP", LEFT = "CHARGE",
    FORESIGHT = "FORESIGHT", SPECIAL_SHEATHE = "SPECIAL_SHEATHE", SPIRIT_THRUST = "SPIRIT_THRUST",
}
local COMBO = { UP = "SPIRIT_THRUST", MOUSE_PRIMARY = "SPIRIT_THRUST", RIGHT = "FORESIGHT", DOWN = "SPECIAL_SHEATHE" }
local ATTACK_SOURCES = { UP = true, MOUSE_PRIMARY = true, RIGHT = true, LEFT = true, SPIRIT = true }

local function iaiPosture(posture)
    return posture == "SPECIAL_SHEATHE" or posture == "SHEATHE_STARTUP"
end

local function spiritIntent(posture)
    if iaiPosture(posture) then return "IAI" end
    return "SPIRIT"
end

local function intentFor(source, raw, posture, skillDown)
    if ATTACK_SOURCES[source] and iaiPosture(posture) then return "IAI" end
    if source == "SPIRIT" then return spiritIntent(posture) end
    if (raw.MODIFIER or skillDown) and COMBO[source] then return COMBO[source] end
    return SINGLE[source]
end

function InputIntents.new()
    return { previous = {}, latched = {} }
end

function InputIntents.reset(state, raw, preserveCharge)
    local latched = state.latched
    state.previous, state.latched = {}, {}
    state.pocket, state.pulseRelease = nil, nil
    -- Held keys at an interruption are a baseline, not a fresh request on resume.
    for _, source in ipairs(SOURCES) do
        state.previous[source] = not not raw[source]
        local old = latched[source]
        -- Only a charge already started by the caller may carry the same held input across rooms.
        if preserveCharge and raw[source] and old and not old.blocked
            and (old.id == "CHARGE" or (source == "MOUSE_PRIMARY" and old.id == "NORMAL")) then
            state.latched[source] = old
        end
    end
    state.previous.POCKET = not not raw.POCKET
    state.previous.SKILL = not not raw.SKILL
end

function InputIntents.sample(state, raw, posture, comboGraceFrames, skillGraceFrames, foresightGuarded)
    local packet = { pressed = {}, held = {}, released = {}, cancelPocket = not not raw.POCKET_CANCEL }
    if state.pulseRelease then
        packet.released[#packet.released + 1] = state.pulseRelease
        state.pulseRelease = nil
    end
    local nativeDown, independentDown = not not raw.POCKET and not raw.POCKET_CANCEL, not not raw.SKILL
    local newNative = nativeDown and not state.previous.POCKET
    local newIndependent = independentDown and not state.previous.SKILL
    local pocket = state.pocket
    if pocket then
        pocket.age = pocket.age + 1
        if pocket.id ~= spiritIntent(posture) then pocket.blocked = true end
        pocket.native = pocket.native and nativeDown
        pocket.skill = pocket.skill and independentDown
    end
    if newNative or newIndependent then
        if not pocket or pocket.blocked then
            pocket = { id = spiritIntent(posture), age = 0, emitted = false, consumed = false,
                blocked = false, source = newIndependent and "SKILL" or "POCKET", nativeRequests = {},
                graceFrames = newIndependent and skillGraceFrames or comboGraceFrames,
                foresightCounter = foresightGuarded }
            state.pocket = pocket
        end
        pocket.native = pocket.native or newNative
        pocket.skill = pocket.skill or newIndependent
        if newIndependent and not pocket.independent then
            -- Joining the independent skill key owns the same request; do not emit a second attack.
            -- Promote an already-buffered native request before a later card/pill cancellation.
            pocket.independent, pocket.source = true, "SKILL"
            packet.independentIntents = {}
            for id in pairs(pocket.nativeRequests) do packet.independentIntents[id] = true end
            for _, latched in pairs(state.latched) do
                if latched.skillHold == pocket then latched.fromPocket = false end
            end
        end
    end
    if raw.POCKET_CANCEL then
        -- Native pocket switching revokes authorization; it is not a quick solo tap.
        for _, latched in pairs(state.latched) do
            if latched.fromPocket then latched.blocked = true end
        end
        if pocket and not pocket.independent then
            if pocket.emitted then
                packet.released[#packet.released + 1] = { id = pocket.id, source = pocket.source }
            end
            state.pocket, pocket = nil, nil
        end
    end
    local skillDown = pocket ~= nil and (pocket.native or pocket.skill) or false

    local requestedIai = false
    for _, source in ipairs(SOURCES) do
        local down, previous = not not raw[source], state.previous[source] or false
        local latched = state.latched[source]
        if down and not previous then
            local id = intentFor(source, raw, posture, skillDown)
            latched = { id = id, blocked = false,
                fromPocket = not raw.MODIFIER and skillDown and not pocket.independent and COMBO[source] == id,
                skillHold = not raw.MODIFIER and skillDown and COMBO[source] == id and pocket or nil }
            state.latched[source] = latched
            if id ~= "IAI" or not requestedIai then
                packet.pressed[#packet.pressed + 1] = { id = id, source = source,
                    fromPocket = latched.fromPocket or nil,
                    foresightCounter = id == "SPIRIT" and foresightGuarded or nil,
                    mouseHold = source == "MOUSE_PRIMARY" and id == "NORMAL" and latched or nil }
            end
            if id == "IAI" then requestedIai = true end
            if latched.fromPocket then pocket.nativeRequests[id] = true end
            if skillDown and (COMBO[source] or id == "IAI") then
                pocket.consumed = true
                pocket.nativeRequests[pocket.id] = nil
            end
        elseif not down and previous then
            if latched then
                packet.released[#packet.released + 1] = { id = latched.id, source = source }
            end
            state.latched[source], latched = nil, nil
        elseif down and latched and ATTACK_SOURCES[source]
            and (latched.id == "IAI") ~= iaiPosture(posture) then
            -- Old attack holds cannot become Iai or revive as ordinary attacks afterward.
            latched.blocked = true
        end
        if down and latched and not latched.blocked then
            packet.held[latched.id] = true
            -- Keep this physical press identifiable through NORMAL -> CHARGE, never a later re-press.
            if source == "MOUSE_PRIMARY" and latched.id == "NORMAL" then packet.held.MOUSE_PRIMARY = latched end
        end
        state.previous[source] = down
    end

    -- One shared solo/combination hold; each physical source leaves independently.
    local pulse = false
    if pocket and not pocket.emitted and not pocket.consumed and not pocket.blocked
        and (pocket.id == "IAI" or pocket.foresightCounter or not skillDown or pocket.age >= pocket.graceFrames) then
        packet.pressed[#packet.pressed + 1] = { id = pocket.id, source = pocket.source,
            fromPocket = not pocket.independent or nil, foresightCounter = pocket.foresightCounter }
        if not pocket.independent then pocket.nativeRequests[pocket.id] = true end
        pocket.emitted, pulse = true, not skillDown
    end
    if pocket and pocket.emitted then
        if pulse or (skillDown and not pocket.consumed and not pocket.blocked) then
            packet.held[pocket.id] = true
        end
        if not skillDown then
            -- A quick tap needs one held tick for the action layer's hold-based intent.
            local release = { id = pocket.id, source = pocket.source }
            if pulse then state.pulseRelease = release
            else packet.released[#packet.released + 1] = release end
        end
    end
    if not skillDown then state.pocket = nil end
    state.previous.POCKET, state.previous.SKILL = not not raw.POCKET, independentDown
    return packet
end

return InputIntents
