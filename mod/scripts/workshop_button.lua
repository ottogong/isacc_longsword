local Button = {}
local width, height = 94, 17
local pixel, palette

-- The drawn rectangle and the mouse target have the same edges in both shops.
function Button.hit(box, pos)
    return pos and pos.X >= box.right - width and pos.X < box.right
        and pos.Y >= box.bottom - height and pos.Y < box.bottom
end

function Button.fill(x, y, w, h, color)
    if not pixel then
        pixel = Sprite()
        pixel:Load("gfx/isacc_longsword/guild_jewels.anm2", true)
        pixel:SetFrame("Fill", 0)
    end
    pixel.Scale, pixel.Color = Vector(w, h), color
    pixel:RenderLayer(0, Vector(math.floor(x), math.floor(y)))
end

function Button.draw(box, label, enabled, line)
    if not palette then
        palette = {
            gold = Color(0.94, 0.75, 0.42, 1), brown = Color(0.42, 0.26, 0.13, 1),
            rim = Color(0.44, 0.41, 0.36, 1), muted = Color(0.24, 0.23, 0.21, 1),
            lightText = KColor(1, 0.96, 0.82, 1), mutedText = KColor(0.76, 0.73, 0.66, 1),
        }
    end
    local x, y = box.right - width, box.bottom - height
    Button.fill(x, y, width, height, enabled and palette.gold or palette.rim)
    Button.fill(x + 1, y + 1, width - 2, height - 2, enabled and palette.brown or palette.muted)
    line(label, x + 6, y + 2, enabled and palette.lightText or palette.mutedText, width - 12)
end

return Button
