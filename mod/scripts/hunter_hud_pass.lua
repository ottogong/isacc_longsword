local Pass = {}
local hiddenHud, hiddenFrame

function Pass.restore()
    if hiddenHud then
        hiddenHud:SetVisible(true)
        hiddenHud, hiddenFrame = nil, nil
    end
end

function Pass.restoreNextFrame()
    if hiddenHud and Isaac.GetFrameCount() ~= hiddenFrame then
        Pass.restore()
    end
end

-- The engine normally draws its HUD after MC_POST_RENDER. Draw that same HUD
-- here first, then suppress its second draw for the rest of this render frame.
function Pass.draw(hud, paint, player)
    if hiddenHud or not hud:IsVisible() then return end
    hud:Render()
    paint(player)
    if hud:IsVisible() then
        hiddenFrame = Isaac.GetFrameCount()
        hud:SetVisible(false)
        hiddenHud = hud
    end
end

return Pass
