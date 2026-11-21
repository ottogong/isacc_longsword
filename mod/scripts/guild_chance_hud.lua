local GuildChanceHud = {}
local badge, momUnlock

local function hasRunIcon(game, seeds)
    if game.Difficulty ~= Difficulty.DIFFICULTY_NORMAL or seeds:IsCustomRun()
        or Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL or game:GetVictoryLap() > 0 then return true end
    -- Mods block achievements before the first Mom kill. Cube of Meat unlocks with that kill.
    momUnlock = momUnlock or Isaac.GetItemConfig():GetCollectible(CollectibleType.COLLECTIBLE_CUBE_OF_MEAT)
    return not momUnlock:IsAvailable()
end

-- Called only for the single-player hunter. Found HUD draws its own percentage
-- beside this 16px tile; Duality replaces the two deal rows with a combined row.
function GuildChanceHud.render(game, player)
    if not Options.FoundHUD or not game:GetHUD():IsVisible()
        or player:HasCollectible(CollectibleType.COLLECTIBLE_DUALITY) then return end
    local seeds = game:GetSeeds()
    if seeds:HasSeedEffect(SeedEffect.SEED_NO_HUD) then return end
    if game:GetRoom():GetType() == RoomType.ROOM_DUNGEON and game:GetLevel():GetAbsoluteStage() == LevelStage.STAGE8 then return end

    if not badge then
        badge = Sprite()
        badge:Load("gfx/isacc_longsword/guild_chance_badge.anm2", true)
        badge:SetFrame("Idle", 0)
    end
    -- Single-player Found HUD rows are 12px apart. Repentance+ moved the
    -- whole stat block 2px down. At max inset on Hard the angel tile is (20,186).
    local y = (REPENTANCE_PLUS and 158 or 156) + (hasRunIcon(game, seeds) and 16 or 0)
    local inset = Options.HUDOffset
    badge:Render(Vector(20 * inset, y + 12 * inset))
end

return GuildChanceHud
