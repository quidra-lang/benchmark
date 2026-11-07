class Safety
  PROPERTIES = %w[OCCUPANCY POINT_MOTION CONFLICT SIGNAL_PASSING].freeze

  def initialize
    @checks, @violations, @records = Hash.new(0), Hash.new(0), []
  end

  def check(time, property, details = nil)
    @checks[property] += 1
    return unless details

    @violations[property] += 1
    @records << "VIOLATION #{time} #{property} #{details}"
  end

  def inspect(time, layout, routes)
    layout.sections.each_value do |section|
      details = section.occupants.size >= 2 ? "#{section.name} #{section.occupants.join(',')}" : nil
      check(time, 'OCCUPANCY', details)
    end
    layout.points.each_value do |point|
      next unless point.moving

      details = if !layout.sections[point.common].occupants.empty?
                  "#{point.name} occupied"
                elsif point.locks.any? { |name, _| %w[USED APPROACH].include?(routes[name].state) }
                  "#{point.name} locked"
                end
      check(time, 'POINT_MOTION', details)
    end
    routes.values.select { |r| %w[LOCKED APPROACH].include?(r.state) }.combination(2) do |a, b|
      conflict = a.conflicts.include?(b.name) || b.conflicts.include?(a.name)
      check(time, 'CONFLICT', conflict ? "#{a.name} #{b.name}" : nil)
    end
  end

  def report
    lines = PROPERTIES.map do |name|
      "#{name} #{@violations[name].zero? ? 'OK' : 'FAIL'} checks #{@checks[name]} violations #{@violations[name]}"
    end
    lines + @records + ["RESULT #{@records.empty? ? 'SAFE' : 'UNSAFE'}"]
  end
end
