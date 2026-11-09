module Road
export Turn, BusStop, Segment, Incident, is_empty, is_obstacle, put_cell!, clear_cell!, free_cells, first_cell, safe, cells_text, update_incident!
mutable struct Turn
    target::Int
    weight::Int
    vehicles::Int
end
mutable struct BusStop
    segment::Int
    cell::Int
    dwell::Int
    buses::Int
end
Base.@kwdef mutable struct Segment
    id::String
    start::String
    finish::String
    length::Int
    lanes::Int
    limit::Int
    cells::Matrix{Int}
    junction::Int = 0
    turns::Vector{Turn} = Turn[]
    stop::Union{Nothing,BusStop} = nothing
    entered::Int = 0
    vehicle_sum::Int = 0
    speed_sum::Int = 0
    max_vehicles::Int = 0
    green_steps::Int = 0
    queue_sum::Int = 0
    max_queue::Int = 0
    failures::Int = 0
    passed::Int = 0
    blocked::Int = 0
    changes::Vector{Int} = zeros(Int, 3)
end
Segment(id, start, finish, count, lanes, limit) = Segment(id=id, start=start, finish=finish, length=count, lanes=lanes, limit=limit, cells=zeros(Int, count, lanes))
is_empty(s, lane, cell) = s.cells[cell+1, lane] == 0
is_obstacle(s, lane, cell) = s.cells[cell+1, lane] == -1
put_cell!(s, lane, cell, value) = (s.cells[cell+1, lane] = value)
clear_cell!(s, lane, cell) = put_cell!(s, lane, cell, 0)
function free_cells(s, lane, cell, limit)
    count = 0
    while count < limit && cell+count+1 < s.length && is_empty(s, lane, cell+count+1)
        count += 1
    end
    count
end
function first_cell(s, lane)
    for cell in 0:s.length-1
        is_empty(s, lane, cell) || return cell
    end
    s.length
end
safe(s, lane, cell) = all(x -> is_empty(s, lane, x), max(0, cell-s.limit):cell)
function cells_text(s, lane, vehicles)
    join(value == 0 ? '.' : value == -1 ? '#' : Char(Int('0') + vehicles[value].speed) for value in s.cells[:, lane])
end
Base.@kwdef mutable struct Incident
    segment::Int
    lane::Int
    cell::Int
    start::Int
    finish::Int
    state::Symbol = :planned
    active_start::Int = 0
    active_end::Int = 0
end
function update_incident!(incident, segments, step)
    s = segments[incident.segment]
    event = nothing
    if incident.state == :active && step > incident.finish
        incident.state = :cleared
        clear_cell!(s, incident.lane, incident.cell)
        event = "INCIDENT_END"
    elseif incident.state == :planned && step > incident.finish
        incident.state = :cancelled
    elseif incident.state == :planned && step >= incident.start && is_empty(s, incident.lane, incident.cell)
        incident.state = :active
        put_cell!(s, incident.lane, incident.cell, -1)
        incident.active_start = step
        event = "INCIDENT_START"
    end
    incident.state == :active && (incident.active_end = step)
    event
end
end
