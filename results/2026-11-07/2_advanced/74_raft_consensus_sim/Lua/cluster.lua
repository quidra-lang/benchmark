local M = {}
local function fields(line)
    local result = {}
    for word in line:gmatch('%S+') do result[#result + 1] = word end
    return result
end
function M.read_settings()
    local values = {}
    for line in io.lines('input/cluster.txt') do
        local f = fields(line)
        local key = table.remove(f, 1)
        for i, value in ipairs(f) do f[i] = tonumber(value) end
        values[key] = f
    end
    return {nodes = values.NODES[1], election_min = values.ELECTION[1], election_max = values.ELECTION[2], heartbeat = values.HEARTBEAT[1], batch = values.BATCH[1], quorum = values.QUORUM[1], seed = values.SEED[1], finish = values.END[1], retry = values.RETRY[1], attempts = values.ATTEMPTS[1], sample = values.SAMPLE[1]}
end
function M.read_script()
    local controls, requests = {}, {}
    for line in io.lines('input/script.txt') do
        local f = fields(line)
        local time, kind = tonumber(f[1]), f[2]
        if kind == 'REQUEST' then
            local command = {f[4], f[5]}
            if f[6] then command[3] = tonumber(f[6]) end
            requests[#requests + 1] = {number = #requests + 1, time = time, initial_destination = tonumber(f[3]), destination = tonumber(f[3]), command = command, scheduled = time, attempts = 0, redirects = 0, abandoned = false}
        else
            local arguments = {}
            for i = 3, #f do
                if kind == 'PARTITION' then
                    local group = {}
                    for number in f[i]:gmatch('[^,]+') do group[#group + 1] = tonumber(number) end
                    arguments[#arguments + 1] = group
                else arguments[#arguments + 1] = tonumber(f[i]) end
            end
            controls[#controls + 1] = {time = time, kind = kind, arguments = arguments}
        end
    end
    return controls, requests
end
return M
