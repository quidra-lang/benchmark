module Signals
  def self.cleared_route(signal, interlocking, occupied)
    interlocking.routes.each_value.find do |route|
      route.start == signal.name && route.state == 'LOCKED' &&
        route.requirements.all? { |name, position|
          point = interlocking.layout.points.fetch(name)
          point.detected? && point.position == position
        } && (route.sections + route.overlap).none? { |name| occupied.call(name) }
    end
  end

  def self.aspects(interlocking, &occupied)
    layout = interlocking.layout
    cleared = layout.signals.to_h { |name, signal| [name, cleared_route(signal, interlocking, occupied)] }
    layout.signals.values.map do |signal|
      route = cleared[signal.name]
      aspect = if !route
                 'RED'
               elsif layout.signals.key?(route.finish)
                 cleared[route.finish] ? 'GREEN' : 'YELLOW'
               elsif layout.buffers.key?(route.finish)
                 'YELLOW'
               else
                 'GREEN'
               end
      [signal, aspect]
    end
  end
end
