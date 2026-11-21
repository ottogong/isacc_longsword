local Jewels = {}
Jewels.keys = { "attack", "expert", "critical", "reach", "speed" }
Jewels.maxLevel = { attack = 7, expert = 7, critical = 3, reach = 7, speed = 7 }
Jewels.maxJewelLevel = 4
Jewels.maxCopies = 2

local function getCopy(run, key, index)
    local copies = run and run.jewels and run.jewels[key]
    return copies and copies[index]
end

function Jewels.copyLevel(run, key, index)
    local copy = getCopy(run, key, index)
    return copy and copy.rank or 0
end

function Jewels.isHeld(run, key, index)
    local copy = getCopy(run, key, index)
    return copy ~= nil and copy.held
end

function Jewels.isPending(run, key, index)
    local copy = getCopy(run, key, index)
    return copy ~= nil and not copy.held
end

function Jewels.level(run, key)
    local sum = 0
    for i = 1, Jewels.maxCopies do
        local copy = getCopy(run, key, i)
        if copy and copy.held then sum = sum + copy.rank end
    end
    return math.min(Jewels.maxLevel[key], sum)
end

-- A quote also identifies the jewel that will be created or upgraded.
function Jewels.price(run, key, mode, index)
    if not Jewels.maxLevel[key] then return nil end
    if mode == "craft" then
        for i = 1, Jewels.maxCopies do
            if Jewels.copyLevel(run, key, i) == 0 then return 5, i end
        end
    elseif mode == "upgrade" and (index == 1 or index == 2) then
        local rank = Jewels.copyLevel(run, key, index)
        if Jewels.isHeld(run, key, index) and rank < Jewels.maxJewelLevel then return 5 + rank, index end
    end
end

function Jewels.buy(run, key, mode, index, place)
    local cost, which = Jewels.price(run, key, mode, index)
    if not cost then return false, "unavailable" end
    if run.materials < cost then return false, "materials" end
    local oldRank = Jewels.copyLevel(run, key, which)
    local ok, reason = place(key, which, oldRank + 1, oldRank)
    if not ok then return false, reason end
    local copies = run.jewels[key] or {}
    copies[which] = { rank = oldRank + 1, held = false, floor = run.floor }
    run.jewels[key] = copies
    run.materials = run.materials - cost
    return true, mode == "craft" and "crafted" or "upgraded"
end

-- Native collectibles encode type and rank, not which of the two slots they
-- belong to. Account for already-held twins before claiming pending pedestals.
function Jewels.syncOwned(run, key, counts)
    local copies = run.jewels[key] or {}
    local remaining = {}
    for rank = 1, Jewels.maxJewelLevel do remaining[rank] = counts[rank] or 0 end
    local changed = false
    for i = 1, Jewels.maxCopies do
        local copy = copies[i]
        if copy and copy.held then
            if remaining[copy.rank] > 0 then
                remaining[copy.rank] = remaining[copy.rank] - 1
            else
                -- A lost or rerolled collectible frees the slot for a new craft.
                copies[i], changed = nil, true
            end
        end
    end
    for i = 1, Jewels.maxCopies do
        local copy = copies[i]
        if copy and not copy.held and remaining[copy.rank] > 0 then
            remaining[copy.rank] = remaining[copy.rank] - 1
            copy.held, copy.floor, changed = true, nil, true
        end
    end
    -- Jewels obtained directly use their native rank (e.g. a console grant).
    for i = 1, Jewels.maxCopies do
        if not copies[i] then
            for rank = Jewels.maxJewelLevel, 1, -1 do
                if remaining[rank] > 0 then
                    remaining[rank] = remaining[rank] - 1
                    copies[i], changed = { rank = rank, held = true }, true
                    break
                end
            end
        end
    end
    if changed then run.jewels[key] = copies end
    return changed
end

-- A previous floor's pedestal can no longer be reached. Deliver each paid
-- jewel to the next guild once, without charging or taking a second old item.
function Jewels.redeliver(run, place)
    local changed = false
    for _, key in ipairs(Jewels.keys) do
        for i = 1, Jewels.maxCopies do
            local copy = getCopy(run, key, i)
            if copy and not copy.held and copy.floor ~= run.floor and place(key, i, copy.rank, 0) then
                copy.floor, changed = run.floor, true
            end
        end
    end
    return changed
end

function Jewels.attackFlat(level)
    return math.min(level, 5)
end

function Jewels.attackMultiplier(level)
    return 1 + math.max(0, level - 5) * 0.05
end

function Jewels.affinity(level)
    return (math.min(level, 5) * 5 + math.max(0, level - 5) * 10) / 100
end

function Jewels.critMultiplier(level)
    return (125 + 5 * level) / 100
end

function Jewels.rangeBonus(level)
    return 1.25 * level
end

function Jewels.tearsBonus(level)
    return 0.35 * level
end

return Jewels
