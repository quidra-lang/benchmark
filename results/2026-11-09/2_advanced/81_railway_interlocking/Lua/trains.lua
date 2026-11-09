local Layout = require("layout")
local Trains = {}

function Trains.read()
    local trains, order, requests = {}, {}, {}
    for _, f in ipairs(Layout.read("input/trains.txt")) do
        local kind, name = f[1], f[2]
        if kind == "TRAIN" then
            local train = {name = name, symbol = string.char(97 + #order), length = tonumber(f[3]),
                acceleration = tonumber(f[4]), deceleration = tonumber(f[5]), max_speed = tonumber(f[6]),
                entry = f[7], entry_time = tonumber(f[8]), entry_speed = tonumber(f[9]), stops = {},
                stop_index = 1, state = "WAITING", path = {}, head = 0, speed = 0, dwelling = false,
                emergency = false, distance = 0, maximum_speed = 0, standing = 0, passes = 0}
            trains[name] = train
            order[#order + 1] = train
        elseif kind == "REQUEST" then
            requests[#requests + 1] = {time = tonumber(f[4]), train = name, route = f[3]}
        elseif kind == "STOP" or kind == "TURN" then
            local stop = {kind = kind, section = f[3], dwell = tonumber(f[4]),
                scheduled_arrival = tonumber(f[5]), scheduled_departure = tonumber(f[6])}
            local stops = trains[name].stops
            stops[#stops + 1] = stop
        else
            trains[name].exit, trains[name].scheduled_exit = f[3], tonumber(f[4])
        end
    end
    return trains, order, requests
end

function Trains.next_stop(train)
    return train.stops[train.stop_index]
end

function Trains.braking_distance(speed, deceleration)
    local count = speed // deceleration
    return count * speed - deceleration * count * (count + 1) // 2
end

function Trains.select_speed(train, distance)
    local low = math.max(train.speed - train.deceleration, 0)
    if not train.emergency then
        for speed = math.min(train.speed + train.acceleration, train.max_speed), low, -1 do
            if not distance or speed + Trains.braking_distance(speed, train.deceleration) <= distance then
                return speed
            end
        end
    end
    return low
end

return Trains
