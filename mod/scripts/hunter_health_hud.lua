local fill = include("scripts.workshop_button").fill
local Hud = {}

local halfHearts = 12
local halfWidth = 6
local width = 4 + halfHearts * halfWidth
local colors

local function healthBar(x, y, health)
    local ink = health <= 4 and colors.low or colors.healthy
    fill(x, y, width, 16, colors.outline)
    fill(x + 1, y + 1, width - 2, 14, colors.rim)
    fill(x + 2, y + 2, width - 4, 12, colors.track)
    local filled = math.max(0, math.min(halfHearts, health)) * halfWidth
    if filled > 0 then
        fill(x + 2, y + 3, filled, 10, ink.base)
        fill(x + 2, y + 3, filled, 2, ink.light)
        fill(x + 2, y + 11, filled, 2, ink.shade)
    end
    for i = 1, 5 do
        fill(x + 1 + i * 2 * halfWidth, y + 2, 1, 12, colors.divide)
    end
end

local function bladeBar(x, y, blade)
    fill(x, y, width, 5, colors.outline)
    fill(x + 1, y + 1, width - 2, 3, colors.track)
    for i = 1, blade do
        fill(x + 2 + (i - 1) * 24, y + 1, 23, 3, colors.blade[blade])
    end
end

-- Repentance+ moved P1's first heart down six pixels. A heart's ANM2 pivot
-- is (8,8); the six native centers are 12 pixels apart, even with an active item.
function Hud.render(game, player, blade)
    if not colors then
        colors = {
            outline = Color(0.12, 0.09, 0.09, 1), rim = Color(0.49, 0.39, 0.23, 1),
            track = Color(0.18, 0.18, 0.15, 1), divide = Color(0.09, 0.12, 0.09, 0.65),
            healthy = { base = Color(0.35, 0.71, 0.29, 1), light = Color(0.70, 0.89, 0.42, 1),
                shade = Color(0.19, 0.44, 0.23, 1) },
            low = { base = Color(0.90, 0.22, 0.17, 1), light = Color(1, 0.48, 0.30, 1),
                shade = Color(0.56, 0.10, 0.11, 1) },
            blade = { Color(0.94, 0.93, 0.86, 1), Color(0.97, 0.78, 0.23, 1), Color(0.96, 0.31, 0.27, 1) },
        }
    end
    local offset, shake = Options.HUDOffset, game.ScreenShakeOffset
    local x = math.floor(40 + 20 * offset + shake.X)
    local y = math.floor((REPENTANCE_PLUS and 10 or 4) + math.floor(24 * offset + 0.5) / 2 + shake.Y)
    local bladeY = y + 17
    if (game:GetLevel():GetCurses() & LevelCurse.CURSE_OF_THE_UNKNOWN) == 0 then
        local maxRed = player:GetMaxHearts()
        local extra = math.ceil(player:GetSoulHearts() / 2) + player:GetBoneHearts() + player:GetBrokenHearts()
        local effects = player:GetEffects()
        if effects:HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then extra = extra + 1 end
        if maxRed == halfHearts and not effects:HasNullEffect(NullItemID.ID_LOST_CURSE) then
            -- A native special-heart overlay can share the same pixels as the red
            -- containers. Place both gauges beside that row to preserve its meaning.
            if extra > 0 or player:GetGoldenHearts() > 0 or player:GetEternalHearts() > 0 or player:GetRottenHearts() > 0 then
                x = x + 86
                if player:GetExtraLives() > 0 then y = y + 17 end
            end
            bladeY = y + 17
            healthBar(x, y, player:GetHearts())
        else
            -- White fire leaves the game's faded hearts and mantle visible.
            local rows = math.max(1, math.ceil((math.ceil(maxRed / 2) + extra) / 6))
            bladeY = bladeY + (rows - 1) * 10
        end
    end
    if blade ~= nil then bladeBar(x, bladeY, blade) end
end

return Hud
