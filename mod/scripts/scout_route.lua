local Route = {}
local WIDTH = 13 -- Native floor grid.
local BOSS_MAP_FLAGS = (1 << 0) | (1 << 2) -- Visible room and native room icon.

local function ordinary(desc)
    if not desc.Data then return false end
    local kind = desc.Data.Type
    return kind == RoomType.ROOM_DEFAULT or kind == RoomType.ROOM_MINIBOSS or kind == RoomType.ROOM_BOSS
end

-- Each side of a large room has slot 0 on the first quadrant and slot 1
-- on the second. GridIndex includes the missing corner of an L-shaped room.
local function allowsExit(desc, cell, side)
    local relative = cell - desc.GridIndex
    local lane = side % 2 == 0 and relative // WIDTH or relative % WIDTH
    return (desc.Data.Doors & (1 << (side + lane * 4))) ~= 0
end

local function connect(edges, cells, first, second, side)
    local a, b = cells[first], cells[second]
    if a and b and a.ListIndex ~= b.ListIndex and allowsExit(a, first, side)
        and allowsExit(b, second, (side + 2) % 4) then
        edges[a.ListIndex][b.ListIndex] = true
        edges[b.ListIndex][a.ListIndex] = true
    end
end

-- Read only the current dimension. Quadrants which actually belong to the
-- same room share a ListIndex, including the three occupied cells of an L.
local function floorGraph(level)
    local edges, cells = {}, {}
    for cell = 0, WIDTH * WIDTH - 1 do
        local desc = level:GetRoomByIdx(cell)
        if ordinary(desc) then
            cells[cell] = desc
            if not edges[desc.ListIndex] then edges[desc.ListIndex] = {} end
            if cell % WIDTH > 0 then connect(edges, cells, cell - 1, cell, 2) end
            if cell >= WIDTH then connect(edges, cells, cell - WIDTH, cell, 3) end
        end
    end
    return edges, cells
end

local function finalBoss(level)
    local last, rooms = level:GetLastBossRoomListIndex(), level:GetRooms()
    if last < 0 or last >= rooms.Size then return end
    local boss = rooms:Get(last)
    if boss and boss.Data and boss.Data.Type == RoomType.ROOM_BOSS then return boss end
end

function Route.markBoss(level)
    local listed = finalBoss(level)
    if not listed then return false end
    -- The room list is read-only. Resolve the same room on the current dimension's grid.
    local boss = level:GetRoomByIdx(listed.SafeGridIndex)
    if not boss.Data or boss.ListIndex ~= listed.ListIndex then return false end
    local flags = boss.DisplayFlags | BOSS_MAP_FLAGS
    if flags ~= boss.DisplayFlags then
        boss.DisplayFlags = flags
        level:UpdateVisibility()
    end
    return true
end

function Route.nextDoor(level, room)
    local boss = finalBoss(level)
    if not boss or boss.Clear then return end
    local last, current = boss.ListIndex, level:GetCurrentRoomDesc()
    if current.ListIndex == last or current.GridIndex < 0 then return end

    local edges, cells = floorGraph(level)
    if not edges[last] then return end
    local queue, head = {last}, 1
    local distance = {[last] = 0}
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        for neighbor in pairs(edges[id]) do
            if neighbor ~= current.ListIndex and not distance[neighbor] then
                queue[#queue + 1] = neighbor
                distance[neighbor] = distance[id] + 1
            end
        end
    end

    local best, shortest = nil, math.huge
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        local target = door and cells[door.TargetRoomIndex]
        local steps = target and distance[target.ListIndex]
        if steps and steps < shortest and not door:IsLocked() then
            best, shortest = door, steps
        end
    end
    return best
end

return Route
