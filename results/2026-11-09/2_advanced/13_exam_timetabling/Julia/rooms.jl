struct Room
    id::String
    capacity::Int
end

struct Placement
    course::Course
    room::Room
    first_seat::Int
    last_seat::Int
end

function load_rooms(path, errors)
    rooms = Dict{String,Room}()
    for (number, fields) in read_records(path)
        id, capacity = fields
        if haskey(rooms, id)
            push!(errors, "rooms.csv line $number: duplicate room $id")
        elseif parse(Int, capacity) < 1
            push!(errors, "rooms.csv line $number: bad capacity $capacity")
        else
            rooms[id] = Room(id, parse(Int, capacity))
        end
    end
    sort(collect(values(rooms)); by=room -> (room.capacity, room.id))
end

function pack(rooms, courses)
    remaining = [room.capacity for room in rooms]
    durations = zeros(Int, length(rooms))
    placements = Placement[]
    for course in sort(collect(courses); by=c -> (-enrolment_count(c), c.id))
        index = findfirst(i -> remaining[i] >= enrolment_count(course) && durations[i] in (0, course.duration), eachindex(rooms))
        isnothing(index) && return nothing
        room = rooms[index]
        first_seat = room.capacity - remaining[index] + 1
        push!(placements, Placement(course, room, first_seat, first_seat + enrolment_count(course) - 1))
        remaining[index] -= enrolment_count(course)
        durations[index] = course.duration
    end
    placements
end
