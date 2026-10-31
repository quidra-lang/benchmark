require 'fileutils'
require 'set'
require_relative 'model_io'
require_relative 'assembly'
require_relative 'solver'
require_relative 'postprocess'
require_relative 'design'

module Formatting
  def total(values)
    values.inject(0.0) { |result, value| result + value }
  end

  def real(value, digits = 4)
    text = format("%.#{digits}f", value)
    text.start_with?('-') && text.to_f.zero? ? text[1..] : text
  end

  def rounded(value)
    real(value).to_f
  end

  def choose(items, minimum = false)
    best, best_value = nil, nil
    items.each do |item|
      value = rounded(yield(item))
      if best_value.nil? || (minimum ? value < best_value : value > best_value)
        best, best_value = item, value
      end
    end
    best
  end

  def extreme_index(values, minimum = false)
    choose(0...values.length, minimum) { |index| values[index] }
  end
end

class Canvas
  attr_reader :width, :height

  def initialize(nodes, horizontal, vertical)
    @x0, @x1 = nodes.map(&:x).minmax
    @y0, @y1 = nodes.map(&:y).minmax
    @horizontal, @vertical = horizontal, vertical
    @width = ((@x1 - @x0).to_f / horizontal + 0.5).floor + 5
    @height = ((@y1 - @y0).to_f / vertical + 0.5).floor + 5
    @grid = Array.new(@height) { Array.new(@width, ' ') }
  end

  def position(x, y)
    [((x - @x0).to_f / @horizontal + 0.5).floor + 2, ((@y1 - y).to_f / @vertical + 0.5).floor + 2]
  end

  def put(column, row, character)
    @grid[row][column] = character if column >= 0 && column < @width && row >= 0 && row < @height
  end

  def line(first, last, character)
    column, row = first
    final_column, final_row = last
    dc, dr = (final_column - column).abs, -(final_row - row).abs
    sc = column < final_column ? 1 : -1
    sr = row < final_row ? 1 : -1
    error = dc + dr
    loop do
      put(column, row, character)
      break if column == final_column && row == final_row

      twice = 2 * error
      if twice >= dr
        error += dr
        column += sc
      end
      if twice <= dc
        error += dc
        row += sr
      end
    end
  end

  def framed
    border = '+' + '-' * @width + '+'
    [border] + @grid.map { |row| '|' + row.join + '|' } + [border]
  end
end

class Truss
  include Formatting
  System = Data.define(:properties, :matrix, :free_matrix, :lower, :unstable, :removed)

  def initialize(model)
    @model, @nodes, @members, @settings = model, model.nodes, model.members, model.settings
    @order, @neighbors = renumber
    @numbers = Array.new(@nodes.length, 0)
    @order.each_with_index { |node, number| @numbers[node] = number }
    @node_dofs = @numbers.map { |number| [2 * number, 2 * number + 1] }
    @degrees = 2 * @nodes.length
    @owners = Array.new(@degrees)
    @node_dofs.each_with_index do |directions, node|
      directions.each_with_index { |degree, axis| @owners[degree] = [node, axis] }
    end
    @prescribed, @support_directions = Array.new(@degrees, 0.0), []
    model.supports.each do |support|
      2.times do |axis|
        next if support.fixed[axis].zero?

        degree = @node_dofs[support.node][axis]
        @prescribed[degree] = support.prescribed[axis]
        @support_directions << [support.node, axis, degree]
      end
    end
    @restrained = @support_directions.map(&:last).sort
    @free = (0...@degrees).to_a - @restrained
    @geometry = Assembly.member_geometry(@nodes, @members, @node_dofs)
    @groups = {}
    @members.each_with_index { |member, number| (@groups[member.group] ||= []) << number }
    @combination_definitions = model.combinations.to_h { |combination| [combination.name, combination] }
    @result_order = model.cases.map { |item| ['case', item.name] } + model.combinations.map { |item| ['combination', item.name] }
    @deck = @settings['deck']
    @deck_x = @deck.map { |node| @nodes[node].x }
    @units = {}
  end

  def renumber
    neighbors = Array.new(@nodes.length) { Set.new }
    @members.each do |member|
      neighbors[member.start].add(member.finish)
      neighbors[member.finish].add(member.start)
    end
    key = ->(node) { [neighbors[node].length, @nodes[node].identifier] }
    queue = [(0...@nodes.length).min_by(&key)]
    visited, index = queue.to_set, 0
    while index < queue.length
      node = queue[index]
      index += 1
      following = (neighbors[node] - visited).sort_by(&key)
      queue.concat(following)
      visited.merge(following)
    end
    [queue.reverse, neighbors]
  end

  def numbering_metrics(numbers)
    bandwidth = @members.map { |member| (numbers[member.start] - numbers[member.finish]).abs }.max
    profile = @neighbors.each_with_index.inject(0) do |result, (adjacent, node)|
      result + numbers[node] - (adjacent.to_a + [node]).map { |item| numbers[item] }.min
    end
    [bandwidth, profile]
  end

  def system(choices, removed = nil)
    properties = Assembly.member_properties(@model, choices, @geometry)
    matrix = Assembly.assemble(@geometry, properties, @degrees, removed)
    free_matrix = @free.map { |row| @free.map { |column| matrix[row][column] } }
    lower, unstable = Solver.cholesky(free_matrix, @free)
    System.new(properties, matrix, free_matrix, lower, unstable, removed)
  end

  def displacement(system, force, settlement = false)
    displacement = Array.new(@degrees, 0.0)
    @restrained.each { |degree| displacement[degree] = settlement ? @prescribed[degree] : 0.0 }
    right = @free.map do |degree|
      value = force[degree]
      @restrained.each { |restrained| value -= system.matrix[degree][restrained] * displacement[restrained] }
      value
    end
    @free.zip(Solver.solve(system.lower, right)).each { |degree, value| displacement[degree] = value }
    displacement
  end

  def case_result(system, case_definition)
    loading = Assembly.load_vectors(case_definition, @geometry, system.properties, @node_dofs, @degrees, system.removed)
    displacements = displacement(system, loading.total, loading.settlement)
    forces = Postprocess.axial_forces(@geometry, system.properties, displacements, loading.temperature, system.removed)
    reactions = Postprocess.reactions(system.matrix, displacements, loading.total, @restrained)
    Postprocess::Result.new(case_definition.name, displacements, forces, reactions, loading.external)
  end

  def analyze(system, combination = nil)
    combinations = combination ? [combination] : @model.combinations
    needed = combinations.flat_map { |item| item.terms.map(&:first) }
    results = {}
    @model.cases.each do |case_definition|
      results[case_definition.name] = case_result(system, case_definition) if combination.nil? || needed.include?(case_definition.name)
    end
    combinations.each { |item| results[item.name] = Postprocess.superpose(item, results) }
    results
  end

  def unit_result(node)
    @units[node] ||= begin
      force = Array.new(@degrees, 0.0)
      force[@node_dofs[node][1]] = -1000.0
      displacements = displacement(@final_system, force)
      forces = Postprocess.axial_forces(@geometry, @properties, displacements, Array.new(@members.length, 0.0))
      reactions = Postprocess.reactions(@final_system.matrix, displacements, force, @restrained)
      Postprocess::Result.new('unit', displacements, forces, reactions, force)
    end
  end

  def design_sections
    choices = @members.map(&:section)
    history = []
    round_number, converged = 0, false
    current_system = results = combinations = limits = utilizations = weight = nil
    (1..10).each do |round|
      round_number = round
      current_system = system(choices)
      results = analyze(current_system)
      combinations = @model.combinations.map { |item| results[item.name] }
      limits = @members.each_index.map { |number| Design.slenderness_limit(number, combinations, @settings['slenderness']) }
      utilizations = current_system.properties.zip(@geometry).each_with_index.map do |(member, shape), number|
        combinations.map { |result| Design.utilization(result.forces[number], member, shape) }
      end
      candidates = utilizations.each_with_index.flat_map do |row, number|
        row.each_with_index.map { |value, case_index| [value, number, case_index] }
      end
      value, member, case_index = choose(candidates) { |item| item[0] }
      weight = total(current_system.properties.zip(@geometry).map { |properties, shape| Assembly.member_weight(properties, shape) })
      changes = []
      @groups.each do |name, members|
        chosen = Design.select_section(members, @model.sections, current_system.properties, @geometry, combinations, limits)
        current = choices[members.first]
        next if chosen == current

        largest = choose(members.flat_map { |number| utilizations[number] }) { |utilization| utilization }
        changes << [name, current, chosen, largest]
      end
      history << "round #{round} weight #{real(weight / 1000)} max_utilization #{real(value)} at #{@members[member].identifier} #{combinations[case_index].name} changes #{changes.length}"
      changes.each do |name, current, chosen, largest|
        history << "change #{name} #{@model.sections[current].name} #{@model.sections[chosen].name} utilization #{real(largest)}"
      end
      converged = changes.empty?
      break if converged || round == 10

      changes.each { |name, _, chosen, _| @groups[name].each { |number| choices[number] = chosen } }
    end
    @choices, @final_system, @properties, @results = choices, current_system, current_system.properties, results
    @combinations, @limits, @utilizations, @weight = combinations, limits, utilizations, weight
    @governing_cases = utilizations.map { |row| extreme_index(row) }
    @governing = utilizations.zip(@governing_cases).map { |row, case_index| row[case_index] }
    history << "result #{converged ? 'converged' : 'not_converged'} rounds #{round_number}"
  end

  def design_report(history)
    lines = history.dup
    @groups.each do |name, members|
      number = choose(members) { |member| @governing[member] }
      section = @model.sections[@choices[members.first]].name
      lines << "group #{name} section #{section} members #{members.length} utilization #{real(@governing[number])} at #{@members[number].identifier}"
    end
    @members.zip(@properties, @geometry).each_with_index do |(member, properties, shape), number|
      section = @model.sections[@choices[number]].name
      value, slender, limit = @governing[number], Design.slenderness(properties, shape), @limits[number]
      verdict = value <= 1 && slender <= limit ? 'ok' : 'over'
      combination = @combinations[@governing_cases[number]].name
      lines << "member #{member.identifier} group #{member.group} section #{section} utilization #{real(value)} governing #{combination} slenderness #{real(slender)} limit #{real(limit)} #{verdict}"
    end
    ranking = @members.each_index.sort_by { |number| [-rounded(@governing[number]), number] }
    ranking.take(5).each_with_index do |number, rank|
      lines << "rank #{rank + 1} member #{@members[number].identifier} utilization #{real(@governing[number])}"
    end
    @members.each_with_index do |member, number|
      values = @combinations.map { |result| result.forces[number] / 1000 }
      largest, smallest = extreme_index(values), extreme_index(values, true)
      lines << "envelope #{member.identifier} max #{real(values[largest])} #{@combinations[largest].name} min #{real(values[smallest])} #{@combinations[smallest].name}"
    end
    @model.sections.each_with_index do |section, number|
      members = @choices.each_index.select { |member| @choices[member] == number }
      next if members.empty?

      length = total(members.map { |member| @geometry[member].length })
      lines << "section #{section.name} members #{members.length} length #{real(length)}"
    end
    lines << "weight #{real(@weight / 1000)}"
  end

  def magnitudes(result)
    @node_dofs.map do |x, y|
      horizontal, vertical = result.displacement[x], result.displacement[y]
      Math.sqrt(horizontal * horizontal + vertical * vertical)
    end
  end

  def result_summary(kind, result)
    magnitudes = magnitudes(result)
    node = extreme_index(magnitudes)
    energy = total(result.forces.zip(@geometry, @properties).map do |force, shape, member|
      force * force * shape.length / (2 * member.young * member.area)
    end) / 1000
    reactions_total = 2.times.map { |axis| total(@node_dofs.map { |directions| result.reactions[directions[axis]] }) / 1000 }
    forces_total = 2.times.map { |axis| total(@node_dofs.map { |directions| result.external[directions[axis]] }) / 1000 }
    scale = [1, result.external.map(&:abs).max, result.reactions.map(&:abs).max].max
    equilibrium = Postprocess.equilibrium_residual(result, @geometry) <= 0.000001 * scale ? 'ok' : 'failed'
    "#{kind} #{result.name} equilibrium #{equilibrium} max_displacement #{real(magnitudes[node])} at #{@nodes[node].identifier} energy #{real(energy)} reactions #{real(reactions_total[0])} #{real(reactions_total[1])} loads #{real(forces_total[0])} #{real(forces_total[1])}"
  end

  def analysis_report
    indeterminacy = @members.length + @restrained.length - 2 * @nodes.length
    before, after = numbering_metrics((0...@nodes.length).to_a), numbering_metrics(@numbers)
    lines = ["model nodes #{@nodes.length} members #{@members.length} supports #{@model.supports.length} free_dofs #{@free.length} restrained_dofs #{@restrained.length} indeterminacy #{indeterminacy}",
             "renumbering #{@order.map { |node| @nodes[node].identifier }.join(' ')}",
             "bandwidth before #{before[0]} after #{after[0]}", "profile before #{before[1]} after #{after[1]}"]
    @members.zip(@geometry).each do |member, shape|
      lines << "member #{member.identifier} nodes #{@nodes[member.start].identifier} #{@nodes[member.finish].identifier} length #{real(shape.length)} cos #{real(shape.cosine, 6)} sin #{real(shape.sine, 6)}"
    end
    @result_order.each { |kind, name| lines << result_summary(kind, @results[name]) }
    @support_directions.each do |node, axis, degree|
      values = @combinations.map { |result| result.reactions[degree] / 1000 }
      largest, smallest = extreme_index(values), extreme_index(values, true)
      line = "reaction_envelope #{@nodes[node].identifier} #{'xy'[axis]} max #{real(values[largest])} #{@combinations[largest].name} min #{real(values[smallest])} #{@combinations[smallest].name}"
      line += " uplift #{values.any?(&:negative?) ? 'yes' : 'no'}" if axis == 1
      lines << line
    end
    displacements = @combinations.map { |result| magnitudes(result) }
    @nodes.each_with_index do |description, node|
      values = displacements.map { |values_by_node| values_by_node[node] }
      largest = extreme_index(values)
      lines << "displacement_envelope #{description.identifier} max #{real(values[largest])} #{@combinations[largest].name}"
    end
    lines + deflection_report + removal_report
  end

  def deflection_report
    name, ratio = @settings['deflection']
    result = @results[name]
    fixed = @support_directions.select { |_, axis, _| axis == 1 }.map(&:first)
    anchors = @deck.each_index.select { |index| fixed.include?(@deck[index]) }
    lines = []
    anchors.each_cons(2) do |first, last|
      left, right = @deck[first], @deck[last]
      xa, xb = @deck_x[first], @deck_x[last]
      va, vb = result.displacement[@node_dofs[left][1]], result.displacement[@node_dofs[right][1]]
      interior = ((first + 1)...last).to_a
      deflections = interior.map do |index|
        (result.displacement[@node_dofs[@deck[index]][1]] -
          (va + (vb - va) * (@deck_x[index] - xa) / (xb - xa))).abs
      end
      chosen = extreme_index(deflections)
      maximum, node = deflections[chosen], @deck[interior[chosen]]
      limit = (xb - xa).to_f / ratio
      verdict = maximum <= limit ? 'ok' : 'exceeded'
      lines << "deflection #{name} span #{@nodes[left].identifier} #{@nodes[right].identifier} max #{real(maximum)} at #{@nodes[node].identifier} limit #{real(limit)} #{verdict}"
      unit = unit_result(node)
      virtual = total(result.forces.zip(unit.forces, @geometry, @properties).map do |force, unit_force, shape, member|
        force * (unit_force / 1000) * shape.length / (member.young * member.area)
      end)
      stiffness = -result.displacement[@node_dofs[node][1]]
      verified = (virtual - stiffness).abs <= 0.000001 * [1, stiffness.abs].max ? 'ok' : 'failed'
      lines << "virtual_work #{name} node #{@nodes[node].identifier} stiffness #{real(stiffness)} virtual #{real(virtual)} #{verified}"
    end
    lines
  end

  def removal_report
    combination = @combination_definitions[@settings['removal']]
    @members.each_with_index.map do |description, removed|
      current_system = system(@choices, removed)
      unless current_system.unstable.nil?
        node, axis = @owners[current_system.unstable]
        next "removal #{description.identifier} unstable at #{@nodes[node].identifier} #{'xy'[axis]}"
      end
      result = analyze(current_system, combination)[combination.name]
      members = @members.each_index.reject { |number| number == removed }
      values = members.map do |number|
        Design.utilization(result.forces[number], current_system.properties[number], @geometry[number])
      end
      largest = extreme_index(values)
      magnitudes = magnitudes(result)
      node = extreme_index(magnitudes)
      "removal #{description.identifier} stable max_utilization #{real(values[largest])} at #{@members[members[largest]].identifier} max_displacement #{real(magnitudes[node])} at #{@nodes[node].identifier}"
    end
  end

  def ordinate(ordinates, position)
    return 0.0 if position < @deck_x.first || position > @deck_x.last
    return ordinates.last if position == @deck_x.last

    index = @deck_x.bsearch_index { |x| x > position } - 1
    first, last = @deck_x[index], @deck_x[index + 1]
    ordinates[index] + (ordinates[index + 1] - ordinates[index]) * (position - first) / (last - first)
  end

  def vehicle_range(ordinates, positions, axles)
    effects = positions.map { |position| total(axles.map { |offset, load| load * ordinate(ordinates, position - offset) }) }
    largest, smallest = extreme_index(effects), extreme_index(effects, true)
    [effects[largest], positions[largest], effects[smallest], positions[smallest]]
  end

  def influence_report
    member_ordinates = Array.new(@members.length) { [] }
    reaction_ordinates = @support_directions.to_h { |_, _, degree| [degree, []] }
    @deck.each do |node|
      result = unit_result(node)
      result.forces.each_with_index { |force, number| member_ordinates[number] << force / 1000 }
      reaction_ordinates.each { |degree, ordinates| ordinates << result.reactions[degree] / 1000 }
    end
    lines = []
    @settings['influence'].each do |number|
      ordinates = member_ordinates[number]
      lines << "influence #{@members[number].identifier}"
      @deck.zip(ordinates).each { |node, value| lines << "node #{@nodes[node].identifier} #{real(value)}" }
      largest, smallest = extreme_index(ordinates), extreme_index(ordinates, true)
      positive, negative = total(ordinates.select(&:positive?)), total(ordinates.select(&:negative?))
      lines << "max #{real(ordinates[largest])} at #{@nodes[@deck[largest]].identifier} min #{real(ordinates[smallest])} at #{@nodes[@deck[smallest]].identifier} positive #{real(positive)} negative #{real(negative)}"
      crossings = []
      ordinates.each_cons(2).with_index do |(first, last), index|
        if (first.positive? && last.negative?) || (first.negative? && last.positive?)
          crossings << @deck_x[index] + (@deck_x[index + 1] - @deck_x[index]) * first / (first - last)
        end
      end
      line = "crossings #{crossings.length}"
      line += ' ' + crossings.map { |position| real(position, 1) }.join(' ') unless crossings.empty?
      lines << line
    end
    step, axles = @settings['vehicle']
    positions = (@deck_x.first..(@deck_x.last + axles.last[0])).step(step).to_a
    lines << "vehicle axles #{axles.length} positions #{positions.length}"
    member_ranges = @members.zip(member_ordinates).map do |member, ordinates|
      largest, high_position, smallest, low_position = vehicle_range(ordinates, positions, axles)
      lines << "vehicle_member #{member.identifier} max #{real(largest)} at #{high_position} min #{real(smallest)} at #{low_position}"
      [largest, smallest]
    end
    @support_directions.each do |node, axis, degree|
      largest, high_position, smallest, low_position = vehicle_range(reaction_ordinates[degree], positions, axles)
      lines << "vehicle_reaction #{@nodes[node].identifier} #{'xy'[axis]} max #{real(largest)} at #{high_position} min #{real(smallest)} at #{low_position}"
    end
    name, dead_factor, vehicle_factor = @settings['rating']
    dead, ratings = @results[name], []
    @members.zip(@properties, @geometry).each_with_index do |(member, properties, shape), number|
      largest, smallest = member_ranges[number]
      dead_force = dead.forces[number] / 1000
      tension_capacity = properties.area * properties.yield_stress / 1000
      compression_capacity = [properties.area * properties.yield_stress, Design.buckling(properties, shape)].min / 1000
      tension, compression = 'none', 'none'
      if rounded(largest).positive?
        rating = (tension_capacity - dead_factor * dead_force) / (vehicle_factor * largest)
        tension = real(rating)
        ratings << [number, 'tension', rating]
      end
      if rounded(smallest).negative?
        rating = (compression_capacity + dead_factor * dead_force) / (vehicle_factor * (-smallest))
        compression = real(rating)
        ratings << [number, 'compression', rating]
      end
      lines << "rating #{member.identifier} tension #{tension} compression #{compression}"
    end
    number, kind, rating = choose(ratings, true) { |item| item[2] }
    lines << "rating_min #{real(rating)} at #{@members[number].identifier} #{kind}"
  end

  def vibration_report
    name, mode_count, iterations = @settings['vibration']
    external = @results[name].external
    masses = @node_dofs.map { |directions| -external[directions[1]] / 9.81 }
    free_masses = @free.map { |degree| masses[@owners[degree][0]] }
    size = @free.length
    modes = []
    lines = ["vibration #{name} mass #{real(total(masses))} iterations #{iterations}"]
    (1..mode_count).each do |mode|
      vector = Array.new(size, 1.0)
      iterations.times do
        modes.each do |previous|
          beta = total(size.times.map { |index| previous[index] * free_masses[index] * vector[index] })
          vector = size.times.map { |index| vector[index] - beta * previous[index] }
        end
        right = size.times.map { |index| free_masses[index] * vector[index] }
        solution = Solver.solve(@final_system.lower, right)
        norm = Math.sqrt(total(size.times.map { |index| free_masses[index] * solution[index] * solution[index] }))
        vector = solution.map { |value| value / norm }
      end
      modes << vector
      stiffness_product = size.times.map do |row|
        total(size.times.map { |column| @final_system.free_matrix[row][column] * vector[column] })
      end
      numerator = total(size.times.map { |index| vector[index] * stiffness_product[index] })
      denominator = total(size.times.map { |index| free_masses[index] * vector[index] * vector[index] })
      eigenvalue = numerator / denominator
      frequency = Math.sqrt(1000 * eigenvalue) / (2 * Design::PI)
      lines << "mode #{mode} frequency #{real(frequency)} period #{real(1 / frequency)}"
      peak = (0...size).max_by { |index| vector[index].abs }
      normalized = Array.new(@degrees, 0.0)
      @free.zip(vector).each { |degree, value| normalized[degree] = value / vector[peak] }
      @nodes.zip(@node_dofs).each do |node, (x, y)|
        lines << "node #{node.identifier} #{real(normalized[x])} #{real(normalized[y])}"
      end
    end
    lines
  end

  def drawing_report
    lines = []
    @settings['drawing'].each do |name, magnification, horizontal, vertical|
      result = @results[name]
      canvas = Canvas.new(@nodes, horizontal, vertical)
      original = @nodes.map { |node| canvas.position(node.x, node.y) }
      deformed = @nodes.zip(@node_dofs).map do |node, (x, y)|
        canvas.position(node.x + magnification * result.displacement[x], node.y + magnification * result.displacement[y])
      end
      @members.each { |member| canvas.line(original[member.start], original[member.finish], '.') }
      original.each { |column, row| canvas.put(column, row, '+') }
      @members.each { |member| canvas.line(deformed[member.start], deformed[member.finish], '*') }
      deformed.each { |column, row| canvas.put(column, row, 'o') }
      lines << "drawing #{name} magnification #{magnification} columns #{canvas.width} rows #{canvas.height}"
      lines.concat(canvas.framed)
    end
    horizontal, vertical = @settings['utilization_map']
    canvas = Canvas.new(@nodes, horizontal, vertical)
    positions = @nodes.map { |node| canvas.position(node.x, node.y) }
    @members.zip(@governing).each do |member, value|
      character = value >= 1 ? '#' : (10 * value).floor.to_s
      canvas.line(positions[member.start], positions[member.finish], character)
    end
    positions.each { |column, row| canvas.put(column, row, 'o') }
    lines << "utilization_map columns #{canvas.width} rows #{canvas.height}"
    lines.concat(canvas.framed)
  end

  def csv_reports
    displacements = ['case,node,dx,dy']
    forces = ['case,member,force,stress,utilization']
    reactions = ['case,node,rx,ry']
    @result_order.each do |_, name|
      result = @results[name]
      @nodes.zip(@node_dofs).each do |node, (x, y)|
        displacements << [name, node.identifier, real(result.displacement[x]), real(result.displacement[y])].join(',')
      end
      @members.zip(@properties, @geometry, result.forces).each do |member, properties, shape, force|
        value = Design.utilization(force, properties, shape)
        forces << [name, member.identifier, real(force / 1000), real(force / properties.area), real(value)].join(',')
      end
      @model.supports.each do |support|
        x, y = @node_dofs[support.node]
        reactions << [name, @nodes[support.node].identifier, real(result.reactions[x] / 1000), real(result.reactions[y] / 1000)].join(',')
      end
    end
    [displacements, forces, reactions]
  end

  def run
    history = design_sections
    displacements, forces, reactions = csv_reports
    outputs = { 'analysis.txt' => analysis_report, 'displacements.csv' => displacements,
                'member_forces.csv' => forces, 'reactions.csv' => reactions,
                'design.txt' => design_report(history), 'influence.txt' => influence_report,
                'drawing.txt' => drawing_report, 'vibration.txt' => vibration_report }
    FileUtils.mkdir_p('output')
    outputs.each { |name, lines| File.write("output/#{name}", lines.join("\n") + "\n") }
  end
end

Truss.new(ModelIO.read_model).run if $PROGRAM_NAME == __FILE__
