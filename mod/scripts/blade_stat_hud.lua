local Locale = include("scripts.locale")
local BladeStatHud = {}

-- Stats+ 2.1.3 has one active provider per stat and no suffix hook. Once its
-- public registration fires, these require names refer to its loaded singletons.
local function connect(api)
    local container = require("app.APPLICATION_CONTAINER").APPLICATION_CONTAINER
    local renderClass = require("services.renderer.RenderService").RenderService
    local service = container:resolve(renderClass)
    if service.modCallbackService ~= api.modCallbackService then return end
    return service, require("entities.Time").Time:ms(6250)
end

local function damageSlot(renderer, player)
    for _, slot in ipairs(renderer.loadoutService:getSlotsForPlayer(player)) do
        if slot.stat.statId == "damage-stat" then return slot end
    end
end

local function formatted(metric)
    return metric and metric:getFormattedValue()
end

local function changeText(metric, time)
    local change = metric and metric:getChangeAt(time)
    return change and change.formattedValue
end

local function createDraw(service, changeLookback, readMultiplier)
    local renderer = service.renderer
    local owner, slot, chineseFont
    return function()
        if not service:shouldRender() then return end
        local player = service.playerService:getMainPlayer()
        local multiplier = player and readMultiplier(player.entityPlayer)
        if not multiplier then return end
        if owner ~= player then
            owner, slot = player, damageSlot(renderer, player)
        end
        if not slot then return end
        local entry = renderer.loadoutService:getEntry(slot)
        local stat = renderer.statService:getStatValue(slot)
        if not entry or not stat then return end

        local active = entry:getActiveProvider():getValue()
        local inactive = entry:getInactiveProvider():getValue()
        local providerText = formatted(active) or formatted(inactive)
        local statText = formatted(stat) or ""
        local occupied = providerText and renderer:getValueWithBrackets(providerText) or ""
        local appearance = renderer.configService:getConfigOrThrow().appearance
        local now = renderer.timeProvider:getLastRenderTime()
        -- Stats+ briefly clears the row for the native red/green damage change.
        if stat:getChangeAt(now) then return end
        local slide = 0
        if occupied ~= "" and appearance:showsProviderChanges() then
            -- Same 6.25s lookback and slide distance as Stats+ renderChange.
            local time = now:minus(changeLookback)
            local delta = changeText(active, time) or changeText(inactive, time)
            if delta then
                occupied = occupied .. renderer:getValueWithBrackets(delta)
                slide = 8
            end
        end
        local xy = renderer.renderPositionProvider:getPosition(slot, statText .. occupied)
        local x, y = xy[1] + slide + 3, xy[2]
        local ink = KColor(1, 1, 1, appearance:getTextOpacity())
        if Locale.isChinese() then
            if not chineseFont then
                chineseFont = Font()
                chineseFont:Load("font/cjk/lanapixel.fnt")
            end
            chineseFont:DrawStringScaledUTF8(("气刃 ×%.2f"):format(multiplier), x, y - 1,
                0.7, 0.7, ink, 0, false)
        else
            renderer.providerFont:DrawStringUTF8(("Spirit x%.2f"):format(multiplier), x, y, ink, 0, false)
        end
    end
end

function BladeStatHud.register(mod, readMultiplier)
    local attempted = false
    mod:AddCallback("STATS_PLUS_REGISTER", function(_, api)
        if attempted then return end
        attempted = true
        local ok, service, lookback = pcall(connect, api)
        if not ok or not service then
            Isaac.DebugString("[Longsword] Stats+ blade HUD unavailable: " ..
                (ok and "unrecognized renderer" or tostring(service)))
            return
        end
        local draw = createDraw(service, lookback, readMultiplier)
        local function render()
            local success, message = pcall(draw)
            if not success then
                mod:RemoveCallback(ModCallbacks.MC_POST_RENDER, render)
                Isaac.DebugString("[Longsword] Stats+ blade HUD unavailable: " .. tostring(message))
            end
        end
        mod:AddCallback(ModCallbacks.MC_POST_RENDER, render)
    end)
end

return BladeStatHud
