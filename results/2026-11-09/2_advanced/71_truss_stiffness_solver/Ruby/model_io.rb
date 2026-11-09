module ModelIO
  Node = Data.define(:identifier, :x, :y)
  Member = Data.define(:identifier, :start, :finish, :section, :material, :group)
  Section = Data.define(:name, :area, :inertia)
  Material = Data.define(:name, :young, :yield_stress, :density, :expansion)
  Support = Data.define(:node, :fixed, :prescribed)
  LoadCase = Data.define(:name, :lines)
  Combination = Data.define(:name, :terms)
  Model = Data.define(:nodes, :members, :sections, :materials, :supports, :cases, :combinations, :settings)

  def self.csv_rows(name)
    File.readlines("input/#{name}.csv", chomp: true).drop(1).map { |line| line.split(',') }
  end

  def self.read_loads(node_index, member_index)
    cases, combinations, loads, name = [], [], [], nil
    File.foreach('input/loads.txt', chomp: true) do |line|
      kind, *values = line.split
      case kind
      when 'LOADCASE'
        name, loads = values[0], []
      when 'END'
        cases << LoadCase.new(name, loads)
      when 'COMBINATION'
        terms = values.drop(1).each_slice(2).map { |case_name, factor| [case_name, factor.to_f] }
        combinations << Combination.new(values[0], terms)
      when 'FORCE'
        loads << [kind, node_index.fetch(values[0].to_i), values[1].to_f, values[2].to_f]
      when 'TEMPERATURE'
        loads << [kind, member_index.fetch(values[0].to_i), values[1].to_f]
      else
        loads << [kind]
      end
    end
    [cases, combinations]
  end

  def self.read_settings(node_index, member_index)
    settings = { 'influence' => [], 'drawing' => [] }
    File.foreach('input/params.txt', chomp: true) do |line|
      kind, *values = line.split
      case kind
      when 'deck'
        settings[kind] = values.map { |value| node_index.fetch(value.to_i) }
      when 'influence'
        settings[kind] << member_index.fetch(values[0].to_i)
      when 'vehicle'
        settings[kind] = [values[0].to_i, values.drop(1).each_slice(2).map { |offset, load| [offset.to_i, load.to_f] }]
      when 'rating'
        settings[kind] = [values[0], values[1].to_f, values[2].to_f]
      when 'slenderness'
        settings[kind] = values.map(&:to_f)
      when 'deflection'
        settings[kind] = [values[0], values[1].to_i]
      when 'vibration'
        settings[kind] = [values[0], values[1].to_i, values[2].to_i]
      when 'removal'
        settings[kind] = values[0]
      when 'drawing'
        settings[kind] << [values[0], *values.drop(1).map(&:to_i)]
      when 'utilization_map'
        settings[kind] = values.map(&:to_i)
      end
    end
    settings
  end

  def self.read_model
    nodes = csv_rows('nodes').map { |row| Node.new(*row.map(&:to_i)) }
    sections = csv_rows('sections').map { |name, area, inertia| Section.new(name, area.to_f, inertia.to_f) }
    materials = csv_rows('materials').map { |row| Material.new(row[0], *row.drop(1).map(&:to_f)) }
    node_index = nodes.each_with_index.to_h { |node, index| [node.identifier, index] }
    section_index = sections.each_with_index.to_h { |section, index| [section.name, index] }
    material_index = materials.each_with_index.to_h { |material, index| [material.name, index] }
    members = csv_rows('members').map do |id, start, finish, section, material, group|
      Member.new(id.to_i, node_index.fetch(start.to_i), node_index.fetch(finish.to_i),
                 section_index.fetch(section), material_index.fetch(material), group)
    end
    member_index = members.each_with_index.to_h { |member, index| [member.identifier, index] }
    supports = csv_rows('supports').map do |node, fix_x, fix_y, dx, dy|
      Support.new(node_index.fetch(node.to_i), [fix_x.to_i, fix_y.to_i], [dx.to_f, dy.to_f])
    end
    cases, combinations = read_loads(node_index, member_index)
    Model.new(nodes, members, sections, materials, supports, cases, combinations, read_settings(node_index, member_index))
  end
end
