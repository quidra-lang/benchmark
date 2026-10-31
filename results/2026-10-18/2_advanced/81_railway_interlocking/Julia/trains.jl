mutable struct RailStop
    kind::String
    section::String
    dwell::Int
    scheduled_arrival::Int
    scheduled_departure::Int
    arrival::Int
    departure::Int
end

mutable struct RailTrain
    name::String
    symbol::Char
    length::Int
    acceleration::Int
    deceleration::Int
    max_speed::Int
    entry::String
    entry_time::Int
    entry_speed::Int
    exit::String
    scheduled_exit::Int
    stops::Vector{RailStop}
    stop_index::Int
    state::String
    direction::String
    path::Vector{Tuple{String,Int}}
    head::Int
    speed::Int
    dwelling::Bool
    awaiting_departure::Union{Nothing,RailStop}
    emergency::Bool
    boundary::String
    boundary_coordinate::Int
    entered::Int
    exited::Int
    distance::Int
    maximum_speed::Int
    standing::Int
    passes::Int
end

next_stop(train) = train.stop_index <= length(train.stops) ? train.stops[train.stop_index] : nothing

function read_trains()
    trains, order, requests = Dict{String,RailTrain}(), String[], Tuple{Int,String,String}[]
    for line in readlines("input/trains.txt")
        fields = String.(split(line, ' '))
        kind, values = fields[1], fields[2:end]
        if kind == "TRAIN"
            train = RailTrain(
                values[1],
                Char(Int('a') + length(order)),
                parse.(Int, values[2:5])...,
                values[6],
                parse.(Int, values[7:8])...,
                "",
                0,
                RailStop[],
                1,
                "WAITING",
                "",
                Tuple{String,Int}[],
                0,
                0,
                false,
                nothing,
                false,
                "",
                0,
                -1,
                -1,
                0,
                0,
                0,
                0
            )
            trains[train.name] = train
            push!(order, train.name)
        elseif kind == "REQUEST"
            push!(requests, (parse(Int, values[3]), values[1], values[2]))
        elseif kind in ("STOP", "TURN")
            push!(trains[values[1]].stops, RailStop(kind, values[2], parse.(Int, values[3:5])..., -1, -1))
        else
            trains[values[1]].exit = values[2]
            trains[values[1]].scheduled_exit = parse(Int, values[3])
        end
    end
    return trains, order, requests
end

function braking_distance(speed, deceleration)
    count = speed ÷ deceleration
    return count * speed - deceleration * count * (count + 1) ÷ 2
end

function select_speed(train, distance)
    low = max(train.speed - train.deceleration, 0)
    if !train.emergency
        for speed in min(train.speed + train.acceleration, train.max_speed):-1:low
            (distance === nothing || speed + braking_distance(
                speed,
                train.deceleration
            ) <= distance) && return speed
        end
    end
    return low
end
