-- Keep the original isaacTearScale line readable alongside the current hunt.
local Slot = {}

function Slot.read(mod)
    local fields = {}
    if mod:HasData() then
        for key, value in mod:LoadData():gmatch("([^=\r\n]+)=([^\r\n]+)") do
            fields[key] = value
        end
    end
    return fields
end

function Slot.write(mod, fields)
    local lines = {}
    for key, value in pairs(fields) do
        lines[#lines + 1] = key .. "=" .. tostring(value)
    end
    table.sort(lines)
    mod:SaveData(table.concat(lines, "\n"))
end

return Slot
