# frozen_string_literal: true

module DungeonGen
  Room = Struct.new(:x, :y, :width, :height) do
    def center
      [x + width / 2, y + height / 2]
    end
  end
  Level = Struct.new(:depth, :terrain, :memory, :rooms, :arrival, :arrival_room, :target, :monsters, :items,
                     :killed, :picked, :monsters_created, :items_placed, keyword_init: true)

  def self.interior(room, generator)
    [room.x + 1 + generator.rnd(room.width - 2), room.y + 1 + generator.rnd(room.height - 2)]
  end

  def self.room_cell(level, generator)
    index = generator.rnd(level.rooms.length)
    [index, interior(level.rooms[index], generator)]
  end

  class Builder
    def initialize(settings, generator)
      @settings = settings
      @generator = generator
      @leaves = []
      @nodes = []
    end

    def split(x, y, width, height, depth)
      minimum, maximum_depth = @settings['bsp']
      vertical = width >= 2 * minimum
      horizontal = height >= 2 * minimum
      if depth == maximum_depth || (!vertical && !horizontal)
        index = @leaves.length
        @leaves << [x, y, width, height]
        return [index]
      end
      if vertical && horizontal
        vertical = if 4 * width >= 5 * height
                     true
                   elsif 4 * height >= 5 * width
                     false
                   else
                     @generator.rnd(2).zero?
                   end
      end
      if vertical
        cut = minimum + @generator.rnd(width - 2 * minimum + 1)
        first = split(x, y, cut, height, depth + 1)
        last = split(x + cut, y, width - cut, height, depth + 1)
      else
        cut = minimum + @generator.rnd(height - 2 * minimum + 1)
        first = split(x, y, width, cut, depth + 1)
        last = split(x, y + cut, width, height - cut, depth + 1)
      end
      @nodes << [first, last]
      first + last
    end

    def rooms(terrain)
      minimum, maximum = @settings['room']
      @leaves.map do |x, y, width, height|
        rw = minimum + @generator.rnd([maximum, width - 1].min - minimum + 1)
        rh = minimum + @generator.rnd([maximum, height - 1].min - minimum + 1)
        rx = x + @generator.rnd(width - rw)
        ry = y + @generator.rnd(height - rh)
        ry.upto(ry + rh - 1) do |row|
          rx.upto(rx + rw - 1) do |column|
            terrain[row][column] = if row == ry || row == ry + rh - 1
                                     '-'
                                   elsif column == rx || column == rx + rw - 1
                                     '|'
                                   else
                                     '.'
                                   end
          end
        end
        Room.new(rx, ry, rw, rh)
      end
    end

    def axis(first, last)
      first.step(last, first <= last ? 1 : -1)
    end

    def corridors(terrain, rooms)
      @nodes.each do |first, last|
        a, b = first.product(last).min_by do |left, right|
          x, y = rooms[left].center
          u, v = rooms[right].center
          [(x - u).abs + (y - v).abs, left, right]
        end
        ax, ay = rooms[a].center
        bx, by = rooms[b].center
        path = if @generator.rnd(2).zero?
                 axis(ax, bx).map { |x| [x, ay] } + axis(ay, by).map { |y| [bx, y] }
               else
                 axis(ay, by).map { |y| [ax, y] } + axis(ax, bx).map { |x| [x, by] }
               end
        path.each do |x, y|
          terrain[y][x] = '#' if terrain[y][x] == ' '
          terrain[y][x] = '+' if terrain[y][x] == '-' || terrain[y][x] == '|'
        end
      end
    end

    def generate(depth)
      width, height = @settings['map']
      split(0, 0, width, height, 0)
      terrain = Array.new(height) { Array.new(width, ' ') }
      room_list = rooms(terrain)
      corridors(terrain, room_list)
      level = Level.new(depth: depth, terrain: terrain, memory: Array.new(height) { Array.new(width, ' ') },
                        rooms: room_list, monsters: [], items: {}, killed: 0, picked: 0)
      level.arrival_room, level.arrival = DungeonGen.room_cell(level, @generator)
      terrain[level.arrival[1]][level.arrival[0]] = '<'
      target_room = @generator.rnd(room_list.length - 1)
      target_room += 1 if target_room >= level.arrival_room
      level.target = DungeonGen.interior(room_list[target_room], @generator)
      level
    end
  end

  def self.generate(settings, depth, generator)
    Builder.new(settings, generator).generate(depth)
  end
end
