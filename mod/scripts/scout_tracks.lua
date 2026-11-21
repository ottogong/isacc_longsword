local Route = include("scripts.scout_route")
local Scout = {}
local variant = Isaac.GetEntityVariantByName("Longsword Scout Track")
local current, progressBar
local tracksNeeded = 3
-- The index is stored with each site. Index 1 uses the original ANM2 art.
local signs = { "hoof", "blood", "fur", "claw", "scale", "mucus" }

local function chooseSign(sites, seed)
    local uses = {}
    for _, site in pairs(sites) do
        uses[site.kind] = (uses[site.kind] or 0) + 1
    end
    local best
    for offset = 0, #signs - 1 do
        local kind = (seed + offset) % #signs + 1
        if not uses[kind] then return kind end
        if not best or uses[kind] < uses[best] then best = kind end
    end
    return best
end

local function effect(position, animation)
    local entity = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, position, Vector.Zero, nil)
    entity:GetSprite():Play(animation, true)
    return entity
end

local function remove(entity)
    if entity and entity:Exists() then entity:Remove() end
end

function Scout.leave()
    if not current then return end
    remove(current.print)
    for _, fly in ipairs(current.flies) do remove(fly) end
    current = nil
end

local function progress(sites)
    local count = 0
    for _, site in pairs(sites) do
        if site.guided then
            count = count + 1
            if count == tracksNeeded then break end
        end
    end
    return count
end

function Scout.enter(game, run)
    Scout.leave()
    local count = progress(run.scoutTracks)
    if count == tracksNeeded then Route.markBoss(game:GetLevel()) end
    local room = game:GetRoom()
    if room:GetType() ~= RoomType.ROOM_DEFAULT or run.rewarded or game:IsGreedMode() then return end
    current = { sites = run.scoutTracks, seed = room:GetSpawnSeed(), flies = {}, age = 0,
        count = count, fought = not room:IsClear() }
end

local function orbit(age, i)
    local t = age * 0.09 + i * 2.4
    return Vector(math.cos(t) * (6 + i), math.sin(t * 1.35) * 4 - 6)
end

local function reveal(state, game, player)
    local room = game:GetRoom()
    local door = Route.nextDoor(game:GetLevel(), room)
    if not door then return false end
    -- Door directions 0..3 are left, up, right, down. Keep the swarm just inside.
    state.goal = door.Position + Vector.FromAngle(door.Direction * 90) * 25
    local site = state.sites[state.seed]
    local newSite = site == nil
    if not site then
        local delta = state.goal - player.Position
        local ahead = player.Position + delta * math.min(0.7, 76 / math.max(1, delta:Length()))
        local pos = room:FindFreePickupSpawnPosition(room:GetClampedPosition(ahead, 28), 0, true, false)
        site = { x = math.floor(pos.X + 0.5), y = math.floor(pos.Y + 0.5),
            kind = chooseSign(state.sites, state.seed) }
        state.sites[state.seed] = site
    end
    state.site = site
    local pos = Vector(site.x, site.y)
    state.position = pos
    if site.guided then
        state.atDoor = true
        for i = 1, 5 do state.flies[i] = effect(state.goal + orbit(0, i), "Fly") end
    else
        state.print = effect(pos, state.fought and "TrackReveal" or "TrackIdle")
        local sign = signs[site.kind]
        if sign and site.kind ~= 1 then
            local sprite = state.print:GetSprite()
            sprite:ReplaceSpritesheet(0, "gfx/isacc_longsword/scout_signs/" .. sign .. ".png")
            sprite:LoadGraphics()
        end
        state.print.SpriteRotation = (state.goal - pos):GetAngleDegrees()
        state.print.DepthOffset = -12
        for i = 1, 2 do state.flies[i] = effect(pos + orbit(0, i), "Fly") end
        if state.fought then
            Isaac.DebugString("[LS_M0] scout_track reveal room=" .. state.seed .. " direction=" .. door.Direction
                .. " sign=" .. tostring(sign))
        end
    end
    return true, newSite
end

local function follow(state, player)
    state.site.guided = true
    state.departure = state.age
    local waist = player.Position + Vector(0, -10)
    for i = 3, 5 do state.flies[i] = effect(waist, "Fly") end
    state.starts = {}
    for i, fly in ipairs(state.flies) do state.starts[i] = fly.Position end
    state.travel = math.max(16, math.ceil((state.goal - state.position):Length() / 8))
end

function Scout.update(game, player)
    local state = current
    if not state then return end
    if player:IsDead() then Scout.leave(); return end
    local room = game:GetRoom()
    if not room:IsClear() then
        if state.site then
            Scout.leave()
            current = { sites = state.sites, seed = state.seed, count = state.count, flies = {}, age = 0 }
        end
        current.fought = true
        return
    end
    if not state.site then
        if not state.fought and not state.sites[state.seed] then return end
        local found, newSite = reveal(state, game, player)
        if not found then Scout.leave() end
        return newSite
    end
    state.age = state.age + 1
    if state.print and state.print:GetSprite():IsFinished("TrackReveal") then
        state.print:GetSprite():Play("TrackIdle", true)
    end
    local collected, marked
    if not state.site.guided and state.age >= 9 and player.ControlsEnabled
        and player.Position:DistanceSquared(state.position) <= 36 * 36 then
        follow(state, player)
        collected = true
        if state.count < tracksNeeded then
            state.count = state.count + 1
            if state.count == tracksNeeded then marked = Route.markBoss(game:GetLevel()) end
        end
        Isaac.DebugString("[LS_M0] scout_track follow room=" .. state.seed
            .. " progress=" .. state.count .. " bossMarked=" .. tostring(marked == true))
    end
    for i, fly in ipairs(state.flies) do
        local drift = orbit(state.age, i)
        if state.atDoor then
            fly.Position = state.goal + drift
        elseif state.departure then
            local elapsed = state.age - state.departure - 6 - (i - 1) * 3
            local p = math.min(1, math.max(0, elapsed / state.travel))
            local start = state.starts[i]
            fly.Position = start + (state.goal - start) * p
                + Vector(0, -12 * math.sin(math.pi * p)) + drift * p
            if i == #state.flies and p == 1 then state.atDoor = true end
        else
            fly.Position = state.position + drift
        end
    end
    if state.departure and state.print and state.age - state.departure >= 12 then
        remove(state.print)
        state.print = nil
    end
    return collected, marked
end

function Scout.render()
    local state = current
    if not state or not state.position then return end
    if not state.print and (not state.departure or state.age - state.departure > 42) then return end
    if not progressBar then
        progressBar = Sprite()
        progressBar:Load("gfx/longsword_scout_tracks.anm2", true)
    end
    progressBar:SetFrame("TrackProgress", state.count)
    progressBar:Render(Isaac.WorldToScreen(state.position) + Vector(0, 12))
end

return Scout
