require_relative 'dataset'
require_relative 'kdtree'
require_relative 'quadtree'
require_relative 'rtree'
require_relative 'grid'
require_relative 'report'

module SpatialLab
  POINT_STRUCTURES = %w[kdtree quadtree rtree str grid].freeze
  RECTANGLE_STRUCTURES = %w[rtree_rect str_rect].freeze
  RTREE_STRUCTURES = %w[rtree str rtree_rect str_rect].freeze
  SEARCH_COMMANDS = %w[RANGE RADIUS KNN WINDOWCOUNT CONTAINS NEAREST JOIN].freeze

  class NodeView
    attr_reader :region, :held, :children, :source, :mark, :depth, :count

    def initialize(region, held, children, source, mark: 'root', depth: 0)
      @region, @held, @children, @source = region, held, children, source
      @mark, @depth = mark, depth
      @count = held.length + children.sum(&:count)
    end
  end

  class PriorityQueue
    def initialize
      @items = []
    end

    def empty?
      @items.empty?
    end

    def precedes?(first, second)
      (first[0, 3] <=> second[0, 3]).negative?
    end

    def push(element)
      index = @items.length
      @items << element
      while index.positive?
        parent = (index - 1) / 2
        break unless precedes?(element, @items[parent])

        @items[index] = @items[parent]
        index = parent
      end
      @items[index] = element
    end

    def pop
      result = @items[0]
      last = @items.pop
      unless @items.empty?
        index = 0
        while (child = 2 * index + 1) < @items.length
          right = child + 1
          child = right if right < @items.length && precedes?(@items[right], @items[child])
          break unless precedes?(@items[child], last)

          @items[index] = @items[child]
          index = child
        end
        @items[index] = last
      end
      result
    end
  end

  module_function

  def kd_child_regions(node, region)
    x1, y1, x2, y2 = region
    if node.axis.zero?
      split = node.point[1]
      [[x1, y1, split, y2], [split, y1, x2, y2]]
    else
      split = node.point[2]
      [[x1, y1, x2, split], [x1, split, x2, y2]]
    end
  end

  def kd_view(root, world)
    views = {}
    pending = [[root, [0, 0, world - 1, world - 1], 'root', 0, false]]
    until pending.empty?
      node, region, mark, depth, ready = pending.pop
      if ready
        children = [node.left, node.right].compact.map { |child| views.fetch(child) }
        views[node] = NodeView.new(region, [node.point], children, node, mark: mark, depth: depth)
        next
      end
      pending << [node, region, mark, depth, true]
      left_region, right_region = kd_child_regions(node, region)
      pending << [node.right, right_region, 'R', depth + 1, false] if node.right
      pending << [node.left, left_region, 'L', depth + 1, false] if node.left
    end
    views.fetch(root)
  end

  def quad_view(node, mark = 'root', depth = 0)
    region = [node.x, node.y, node.x + node.size - 1, node.y + node.size - 1]
    children = node.children.each_with_index.map do |child, index|
      quad_view(child, QuadTree::CHILD_NAMES[index], depth + 1)
    end
    NodeView.new(region, node.points, children, node, mark: mark, depth: depth)
  end

  def rtree_view(node, objects, depth = 0)
    if node.level.zero?
      held = node.entries.map { |entry| objects.fetch(entry.id) }
      children = []
    else
      held = []
      children = node.entries.map { |entry| rtree_view(entry.child, objects, depth + 1) }
    end
    NodeView.new(node.box, held, children, node, depth: depth)
  end

  def grid_view(directory)
    children = directory.cells.map { |cell| NodeView.new(cell.box, cell.points, [], cell, depth: 1) }
    world = directory.world
    NodeView.new([0, 0, world - 1, world - 1], [], children, directory)
  end

  def preorder(root)
    return enum_for(__method__, root) unless block_given?

    pending = [root]
    until pending.empty?
      node = pending.pop
      yield node
      pending.concat(node.children.reverse)
    end
  end

  def object_box(object)
    object.length == 3 ? RTree.point_box(object) : object[1..]
  end

  def point_distance(query, point)
    dx = point[1] - query[0]
    dy = point[2] - query[1]
    dx * dx + dy * dy
  end

  def minimum_distance(query, box)
    x, y = query
    dx = if x < box[0]
           box[0] - x
         elsif x > box[2]
           x - box[2]
         else
           0
         end
    dy = if y < box[1]
           box[1] - y
         elsif y > box[3]
           y - box[3]
         else
           0
         end
    dx * dx + dy * dy
  end

  def object_distance(query, object)
    object.length == 3 ? point_distance(query, object) : minimum_distance(query, object_box(object))
  end

  def search_conditions(command, values)
    case command
    when 'RANGE'
      [->(region) { RTree.intersects?(region, values) },
       ->(point) { RTree.contains?(values, RTree.point_box(point)) }]
    when 'RADIUS'
      x, y, radius = values
      query = [x, y]
      limit = radius * radius
      [->(region) { minimum_distance(query, region) <= limit },
       ->(point) { point_distance(query, point) <= limit }]
    when 'CONTAINS'
      x, y = values
      query_box = [x, y, x, y]
      [->(region) { RTree.contains?(region, query_box) },
       ->(rectangle) { RTree.contains?(object_box(rectangle), query_box) }]
    end
  end

  def condition_search(root, region_condition, object_condition)
    answer = []
    nodes = tests = 0
    pending = [root]
    until pending.empty?
      node = pending.pop
      nodes += 1
      tests += node.held.length
      node.held.each { |object| answer << object[0] if object_condition.call(object) }
      node.children.reverse_each do |child|
        pending << child if region_condition.call(child.region)
      end
    end
    [answer.sort, nodes, tests]
  end

  def window_count(root, window)
    answer = nodes = tests = 0
    pending = [root]
    until pending.empty?
      node = pending.pop
      nodes += 1
      if RTree.contains?(window, node.region)
        answer += node.count
        next
      end
      tests += node.held.length
      answer += node.held.count { |point| RTree.contains?(window, RTree.point_box(point)) }
      node.children.reverse_each do |child|
        pending << child if RTree.intersects?(child.region, window)
      end
    end
    [answer, nodes, tests]
  end

  def best_first(root, query, count)
    pending = PriorityQueue.new
    pending.push([minimum_distance(query, root.region), 0, 0, root])
    next_serial = 1
    answer = []
    nodes = tests = 0
    until pending.empty?
      distance, kind, _tie, element = pending.pop
      if kind == 1
        answer << [element[0], distance]
        break if answer.length == count

        next
      end
      nodes += 1
      tests += element.held.length
      element.held.each do |object|
        pending.push([object_distance(query, object), 1, object[0], object])
      end
      element.children.each do |child|
        pending.push([minimum_distance(query, child.region), 0, next_serial, child])
        next_serial += 1
      end
    end
    [answer, nodes, tests]
  end

  def spatial_join(point_root, rectangle_root)
    answer = []
    nodes = tests = 0
    pending = [[point_root, rectangle_root]]
    until pending.empty?
      points, rectangles = pending.pop
      nodes += 1
      if points.children.empty? && rectangles.children.empty?
        tests += points.held.length * rectangles.held.length
        points.held.each do |point|
          rectangles.held.each do |rectangle|
            if RTree.contains?(object_box(rectangle), RTree.point_box(point))
              answer << [rectangle[0], point[0]]
            end
          end
        end
        next
      end
      children = []
      if points.children.empty?
        rectangles.children.each do |child|
          children << [points, child] if RTree.intersects?(points.region, child.region)
        end
      elsif rectangles.children.empty?
        points.children.each do |child|
          children << [child, rectangles] if RTree.intersects?(child.region, rectangles.region)
        end
      else
        points.children.each do |point_child|
          rectangles.children.each do |rectangle_child|
            if RTree.intersects?(point_child.region, rectangle_child.region)
              children << [point_child, rectangle_child]
            end
          end
        end
      end
      pending.concat(children.reverse)
    end
    [answer.sort, nodes, tests]
  end

  def brute_force(command, values, points, rectangles)
    case command
    when 'RANGE', 'RADIUS', 'CONTAINS'
      _, condition = search_conditions(command, values)
      objects = command == 'CONTAINS' ? rectangles : points
      objects.filter_map { |object| object[0] if condition.call(object) }.sort
    when 'WINDOWCOUNT'
      points.count { |point| RTree.contains?(values, RTree.point_box(point)) }
    when 'KNN', 'NEAREST'
      x, y, count = values
      objects = command == 'NEAREST' ? rectangles : points
      objects.map { |object| [object_distance([x, y], object), object[0]] }
             .sort.first(count).map { |distance, id| [id, distance] }
    when 'JOIN'
      rectangles.flat_map do |rectangle|
        points.filter_map do |point|
          [rectangle[0], point[0]] if RTree.contains?(object_box(rectangle), RTree.point_box(point))
        end
      end.sort
    end
  end

  def structures_for(command)
    return %w[rtree str] if command == 'JOIN'
    return RECTANGLE_STRUCTURES if %w[CONTAINS NEAREST].include?(command)

    POINT_STRUCTURES
  end

  def locate_kd(root, point)
    path = +''
    node = root
    until node.point[0] == point[0]
      if KDTree.less?(point, node.point, node.axis)
        path << 'L'
        node = node.left
      else
        path << 'R'
        node = node.right
      end
    end
    path.empty? ? '-' : path
  end

  def locate_quad(root, point)
    path = []
    node = root
    until node.children.empty?
      destination = QuadTree.destination(node, point)
      path << QuadTree::CHILD_NAMES[destination]
      node = node.children[destination]
    end
    path.empty? ? '-' : path.join('/')
  end

  def locate_rtree(root, point)
    box = RTree.point_box(point)
    pending = [[root, []]]
    until pending.empty?
      node, path = pending.pop
      if node.level.zero?
        node.entries.each_with_index do |entry, index|
          return (path + [index + 1]).join('/') if entry.id == point[0]
        end
      else
        (node.entries.length - 1).downto(0) do |index|
          entry = node.entries[index]
          pending << [entry.child, path + [index + 1]] if RTree.contains?(entry.box, box)
        end
      end
    end
    raise 'Point is absent from its R-tree'
  end

  def dump_kd(root)
    preorder(root).map do |view|
      prefix = '  ' * (view.depth + 1)
      id, x, y = view.held[0]
      axis = 'xy'[view.source.axis]
      "#{prefix}#{view.mark} #{axis} #{id} #{x} #{y} box #{Report.ids(view.region)}"
    end
  end

  def dump_quad(root)
    preorder(root).map do |view|
      node = view.source
      prefix = '  ' * (view.depth + 1)
      square = "#{view.mark} #{node.x} #{node.y} #{node.size}"
      contents = if view.children.empty?
                   "leaf #{Report.ids(view.held.map(&:first))}"
                 else
                   "node count #{view.count}"
                 end
      "#{prefix}#{square} #{contents}"
    end
  end

  def dump_rtree(root)
    preorder(root).map do |view|
      prefix = '  ' * (view.depth + 1)
      box = Report.ids(view.region)
      if view.source.level.zero?
        "#{prefix}leaf #{box} ids #{Report.ids(view.held.map(&:first))}"
      else
        "#{prefix}node #{view.source.level} #{box} entries #{view.source.entries.length}"
      end
    end
  end

  def kd_statistics(root)
    depths = Hash.new { |hash, depth| hash[depth] = [0, 0, 0] }
    depth_sum = 0
    preorder(root).each do |view|
      row = depths[view.depth]
      row[0] += 1
      row[1] += 1 if view.children.empty?
      row[2] += 1 if view.children.length == 1
      depth_sum += view.depth
    end
    height = depths.keys.max + 1
    nodes = depths.values.sum(&:first)
    leaves = depths.values.sum { |row| row[1] }
    one_child = depths.values.sum { |row| row[2] }
    average = Report.fraction(depth_sum, nodes)
    lines = ["kdtree height #{height} ideal #{nodes.bit_length} nodes #{nodes} " \
             "leaves #{leaves} one_child #{one_child} depth_sum #{depth_sum} avg_depth #{average}"]
    height.times do |depth|
      count, leaf_count, single_count = depths[depth]
      lines << "  depth #{depth} nodes #{count} leaves #{leaf_count} one_child #{single_count}"
    end
    lines
  end

  def quad_statistics(root, capacity)
    depths = Hash.new { |hash, depth| hash[depth] = [0, 0, 0] }
    empty = maximum = 0
    preorder(root).each do |view|
      row = depths[view.depth]
      if view.children.empty?
        count = view.held.length
        row[1] += 1
        row[2] += count
        empty += 1 if count.zero?
        maximum = [maximum, count].max
      else
        row[0] += 1
      end
    end
    height = depths.keys.max + 1
    internal = depths.values.sum(&:first)
    leaves = depths.values.sum { |row| row[1] }
    fill = Report.fraction(root.count, leaves * capacity)
    lines = ["quadtree height #{height} internal #{internal} leaves #{leaves} " \
             "empty #{empty} max_leaf #{maximum} fill #{fill}"]
    height.times do |depth|
      internal_count, leaf_count, point_count = depths[depth]
      lines << "  depth #{depth} internal #{internal_count} leaves #{leaf_count} points #{point_count}"
    end
    lines
  end

  def rtree_statistics(name, root, maximum, minimum)
    levels = Hash.new { |hash, level| hash[level] = [] }
    entries = 0
    preorder(root).each do |view|
      levels[view.source.level] << view
      entries += view.source.entries.length
    end
    height = root.source.level + 1
    nodes = levels.values.sum(&:length)
    leaves = levels[0].length
    fill = Report.fraction(entries, nodes * maximum)
    lines = ["#{name} height #{height} nodes #{nodes} leaves #{leaves} entries #{entries} fill #{fill}"]
    (height - 1).downto(0) do |level|
      group = levels[level]
      sizes = group.map { |view| view.source.entries.length }
      area_sum = group.sum { |view| RTree.area(view.region) }
      overlap_sum = group.combination(2).sum { |first, second| RTree.overlap(first.region, second.region) }
      under = sizes.count { |size| size < minimum }
      lines << "  level #{level} nodes #{group.length} entries #{sizes.sum} " \
               "min #{sizes.min} max #{sizes.max} under #{under} area #{area_sum} overlap #{overlap_sum}"
    end
    lines
  end

  def grid_statistics(root)
    occupancy = root.children.map { |cell| cell.held.length }.tally
    cells = root.children.length
    used = cells - occupancy.fetch(0, 0)
    sequence = occupancy.keys.sort.map { |count| "#{count}:#{occupancy[count]}" }.join(' ')
    ["grid cells #{cells} used #{used} max #{occupancy.keys.max}", "  occupancy #{sequence}"]
  end

  def visits_summary(totals)
    lines = ['visits']
    SEARCH_COMMANDS.each do |command|
      next unless totals.key?(command)

      structures = structures_for(command)
      command_totals = totals[command]
      structures.each do |name|
        queries, nodes, tests, maximum = command_totals[name]
        mean = Report.fraction(nodes, queries)
        lines << "#{command} #{name} queries #{queries} nodes #{nodes} tests #{tests} " \
                 "max_nodes #{maximum} mean_nodes #{mean}"
      end
      ranking = structures.each_with_index.sort_by do |name, position|
        [command_totals[name][1], command_totals[name][2], position]
      end.map(&:first)
      lines << "rank #{command} #{ranking.join(' ')}"
    end
    lines
  end

  class Laboratory
    include SpatialLab

    def initialize(points, rectangles, parameters)
      @points = points.to_h { |point| [point[0], point] }
      @rectangles = rectangles.to_h { |rectangle| [rectangle[0], rectangle] }
      @parameters = parameters
      world = parameters[:world]
      @kd_root = KDTree.build(points)
      @quad_root = QuadTree.build(points, world, parameters[:bucket])
      @grid = Grid.new(world, parameters[:cell_size], points)
      @rtrees = {}
      RTREE_STRUCTURES.each do |name|
        objects = RECTANGLE_STRUCTURES.include?(name) ? rectangles : points
        entries = objects.map { |object| RTree::Entry.new(object_box(object), object[0]) }
        @rtrees[name] = RTree.build(entries, parameters[:maximum], parameters[:minimum],
                                   bulk: %w[str str_rect].include?(name))
      end
      @views = {}
      refresh_point_views
      RECTANGLE_STRUCTURES.each do |name|
        @views[name] = rtree_view(@rtrees[name].root, @rectangles)
      end
      @answers = []
      @visits = ['query,command,structure,nodes,tests']
      @join_rows = ['query,rect,point']
      @structures = []
      @statistics = []
      @visit_totals = {}
      @snapshot_number = 0
      record_snapshot(0)
    end

    def refresh_point_views
      @views['kdtree'] = kd_view(@kd_root, @parameters[:world])
      @views['quadtree'] = quad_view(@quad_root)
      %w[rtree str].each { |name| @views[name] = rtree_view(@rtrees[name].root, @points) }
      @views['grid'] = grid_view(@grid)
    end

    def record_snapshot(query)
      header = "snapshot #{@snapshot_number} query #{query} points #{@points.length} rects #{@rectangles.length}"
      unless @structures.empty?
        @structures << ''
        @statistics << ''
      end
      @structures.concat([header, 'kdtree']).concat(dump_kd(@views['kdtree']))
      @structures << 'quadtree'
      @structures.concat(dump_quad(@views['quadtree']))
      @statistics << header
      @statistics.concat(kd_statistics(@views['kdtree']))
      @statistics.concat(quad_statistics(@views['quadtree'], @parameters[:bucket]))
      RTREE_STRUCTURES.each do |name|
        @structures << name
        @structures.concat(dump_rtree(@views[name]))
        @statistics.concat(rtree_statistics(name, @views[name], @parameters[:maximum], @parameters[:minimum]))
      end
      @statistics.concat(grid_statistics(@views['grid']))
    end

    def search_structure(name, command, values)
      root = @views[name]
      case command
      when 'RANGE', 'RADIUS', 'CONTAINS'
        condition_search(root, *search_conditions(command, values))
      when 'WINDOWCOUNT'
        window_count(root, values)
      when 'JOIN'
        spatial_join(root, @views["#{name}_rect"])
      else
        x, y, count = values
        best_first(root, [x, y], count)
      end
    end

    def record_visit(query, command, name, nodes, tests)
      @visits << "#{query},#{command},#{name},#{nodes},#{tests}"
      totals = (@visit_totals[command] ||= {})
      row = (totals[name] ||= [0, 0, 0, 0])
      row[0] += 1
      row[1] += nodes
      row[2] += tests
      row[3] = [row[3], nodes].max
    end

    def process_search(query, command, values)
      expected = brute_force(command, values, @points.values, @rectangles.values)
      mismatches = []
      structures_for(command).each do |name|
        actual, nodes, tests = search_structure(name, command, values)
        record_visit(query, command, name, nodes, tests)
        mismatches << name unless actual == expected
      end
      check = mismatches.empty? ? 'ok' : "mismatch #{mismatches.join(' ')}"
      prefix = "#{query} #{command} count"
      line = if command == 'WINDOWCOUNT'
               "#{prefix} #{expected} check #{check}"
             elsif command == 'JOIN'
               expected.each { |rectangle, point| @join_rows << "#{query},#{rectangle},#{point}" }
               "#{prefix} #{expected.length} check #{check}"
             else
               sequence = %w[KNN NEAREST].include?(command) ? Report.distances(expected) : Report.ids(expected)
               "#{prefix} #{expected.length} ids #{sequence} check #{check}"
             end
      @answers << line
    end

    def process_locate(query, identifier)
      unless @points.key?(identifier)
        @answers << "#{query} LOCATE #{identifier} missing"
        return
      end
      point = @points[identifier]
      kd_position = locate_kd(@kd_root, point)
      quad_position = locate_quad(@quad_root, point)
      rtree_position = locate_rtree(@rtrees['rtree'].root, point)
      str_position = locate_rtree(@rtrees['str'].root, point)
      column, row = @grid.position(point)
      @answers << "#{query} LOCATE #{identifier} kdtree #{kd_position} quadtree #{quad_position} " \
                  "rtree #{rtree_position} str #{str_position} grid #{column} #{row}"
    end

    def process_insert(query, point)
      @points[point[0]] = point
      @kd_root = KDTree.insert(@kd_root, point)
      QuadTree.insert(@quad_root, point, @parameters[:bucket])
      %w[rtree str].each do |name|
        @rtrees[name].insert(RTree::Entry.new(RTree.point_box(point), point[0]))
      end
      @grid.insert(point)
      refresh_point_views
      @answers << "#{query} INSERT #{point[0]} inserted points #{@points.length}"
    end

    def process_delete(query, identifier)
      point = @points[identifier]
      if point
        @kd_root = KDTree.delete(@kd_root, point)
        QuadTree.delete(@quad_root, point, @parameters[:bucket])
        %w[rtree str].each { |name| @rtrees[name].delete(point) }
        @grid.delete(point)
        @points.delete(identifier)
        refresh_point_views
        status = 'deleted'
      else
        status = 'missing'
      end
      @answers << "#{query} DELETE #{identifier} #{status} points #{@points.length}"
    end

    def process_commands(commands)
      commands.each_with_index do |(command, values), index|
        query = index + 1
        if SEARCH_COMMANDS.include?(command)
          process_search(query, command, values)
        else
          case command
          when 'LOCATE' then process_locate(query, values[0])
          when 'INSERT' then process_insert(query, values)
          when 'DELETE' then process_delete(query, values[0])
          when 'DUMP'
            @snapshot_number += 1
            record_snapshot(query)
            @answers << "#{query} DUMP snapshot #{@snapshot_number}"
          end
        end
      end
    end

    def write_outputs
      files = {
        'answers.txt' => @answers,
        'visits.csv' => @visits,
        'join.csv' => @join_rows,
        'structures.txt' => @structures,
        'stats.txt' => @statistics + [''] + visits_summary(@visit_totals)
      }
      files.each { |filename, lines| Report.write_lines(File.join('output', filename), lines) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  points, rectangles, parameters, commands = Dataset.read
  laboratory = SpatialLab::Laboratory.new(points, rectangles, parameters)
  laboratory.process_commands(commands)
  laboratory.write_outputs
end
