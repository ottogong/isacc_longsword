-- Keep an entry marker before includes so startup failures can be located in log.txt.
local version = 121
Isaac.DebugString("[LS_M0] boot stage=entry version=prototype-" .. version)
local Config = include("scripts.config")
local Locale = include("scripts.locale")
local ItemText = include("scripts.item_text")
local DebugText = include("scripts.debug_text")
Isaac.DebugString("[LS_M0] boot stage=config_loaded")
local Native = include("scripts.native")
Isaac.DebugString("[LS_M0] boot stage=native_loaded")
local Intents = include("scripts.input")
local Actions = include("scripts.actions")
local Melee = include("scripts.melee")
local WeaponSize = include("scripts.weapon_size")
local Visual = include("scripts.longsword_visual")
local Character = include("scripts.hunter_character")
local Hunt = include("scripts.hunt")
local Jewels = include("scripts.hunt_jewels")
local Gear = include("scripts.hunt_gear")
local Workshop = include("scripts.hunt_workshop")
local MenuInput = include("scripts.hunt_menu_input")
local MonstroHunt = include("scripts.monstro_hunt")
local EarlyHunts = include("scripts.early_hunts")
local CritSlash = include("scripts.crit_slash")
local Wave = include("scripts.blade_wave")
local WaveVisual = include("scripts.blade_wave_visual")
local Field = include("scripts.hunt_field")
local Scout = include("scripts.scout_tracks")
local Vitals = include("scripts.hunter_vitals")
local SupplyBox = include("scripts.hunter_supply_box")
local HunterHealthHud = include("scripts.hunter_health_hud")
local GuildChanceHud = include("scripts.guild_chance_hud")
local HunterHudPass = include("scripts.hunter_hud_pass")
local GuildPassives = include("scripts.hunter_guild_passives")
local Loot = include("scripts.hunter_loot")
local Guild = include("scripts.guild_room")
local mod = RegisterMod(Config.MOD_NAME, 1)
Isaac.DebugString("[LS_M0] boot stage=registered")
local game = Game()
Locale.load(mod)
local englishSwordId = Isaac.GetItemIdByName(Config.ITEM_NAME)
local chineseSwordId = Isaac.GetItemIdByName(ItemText.chineseSwordName)
local function pocketSwordId()
    -- With an English native font the mod draws its Chinese subtitle itself.
    return (Locale.isChinese() and Options.Language == "zh") and chineseSwordId or englishSwordId
end
local itemId = pocketSwordId()
local flySuitId = Isaac.GetItemIdByName(ItemText.englishName("flySuit"))
local sfx = SFXManager()
local sound = {
    crit = 540, -- Native knife_pull.wav.
    hit = Isaac.GetSoundIdByName("Longsword Hit"), draw = Isaac.GetSoundIdByName("Longsword Draw"),
    gp = Isaac.GetSoundIdByName("Longsword GP"), helm = Isaac.GetSoundIdByName("Longsword Helm"),
    helmHit = Isaac.GetSoundIdByName("Longsword Helm Hit"),
    helmFinish = Isaac.GetSoundIdByName("Longsword Helm Finish"),
}
Isaac.DebugString("[LS_M0] boot stage=item_resolved itemId=" .. tostring(itemId))
local session = { watch = Config.WATCH_DEFAULT, blindfoldAttempted = false }
-- Text visibility is a player choice. Probe logging may enable itself on equip or use.
local showDebugText = false
local lastDirections, lastStatus = {}, nil
local lastEquipReason = "not requested"
local lastBlindfoldReason = "not requested"
local taidaoUseCount = 0
local inputState, combat = Intents.new(), Actions.new()
local motion = Native.newMotion()
local melee = Melee.new(Config.MELEE)
local size = WeaponSize.new()
local baseTearScale = Config.MELEE.size.initialTearScale
local lastMelee = "none"
local pocket = { armed = false, pending = false, blocked = false }
local lastPocketInput, lastCancel = nil, "none"
local lastFacing = nil
local mode = { held = false, pending = true, origin = "load", rebase = true, suspended = false }
local hostVariant = Isaac.GetEntityVariantByName("Longsword Combat Render Host")
local renderOwner, renderHost, originalVisibility
local huntRun, guild, carvePosition, menuInput
local waves = {}
local huntTiming = Config.ACTIONS

local function syncSwordLanguage(player)
    itemId = pocketSwordId()
    if not player or game:GetNumPlayers() ~= 1 or itemId <= 0 then return end
    local held = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
    -- Only replace our existing sword. Cards, pills and other pocket actives keep their slots.
    if held > 0 and held ~= itemId and (held == englishSwordId or held == chineseSwordId) then
        player:SetPocketActiveItem(itemId, ActiveSlot.SLOT_POCKET, true)
    end
end

local function toggleCampLanguage()
    local mode = Locale.toggle(mod)
    syncSwordLanguage(Isaac.GetPlayer(0))
    return mode
end

local function activeHunt(player)
    if huntRun and Character.isHunter(game, player) then return huntRun end
end

include("scripts.blade_stat_hud").register(mod, function(player)
    if Native.guard(game, player, itemId, true) then
        return Config.MELEE.spiritBladeMultipliers[combat.blade + 1]
    end
end)

function mod:GetAnimationState(player)
    if not Native.guard(game, player, itemId, true) or player:IsDead()
        or game:IsPaused() or player.ControlsEnabled == false then
        -- Visual.sync accepts this empty pose and clears any previous clip.
        return { enabled = false }
    end

    local hunt = activeHunt(player)
    local state = {
        toothCharm = hunt and hunt.tooth,
        enabled = true, tick = combat.tick, action = combat.action, posture = combat.posture,
        phase = combat.phase, phaseFrame = combat.phaseFrame,
        authoredTime = combat.elapsed * combat.attackRate,
        moving = motion.movement.X ~= 0 or motion.movement.Y ~= 0,
        size = { x = size.x, y = size.y, body = size.body, reach = size.reach, width = size.width,
            bladeScale = WeaponSize.bladeScale(size) },
    }
    if combat.action == "CHARGE" then
        local heldTime = combat.elapsed * combat.attackRate
        if combat.phase == "RECOVERY" then
            local lastTick = math.max(1, math.ceil(Config.ACTIONS.chargeRecovery / combat.attackRate) - 1)
            heldTime = combat.chargeReleaseTime * (1 - combat.elapsed / lastTick)
        end
        state.chargeProgress = math.min(1, heldTime / Config.ACTIONS.chargeFrames)
    elseif combat.action == "NONE" and combat.posture == "SHEATHED_FREE" then
        local body = player:GetSprite()
        state.nativeBodyAnimation, state.nativeBodyFrame = body:GetAnimation(), body:GetFrame()
    end
    -- Only the active move owns the locked direction; idle follows the current aim.
    local lockedFacing
    if melee.action == combat.action and melee.facing then
        lockedFacing, state.trailColor = melee.facing, melee.trailColor
    end
    local timing = Config.ACTIONS.frames[combat.action] or Config.ACTIONS.frames.NORMAL
    return state, Native.directionName(motion.facing), lockedFacing,
        { startup = combat.action == "SPECIAL_SHEATHE" and (hunt and huntTiming or Config.ACTIONS).sheatheStartup or timing.startup,
          active = timing.active, recovery = timing.recovery,
          takeoffTicks = timing.takeoffTicks, jumpHeight = timing.jumpHeight,
          fallSpeed = timing.fallSpeed, fallSourceTicks = timing.fallSourceTicks }
end

local function walkingLocked()
    return combat.posture == "SHEATHE_STARTUP" or combat.posture == "SPECIAL_SHEATHE"
        or combat.action == "HELM_BREAKER" and combat.phase ~= "RECOVERY"
        or combat.action == "IAI" and motion.stepDirection ~= nil
end

local function encode(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function log(event, data)
    local message = Config.LOG_PREFIX .. event .. " " .. encode(data or {})
    Isaac.DebugString(message)
    return message
end

local function playerNow()
    if game:GetNumPlayers() == 0 then return nil end
    return Isaac.GetPlayer(0)
end

local jewelCache = { attack = CacheFlag.CACHE_DAMAGE, reach = CacheFlag.CACHE_RANGE, speed = CacheFlag.CACHE_FIREDELAY }
local function syncGear(run, player)
    local changed = Gear.sync(run, player)
    if changed then
        huntTiming = Hunt.actionConfig(Config.ACTIONS, run.gear.braces)
        log("hunter_equipment", { gear = run.gear, tooth = run.tooth, flySuit = run.flySuit, spur = run.spur, spurPlus = run.spurPlus })
    end
    local flags = 0
    for _, key in ipairs(Jewels.keys) do
        if Gear.syncJewel(run, player, key) then
            changed = true
            flags = flags | (jewelCache[key] or 0)
        end
    end
    if flags ~= 0 then Vitals.refresh(player, flags) end
    return changed
end

local function placeJewel(key, copyIndex, rank, oldRank)
    return Gear.placeJewel(game:GetRoom(), playerNow(), guild.position, key, rank, oldRank)
end

local function enterHuntRoom(player)
    carvePosition = nil
    local run = activeHunt(player)
    if not run or run.seed ~= game:GetSeeds():GetStartSeed() then Scout.leave(); return end
    Character.enterRoom()
    Field.clear(guild)
    local changed = Hunt.enterFloor(run, game:GetLevel())
    Scout.enter(game, run)
    changed = syncGear(run, player) or changed
    local hall = Guild.enterRoom(game, run, Gear.isJewelPedestal)
    local board = Workshop.enterRoom(guild, game, player, run, hall)
    SupplyBox.enter(game:GetRoom(), not hall and board, run, player)
    if hall then changed = Jewels.redeliver(run, placeJewel) or changed end
    if board and (changed or game:GetRoom():IsFirstVisit()) then Character.sendCat(board, 45) end
    if game:GetRoom():GetType() == RoomType.ROOM_BOSS then
        local eucharist = CollectibleType.COLLECTIBLE_EUCHARIST
        log("hunter_deal_chance", { chance = game:GetRoom():GetDevilRoomChance(),
            eucharist = player:HasCollectible(eucharist), eucharistInventory = player:HasCollectible(eucharist, true),
            duality = player:HasCollectible(CollectibleType.COLLECTIBLE_DUALITY) })
        local visited, healed = Hunt.enterBoss(run, player)
        changed = changed or visited
        if healed > 0 then
            Character.sendCat(player.Position, 16)
            Workshop.announce(guild, healed == 1 and Locale.text("First aid · Half a red heart restored", "急救药 · 回复半颗红心")
                or Locale.text("First aid · One red heart restored", "急救药 · 回复一颗红心"))
            log("hunter_first_aid", { halfHearts = healed })
        end
    end
    if changed then Hunt.save(mod, run) end
end

local function spawnGear(key, rank)
    return Gear.spawn(game:GetRoom(), playerNow(), key, rank)
end

local function craftGear(key, page, copyIndex)
    local player = playerNow()
    local isJewel = Jewels.maxLevel[key] ~= nil
    local ok, reason
    if isJewel then
        if not Guild.isHall(game, huntRun) then return false, "guild" end
        ok, reason = Jewels.buy(huntRun, key, page, copyIndex, placeJewel)
    else
        ok, reason = Hunt.craft(huntRun, key, spawnGear)
    end
    if ok then
        if jewelCache[key] then Vitals.refresh(player, jewelCache[key])
        elseif not isJewel and not huntRun.gear[key] then Vitals.supply(game, player, key) end
        Hunt.save(mod, huntRun)
        Character.sendCat(player.Position, 24)
        local level = isJewel and Jewels.level(huntRun, key) or huntRun.gear[key] and huntRun.gear[key] + 1
        log("hunter_forge", { gear = key, level = level, page = page, copy = copyIndex, materials = huntRun.materials })
    end
    return ok, reason
end

local function carveReward(run, seed)
    local parts = run.parts[seed] or {}
    local rewards = {}
    for _, key in ipairs({ "tooth", "flySuit", "spur", "spurPlus" }) do
        if (parts[key] or key == "tooth" and run.remains[seed].tooth) and not run[key] then
            local made, reason = spawnGear(key, 1)
            if not made and reason == "space" then
                Workshop.announce(guild, Locale.text("Carve from the other side to make room for the gear", "装备底座需要空地，换一侧剥取"))
                return
            end
            rewards[#rewards + 1] = key
        end
    end
    local amount, tooth = Hunt.carve(run, seed)
    Hunt.save(mod, run)
    local message = Locale.text("Carve complete", "剥取完成")
    if amount > 0 then message = message .. Locale.text(" · Materials ×", " · 素材 ×") .. amount end
    if #rewards > 0 then
        local names = {}
        for i, key in ipairs(rewards) do names[i] = ItemText.name(key, 1) end
        message = message .. Locale.text(" · Collect ", " · 请拾取") .. table.concat(names, Locale.text(", ", "、"))
    end
    Workshop.announce(guild, message)
    log("hunter_carved", { room = seed, amount = amount, tooth = tooth, equipment = table.concat(rewards, ","), balance = run.materials })
end

local function recordPart(run, cue)
    local key = EarlyHunts.onHit(melee, cue)
    if not key then return end
    local room = game:GetRoom()
    local seed = room:GetSpawnSeed()
    local reward = Hunt.breakPart(run, seed, key)
    if not reward then return end
    if room:IsClear() and not run.remains[seed] then
        Hunt.leaveRemains(run, seed, Field.site(room, carvePosition), false, false)
    end
    Hunt.save(mod, run)
    Workshop.announce(guild, key == "flySuit" and Locale.text("Part broken · Duke's fly sac", "部位破坏 · 公爵的虫囊")
        or Locale.text("Part broken · Famine's spur", "部位破坏 · 饥荒的马刺"))
    log("hunter_part_break", { part = reward, room = seed })
end

local function checkToothBreak(run, hit)
    if not run or run.tooth or melee.action ~= "FORESIGHT" then return end
    local room = game:GetRoom()
    if room:GetType() ~= RoomType.ROOM_BOSS or run.toothRoom == room:GetSpawnSeed() then return end
    if MonstroHunt.brokeTooth(run, melee, hit) then
        local seed = room:GetSpawnSeed()
        Hunt.breakTooth(run, seed)
        -- A lethal return cut may finish native clear processing within TakeDamage.
        if room:IsClear() and not run.remains[seed] then
            Hunt.leaveRemains(run, seed, Field.site(room, carvePosition), false, false)
        end
        Hunt.save(mod, run)
        Workshop.announce(guild, Locale.text("Part broken · Monstro's fang", "部位破坏 · 萌死戳的门牙"))
        log("hunter_tooth_break", { target = hit.target })
    end
end

local function playerRenderOrigin(player, offset)
    return Isaac.WorldToScreen(player.Position + player.PositionOffset)
        + player.SpriteOffset + offset - game:GetRoom():GetRenderScrollOffset()
end

local function inPickupPose(player)
    if player:IsHoldingItem() then return true end
    local animation = player:GetSprite():GetAnimation()
    return animation:sub(1, 6) == "Pickup" or animation == "LiftItem" or animation == "HideItem"
end

local function activeCounterShield(player)
    local data = player:GetData()
    local shield = data.longswordCounterShield
    if not shield then return end
    if player:IsDead() or (not shield.follow and player.FrameCount >= shield.expires) then
        data.longswordCounterShield = nil
        return
    end
    return shield
end

local function extendCounterShield(player, shield, frames)
    player:SetMinDamageCooldown(frames)
    shield.expires = math.max(shield.expires, player.FrameCount + frames)
end

local function grantCounterShield(player, id)
    local frames = math.ceil(Config.COUNTER_SHIELD_SECONDS[id] * 30)
    if frames <= 0 then return 0 end
    local shield = activeCounterShield(player)
    if not shield then
        local sprite = Sprite()
        sprite:Load("gfx/characters/058_book of shadows.anm2", true)
        shield = { sprite = sprite, started = player.FrameCount, expires = player.FrameCount }
        player:GetData().longswordCounterShield = shield
    end
    local followsAction = id == "FORESIGHT" or id == "HELM_BREAKER"
    if followsAction then shield.follow, shield.tail = id, frames end
    extendCounterShield(player, shield, followsAction and 1 or frames)
    return frames
end

local function updateActionShield(player)
    local shield = player and activeCounterShield(player)
    if not shield or not shield.follow then return end
    local following = shield.follow == "HELM_BREAKER" and combat.action == "HELM_BREAKER"
        or shield.follow == "FORESIGHT" and (combat.guardedAction == "FORESIGHT" or combat.source == "FORESIGHT_COUNTER")
    if following then
        -- A cancel can end the chain on the very next update.
        extendCounterShield(player, shield, 1)
    else
        extendCounterShield(player, shield, shield.tail)
        log(shield.follow == "FORESIGHT" and "foresight_shield_tail" or "helm_shield_tail",
            { frames = shield.tail, tick = combat.tick })
        shield.follow, shield.tail = nil, nil
    end
end

local function drawCounterShield(player, origin)
    local shield = activeCounterShield(player)
    if not shield or inPickupPose(player) then return end
    -- All four directions of the book's native costume share this 40-frame loop.
    shield.sprite:SetFrame("WalkDown", (player.FrameCount - shield.started) % 40)
    shield.sprite.Scale = player.SpriteScale
    shield.sprite:Render(origin)
end

local function releaseCombatView()
    if renderOwner and renderOwner:Exists() then renderOwner.Visible = originalVisibility end
    if renderHost and renderHost:Exists() then renderHost:Remove() end
    renderOwner, renderHost, originalVisibility = nil, nil, nil
end

local function syncCombatView()
    -- The camp portrait draws the player's current native costume layers.
    if Workshop.isOpen(guild) then
        releaseCombatView()
        return
    end
    local player = playerNow()
    if renderOwner and (not player or not renderOwner:Exists()
        or GetPtrHash(renderOwner) ~= GetPtrHash(player)) then
        releaseCombatView()
    end
    if not player then return end
    local data = player:GetData()
    local view = data.longswordCombatView
    if not view then
        if not Native.guard(game, player, itemId, true) then return end
        view = Visual.new()
        data.longswordCombatView = view
    end
    -- Pickup draws the whole player on the native extra layer, including the head.
    local active = not inPickupPose(player) and Visual.sync(view, mod:GetAnimationState(player))
    if not active then
        releaseCombatView()
        return
    end
    if not renderOwner then
        if not player.Visible then return end
        renderOwner, originalVisibility = player, player.Visible
    end
    if not renderHost or not renderHost:Exists() then
        renderHost = Isaac.Spawn(EntityType.ENTITY_EFFECT, hostVariant, 0,
            player.Position, Vector.Zero, player)
    end
    renderHost.Position = player.Position
    renderHost.DepthOffset = player.DepthOffset
    player.Visible = false
end

local function watchedPlayer(player)
    return session.watch and Native.guard(game, player, itemId, true)
end

local function clearCombatInput(player)
    if motion.helm and motion.helm.moving and player then player.Velocity = Vector(0, 0) end
    motion.debugThrustBox, motion.helm, motion.helmStartFrame = nil, nil, nil
    pocket.armed, pocket.pending, pocket.blocked = false, false, true
    mode.rebase = true
    lastDirections = {}
end

local function stepTravel()
    if combat.action == "SHEATHED_STEP" then
        return Config.STEP_DISTANCE, Config.ACTIONS.stepFrames
    end
    local dash = Config.IAI_DASH
    if combat.action ~= "IAI" or dash.distance <= 0 then return end
    local first = math.ceil(dash.firstFrame / combat.attackRate)
    local after = math.max(first + 1, math.ceil(dash.endFrame / combat.attackRate))
    if combat.elapsed >= first and combat.elapsed < after then
        return dash.distance, after - first, melee.direction
    end
end

local function recordMeleeHit(event, tick)
    event.id, event.tick = combat.action, tick or combat.tick
    if event.accepted then
        local player = playerNow()
        local context, stop = melee.damageContext, Config.MELEE.hitstop
        -- Only accepted enemy hits carry a position. Keep a spent zero on this swing's snapshot.
        if event.position and stop.actions[event.id] and stop.maxFrames > 0 and context.hitstopLeft == nil then
            context.hitstopLeft = math.min(stop.maxFrames, math.max(stop.minFrames, math.ceil(event.damage / stop.damagePerFrame)))
            if motion.stepDirection then
                -- Delay this authored iai step until the contact pose releases.
                context.heldDashVelocity = player.Velocity
                player.Velocity = Vector.Zero
            else
                player.Velocity = player.Velocity * stop.movementScale
            end
            game:ShakeScreen(stop.shake)
            event.hitstopFrames = context.hitstopLeft
        end
        local hunt = activeHunt(player)
        if hunt then
            Character.markEnemy(event.target)
            if event.huntCue then recordPart(hunt, event.huntCue) end
            if hunt.flySuit and Character.rollFly(player, melee.damageContext, flySuitId) then
                log("hunter_blue_fly", { target = event.target })
            end
        end
        if event.critical then
            local stage = event.id == "HELM_BREAKER" and event.hitStage or 1
            if melee.damageContext.lastCritFlashStage ~= stage then
                melee.damageContext.lastCritFlashStage = stage
                CritSlash.spawn(event.position, melee.direction)
                sfx:Play(sound.crit, 0.5, 0, false, 1.25)
                log("hunter_crit", { target = event.target, stage = stage, damage = event.damage })
            end
        else
            CritSlash.spawnNormal(event.position, event.id == "SPIRIT_III" and context, event.hitStage)
        end
        if event.id == "HELM_BREAKER" then
            -- All enemies caught in one cut share its impact sound.
            if motion.helm.lastSoundStage ~= event.hitStage then
                event.soundId = event.hitStage == combat.helmCuts.count and sound.helmFinish or sound.helmHit
                sfx:Play(event.soundId, 1, 0, false, 1)
                motion.helm.lastSoundStage = event.hitStage
            end
        elseif melee.lastHitSoundTick ~= event.tick then
            sfx:Play(sound.hit, 0.8, 0, false, 1)
            melee.lastHitSoundTick = event.tick
        end
    end
    lastMelee = event.id .. " " .. (event.accepted and "HIT " or "BLOCKED ") .. event.damage
    event.position, event.huntCue = nil, nil
    log("melee_hit", event)
end

local function startMelee(player)
    local direction = combat.action == "HELM_BREAKER" and motion.thrustDirection or motion.facing
    -- Helm damage uses the level that paid for it, not the remaining level after spending.
    local blade = combat.blade + (combat.action == "HELM_BREAKER" and 1 or 0)
    Melee.start(melee, player, combat.action, direction, blade, Config.MELEE, combat.source)
    local hunt = activeHunt(player)
    if melee.damageContext and hunt then
        melee.damageContext.critItemId = englishSwordId
        melee.damageContext.greavesCritBonus = Hunt.greavesCritBonus(hunt.gear.boots)
        melee.damageContext.jewelAffinity = Jewels.affinity(Jewels.level(hunt, "expert"))
        melee.damageContext.jewelCritMultiplier = Jewels.critMultiplier(Jewels.level(hunt, "critical"))
        if game:GetRoom():GetType() == RoomType.ROOM_BOSS then melee.observeHit = EarlyHunts.observe end
    end
    if combat.action == "HELM_BREAKER" then
        local origin = Vector(player.Position.X, player.Position.Y)
        motion.helm = { origin = origin, ground = origin }
        grantCounterShield(player, "HELM_BREAKER")
    end
    if melee.profile then
        -- The native tear roll supplies both width and color for this entire attack.
        local tear = WeaponSize.tearParams(player)
        size.reach = WeaponSize.reach(player, Config.MELEE.size)
        size.width, melee.trailColor = tear.TearScale / baseTearScale, tear.TearColor
        log("melee_start", { id = combat.action, facing = melee.facing,
            x = melee.direction.X, y = melee.direction.Y, head = player:GetHeadDirection(),
            rotation = Config.MELEE.visual.rotationByFacing[melee.facing],
            baseDamage = melee.damageContext.baseDamage, body = size.body, reach = size.reach,
            width = size.width, bladeScale = WeaponSize.bladeScale(size), baseTearScale = baseTearScale, tick = combat.tick })
    end
end

local function checkThrustHit(player, tick)
    if combat.action ~= "SPIRIT_THRUST" or combat.phase ~= "ACTIVE" then return false end
    local hits, length, halfWidth = Melee.update(melee, player, combat, Config.MELEE, size,
        motion.thrustPosition or player.Position)
    if showDebugText and length then
        -- Retain the box for this frame even if an accepted hit switches straight to takeoff.
        motion.debugThrustBox = { origin = player.Position, direction = melee.direction,
            length = length, halfWidth = halfWidth }
    end
    for _, event in ipairs(hits) do
        recordMeleeHit(event, tick)
        if event.accepted then
            log("thrust_contact", { target = event.target, tick = tick })
            return true
        end
    end
    return false
end

local function resolveThrustContact(player)
    if not checkThrustHit(player, combat.tick) then return end
    combat.nextAttackRate = Native.attackRate(player, Config.ACTIONS.baseFireRate)
    for _, event in ipairs(Actions.hit(combat, Config.ACTIONS)) do
        event.tick, event.blade = combat.tick, combat.blade
        log("action", event)
    end
    startMelee(player)
    Native.stopThrust(player, motion)
    return true
end

local function suspendCombat(reason, sheathe, preserveCharge)
    local player = playerNow()
    Melee.clear(melee)
    Native.stopStep(player, motion)
    Native.stopThrust(player, motion)
    if preserveCharge and combat.action == "CHARGE" and combat.phase == "HOLD"
        and Native.guard(game, player, itemId, true) and not player:IsDead() then
        -- Door transitions can disable controls before NEW_ROOM; freeze the live hold until input resumes.
        combat.pending, combat.repeatHeld = nil, {}
        log("charge_suspend", { reason = reason, charge = combat.chargeFrames, tick = combat.tick })
    else
        Actions.interrupt(combat, reason, sheathe)
        updateActionShield(player)
    end
    clearCombatInput(player)
end

local function syncOwnership(player)
    local held = Native.guard(game, player, itemId, true)
    if held ~= mode.held then
        mode.held, mode.pending, mode.origin = held, true, "ownership_changed"
        suspendCombat(held and "EQUIPPED" or "NOT_HELD", true)
    end
    if held and mode.pending and not player:IsDead() then
        -- Run once after equip/entry; never reset the character on every update.
        mode.pending = false
        local result = Native.ensureBlindfold(game, player, itemId)
        lastBlindfoldReason = result.reason
        session.watch = true
        if result.reason ~= "ALREADY_CANNOT_SHOOT" then
            result.origin = mode.origin
            log("auto_blindfold", result)
        end
    end
    return held
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    HunterHudPass.restore()
    GuildPassives.reset()
    releaseCombatView()
    waves = {}
    CritSlash.reset()
    local player = playerNow()
    if player then
        local data = player:GetData()
        data.longswordCombatView, data.longswordCounterShield = nil, nil
    end
    session = { watch = Config.WATCH_DEFAULT, blindfoldAttempted = false }
    lastDirections, lastStatus = {}, nil
    lastEquipReason = "not requested"
    lastBlindfoldReason = "not requested"
    taidaoUseCount = 0
    inputState, combat = Intents.new(), Actions.new()
    motion = Native.newMotion()
    melee, lastMelee = Melee.new(Config.MELEE), "none"
    size = WeaponSize.new()
    local reference = WeaponSize.reference(mod, game, player, continued, Config.MELEE.size)
    baseTearScale = reference or Config.MELEE.size.initialTearScale
    log("size_reference", { tearScale = baseTearScale, measured = reference ~= nil })
    pocket = { armed = false, pending = false, blocked = false }
    lastPocketInput, lastCancel = nil, "none"
    lastFacing = nil
    mode = { held = false, pending = true, origin = continued and "continue" or "new_game",
        rebase = true, suspended = false }
    huntRun, guild, menuInput, huntTiming = nil, nil, nil, Config.ACTIONS
    Locale.load(mod)
    syncSwordLanguage(player)
    Character.start(game, player, itemId, continued, Native)
    if Character.isHunter(game, player) then
        huntRun = Hunt.start(mod, game:GetSeeds():GetStartSeed(), continued)
        GuildPassives.start(player, huntRun.migrateGuildItems)
        if huntRun.migrateGuildItems then
            huntRun.migrateGuildItems = nil
            Hunt.save(mod, huntRun)
        end
        if huntRun.legacyGear then
            Gear.migrate(huntRun, player)
            huntRun.legacyGear = nil
            Hunt.save(mod, huntRun)
        end
        if huntRun.postMom == nil then
            huntRun.postMom = Field.legacyPostMom(game, huntRun)
            Hunt.save(mod, huntRun)
        end
        Vitals.start(game, player, huntRun, continued)
        guild = Workshop.new()
        huntTiming = Hunt.actionConfig(Config.ACTIONS, huntRun.gear.braces)
        enterHuntRoom(player)
        log("hunter_started", { continued = continued, materials = huntRun.materials, gear = huntRun.gear })
    end
    -- Resume held-item logging when continuing a run.
    mode.held = Native.guard(game, playerNow(), itemId, true)
    if mode.held then session.watch = true end
    log("game_started", { continued = continued, players = game:GetNumPlayers(), watch = session.watch })
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    HunterHudPass.restore()
    releaseCombatView()
    waves = {}
    Melee.clear(melee)
    mode.pending, mode.origin = true, "new_room"
    local player = playerNow()
    enterHuntRoom(player)
    Native.stopStep(player, motion)
    Native.stopThrust(player, motion)
    local preserved, chargePreserved = Actions.enterRoom(combat)
    updateActionShield(player)
    clearCombatInput(player)
    log("room_state", { preserved = preserved, posture = combat.posture,
        sheatheLeft = combat.sheatheRemaining, blade = combat.blade,
        chargePreserved = chargePreserved, charge = combat.chargeFrames,
        action = combat.action, phase = combat.phase })
end)

mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc)
    local run = activeHunt(playerNow())
    if not run then return end
    if npc:IsBoss() then
        if game:GetRoom():GetType() == RoomType.ROOM_BOSS then carvePosition = npc.Position end
    else
        local drop = Field.drop(npc, run.postMom)
        if drop then
            Character.noticeDrop(drop.Position)
            sfx:Play(SoundEffect.SOUND_SCAMPER, 0.55, 0, false, 1)
            log("hunter_material_drop", { target = npc.InitSeed })
        end
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    local run = activeHunt(playerNow())
    local room = game:GetRoom()
    if not run or room:GetType() ~= RoomType.ROOM_BOSS then return end
    local level = game:GetLevel()
    local lastBoss = level:GetLastBossRoomListIndex()
    local floorBoss = lastBoss < 0 or level:GetCurrentRoomDesc().ListIndex == lastBoss
    local xlBoss = not floorBoss and level:GetCurrentRoomIndex() >= 0
        and level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0
    local site = Field.site(room, carvePosition)
    local firstMomClear = floorBoss and not run.postMom and Field.isMomClear(room)
    if firstMomClear then
        if not run.testBladeWave then Character.announceBladeWave() end
        run.postMom = true
        run.testBladeWave = nil
        log("blade_wave_unlocked", { room = room:GetSpawnSeed() })
    end
    local remains = Hunt.leaveRemains(run, room:GetSpawnSeed(), site, floorBoss, xlBoss)
    if firstMomClear or remains then Hunt.save(mod, run) end
    if not remains then return end
    Workshop.announce(guild, Locale.text("Stand by the remains for 1 second to carve", "靠近首领残骸，站定一秒剥取"))
    log("hunter_remains", { room = room:GetSpawnSeed(), x = site.X, y = site.Y })
end)

mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, flag)
    if not Character.isHunter(game, player) then return end
    if flag == CacheFlag.CACHE_DAMAGE then
        local level = huntRun and Jewels.level(huntRun, "attack") or 0
        Vitals.damage(player, huntRun and huntRun.smithLevel or 0, Jewels.attackFlat(level), Jewels.attackMultiplier(level))
    elseif huntRun and flag == CacheFlag.CACHE_FIREDELAY then
        Vitals.tears(player, huntRun.smithSpeedLevel, Jewels.tearsBonus(Jewels.level(huntRun, "speed")))
    elseif huntRun and flag == CacheFlag.CACHE_RANGE then
        Vitals.range(player, huntRun.smithRangeLevel, Jewels.rangeBonus(Jewels.level(huntRun, "reach")))
    end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, function(_, pool, decrease, seed)
    local player = playerNow()
    if Character.isHunter(game, player) then return Loot.draw(game, player, pool, decrease, seed) end
end)

mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    if pickup.Variant == SupplyBox.variant then SupplyBox.update(pickup); return end
    if activeHunt(playerNow()) then Field.updatePickup(pickup) end
end)

mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
    HunterHudPass.restoreNextFrame()
    if menuInput and not game:IsPaused() and activeHunt(playerNow()) then
        local blocked = MenuInput.filter(menuInput, hook, action)
        if blocked ~= nil then return blocked end
    end
    local lockedHead = Visual.attackClips[combat.action] and melee.action == combat.action and melee.direction
    if combat.action == "IAI" and renderOwner then
        local view = renderOwner:GetData().longswordCombatView
        lockedHead = view.headDirection or lockedHead
    end
    return Native.filterInput(game, entity, hook, action, itemId, walkingLocked(),
        Config.CONTROLLER_AIM, motion, Config.MOUSE_AIM, lockedHead)
end)

local function guardHit(player, amount, flags, source, lostCollision)
    if not Native.inActionGuardWindow(combat, Config.ACTION_PROTECTION) then
        local shield = activeCounterShield(player)
        if not shield then return nil end
        log("counter_shield_block", { id = combat.action, tick = combat.tick,
            followsAction = shield.follow and true or nil,
            framesLeft = not shield.follow and (shield.expires - player.FrameCount) or nil,
            amount = amount, flags = flags, sourceType = source and source.Type, sourceVariant = source and source.Variant })
        return true
    end
    local firstGuard = Actions.confirmCounterGuard(combat)
    local counterReady = firstGuard and combat.action == "FORESIGHT"
    local shieldFrames
    if firstGuard then
        shieldFrames = grantCounterShield(player, combat.action)
        sfx:Play(sound.gp, 1, 0, false, 1)
        local result = MonstroHunt.onGuard(activeHunt(player), player, combat, melee, source)
        if result then log("hunter_counter", { result = result }) end
    end
    log("action_guard", { id = combat.action, phase = combat.phase, phaseFrame = combat.phaseFrame,
        amount = amount, flags = flags, tick = combat.tick, counterReady = counterReady or nil, lostCollision = lostCollision,
        blade = firstGuard and combat.action == "IAI" and combat.blade or nil,
        shieldFrames = not counterReady and shieldFrames or nil, shieldTailFrames = counterReady and shieldFrames or nil,
        sourceType = source and source.Type, sourceVariant = source and source.Variant })
    return true
end

mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    local player = entity:ToPlayer()
    if not Native.canGuardDamage(game, player, itemId, flags) then return end
    if source and source.Type == EntityType.ENTITY_FIREPLACE and source.Variant == 4 then return end
    -- Body contact can precede POST_UPDATE. Only an accepted thrust starts the jump and its shield.
    if combat.action == "SPIRIT_THRUST" and combat.phase == "ACTIVE" and resolveThrustContact(player) then
        motion.helmStartFrame = player.FrameCount
    end
    if guardHit(player, amount, flags, source) then return false end
end, EntityType.ENTITY_PLAYER)

mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, wisp)
    if GuildPassives.isWisp(wisp) then
        if Character.isHunter(game, wisp.Player) then GuildPassives.visit(wisp)
        else GuildPassives.remove(wisp) end
    end
end, FamiliarVariant.ITEM_WISP)

mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity)
    if GuildPassives.isWisp(entity) then return false end
end, EntityType.ENTITY_FAMILIAR)

mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, function(_, tear)
    if GuildPassives.isWisp(tear.SpawnerEntity) then tear:Remove() end
end)

mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, function(_, _, _, player)
    -- Sacrificial Altar must only consume the hunter's ordinary familiars.
    if activeHunt(player) then GuildPassives.update(nil) end
end, CollectibleType.COLLECTIBLE_SACRIFICIAL_ALTAR)

-- A Holy Mantle charge can absorb the contact before the player damage callback.
mod:AddCallback(ModCallbacks.MC_PRE_PLAYER_COLLISION, function(_, player, collider)
    if combat.action ~= "FORESIGHT" and combat.action ~= "IAI" and not activeCounterShield(player) then return end
    if not Native.guard(game, player, itemId, true) or player:IsDead()
        or not player:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE) then return end
    if Native.isLostGuardContact(collider) and guardHit(player, nil, nil, EntityRef(collider), true) then
        if collider.Type == EntityType.ENTITY_PROJECTILE then collider:Die() end
        return true
    end
end)

mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, command, params)
    if command == "ls_wave" then
        local run = activeHunt(playerNow())
        if (params or ""):find("%S") then
            Isaac.ConsoleOutput("Usage: ls_wave\n")
        elseif not run then
            Isaac.ConsoleOutput("Start a single-player Little Hunter run first.\n")
        elseif Hunt.hasBladeWave(run) then
            Isaac.ConsoleOutput("Blade wave is already unlocked for this run.\n")
        else
            run.testBladeWave = true
            Hunt.save(mod, run)
            Character.announceBladeWave()
            Isaac.ConsoleOutput("Blade wave unlocked for this run.\n")
        end
        return
    end
    if command == "ls_lang" then
        local mode = (params or ""):lower():match("^%s*(.-)%s*$")
        if Locale.set(mod, mode) then syncSwordLanguage(playerNow()) end
        Isaac.ConsoleOutput("Longsword language: " .. Locale.mode() .. " (" .. Locale.text("en", "zh")
            .. ").  ls_lang auto | en | zh\n")
        return
    end
    if command ~= Config.COMMAND then return nil end
    local action, arg = string.match(params or "", "^%s*(%S*)%s*(%S*)%s*$")
    local player = playerNow()
    local result
    if action == "status" and arg == "" then
        result = Native.inspect(game, player, itemId)
        result.watch = session.watch
        result.debugText = showDebugText
        result.blindfoldAttempted = session.blindfoldAttempted
    elseif action == "equip" and arg == "" then
        result = Native.equip(game, player, itemId)
        lastEquipReason = result.reason
    elseif action == "blindfold" and arg == "" then
        result = Native.blindfold(game, player, itemId, session)
        lastBlindfoldReason = result.reason
    elseif action == "watch" and (arg == "on" or arg == "off") then
        session.watch = arg == "on"
        showDebugText = session.watch
        lastDirections, lastStatus = {}, nil
        result = { watch = session.watch }
    else
        result = { help = "ls_probe status | equip | blindfold | watch on | watch off" }
    end
    Isaac.ConsoleOutput(log(action or "help", result) .. "\n")
    return nil
end)

local function updateCombat()
    if game:IsPaused() then
        if not mode.suspended then suspendCombat("PAUSED", false, true) end
        mode.suspended = true
        return
    end
    local player = playerNow()
    if menuInput and activeHunt(player) then return end
    if not player or motion.helmStartFrame ~= player.FrameCount then motion.debugThrustBox = nil end
    syncSwordLanguage(player)
    if player and game:GetNumPlayers() == 1 then ItemText.localizePickup(player, game:GetHUD()) end
    if Input.IsButtonTriggered(Config.DEBUG_TEXT_KEY, 0) then
        showDebugText = not showDebugText
        log("debug_text", { visible = showDebugText })
    end
    -- M0-only shortcut: test the same native equip path while console delivery is unresolved.
    if Input.IsButtonTriggered(Config.PROBE_EQUIP_KEY, 0) then
        log("hotkey_equip", { key = "F6" })
        local result = Native.equip(game, player, itemId)
        lastEquipReason = result.reason
        session.watch = true
        lastDirections, lastStatus = {}, nil
        log("equip", result)
    end
    local held = syncOwnership(player)
    if not session.watch and not held then return end
    local allowed, reason = Native.guard(game, player, itemId, true)
    local status = Native.inspect(game, player, itemId)
    status.reason = reason
    local fingerprint = encode(status)
    if fingerprint ~= lastStatus then
        if session.watch then log("status", status) end
        lastStatus = fingerprint
    end
    if not allowed then lastDirections = {}; return end
    if player:IsDead() or player.ControlsEnabled == false then
        if not mode.suspended or (player:IsDead() and combat.action ~= "NONE") then
            suspendCombat(player:IsDead() and "DEAD" or "CONTROLS_DISABLED", false, not player:IsDead())
        end
        mode.suspended = true
        return
    end
    mode.suspended = false
    if Input.IsButtonTriggered(Config.PROBE_BLADE_KEY, 0) then
        combat.blade = (combat.blade + 1) % 4
        log("debug_blade", { blade = combat.blade, key = "F8" })
    end
    local pocketDown, pocketCancelled, nativePocketDown = Native.readPocketInput(player, pocket)
    local pocketFingerprint = tostring(nativePocketDown) .. ":" .. tostring(pocketDown)
    if lastPocketInput ~= pocketFingerprint then
        log("pocket_input", { down = nativePocketDown, authorized = pocketDown,
            cancelled = pocketCancelled, posture = combat.posture, tick = combat.tick })
        lastPocketInput = pocketFingerprint
    end
    local raw = Native.readCombatInput(player, Config.COMBAT_BINDINGS, pocketDown)
    local device = Native.inputDevice(player)
    raw.POCKET_CANCEL = pocketCancelled
    local directions = { UP = raw.UP or raw.MOUSE_PRIMARY, RIGHT = raw.RIGHT, DOWN = raw.DOWN, LEFT = raw.LEFT }
    for _, direction in ipairs(Config.DIRECTIONS) do
        local current, previous = directions[direction.name], lastDirections[direction.name] or false
        if current ~= previous and session.watch then
            log("direction", { name = direction.name, pressed = current, canShoot = player:CanShoot(),
                button = device == "gamepad" and Config.COMBAT_BINDINGS[direction.name].button or nil })
        end
    end
    lastDirections = directions
    if mode.rebase then
        local charging = combat.action == "CHARGE" and combat.phase == "HOLD"
        Intents.reset(inputState, raw, charging)
        if charging then
            local chargeDown = raw.LEFT
            if combat.source == "MOUSE_PRIMARY" then chargeDown = raw.MOUSE_PRIMARY end
            log("charge_resume", { charge = combat.chargeFrames, held = chargeDown,
                source = combat.source, tick = combat.tick })
        end
        mode.rebase = false
    end
    local packet = Intents.sample(inputState, raw, combat.posture, Config.POCKET_COMBO_FRAMES,
        Config.MOUSE_SKILL_COMBO_FRAMES, combat.guardedAction == "FORESIGHT")
    for _, request in ipairs(packet.pressed) do log("intent", request) end
    for _, release in ipairs(packet.released) do log("intent_release", release) end
    if held then
        WeaponSize.readBody(size, player)
        -- Check the travelled ACTIVE segment before advancing its last tick to recovery.
        local contact = checkThrustHit(player, combat.tick + 1)
        -- A native collision may already have started 171 during this very engine update.
        packet.keepOpeningPose = combat.action == "HELM_BREAKER" and motion.helmStartFrame == player.FrameCount
        motion.helmStartFrame = nil
        packet.attackRate = Native.attackRate(player, Config.ACTIONS.baseFireRate)
        local previousCharge = combat.chargeFrames
        local contactContext = melee.damageContext
        packet.hitstop = contactContext and (contactContext.hitstopLeft or 0) > 0
        local stepStarted, thrustStarted, meleeStarted = false, false, false
        local hunt = activeHunt(player)
        for _, event in ipairs(Actions.update(combat, packet, hunt and huntTiming or Config.ACTIONS, contact)) do
            if event.kind == "start" then meleeStarted = true end
            if event.drewBlade and event.id ~= "IAI" then sfx:Play(sound.draw, 0.8, 0, false, 1) end
            if event.id == "SHEATHED_STEP" then
                event.sheatheLeft = combat.sheatheRemaining
                if event.kind == "start" then stepStarted = true end
            end
            if event.id == "SPIRIT_THRUST" and event.kind == "start" then thrustStarted = true end
            if event.kind == "cancel" then
                lastCancel = event.id .. " -> " .. event.reason .. " @ " .. event.phase
            end
            event.tick = combat.tick
            if event.kind == "blade" then event.blade = combat.blade end
            log("action", event)
        end
        updateActionShield(player)
        if packet.hitstop and not meleeStarted then
            contactContext.hitstopLeft = contactContext.hitstopLeft - 1
            if contactContext.heldDashVelocity then
                player.Velocity = contactContext.hitstopLeft == 0 and contactContext.heldDashVelocity or Vector.Zero
            elseif contactContext.hitstopLeft > 0 then
                player.Velocity = player.Velocity * Config.MELEE.hitstop.movementScale
            end
            -- The outer update still renders the held pose and runs the rest of the room.
            return
        end
        -- The first poses of 308 still hold the blade in its sheath.
        if combat.action == "IAI" and combat.elapsed == math.ceil(Config.IAI_DASH.firstFrame / combat.attackRate) then
            sfx:Play(sound.draw, 0.8, 0, false, 1)
        end
        if combat.action == "CHARGE" and previousCharge < Config.ACTIONS.chargeFrames
            and combat.chargeFrames >= Config.ACTIONS.chargeFrames then
            log("charge_full", { speed = combat.attackRate, tick = combat.tick })
        end
        local distance, travelFrames, attackDirection = stepTravel()
        if attackDirection and not motion.stepDirection then
            log("iai_dash", { direction = Native.directionName(attackDirection), distance = distance,
                frames = travelFrames, tick = combat.tick })
        end
        if combat.action ~= "HELM_BREAKER" or combat.phase == "RECOVERY" then
            motion.helm = nil
        elseif motion.helm then
            -- Resolve the ground point before measuring cursor direction from the shadow.
            Native.settleHelmPosition(player, motion.helm, Config.HELM_AIR_STEER.radius)
        end
        local movement = Native.updateMotion(player, motion, distance ~= nil,
            stepStarted, distance, travelFrames, walkingLocked(),
            Config.CONTROLLER_AIM, Config.MOUSE_AIM, attackDirection)
        if meleeStarted then startMelee(player) end
        if combat.action == "NONE" or (combat.action ~= "HELM_BREAKER" and walkingLocked()) then
            size.reach = WeaponSize.reach(player, Config.MELEE.size)
        end
        local facing = { head = player:GetHeadDirection(), moveX = movement.X, moveY = movement.Y,
            controller = player.ControllerIndex, device = device, aimX = motion.aim.X, aimY = motion.aim.Y,
            face = Native.directionName(motion.facing), walkingLocked = walkingLocked() }
        if motion.aimSample then
            for key, value in pairs(motion.aimSample) do facing[key] = value end
            if device == "gamepad" then
                facing.buttons = (raw.MOUSE_PRIMARY and "Y" or "-") .. (raw.RIGHT and "B" or "-")
                    .. (raw.LEFT and "X" or "-") .. (raw.DOWN and "A" or "-")
            end
        end
        local facingFingerprint = encode(facing)
        if facingFingerprint ~= lastFacing then
            log("facing", facing)
            lastFacing = facingFingerprint
        end
        if stepStarted then
            if hunt and (hunt.spur or hunt.spurPlus) and Character.spurPounce(player, hunt.spurPlus and 2 or 1) then
                log("hunter_spur", { rank = hunt.spurPlus and 2 or 1 })
            end
            log("step_motion", { direction = motion.stepFacing,
                x = motion.stepDirection.X, y = motion.stepDirection.Y,
                distance = distance, speed = distance / Config.ACTIONS.stepFrames,
                frames = Config.ACTIONS.stepFrames,
                sheatheLeft = combat.sheatheRemaining, tick = combat.tick })
        end
        local enteringActive = Native.updateThrust(player, motion, combat, thrustStarted,
            Config.SPIRIT_THRUST, combat.activeTicks)
        if thrustStarted then
            log("thrust_motion", { x = motion.thrustDirection.X, y = motion.thrustDirection.Y,
                distance = Config.SPIRIT_THRUST.distance, blade = combat.blade, tick = combat.tick })
        end
        -- Also allow contact at the instant startup enters ACTIVE.
        if enteringActive then resolveThrustContact(player) end
        if motion.helm then
            local facing = Native.updateHelm(player, motion, combat.phase, Config.HELM_AIR_STEER, melee.direction)
            if facing then
                Melee.setDirection(melee, facing)
                if combat.phase == "ACTIVE" then
                    sfx:Play(sound.helm, 0.32, 0, false, 1)
                    log("helm_land", { facing = melee.facing, x = player.Position.X, y = player.Position.Y,
                        cuts = combat.helmCuts.count, tick = combat.tick })
                end
            end
        end
        local hits, reach = Melee.update(melee, player, combat, Config.MELEE, size)
        -- A move exposes its reach on its first damaging pose, even on a whiff.
        -- Spirit Thrust has its own contact path; Helm releases once at the locked landing.
        if hunt and Hunt.hasBladeWave(hunt) and reach and not melee.damageContext.waveEmitted then
            melee.damageContext.waveEmitted = true
            Wave.emit(waves, player, melee.landingPosition or player.Position, melee.direction, reach)
            log("blade_wave", { id = combat.action, tick = combat.tick, reach = reach })
        end
        for _, hit in ipairs(hits) do
            recordMeleeHit(hit)
            checkToothBreak(hunt, hit)
            if hit.accepted then
                for _, event in ipairs(Actions.hit(combat, Config.ACTIONS)) do
                    event.tick, event.blade = combat.tick, combat.blade
                    log("action", event)
                end
            end
        end
    end
end

local function updateWorkshop(player, run, busy)
    if player:IsDead() then
        Workshop.close(guild)
        menuInput = nil
        return
    end
    local wasOpen = Workshop.isOpen(guild)
    local action, cursor
    if wasOpen then
        action, cursor = MenuInput.read(menuInput, player)
    end
    local canOpen = not menuInput and not busy and player.ControlsEnabled
    Workshop.update(guild, game, player, run, craftGear, toggleCampLanguage, action, cursor, canOpen)
    if not wasOpen and Workshop.isOpen(guild) then
        menuInput = MenuInput.open(player)
        guild.orderSelected = menuInput.mouse == nil
        clearCombatInput(player)
        player.Velocity = Vector(0, 0)
    elseif menuInput and not Workshop.isOpen(guild)
        and MenuInput.released(menuInput, player, Config.COMBAT_BINDINGS) then
        menuInput = nil
        local pocketDown = Native.readPocketInput(player, pocket)
        Intents.reset(inputState, Native.readCombatInput(player, Config.COMBAT_BINDINGS, pocketDown))
        mode.rebase = false
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    HunterHudPass.restore()
    updateCombat()
    local player = playerNow()
    if not game:IsPaused() then
        Character.syncHelmet(game, player)
        Character.updateCat(game, player)
        local run = activeHunt(player)
        GuildPassives.update(run and player)
        if #waves > 0 then
            if run and not player:IsDead() and Native.guard(game, player, itemId, true) then
                for _, position in ipairs(Wave.update(waves, game:GetRoom())) do
                    CritSlash.spawnWave(position)
                end
            else
                waves = {}
            end
        end
        if run then
            local trackChanged, bossMarked = Scout.update(game, player)
            if trackChanged then Hunt.save(mod, run) end
            if bossMarked then Workshop.announce(guild, Locale.text("Boss room marked", "已标出首领房")) end
            if syncGear(run, player) then Hunt.save(mod, run) end
            local bought = Field.redeemShopBundles(player)
            if bought > 0 then
                run.materials = run.materials + bought
                Hunt.save(mod, run)
                log("hunter_material_purchase", { amount = bought, balance = run.materials })
            end
            if Vitals.update(game, player, run) then Hunt.save(mod, run) end
            if Guild.update(game, run) then
                Workshop.enterRoom(guild, game, player, run, true)
                if Jewels.redeliver(run, placeJewel) then Hunt.save(mod, run) end
            end
            local busy = combat.action ~= "NONE" or inPickupPose(player)
            local carved, moved = Field.updateCarve(guild, run, game:GetRoom(), player,
                busy or menuInput ~= nil, Character.sendCat)
            if moved then Hunt.save(mod, run) end
            if carved then carveReward(run, carved) end
            updateWorkshop(player, run, busy)
        else
            Scout.leave()
            if menuInput then
                Workshop.close(guild)
                menuInput = nil
            end
        end
    end
    syncCombatView()
end)

-- The engine skips drawing the real player while the blank host occupies its
-- room depth. Its pass does not depend on an invisible player's render callback.
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, function(_, effect, renderOffset)
    if not renderOwner or not renderHost or GetPtrHash(effect) ~= GetPtrHash(renderHost) then return end
    local player = renderOwner
    if inPickupPose(player) then
        releaseCombatView()
        return
    end
    local view = player:GetData().longswordCombatView
    local origin = playerRenderOrigin(player, renderOffset)
    local carving = activeHunt(player) and guild.carveTicks > 0
    local headDip = carving and Vector(0, 4 + math.sin(guild.carveTicks * 0.6) * 1.5) or nil
    player.Visible = originalVisibility
    if view.lift > 0 then
        player:RenderShadowLayer(renderOffset)
        origin = origin + Vector(0, -view.lift)
    end
    if view.clip == "SheathedWeapon" then
        Visual.drawSheathedPlayer(view, player, origin, headDip)
    else
        local headOrigin = Visual.drawBehindHead(view, origin)
        player:RenderHead(headDip and headOrigin + headDip or headOrigin)
        Visual.drawInFrontOfHead(view, origin)
    end
    player.Visible = false
    drawCounterShield(player, origin)
end, hostVariant)

mod:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, function(_, player, renderOffset)
    if player.Visible and not renderOwner then drawCounterShield(player, playerRenderOrigin(player, renderOffset)) end
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    HunterHudPass.restore()
    GuildPassives.reset()
    Scout.leave()
    waves = {}
    releaseCombatView()
    if guild then Field.clear(guild) end
    huntRun, guild, menuInput = nil, nil, nil
end)

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    local player = collider:ToPlayer()
    if pickup.Variant == SupplyBox.variant then
        local run = activeHunt(player)
        if run and SupplyBox.open(game, pickup, player, run) then
            Hunt.save(mod, run)
            sfx:Play(SoundEffect.SOUND_CHEST_OPEN, 1, 0, false, 1)
            log("hunter_supply_box_opened", { floor = run.floor })
        end
        return true
    end
    if pickup.Variant == PickupVariant.PICKUP_HEART and activeHunt(player) then
        return Field.offerShopBundle(pickup, player)
    end
    if pickup.Variant == Field.materialVariant() then
        local run = activeHunt(player)
        if run then
            local amount = Field.collect(pickup, player)
            if amount then
                run.materials = run.materials + amount
                Hunt.save(mod, run)
                sfx:Play(SoundEffect.SOUND_LUCKYPICKUP, 0.65, 0, false, 1)
                log("hunter_material_pickup", { amount = amount, balance = run.materials })
            end
        end
        return true
    end
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and (pickup.SubType == englishSwordId or pickup.SubType == chineseSwordId)
        and Native.guard(game, player, itemId, false) then return true end
end)

local function useSword(_, usedId, _, player, flags, slot, varData)
    -- The native selected-item callback grants pocket input; raw Q/card use cannot grant it.
    if usedId ~= englishSwordId and usedId ~= chineseSwordId then return nil end
    if menuInput and activeHunt(player) then return { Discharge = false, Remove = false, ShowAnim = false } end
    log("item_use_callback", { id = usedId, slot = slot, flags = flags, watch = session.watch })
    local allowed, reason = Native.guard(game, player, usedId, true)
    if slot ~= ActiveSlot.SLOT_POCKET or not allowed then
        log("item_use_ignored", { slot = slot,
            reason = slot ~= ActiveSlot.SLOT_POCKET and "NOT_PERMANENT_SLOT" or reason })
        return nil
    end
    taidaoUseCount = taidaoUseCount + 1
    session.watch = true
    log("POCKET_USE_TAIDAO", { id = usedId, slot = slot, flags = flags, varData = varData,
        charge = player:GetActiveCharge(slot), count = taidaoUseCount })
    if not pocket.armed and not pocket.blocked and not game:IsPaused()
        and not player:IsDead() and player.ControlsEnabled ~= false then
        pocket.armed, pocket.pending = true, true
    end
    -- Sword combat owns the feedback; suppress only this item's old pickup animation.
    return { Discharge = false, Remove = false, ShowAnim = false }
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, useSword, englishSwordId)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, useSword, chineseSwordId)

mod:AddCallback(ModCallbacks.MC_USE_CARD, function(_, cardId, player, flags)
    pocket.armed, pocket.pending, pocket.blocked = false, false, true
    if watchedPlayer(player) then log("card_used", { id = cardId, flags = flags }) end
    return nil
end)

mod:AddCallback(ModCallbacks.MC_USE_PILL, function(_, pillEffect, player, flags)
    pocket.armed, pocket.pending, pocket.blocked = false, false, true
    if watchedPlayer(player) then log("pill_used", { effect = pillEffect, flags = flags }) end
    return nil
end)

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    -- Render still runs in the pause menu, where normal update callbacks can stop.
    if menuInput and game:IsPaused() and Workshop.isOpen(guild) then Workshop.close(guild) end
    if game:IsPaused() and not mode.suspended then
        suspendCombat("PAUSED", false, true)
        mode.suspended = true
        syncCombatView()
    end
    local player = playerNow()
    if not player then return end
    local hunting = activeHunt(player)
    if hunting and not game:IsPaused() then
        if #waves > 0 then WaveVisual.render(waves) end
        Workshop.render(guild, game, player, huntRun, Character.bladeWaveNoticePosition())
        if Workshop.isOpen(guild) then
            Native.renderMouseCursor(player, Config.MOUSE_CURSOR)
            return
        end
        if game:GetHUD():IsVisible() then Scout.render() end
    end
    local hudVisible = game:GetHUD():IsVisible()
    if hudVisible and game:GetNumPlayers() == 1 then ItemText.renderPickup(player) end
    local holdingSword = Native.guard(game, player, itemId, true)
    if holdingSword then
        if hudVisible then
            local position, primary = Native.pocketBladePosition(player, Config.BLADE_BAR)
            if not hunting then Native.renderBladeBar(position, combat.blade, Config.BLADE_BAR) end
            if primary and Locale.isChinese() and Options.Language ~= "zh" then ItemText.renderPocketName(position) end
        end
        local pickingUp = inPickupPose(player)
        if not renderOwner and not pickingUp then
            Melee.render(melee, player, combat, Config.ACTIONS.frames, Config.MELEE, size)
        end
        -- Normal weapon UI remains visible when diagnostic text is hidden.
        if not game:IsPaused() and player.ControlsEnabled and not player:IsDead() then
            if not pickingUp then
                if showDebugText then Melee.renderHitArea(melee, player, combat, size, motion.debugThrustBox) end
                Native.renderChargeIndicator(player, combat, Config.ACTIONS, Config.CHARGE_INDICATOR)
            end
            Native.renderMouseCursor(player, Config.MOUSE_CURSOR)
        end
    end
    if not showDebugText then return end
    local status = Native.inspect(game, player, itemId)
    local device = Native.inputDevice(player)
    local t, value = Locale.text, DebugText.value
    if device == "gamepad" then device = t("pad=", "手柄=") .. player.ControllerIndex end
    local speed = combat.action == "NONE" and Native.attackRate(player, Config.ACTIONS.baseFireRate) or combat.attackRate
    -- Keep only current state on screen; event details and bindings remain in log.txt.
    local rows = {
        t("LS PROTOTYPE v", "太刀测试版 v") .. version .. " | " .. value(device) .. t(" | held=", " | 持刀=") .. value(status.held),
        string.format(t("Move: %.2f,%.2f | Aim: %.2f,%.2f", "移动 %.2f,%.2f | 瞄准 %.2f,%.2f"),
            motion.movement.X, motion.movement.Y, motion.aim.X, motion.aim.Y),
        t("Face: ", "朝向 ") .. value(Native.directionName(combat.action == "HELM_BREAKER" and melee.direction or motion.facing))
            .. t(" | head=", " | 头向=") .. player:GetHeadDirection()
            .. t(" | canShoot=", " | 可射泪=") .. value(status.canShoot),
        t("Pose: ", "姿态 ") .. value(combat.posture) .. t(" | blade=", " | 刃等级=") .. combat.blade,
        string.format(t("Action: %s | %s %d | x%.2f", "招式 %s | %s %d | x%.2f"), value(combat.action), value(combat.phase), combat.phaseFrame, speed),
        t("Charge: ", "蓄力 ") .. math.floor(combat.chargeFrames) .. "/" .. Config.ACTIONS.chargeFrames
            .. t(" | Sheathe left: ", " | 纳刀剩余 ") .. combat.sheatheRemaining,
        t("Walking: ", "移动状态 ") .. value(walkingLocked() and "LOCKED" or "FREE")
            .. t(" | Step: ", " | 闪身 ") .. value(motion.stepFacing) .. t(" | Q uses: ", " | 口袋使用 ") .. taidaoUseCount,
        status.held and (t("Request: ", "输入 ") .. value(combat.lastRequest) .. " | " .. value(combat.reason))
            or (t("F6 equip: ", "F6 装备 ") .. value(lastEquipReason)),
    }
    for index, text in ipairs(rows) do
        DebugText.draw(text, Config.TEXT_X, Config.TEXT_Y + (index - 1) * Config.TEXT_STEP)
    end
end)

local function paintHunterHud(player)
    local holdingSword = Native.guard(game, player, itemId, true)
    HunterHealthHud.render(game, player, holdingSword and combat.blade or nil)
    GuildChanceHud.render(game, player)
end

-- Restore before other HUD consumers, then composite after their normal renders.
mod:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, unloading)
    if unloading == mod then HunterHudPass.restore() end
end)
mod:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, -10000, HunterHudPass.restoreNextFrame)
mod:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, 10000, function()
    local player = playerNow()
    if not activeHunt(player) or game:IsPaused() or player:IsDead() or Workshop.isOpen(guild) then return end
    if game:GetSeeds():HasSeedEffect(SeedEffect.SEED_NO_HUD) then return end
    HunterHudPass.draw(game:GetHUD(), paintHunterHud, player)
end)

log("bindings", Config.COMBAT_BINDINGS)
log("mouse_cursor", Config.MOUSE_CURSOR)
log("mouse_aim", { enabled = Config.MOUSE_AIM.enabled, minDistance = Config.MOUSE_AIM.minDistance,
    source = "player_to_cursor", capture = false })
log("controller_aim", { deadzone = Config.CONTROLLER_AIM.deadzone, source = "Input.GetButtonValue_axes",
    moveButtons = "physical", axes = Config.CONTROLLER_AIM.axes })
log("load", { itemId = itemId, repentance = REPENTANCE, repentancePlus = REPENTANCE_PLUS,
    watch = session.watch, version = "prototype-" .. version })
log("skill_timing", { pocketFrames = Config.POCKET_COMBO_FRAMES,
    mouseFrames = Config.MOUSE_SKILL_COMBO_FRAMES })
