module Design
  PI = 3.141592653589793

  def self.buckling(properties, geometry, inertia = properties.inertia)
    PI * PI * properties.young * inertia / (geometry.length * geometry.length)
  end

  def self.utilization(force, properties, geometry, section = nil)
    area, inertia = section ? [section.area, section.inertia] : [properties.area, properties.inertia]
    [(force / area).abs / properties.yield_stress, [0, -force].max / buckling(properties, geometry, inertia)].max
  end

  def self.slenderness(properties, geometry, section = nil)
    area, inertia = section ? [section.area, section.inertia] : [properties.area, properties.inertia]
    geometry.length / Math.sqrt(inertia / area)
  end

  def self.slenderness_limit(number, combinations, limits)
    combinations.any? { |result| result.forces[number].negative? } ? limits[0] : limits[1]
  end

  def self.select_section(members, sections, properties, geometry, combinations, limits)
    sections.each_with_index do |section, number|
      acceptable = members.all? do |member|
        slenderness(properties[member], geometry[member], section) <= limits[member] &&
          combinations.all? do |result|
            utilization(result.forces[member], properties[member], geometry[member], section) <= 1
          end
      end
      return number if acceptable
    end
    sections.length - 1
  end
end
