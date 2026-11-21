local Native = include("scripts.native")
local MenuInput = {}
local commands = { "back", "click", "confirm", "up", "down", "left", "right" }

local function readButtons(player)
    local keyboard = Native.inputDevice(player) == "keyboard"
    local index = keyboard and 0 or player.ControllerIndex
    local function held(action)
        return Input.IsActionPressed(action, index)
    end
    return {
        back = held(ButtonAction.ACTION_MENUBACK) or
            (keyboard and (Input.IsButtonPressed(Keyboard.KEY_BACKSPACE, 0) or Input.IsMouseBtnPressed(1))),
        click = keyboard and Input.IsMouseBtnPressed(0),
        confirm = held(ButtonAction.ACTION_MENUCONFIRM) or (keyboard and
            (Input.IsButtonPressed(Keyboard.KEY_ENTER, 0) or Input.IsButtonPressed(Keyboard.KEY_KP_ENTER, 0))),
        up = held(ButtonAction.ACTION_MENUUP) or held(ButtonAction.ACTION_UP),
        down = held(ButtonAction.ACTION_MENUDOWN) or held(ButtonAction.ACTION_DOWN),
        left = held(ButtonAction.ACTION_MENULEFT) or held(ButtonAction.ACTION_LEFT),
        right = held(ButtonAction.ACTION_MENURIGHT) or held(ButtonAction.ACTION_RIGHT),
    }, keyboard
end

function MenuInput.open(player)
    local down, keyboard = readButtons(player)
    return { down = down, mouse = keyboard and Native.mouseScreenPosition() or nil }
end

function MenuInput.read(state, player)
    local previous, lastMouse = state.down, state.mouse
    local down, keyboard = readButtons(player)
    local mouse = keyboard and Native.mouseScreenPosition() or nil
    state.down, state.mouse = down, mouse
    for _, command in ipairs(commands) do
        if down[command] and not previous[command] then
            -- A mouse binding can surface as menu-confirm on the click or release tick.
            if command ~= "confirm" or not (down.click or previous.click) then return command, mouse end
        end
    end
    if mouse and lastMouse and mouse:DistanceSquared(lastMouse) >= 1 then return "point", mouse end
end

-- Snapshot held controls on closing, then wait only for those same controls.
-- This includes the user's own sword bindings, which bypass MC_INPUT_ACTION.
function MenuInput.released(state, player, bindings)
    local down, keyboard = readButtons(player)
    local index = keyboard and 0 or player.ControllerIndex
    for action = ButtonAction.ACTION_LEFT, ButtonAction.ACTION_DROP do
        down[action] = Input.IsActionPressed(action, index)
    end
    for source, pressed in pairs(Native.readCombatInput(player, bindings, false)) do
        down[source] = pressed
    end
    if not state.releasing then state.releasing = down end
    for key in pairs(state.releasing) do
        if not down[key] then state.releasing[key] = nil end
    end
    return next(state.releasing) == nil
end

function MenuInput.filter(state, hook, action)
    if state and ((action >= ButtonAction.ACTION_LEFT and action <= ButtonAction.ACTION_DROP)
        or action == ButtonAction.ACTION_MAP) then
        if hook == InputHook.GET_ACTION_VALUE then return 0 end
        return false
    end
end

return MenuInput
