module Vehicles
using ..Road
export VehicleClass, Vehicle, max_speed, place!, leave!, heading_for_stop, travel_time, random_slowdown
struct VehicleClass
    name::String
    vmax::Int
    weight::Int
    overtakes::Bool
    stops::Bool
end
Base.@kwdef mutable struct Vehicle
    number::Int
    kind::Int
    source::Int
    arrival::Int
    inserted::Int = 0
    exited::Int = 0
    sink::String = "-"
    segment::Int = 0
    lane::Int = 0
    cell::Int = 0
    speed::Int = 0
    turn::Int = 0
    route::Vector{Int} = Int[]
    steps::Int = 0
    distance::Int = 0
    stopped_steps::Int = 0
    stop_count::Int = 0
    lane_changes::Int = 0
    dwell::Int = 0
    completed_stops::Set{Int} = Set{Int}()
end
max_speed(v, classes, segments) = min(classes[v.kind].vmax, segments[v.segment].limit)
function place!(v, segments, segment, lane, cell)
    v.segment != 0 && clear_cell!(segments[v.segment], v.lane, v.cell)
    put_cell!(segments[segment], lane, cell, v.number)
    v.segment, v.lane, v.cell = segment, lane, cell
end
function leave!(v, segments)
    clear_cell!(segments[v.segment], v.lane, v.cell)
    v.segment = 0
end
function heading_for_stop(v, classes, segments)
    (v.segment == 0 || !classes[v.kind].stops || v.segment in v.completed_stops) && return false
    stop = segments[v.segment].stop
    stop !== nothing && v.cell <= stop.cell
end
travel_time(v) = v.exited - v.inserted + 1
function random_slowdown(speed, previous, value, dawdle, stopped)
    probability = previous == 0 ? stopped : dawdle
    speed > 0 && mod(value, 1000) < probability ? speed - 1 : speed
end
end
