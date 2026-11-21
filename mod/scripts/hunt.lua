local Slot = include("scripts.slot_data")
local Jewels = include("scripts.hunt_jewels")
local Hunt = {}
Hunt.bossMaterials = 6
local gearKeys = { "braces", "boots", "kit" }
-- Old saves keep every stat increase already bought from the smith.
local legacySmithRanks = { smith = "smithLevel", smithSpeed = "smithSpeedLevel", smithRange = "smithRangeLevel" }

function Hunt.start(mod, seed, continued)
    local run = { seed = seed, materials = 0, gear = { braces = 0, boots = 0, kit = 0 },
        smithLevel = 0, smithSpeedLevel = 0, smithRangeLevel = 0, jewels = {},
        remains = {}, parts = {}, scoutTracks = {}, tooth = false, flySuit = false, spur = false, spurPlus = false,
        reservePill = false, postMom = false, supplyBox = not continued and "closed" or nil }
    local saved = continued and Slot.read(mod) or {}
    if tonumber(saved.huntSeed) == seed then
        run.supplyBox = saved.supplyBox -- Earlier versions already gave out both starting supplies.
        run.migrateGuildItems = saved.hiddenGuild ~= "1"
        run.legacyGear = saved.gearItems ~= "1"
        run.materials = tonumber(saved.materials) or 0
        for _, key in ipairs(gearKeys) do run.gear[key] = tonumber(saved[key]) or 0 end
        run.floor, run.rewarded = saved.huntFloor, saved.rewarded == "1"
        run.kitVisited, run.tooth = saved.kitVisited == "1", saved.tooth == "1"
        run.flySuit, run.spur, run.spurPlus = saved.flySuit == "1", saved.spur == "1", saved.spurPlus == "1"
        run.toothRoom = tonumber(saved.toothRoom)
        run.postMom = saved.postMom and saved.postMom == "1" -- nil identifies pre-v82 saves.
        run.testBladeWave = saved.testBladeWave == "1"
        for _, field in pairs(legacySmithRanks) do
            run[field] = tonumber(saved[field]) or 0
        end
        for _, key in ipairs(Jewels.keys) do
            local copies = {}
            for i = 1, Jewels.maxCopies do
                local field = "jewel_" .. key .. "_" .. i
                local rank = tonumber(saved[field])
                if rank then
                    copies[i] = { rank = rank, held = saved[field .. "_held"] == "1", floor = saved[field .. "_floor"] }
                end
            end
            run.jewels[key] = copies
        end
        run.reservePill = saved.reservePill == "1"
        for key, value in pairs(saved) do
            local track = tonumber(key:match("^track_(%-?%d+)$"))
            if track then
                local x, y, guided, kind = value:match("^(%-?%d+),(%-?%d+),([01]),?(%d*)$")
                if x then run.scoutTracks[track] = { x = tonumber(x), y = tonumber(y),
                    guided = guided == "1", kind = tonumber(kind) or 1 } end
            end
            local room = tonumber(key:match("^carcass_([%-]?%d+)$"))
            if room then
                local x, y, amount, tooth, carved = value:match("^(%-?%d+),(%-?%d+),(%d+),(%d),(%d)$")
                if x then
                    -- Before the six-material reward, an unclaimed floor boss was saved with three.
                    local pending = amount == "3" and carved == "0"
                    run.remains[room] = { x = tonumber(x), y = tonumber(y),
                        amount = pending and Hunt.bossMaterials or tonumber(amount),
                        tooth = tooth == "1", carved = carved == "1" }
                end
            end
            local site = tonumber(key:match("^parts_([%-]?%d+)$"))
            if site then
                local parts = {}
                for part in value:gmatch("%a+") do parts[part] = true end
                run.parts[site] = parts
            end
        end
    end
    return run
end

function Hunt.hasBladeWave(run)
    return run.postMom or run.testBladeWave
end

function Hunt.save(mod, run)
    local slot = Slot.read(mod)
    slot.huntSeed, slot.huntFloor, slot.materials = run.seed, run.floor, run.materials
    slot.gearItems = not run.legacyGear and 1 or nil
    slot.hiddenGuild = not run.migrateGuildItems and 1 or nil
    slot.toothRoom = run.toothRoom
    slot.postMom = run.postMom and 1 or 0
    slot.testBladeWave = run.testBladeWave and 1 or nil
    for key, field in pairs(legacySmithRanks) do
        slot[field] = run[field]
        slot[key .. "BuysThisFloor"] = nil
    end
    for _, key in ipairs(Jewels.keys) do
        local copies = run.jewels[key] or {}
        for i = 1, Jewels.maxCopies do
            local field = "jewel_" .. key .. "_" .. i
            local copy = copies[i]
            slot[field] = copy and copy.rank
            slot[field .. "_held"] = copy and copy.held and 1 or nil
            slot[field .. "_floor"] = copy and copy.floor
        end
    end
    slot.reservePill = run.reservePill and 1 or 0
    slot.supplyBox = run.supplyBox
    slot.smithUsed = nil -- Retire the per-floor purchase flag from older runs.
    for key in pairs(slot) do
        if key:match("^carcass_") or key:match("^parts_") or key:match("^track_") then slot[key] = nil end
    end
    for seed, site in pairs(run.scoutTracks) do
        slot["track_" .. seed] = ("%d,%d,%d,%d"):format(site.x, site.y, site.guided and 1 or 0, site.kind)
    end
    for room, body in pairs(run.remains) do
        slot["carcass_" .. room] = table.concat({body.x, body.y, body.amount, body.tooth and 1 or 0,
            body.carved and 1 or 0}, ",")
    end
    for room, parts in pairs(run.parts) do
        local keys = {}
        for key in pairs(parts) do keys[#keys + 1] = key end
        slot["parts_" .. room] = table.concat(keys, ",")
    end
    slot.flySuit, slot.spur, slot.spurPlus = run.flySuit and 1 or 0, run.spur and 1 or 0, run.spurPlus and 1 or 0
    slot.rewarded, slot.kitVisited, slot.tooth = run.rewarded and 1 or 0, run.kitVisited and 1 or 0, run.tooth and 1 or 0
    for _, key in ipairs(gearKeys) do slot[key] = run.gear[key] end
    Slot.write(mod, slot)
end

function Hunt.enterFloor(run, level)
    local floor = level:GetStage() .. ":" .. level:GetStageType() .. ":" .. level:GetDungeonPlacementSeed()
    if floor == run.floor then return false end
    if run.floor then run.supplyBox = nil end
    run.floor, run.rewarded, run.kitVisited, run.toothRoom = floor, false, false, nil
    run.remains, run.parts, run.scoutTracks = {}, {}, {}
    return true
end

function Hunt.enterBoss(run, player)
    if run.kitVisited then return false, 0 end
    run.kitVisited = true
    local heal = math.min(run.gear.kit, player:GetEffectiveMaxHearts() - player:GetHearts())
    if heal > 0 then player:AddHearts(heal) end
    return true, math.max(0, heal)
end

function Hunt.breakTooth(run, roomSeed)
    run.toothRoom = roomSeed
    local body = run.remains[roomSeed]
    if body and not body.carved then body.tooth = true end
end

function Hunt.breakPart(run, room, key)
    local parts = run.parts[room] or {}
    if key == "spur" then
        if run.spurPlus or parts.spur then return end
        if run.spur then key = "spurPlus" end
    end
    if run[key] or parts[key] or (run.remains[room] and run.remains[room].carved) then return end
    parts[key], run.parts[room] = true, parts
    return key
end

function Hunt.leaveRemains(run, roomSeed, position, finalBoss, extraXLBoss)
    local material = (finalBoss and not run.rewarded) or extraXLBoss
    local existing = run.remains[roomSeed]
    if existing then
        -- A lethal part break can create the body before the native clear award.
        if not material or existing.carved or existing.amount > 0 then return false end
        existing.amount = Hunt.bossMaterials
        if finalBoss then run.rewarded = true end
        return true
    end
    local tooth = not run.tooth and run.toothRoom == roomSeed
    if not material and not tooth and not run.parts[roomSeed] then return false end
    run.remains[roomSeed] = { x = math.floor(position.X), y = math.floor(position.Y),
        amount = material and Hunt.bossMaterials or 0, tooth = tooth, carved = false }
    if finalBoss then run.rewarded = true end
    return true
end

function Hunt.carve(run, roomSeed)
    local body = run.remains[roomSeed]
    if not body or body.carved then return end
    body.carved = true
    run.materials = run.materials + body.amount
    if body.tooth then run.toothRoom = nil end
    return body.amount, body.tooth and not run.tooth
end

function Hunt.price(run, key)
    if key == "pill" then return 5 end
    if key == "devil" or key == "key" or key == "bomb" then return 2 end
    local rank = run.gear[key]
    if rank and rank < 2 then return rank + 1 end
end

function Hunt.craft(run, key, makeGear)
    local cost = Hunt.price(run, key)
    if not cost then return false, "unavailable" end
    if run.materials < cost then return false, "materials" end
    if run.gear[key] then
        local made, reason = makeGear(key, run.gear[key] + 1)
        if not made then return false, reason end
    end
    run.materials = run.materials - cost
    return true, "crafted"
end

function Hunt.actionConfig(base, level)
    if level == 0 then return base end
    local duration = level == 1 and 0.85 or 0.75
    return setmetatable({
        sheatheStartup = math.max(1, math.floor(base.sheatheStartup * duration + 0.5)),
        sheatheSeatFrame = math.max(1, math.floor(base.sheatheSeatFrame * duration + 0.5)),
    }, { __index = base })
end

function Hunt.greavesCritBonus(level)
    return 0.15 * level
end

return Hunt
