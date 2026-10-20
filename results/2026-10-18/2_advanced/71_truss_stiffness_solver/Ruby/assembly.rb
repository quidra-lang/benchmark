module Assembly
  Geometry = Data.define(:length, :cosine, :sine, :dofs)
  Properties = Data.define(:area, :inertia, :young, :yield_stress, :density, :expansion, :stiffness)
  Loading = Data.define(:external, :total, :temperature, :settlement)

  def self.member_geometry(nodes, members, node_dofs)
    members.map do |member|
      start, finish = nodes[member.start], nodes[member.finish]
      dx, dy = finish.x - start.x, finish.y - start.y
      length = Math.sqrt(dx * dx + dy * dy)
      Geometry.new(length, dx / length, dy / length, node_dofs[member.start] + node_dofs[member.finish])
    end
  end

  def self.member_properties(model, choices, geometry)
    model.members.zip(choices, geometry).map do |member, choice, shape|
      section, material = model.sections[choice], model.materials[member.material]
      Properties.new(section.area, section.inertia, material.young, material.yield_stress,
                     material.density, material.expansion, material.young * section.area / shape.length)
    end
  end

  def self.member_weight(properties, geometry)
    properties.density * 9.81 * properties.area * geometry.length / 1_000_000_000
  end

  def self.member_stiffness(properties, geometry)
    k, c, s = properties.stiffness, geometry.cosine, geometry.sine
    xx, xy, yy = k * (c * c), k * (c * s), k * (s * s)
    [[xx, xy, -xx, -xy], [xy, yy, -xy, -yy], [-xx, -xy, xx, xy], [-xy, -yy, xy, yy]]
  end

  def self.assemble(geometry, properties, degrees, removed = nil)
    matrix = Array.new(degrees) { Array.new(degrees, 0.0) }
    geometry.zip(properties).each_with_index do |(shape, member), number|
      next if number == removed

      local = member_stiffness(member, shape)
      shape.dofs.each_with_index do |global_row, row|
        shape.dofs.each_with_index { |global_column, column| matrix[global_row][global_column] += local[row][column] }
      end
    end
    matrix
  end

  def self.load_vectors(case_definition, geometry, properties, node_dofs, degrees, removed = nil)
    external, thermal = Array.new(degrees, 0.0), Array.new(degrees, 0.0)
    temperature, settlement = Array.new(geometry.length, 0.0), false
    case_definition.lines.each do |line|
      case line[0]
      when 'FORCE'
        _, node, horizontal, vertical = line
        x, y = node_dofs[node]
        external[x] += horizontal * 1000
        external[y] += vertical * 1000
      when 'TEMPERATURE'
        _, number, change = line
        next if number == removed

        member, shape = properties[number], geometry[number]
        force = member.young * member.area * member.expansion * change
        temperature[number] = force
        direction = [-shape.cosine, -shape.sine, shape.cosine, shape.sine]
        shape.dofs.zip(direction).each { |degree, coefficient| thermal[degree] += force * coefficient }
      when 'SELFWEIGHT'
        properties.zip(geometry).each_with_index do |(member, shape), number|
          next if number == removed

          weight = member_weight(member, shape)
          external[shape.dofs[1]] -= weight / 2
          external[shape.dofs[3]] -= weight / 2
        end
      when 'SETTLEMENT'
        settlement = true
      end
    end
    Loading.new(external, external.zip(thermal).map { |first, second| first + second }, temperature, settlement)
  end
end
