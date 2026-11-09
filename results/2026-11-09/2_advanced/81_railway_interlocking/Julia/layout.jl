mutable struct TrackSection
    name::String
    length::Int
    row::Int
    first::Int
    last::Int
    failed::Bool
    occupants::Vector{String}
    occupied_seconds::Int
    locked_seconds::Int
    trains::Set{String}
    route_lock::String
    overlap_locks::Set{String}
end

mutable struct TrackPoint
    name::String
    side::String
    common::String
    normal::String
    reverse::String
    row::Int
    column::Int
    position::String
    moving::Bool
    failed::Bool
    target::String
    completion::Int
    throws::Int
    locked_seconds::Int
    moving_seconds::Int
    locks::Set{Tuple{String,String}}
end

mutable struct TrackSignal
    name::String
    section::String
    direction::String
    row::Int
    column::Int
    aspect::String
    seconds::Dict{String,Int}
    passes::Int
end

struct TrackLayout
    sections::Dict{String,TrackSection}
    points::Dict{String,TrackPoint}
    signals::Dict{String,TrackSignal}
    buffers::Dict{String,NamedTuple}
    boundaries::Dict{String,NamedTuple}
    section_order::Vector{String}
    point_order::Vector{String}
    signal_order::Vector{String}
    buffer_order::Vector{String}
    labels::Vector{Tuple{Int,Int,String}}
    ends::Dict{Tuple{String,String},Tuple{String,String}}
    signals_at::Dict{Tuple{String,String},TrackSignal}
end

point_detected(point) = !point.moving && !point.failed

function read_layout()
    layout = TrackLayout(
        Dict{String,TrackSection}(),
        Dict{String,TrackPoint}(),
        Dict{String,TrackSignal}(),
        Dict{String,NamedTuple}(),
        Dict{String,NamedTuple}(),
        String[],
        String[],
        String[],
        String[],
        Tuple{Int,Int,String}[],
        Dict{Tuple{String,String},Tuple{String,String}}(),
        Dict{Tuple{String,String},TrackSignal}()
    )
    for line in readlines("input/layout.txt")
        fields = String.(split(line, ' '))
        kind, values = fields[1], fields[2:end]
        if kind == "SECTION"
            name = values[1]
            item = TrackSection(
                name,
                parse.(Int, values[2:end])...,
                false,
                String[],
                0,
                0,
                Set{String}(),
                "",
                Set{String}()
            )
            layout.sections[name] = item
            push!(layout.section_order, name)
        elseif kind == "JOINT"
            first_section, second_section = values
            layout.ends[(first_section, "R")] = ("section", second_section)
            layout.ends[(second_section, "L")] = ("section", first_section)
        elseif kind == "POINT"
            name, side, common, normal, reverse = values[1:5]
            item = TrackPoint(
                name,
                side,
                common,
                normal,
                reverse,
                parse.(Int, values[6:7])...,
                "N",
                false,
                false,
                "",
                -1,
                0,
                0,
                0,
                Set{Tuple{String,String}}()
            )
            layout.points[name] = item
            push!(layout.point_order, name)
            layout.ends[(common, side)] = ("point", name)
            other = side == "R" ? "L" : "R"
            layout.ends[(normal, other)] = layout.ends[(reverse, other)] = ("point", name)
        elseif kind == "SIGNAL"
            name, section, direction = values[1:3]
            item = TrackSignal(
                name,
                section,
                direction,
                parse.(Int, values[4:5])...,
                "RED",
                Dict("RED" => 0, "YELLOW" => 0, "GREEN" => 0),
                0
            )
            layout.signals[name] = layout.signals_at[(section, direction)] = item
            push!(layout.signal_order, name)
        elseif kind in ("BUFFER", "BOUNDARY")
            name, section, endpoint = values[1:3]
            if kind == "BUFFER"
                layout.buffers[name] = (
                    name=name,
                    section=section,
                    endpoint=endpoint,
                    row=parse(Int, values[4]),
                    column=parse(Int, values[5])
                )
                push!(layout.buffer_order, name)
            else
                layout.boundaries[name] = (name=name, section=section, endpoint=endpoint)
            end
            layout.ends[(section, endpoint)] = (lowercase(kind), name)
        else
            push!(layout.labels, (parse(Int, values[1]), parse(Int, values[2]), values[3]))
        end
    end
    return layout
end

function beyond(layout, section, direction)
    kind, name = layout.ends[(section, direction == "UP" ? "R" : "L")]
    kind != "point" && return kind, name
    point = layout.points[name]
    branch = point.position == "N" ? point.normal : point.reverse
    (point.moving || section != point.common && section != branch) && return "impassable", ""
    return "section", section == point.common ? branch : point.common
end
