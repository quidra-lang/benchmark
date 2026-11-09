module Rooms
  Room = Struct.new(:id, :capacity, keyword_init: true)
  Placement = Struct.new(:room, :first, :last, keyword_init: true)

  module_function

  def read(errors)
    rooms = {}
    File.readlines('input/rooms.csv', chomp: true).drop(1).each_with_index do |line, index|
      id, capacity = line.split(',')
      capacity = capacity.to_i
      message = if rooms.key?(id)
                  "duplicate room #{id}"
                elsif capacity < 1
                  "bad capacity #{capacity}"
                end
      if message
        errors << "rooms.csv line #{index + 2}: #{message}"
      else
        rooms[id] = Room.new(id: id, capacity: capacity)
      end
    end
    rooms.values.sort_by { |room| [room.capacity, room.id] }
  end

  def pack(ids, courses, rooms)
    remaining = rooms.to_h { |room| [room.id, room.capacity] }
    durations = {}
    placements = {}
    ids.sort_by { |id| [-courses[id].count, id] }.each do |id|
      course = courses[id]
      room = rooms.find do |candidate|
        remaining[candidate.id] >= course.count &&
          (!durations.key?(candidate.id) || durations[candidate.id] == course.duration)
      end
      return nil unless room

      first = room.capacity - remaining[room.id] + 1
      placements[id] = Placement.new(room: room, first: first, last: first + course.count - 1)
      remaining[room.id] -= course.count
      durations[room.id] = course.duration
    end
    placements
  end
end
