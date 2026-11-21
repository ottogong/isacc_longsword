-- Native sprite presentation for drawn movement and attacks. The caller owns
-- the player's render pass and advances combat state on the logic clock.
local head = include("scripts.longsword_head_offsets")
local walkHead = include("scripts.walk_head_offsets")
local cycleHead = include("scripts.thrust_rising_head_offsets")
local spiritHead = include("scripts.spirit_head_offsets")
local roundSlashHead = include("scripts.roundslash_head_offsets")
local foresightHead = include("scripts.foresight_head_offsets")
local sheatheHead = include("scripts.special_sheathe_head_offsets")
local charge = include("scripts.spirit_charge_poses")
local iaiHead = include("scripts.iai_head_offsets")
local helm = include("scripts.helm_breaker_poses")
local weaponAnchors = include("scripts.weapon_anchors")
local trailTips = include("scripts.spirit_trail_tips")
for clip, tips in pairs(include("scripts.counter_trail_tips")) do trailTips[clip] = tips end
for clip, tips in pairs(include("scripts.helm_trail_tips")) do trailTips[clip] = tips end
trailTips.Slash = include("scripts.slash_trail_tips")
local glowPalette = include("scripts.glow_trail_palette")
local backAnchors = include("scripts.sheathed_walk_anchors")
local WeaponSize = include("scripts.weapon_size")
local Visual = {}
Visual.attackClips = {
    NORMAL = "Slash", THRUST = "Thrust", RISING = "Rising",
    SPIRIT_I = "SpiritI", SPIRIT_II = "SpiritII", SPIRIT_III = "SpiritIII",
    ROUND_SLASH = "RoundSlash", FORESIGHT = "Foresight", IAI = "Iai",
    SPIRIT_THRUST = "SpiritThrust", HELM_BREAKER = "HelmTakeoff",
}

local faces = { DOWN = "Down", LEFT = "Left", UP = "Up", RIGHT = "Right" }
local quarterTurns = { Down = 0, Right = 1, Up = 2, Left = 3 }
local headDirections = { Vector(0, 1), Vector(1, 0), Vector(0, -1), Vector(-1, 0) }
local loopFrames = { Idle = 30, Walk = 25, SheatheHold = #sheatheHead.SheatheHold.Down }
local BODY = 1
local baseSize = { x = 1, y = 1, body = 1, reach = 1, width = 1 }
-- Each facing uses a different set of atlas pages for the scabbard and weapon.
local spiritSide = { scabbard = 3, weapon = 5 }
local spiritLayers = {
    Down = { scabbard = 0, weapon = 2 }, Up = { scabbard = 0, weapon = 4 },
    Left = spiritSide, Right = spiritSide,
}
local glowPath = "gfx/isacc_longsword/glow_trail/glow_trail"

function Visual.new()
    local sprite = Sprite()
    sprite:Load("gfx/isacc_longsword/isaac_longsword.anm2", true)
    return { sprite = sprite, baseSprite = sprite }
end

local function paletteFor(color)
    if not color then return "white" end
    if color.A <= 0 then return "transparent" end
    -- Sample a light grey in the ribbon. Positive offsets can change its hue
    -- even when all three native multipliers are white.
    local grey = 0.7
    local r = math.max(0, math.min(1, color.R * grey + color.RO))
    local g = math.max(0, math.min(1, color.G * grey + color.GO))
    local b = math.max(0, math.min(1, color.B * grey + color.BO))
    local peak = math.max(grey, r, g, b)
    r, g, b = r / peak, g / peak, b / peak
    local name, best = "white", math.huge
    for _, swatch in ipairs(glowPalette) do
        local distance = (swatch.r - r)^2 + (swatch.g - g)^2 + (swatch.b - b)^2
        if distance < best then name, best = swatch.name, distance end
    end
    return name
end

local function syncGlow(view, clip, facing, animation, frame, color)
    local tips = trailTips[clip]
    view.trailTip = tips and tips[facing][frame]
    if not view.trailTip then return end
    if not view.glowSprite then
        view.glowSprite = Sprite()
        view.glowSprite:Load(glowPath .. ".anm2", false)
    end
    if not view.glowPalette or view.trailColor ~= color then
        local palette = paletteFor(color)
        if view.glowPalette ~= palette then
            local suffix = palette == "white" and "" or "_" .. palette
            view.glowSprite:ReplaceSpritesheet(0, glowPath .. suffix .. ".png")
            view.glowSprite:LoadGraphics()
            view.glowPalette = palette
        end
        view.trailColor = color
    end
    view.glowSprite:SetFrame(animation, frame)
end

-- Both airborne clips are drawn in place. Pose may loop, but height always falls to the landing.
local function helmPose(combat, timing)
    if combat.phase ~= "STARTUP" then
        local tick = combat.phaseFrame + (combat.phase == "RECOVERY" and timing.active or 0)
        return "HelmLand", math.min(tick * 2, #helm.head.HelmLand.Down - 1), 0
    end
    local age = math.min(combat.authoredTime, timing.startup - 0.5)
    if age < timing.takeoffTicks then
        local curve = helm.lift.HelmTakeoff
        local frame = math.min(math.floor(age * 2), #curve - 1)
        local rise = (curve[frame + 1] - curve[1]) / (curve[#curve] - curve[1])
        return "HelmTakeoff", frame, timing.jumpHeight * rise
    end
    local curve = helm.lift.HelmFall
    -- Advance pose and height on the same accelerated clock, including repeated fall poses.
    local fallAge = math.min((age - timing.takeoffTicks) * timing.fallSpeed, timing.fallSourceTicks - 0.5)
    local frame = math.floor(fallAge * 2)
    if frame >= #curve then
        local loop = helm.lift.loopStart - 1
        frame = loop + (frame - #curve) % (#curve - loop)
    end
    local progress = fallAge / timing.fallSourceTicks
    local sample = 1 + math.floor(progress * (#curve - 1))
    return "HelmFall", frame, timing.jumpHeight * curve[sample] / curve[1]
end

-- Call after the current tick's action transitions and attack-facing snapshot.
function Visual.sync(view, combat, idleFacing, lockedFacing, timing)
    local clip, facing, frame
    view.lift = 0
    view.toothCharm = combat.toothCharm
    if combat.action == "NONE" and combat.posture == "SHEATHED_FREE" and combat.nativeBodyAnimation then
        facing = combat.nativeBodyAnimation:match("^Walk(%a+)$")
        frame = combat.moving and combat.nativeBodyFrame or 0
        local anchor = backAnchors[facing] and backAnchors[facing][frame + 1]
        if anchor then
            if not view.backSprite then
                view.backSprite = Sprite()
                view.backSprite:Load("gfx/isacc_longsword/sheathed_walk/sheathed_walk.anm2", true)
            end
            view.sprite = view.backSprite
            view.sprite:SetFrame((combat.moving and "Walk" or "Idle") .. facing, frame)
            view.clip, view.facing, view.frame = "SheathedWeapon", facing, frame
            view.head, view.headDirection = nil, nil
            view.weaponLayer, view.scabbardLayer = 0, nil
            view.trailTip = nil
            view.size, view.anchors = combat.size or baseSize, anchor
            return true
        end
    elseif combat.action == "CHARGE" and combat.chargeProgress then
        clip, facing = "SpiritCharge", faces[idleFacing:upper()]
        frame = math.floor(combat.chargeProgress * (#charge.head[facing] - 1) + 1e-9)
    elseif combat.action == "SPECIAL_SHEATHE" and combat.phase == "STARTUP" then
        clip, facing = "SheatheEntry", faces[idleFacing:upper()]
        frame = math.floor(combat.phaseFrame * #sheatheHead.SheatheEntry[facing] / timing.startup)
    elseif combat.posture == "SPECIAL_SHEATHE"
        or (combat.action == "NONE" and combat.posture == "DRAWN_FREE" and combat.phase == "IDLE") then
        -- A sheathed step carries the same stance through its displacement.
        clip = combat.posture == "SPECIAL_SHEATHE" and "SheatheHold" or (combat.moving and "Walk" or "Idle")
        facing = faces[idleFacing:upper()]
        -- Changing aim keeps the same footfall; starting or stopping begins a fresh loop.
        if view.clip ~= clip or combat.tick < view.loopStart then view.loopStart = combat.tick end
        frame = (combat.tick - view.loopStart) % loopFrames[clip]
    elseif Visual.attackClips[combat.action] and lockedFacing then
        clip = Visual.attackClips[combat.action]
        facing = faces[lockedFacing:upper()]
        if combat.action == "HELM_BREAKER" then
            clip, frame, view.lift = helmPose(combat, timing)
        elseif combat.phase == "STARTUP" then frame = combat.phaseFrame
        elseif combat.phase == "ACTIVE" then frame = timing.startup + combat.phaseFrame
        elseif combat.phase == "RECOVERY" then frame = timing.startup + timing.active + combat.phaseFrame end
        if clip == "SpiritThrust" then frame = math.min(frame * 2, #helm.head[clip].Down - 1) end
    end
    if clip and facing and frame then
        view.scabbardLayer = 0
        if clip == "SpiritCharge" then
            if not view.chargeSprite then
                view.chargeSprite = Sprite()
                view.chargeSprite:Load("gfx/isacc_longsword/spirit_charge/spirit_charge.anm2", true)
            end
            view.sprite, view.head = view.chargeSprite, charge.head[facing]
            local layers = charge.layers[facing]
            view.scabbardLayer, view.weaponLayer = layers[1], layers[2]
        elseif helm.head[clip] then
            view.helmSprites = view.helmSprites or {}
            if not view.helmSprites[clip] then
                local sprite = Sprite()
                sprite:Load("gfx/isacc_longsword/helm_breaker/" .. clip .. "/anim.anm2", true)
                view.helmSprites[clip] = sprite
            end
            view.sprite, view.head = view.helmSprites[clip], helm.head[clip][facing]
            local layers = helm.layers[clip][facing]
            view.scabbardLayer, view.weaponLayer = layers[1], layers[2]
        elseif sheatheHead[clip] then
            if not view.sheatheSprite then
                view.sheatheSprite = Sprite()
                view.sheatheSprite:Load("gfx/isacc_longsword/special_sheathe/special_sheathe.anm2", true)
            end
            view.sprite, view.head = view.sheatheSprite, sheatheHead[clip][facing]
            view.weaponLayer = 2
        elseif clip == "Iai" then
            if not view.iaiSprite then
                view.iaiSprite = Sprite()
                view.iaiSprite:Load("gfx/isacc_longsword/iai/iai.anm2", true)
            end
            view.sprite, view.head = view.iaiSprite, iaiHead.Iai[facing]
            view.weaponLayer = 2
        elseif clip == "Walk" then
            if not view.walkSprite then
                view.walkSprite = Sprite()
                view.walkSprite:Load("gfx/isacc_longsword/walk/walk.anm2", true)
            end
            view.sprite, view.head = view.walkSprite, walkHead.Walk[facing]
            view.weaponLayer = 2
        elseif clip == "Foresight" then
            if not view.foresightSprite then
                view.foresightSprite = Sprite()
                view.foresightSprite:Load("gfx/isacc_longsword/foresight/foresight.anm2", true)
            end
            view.sprite, view.head = view.foresightSprite, foresightHead.Foresight[facing]
            view.weaponLayer = 2
        elseif clip == "RoundSlash" then
            if not view.roundSlashSprite then
                view.roundSlashSprite = Sprite()
                view.roundSlashSprite:Load("gfx/isacc_longsword/roundslash/roundslash.anm2", true)
            end
            view.sprite, view.head = view.roundSlashSprite, roundSlashHead.RoundSlash[facing]
            view.weaponLayer = 2
        elseif spiritHead[clip] then
            if not view.spiritSprite then
                view.spiritSprite = Sprite()
                view.spiritSprite:Load("gfx/isacc_longsword/spirit/spirit.anm2", true)
            end
            view.sprite, view.head = view.spiritSprite, spiritHead[clip][facing]
            local layers = spiritLayers[facing]
            view.scabbardLayer, view.weaponLayer = layers.scabbard, layers.weapon
        elseif clip == "Thrust" or clip == "Rising" then
            if not view.cycleSprite then
                view.cycleSprite = Sprite()
                view.cycleSprite:Load("gfx/isacc_longsword/thrust_rising/thrust_rising.anm2", true)
            end
            view.sprite, view.head = view.cycleSprite, cycleHead[clip][facing]
            -- The side views of 112/107 use the second weapon atlas.
            view.weaponLayer = (facing == "Left" or facing == "Right") and 3 or 2
        else
            view.sprite, view.head = view.baseSprite, head[clip][facing]
            view.weaponLayer = 2
        end
        local animation = clip .. facing
        view.sprite:SetFrame(animation, frame)
        view.clip, view.facing, view.frame = clip, facing, frame
        syncGlow(view, clip, facing, animation, frame, combat.trailColor)
        view.headDirection = nil
        if clip == "Iai" then
            -- The sheet contains the entire turn. Only the native head needs rotating.
            for i = #iaiHead.turns, 1, -1 do
                local cue = iaiHead.turns[i]
                if frame >= cue[1] then
                    view.headDirection = headDirections[(quarterTurns[facing] + cue[2]) % 4 + 1]
                    break
                end
            end
        end
        view.size = combat.size or baseSize
        view.anchors = (charge.anchors[clip] or helm.anchors[clip] or weaponAnchors[clip])[facing][frame + 1]
        return true
    end
    view.clip, view.facing, view.frame, view.headDirection = nil, nil, nil, nil
    return false
end

local function drawLayer(view, layer, origin, glow)
    local size = view.size
    local sprite = glow or view.sprite
    local sx, sy = size.x, size.y
    if layer ~= BODY then
        local length = WeaponSize.bladeScale(size)
        sx, sy = length, length
        local index = layer == view.scabbardLayer and 3 or 1
        local px, py = view.anchors[index], view.anchors[index + 1]
        origin = origin + Vector((size.x - length) * px, (size.y - length) * py)
        if glow then
            if view.facing == "Left" or view.facing == "Right" then sy = length * size.width
            else sx = length * size.width end
            px, py = view.trailTip[1], view.trailTip[2]
            origin = origin + Vector((length - sx) * px, (length - sy) * py)
        end
    end
    local previous = sprite.Scale
    local previousX, previousY = previous.X, previous.Y
    local id = glow and 0 or layer
    if sx == previousX and sy == previousY then
        sprite:RenderLayer(id, origin)
        return
    end
    sprite.Scale = Vector(sx, sy)
    sprite:RenderLayer(id, origin)
    sprite.Scale = Vector(previousX, previousY)
end

local function drawWeaponAndTrail(view, origin)
    if view.trailTip then
        drawLayer(view, view.weaponLayer, origin, view.glowSprite)
    end
    drawLayer(view, view.weaponLayer, origin)
end

-- The packed back weapon anchors at the spine. These offsets reach the guard
-- in the four idle atlas cells; attack clips already carry the sheath dock.
local backToGuard = { Down = {-20, -10}, Up = {20, -10}, Left = {10, -15}, Right = {-10, -15} }
local toothSprite
local function drawScabbard(view, origin)
    local onBack = view.clip == "SheathedWeapon"
    drawLayer(view, onBack and view.weaponLayer or view.scabbardLayer, origin)
    if not view.toothCharm then return end
    if not toothSprite then
        toothSprite = Sprite()
        toothSprite:Load("gfx/005.100_collectible.anm2", false)
        toothSprite:ReplaceSpritesheet(1, "gfx/items/collectibles/collectibles_086_monstrostooth.png")
        toothSprite:LoadGraphics()
        toothSprite:SetFrame("Idle", 0)
    end
    local size = view.size
    local x, y
    if onBack then
        local offset, length = backToGuard[view.facing], WeaponSize.bladeScale(size)
        x = view.anchors[1] * size.x + offset[1] * length
        y = view.anchors[2] * size.y + offset[2] * length
    else
        x, y = view.anchors[3] * size.x, view.anchors[4] * size.y
    end
    toothSprite.Scale = Vector(0.4 * size.body, 0.4 * size.body)
    -- The native pickup layer's 32px pivot sits below the pictured tooth.
    toothSprite:RenderLayer(1, origin + Vector(x, y + 13 * size.body))
end

function Visual.drawSheathedPlayer(view, player, origin, headDip)
    player:RenderGlow(origin)
    if view.facing ~= "Up" then drawScabbard(view, origin) end
    player:RenderBody(origin)
    if view.facing == "Up" then drawScabbard(view, origin) end
    player:RenderHead(headDip and origin + headDip or origin)
    player:RenderTop(origin)
end

-- RenderHead owns the native head scale; only its per-frame neck displacement changes here.
function Visual.drawBehindHead(view, origin)
    if not view.clip then return nil end
    if view.facing == "Up" then
        drawWeaponAndTrail(view, origin)
        drawLayer(view, BODY, origin)
        drawScabbard(view, origin)
    else
        drawScabbard(view, origin)
        drawLayer(view, BODY, origin)
    end
    local offset = view.head[view.frame + 1]
    return origin + Vector(offset[1] * view.size.x, offset[2] * view.size.y)
end

function Visual.drawInFrontOfHead(view, origin)
    if view.clip and view.facing ~= "Up" then
        drawWeaponAndTrail(view, origin)
    end
end

return Visual
