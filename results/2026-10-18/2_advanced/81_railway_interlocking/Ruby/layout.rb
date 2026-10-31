require 'set'

class Layout
  Section = Struct.new(:name, :length, :row, :first, :last, :failed, :occupants,
                       :route_lock, :overlap_locks, :stats, :trains, keyword_init: true)
  Point = Struct.new(:name, :side, :common, :normal, :reverse, :row, :column,
                     :position, :moving, :failed, :target, :completion, :locks, :stats,
                     keyword_init: true) do
    def detected? = !moving && !failed
  end
  Signal = Struct.new(:name, :section, :direction, :row, :column, :aspect, :stats, keyword_init: true)
  EndObject = Struct.new(:name, :section, :end, :row, :column, keyword_init: true)
  attr_reader :sections, :points, :signals, :buffers, :boundaries, :labels, :signals_at

  def initialize
    @sections, @points, @signals, @buffers, @boundaries = {}, {}, {}, {}, {}
    @labels, @ends, @signals_at = [], {}, {}
    File.foreach('input/layout.txt', chomp: true) do |line|
      type, *fields = line.split(' ')
      case type
      when 'SECTION'
        name, length, row, first, last = fields
        @sections[name] = Section.new(name: name, length: length.to_i, row: row.to_i,
          first: first.to_i, last: last.to_i, failed: false, occupants: [],
          overlap_locks: Set.new, stats: Hash.new(0), trains: Set.new)
      when 'JOINT'
        a, b = fields
        @ends[[a, 'R']], @ends[[b, 'L']] = [:section, b], [:section, a]
      when 'POINT'
        name, side, common, normal, reverse, row, column = fields
        @points[name] = Point.new(name: name, side: side, common: common, normal: normal,
          reverse: reverse, row: row.to_i, column: column.to_i, position: 'N',
          moving: false, failed: false, locks: Set.new, stats: Hash.new(0))
        @ends[[common, side]] = [:point, name]
        other = side == 'R' ? 'L' : 'R'
        @ends[[normal, other]] = @ends[[reverse, other]] = [:point, name]
      when 'SIGNAL'
        name, section, direction, row, column = fields
        signal = Signal.new(name: name, section: section, direction: direction,
          row: row.to_i, column: column.to_i, aspect: 'RED', stats: Hash.new(0))
        @signals[name] = @signals_at[[section, direction]] = signal
      when 'BUFFER', 'BOUNDARY'
        name, section, endpoint, row, column = fields
        object = EndObject.new(name: name, section: section, end: endpoint,
          row: row&.to_i, column: column&.to_i)
        (type == 'BUFFER' ? @buffers : @boundaries)[name] = object
        @ends[[section, endpoint]] = [type.downcase.to_sym, name]
      when 'LABEL'
        row, column, text = fields
        @labels << [row.to_i, column.to_i, text]
      end
    end
  end

  def beyond(section, direction)
    type, name = @ends.fetch([section, direction == 'UP' ? 'R' : 'L'])
    return [type, name] unless type == :point

    point = @points.fetch(name)
    branch = point.position == 'N' ? point.normal : point.reverse
    return [:impassable, nil] if point.moving || (section != point.common && section != branch)

    [:section, section == point.common ? branch : point.common]
  end
end
