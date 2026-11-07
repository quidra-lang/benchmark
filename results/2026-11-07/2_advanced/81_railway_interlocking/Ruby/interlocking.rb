require 'set'

class Interlocking
  Route = Struct.new(:name, :start, :finish, :points, :sections, :overlap, :flank,
                     :conflicts, :approach_time, :direction, :state, :release_time,
                     :passed, :overlap_locked, :overlap_counter, :stats, keyword_init: true) do
    def requirements = points + flank
    def set? = !state.nil?
  end
  attr_reader :layout, :routes

  def self.names(text) = text == '-' ? [] : text.split(',')

  def initialize(layout)
    @layout, @routes = layout, {}
    File.foreach('input/routes.txt', chomp: true) do |line|
      _, name, start, finish, points, sections, overlap, flank, conflicts, approach = line.split(' ')
      @routes[name] = Route.new(name: name, start: start, finish: finish,
        points: self.class.names(points).map { |p| p.split(':') },
        sections: self.class.names(sections), overlap: self.class.names(overlap),
        flank: self.class.names(flank).map { |p| p.split(':') },
        conflicts: self.class.names(conflicts), approach_time: approach.to_i,
        direction: layout.signals.fetch(start).direction, passed: Set.new,
        overlap_locked: false, overlap_counter: 0, stats: Hash.new(0))
    end
  end

  def lock(route)
    route.state, route.release_time = 'LOCKED', nil
    route.passed, route.overlap_locked, route.overlap_counter = Set.new, true, 0
    route.sections.each { |name| @layout.sections[name].route_lock = route.name }
    route.overlap.each { |name| @layout.sections[name].overlap_locks.add(route.name) }
    route.requirements.each { |name, position| @layout.points[name].locks.add([route.name, position]) }
  end

  def unlock_points(route, sections = nil)
    @layout.points.each_value do |point|
      next if sections && !sections.include?(point.common)

      point.locks.delete_if { |name, _| name == route.name }
    end
  end

  def unlock_section(route, name)
    section = @layout.sections.fetch(name)
    section.route_lock = nil if section.route_lock == route.name
    unlock_points(route, [name])
  end

  def unlock_overlap(route)
    route.overlap.each { |name| @layout.sections[name].overlap_locks.delete(route.name) }
    unlock_points(route, route.overlap)
    route.overlap_locked = false
  end

  def release(route)
    route.sections.each do |name|
      section = @layout.sections[name]
      section.route_lock = nil if section.route_lock == route.name
    end
    unlock_overlap(route) if route.overlap_locked
    unlock_points(route)
    route.state, route.release_time = nil, nil
  end
end
