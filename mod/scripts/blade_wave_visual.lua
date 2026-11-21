local WaveVisual = {}
local arc

function WaveVisual.render(waves)
    if #waves == 0 then return end
    if not arc then
        arc = Sprite()
        arc:Load("gfx/002.014_pupula tear.anm2", true)
        arc:SetFrame("RegularTear12", 0)
    end
    for _, wave in ipairs(waves) do
        local origin = Isaac.WorldToScreen(wave.position)
        local forward = Isaac.WorldToScreen(wave.position + wave.direction * 16) - origin
        local side = Vector(-wave.direction.Y, wave.direction.X)
        local edge = Isaac.WorldToScreen(wave.position + side * wave.halfWidth) - origin
        -- The native right-facing Pupula frame has 24 visible pixels across the arc.
        local scale = 2 * math.sqrt(edge:LengthSquared()) / 24
        arc.Scale = Vector(scale, scale)
        arc.Rotation = forward:GetAngleDegrees()
        arc:Render(origin + Vector(0, -6))
    end
end

return WaveVisual
