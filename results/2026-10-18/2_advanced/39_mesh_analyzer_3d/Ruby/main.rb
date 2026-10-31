require 'set'
require 'fileutils'
require_relative 'obj_io'
require_relative 'measure'
require_relative 'repair'
require_relative 'topology'
require_relative 'orientation'

module MeshAnalyzer
  class Analyzer
    include Measure

    def self.read_parameters(path)
      settings = { snap: 1, merge: true, degenerate: true, duplicates: true, orient: true,
                   outward: true, fill_holes: 0, keep_unused: true,
                   sections: %w[summary components], queries: [] }
      File.readlines(path, chomp: true).each do |text|
        next if text.empty? || text.start_with?('#')

        name, *args = text.split(' ')
        case name
        when 'query' then settings[:queries] << [args.first, args.drop(1).map(&:to_i)]
        when 'sections' then settings[:sections] = args
        when 'snap', 'fill_holes' then settings[name.to_sym] = args[0].to_i
        else settings[name.to_sym] = args[0] == 'on'
        end
      end
      settings
    end

    def initialize(source, settings)
      @source, @settings = source, settings
      cleanup
      analyze_before_filling
      analyze_final_mesh
      @nonplanar = @source.polygons.select { |polygon| nonplanar?(polygon) }.map(&:number).to_set
      @group_order = @source.polygons.map(&:group).uniq
      @group_order << 'fill' unless @added.empty?
    end

    def yes(value) = value ? 'yes' : 'no'
    def listing(items) = items.empty? ? '-' : items.join(' ')

    def cleanup
      @snapped, @snapped_list = Repair.snap(@source.vertices, @settings[:snap])
      @representatives = Repair.representatives(@snapped, @settings[:merge])
      @merged = (1...@representatives.length).count { |vertex| @representatives[vertex] != vertex }
      @merge_groups = (1...@representatives.length).group_by { |vertex| @representatives[vertex] }
      @triangles = Repair.split_polygons(@source.polygons)
      @faces, @removed = Repair.clean(@triangles, @snapped, @representatives,
                                      @settings[:degenerate], @settings[:duplicates])
      renumber_vertices
      @initial_faces = @faces.length
      @initial_orientations = @faces.map(&:vertices)
    end

    def renumber_vertices
      present = if @settings[:keep_unused]
                  (1...@representatives.length).select { |vertex| @representatives[vertex] == vertex }
                else
                  @faces.flat_map(&:vertices).uniq.sort
                end
      @renumber = present.each_with_index.to_h { |original, index| [original, index + 1] }
      @points = [nil] + present.map { |original| @snapped[original] }
      @faces.each { |face| face.vertices = face.vertices.map { |vertex| @renumber.fetch(vertex) } }
    end

    def build_loops(faces, mesh)
      Topology.trace_loops(mesh).each do |loop|
        unless loop.closed
          loop.kind = 'open'
          next
        end
        directed = loop.vertices.each_with_index.map do |first, index|
          last = loop.vertices[(index + 1) % loop.length]
          face = faces[mesh[:edges][Topology.key_edge(first, last)].first - 1]
          Orientation.has_directed?(face.vertices, first, last)
        end
        if directed.all?
          loop.kind = 'coherent'
        elsif directed.none?
          loop.kind = 'coherent'
          loop.vertices = [loop.vertices.first, *loop.vertices.drop(1).reverse]
        else
          loop.kind = 'mixed'
        end
      end
    end

    def analyze_before_filling
      @mesh_before = Topology.analyze(@faces)
      @inconsistent_before = Orientation.inconsistent_edges(@faces, @mesh_before[:edges])
      Orientation.repair(@faces, @mesh_before[:edges]) if @settings[:orient]
      @inconsistent_after = Orientation.inconsistent_edges(@faces, @mesh_before[:edges])
      violations = @inconsistent_after.to_set
      permitted = @mesh_before[:components].select do |component|
        component[:nonmanifold].empty? && component[:edges].none? { |edge| violations.include?(edge) }
      end.map { |component| component[:number] }.to_set
      @loops_before = build_loops(@faces, @mesh_before)
      @added = []
      @loops_before.each do |loop|
        next unless loop.kind == 'coherent' && loop.length >= 3 && loop.length <= @settings[:fill_holes]
        next unless loop.vertices.uniq.length == loop.length && permitted.include?(loop.component)

        loop.filled = true
        @added.concat(Repair.fill_triangles(loop.vertices))
      end
      @faces.concat(@added)
    end

    def analyze_final_mesh
      @mesh = Topology.analyze(@faces)
      violations = Orientation.inconsistent_edges(@faces, @mesh[:edges]).to_set
      @components = @mesh[:components].map do |component|
        closed = component[:boundary].empty?
        manifold = component[:nonmanifold].empty? && component[:nonmanifold_vertices].empty?
        consistent = component[:edges].none? { |edge| violations.include?(edge) }
        component.merge(closed: closed, manifold: manifold, consistent: consistent,
                        solid: closed && manifold && consistent)
      end
      find_nesting
      orient_outward
      @flipped_faces = (0...@initial_faces).count do |index|
        @faces[index].vertices != @initial_orientations[index]
      end
      copied = @faces.map(&:dup)
      Orientation.repair(copied, @mesh[:edges])
      orientability_violations = Orientation.inconsistent_edges(copied, @mesh[:edges]).to_set
      final_loops = build_loops(@faces, @mesh)
      loop_counts = final_loops.map(&:component).tally
      @edge_details = @mesh[:edges].to_h do |edge, ids|
        kind = ids.length == 1 ? 'boundary' : (ids.length == 2 ? 'manifold' : 'nonmanifold')
        [edge, { kind: kind, shape: edge_shape(edge, ids), len2: edge_length_squared(edge, @points) }]
      end
      @components.each do |component|
        component[:orientable] = component[:edges].none? { |edge| orientability_violations.include?(edge) }
        component[:loops] = loop_counts.fetch(component[:number], 0)
        measure_component(component)
      end
      @neighbors = Array.new(@points.length) { [] }
      @mesh[:edges].each_key do |a, b|
        @neighbors[a] << b
        @neighbors[b] << a
      end
      @neighbors.each(&:sort!)
    end

    def find_nesting
      solids = @components.select { |component| component[:solid] }
      @components.each { |component| component[:inside] = [] }
      solids.each do |component|
        solids.each do |other|
          next if component.equal?(other)

          sample_vertex = (component[:vertices] - other[:vertices]).first
          next if sample_vertex.nil?

          winding = winding_number(other[:faces], @faces, @points, @points[sample_vertex])
          component[:inside] << other[:number] unless winding.zero?
        end
      end
    end

    def orient_outward
      @outward_components = 0
      return unless @settings[:outward]

      @components.each do |component|
        next unless component[:solid]

        signed = volume6(component[:faces], @faces, @points)
        wrong = component[:inside].length.even? ? signed.negative? : signed.positive?
        next unless wrong

        component[:faces].each { |id| Orientation.flip(@faces[id - 1]) }
        @outward_components += 1
      end
    end

    def edge_shape(edge, ids)
      return '-' unless ids.length == 2

      a, b = edge
      first, second = ids.map { |id| @faces[id - 1] }
      if Orientation.has_directed?(first.vertices, a, b) == Orientation.has_directed?(second.vertices, a, b)
        return 'inconsistent'
      end
      third = second.vertices.find { |vertex| vertex != a && vertex != b }
      signed = dot(subtract(@points[third], @points[first.vertices[0]]), normal(first, @points))
      signed.negative? ? 'convex' : (signed.positive? ? 'concave' : 'flat')
    end

    def measure_component(component)
      ids, edges = component[:faces], component[:edges]
      component[:euler] = component[:vertices].length - edges.length + ids.length
      characteristic = 2 - component[:euler] - component[:loops]
      component[:genus] = characteristic.div(2) if component[:manifold] && component[:orientable]
      component[:crosscaps] = characteristic if component[:manifold] && !component[:orientable]
      component[:volume6] = volume6(ids, @faces, @points)
      if component[:solid] && !component[:volume6].zero?
        component[:centroid] = centroid(ids, @faces, @points, component[:volume6])
      end
      selected_faces = ids.map { |id| @faces[id - 1] }
      component[:area] = area(selected_faces, @points)
      component[:normal_sum] = selected_faces.map { |face| normal(face, @points) }.transpose.map(&:sum)
      component[:bbox] = bbox(component[:vertices], @points)
      component[:shapes] = edges.map { |edge| @edge_details[edge][:shape] }.tally
      component[:angles] = selected_faces.map { |face| triangle_angle(face, @points) }.tally
      lengths = edges.map { |edge| @edge_details[edge][:len2] }
      component[:edge_min], component[:edge_max] = lengths.minmax
      degree = Hash.new(0)
      edges.each { |edge| edge.each { |vertex| degree[vertex] += 1 } }
      component[:valence_min], component[:valence_max] = degree.values.minmax
    end

    def nonplanar?(polygon)
      corners = polygon.vertices
      first = @snapped[corners[0]]
      normal_sum = [0, 0, 0]
      (1...corners.length - 1).each do |index|
        n = cross(subtract(@snapped[corners[index]], first), subtract(@snapped[corners[index + 1]], first))
        normal_sum = normal_sum.zip(n).map { |a, b| a + b }
      end
      corners.any? { |vertex| !dot(subtract(@snapped[vertex], first), normal_sum).zero? }
    end

    def section_summary
      sizes = @source.polygons.map { |polygon| polygon.vertices.length }.tally
      removals = @removed.map(&:last).tally
      lines = ['[summary]', "lines #{@source.line_count}", "vertices #{@source.vertices.length - 1}",
               "polygons #{@source.polygons.length}", "errors #{@source.errors.length}",
               "ignored #{@source.ignored}", "nonplanar_polygons #{@nonplanar.length}"]
      sizes.sort.each { |size, count| lines << "polygon_size #{size} #{count}" }
      lines.concat([
        "triangles #{@triangles.length}", "snapped #{@snapped_list.length}", "merged #{@merged}",
        "removed_repeated #{removals.fetch('repeated', 0)}",
        "removed_zero_area #{removals.fetch('zero_area', 0)}",
        "removed_duplicate #{removals.fetch('duplicate', 0)}", "faces #{@initial_faces}",
        "inconsistent_before #{@inconsistent_before.length}", "flipped_faces #{@flipped_faces}",
        "outward_components #{@outward_components}", "boundary_loops #{@loops_before.length}",
        "holes_filled #{@loops_before.count(&:filled)}", "fill_faces #{@added.length}",
        "final_vertices #{@points.length - 1}", "final_faces #{@faces.length}",
        "components #{@components.length}", "solids #{@components.count { |component| component[:solid] }}",
        "total_area #{real(area(@faces, @points))}",
        "total_volume #{fraction(@components.select { |component| component[:solid] }.sum { |component| component[:volume6] }, 6)}"
      ])
      lines
    end

    def section_warnings
      ['[warnings]', *@source.errors.map { |line, kind| "line #{line} #{kind}" }]
    end

    def section_cleanup
      lines = ['[cleanup]', "snapped #{@snapped_list.length}"]
      @snapped_list.each { |number, before, after| lines << "snap #{number} #{listing(before)} to #{listing(after)}" }
      lines << "merged #{@merged}"
      @merge_groups.sort.each do |original, members|
        lines << "merge #{@renumber.fetch(original, '-')} #{listing(members)}" if members.length > 1
      end
      lines << "removed #{@removed.length}"
      @removed.each do |triangle, reason|
        lines << "remove #{triangle.triangle} polygon #{triangle.polygon} line #{triangle.line} #{reason}"
      end
      lines
    end

    def section_components
      @components.flat_map do |component|
        groups = component[:faces].map { |id| @faces[id - 1].group }.to_set
        genus = if component.key?(:genus)
                  "genus #{component[:genus]}"
                elsif component.key?(:crosscaps)
                  "crosscaps #{component[:crosscaps]}"
                else
                  'genus -'
                end
        center = component[:centroid]&.map { |coordinate| fraction(coordinate) }
        shapes, angles = component[:shapes], component[:angles]
        ["[component #{component[:number]}]",
         "groups #{listing(@group_order.select { |group| groups.include?(group) })}",
         "faces #{component[:faces].length}", "vertices #{component[:vertices].length}",
         "edges #{component[:edges].length}", "boundary_edges #{component[:boundary].length}",
         "nonmanifold_edges #{component[:nonmanifold].length}",
         "nonmanifold_vertices #{component[:nonmanifold_vertices].length}",
         "boundary_loops #{component[:loops]}", "closed #{yes(component[:closed])}",
         "manifold #{yes(component[:manifold])}", "orientable #{yes(component[:orientable])}",
         "consistent #{yes(component[:consistent])}", "solid #{yes(component[:solid])}",
         "euler #{component[:euler]}", genus,
         "volume #{component[:solid] ? fraction(component[:volume6], 6) : '-'}",
         "area #{real(component[:area])}", "normal_sum #{listing(component[:normal_sum])}",
         "bbox #{listing(component[:bbox])}", "inside #{listing(component[:inside])}",
         "centroid #{center ? listing(center) : '-'}",
         "convex #{shapes.fetch('convex', 0)}", "concave #{shapes.fetch('concave', 0)}",
         "flat #{shapes.fetch('flat', 0)}", "acute #{angles.fetch('acute', 0)}",
         "right #{angles.fetch('right', 0)}", "obtuse #{angles.fetch('obtuse', 0)}",
         "edge_len2 #{component[:edge_min]} #{component[:edge_max]}",
         "valence #{component[:valence_min]} #{component[:valence_max]}"]
      end
    end

    def section_groups
      @group_order.flat_map do |group|
        polygons = @source.polygons.select { |polygon| polygon.group == group }
        ids = @faces.each_index.select { |index| @faces[index].group == group }
        components = ids.map { |index| @mesh[:face_components][index + 1] }.uniq.sort
        ["[group #{group}]", "polygons #{polygons.length}",
         "triangles #{@triangles.count { |triangle| triangle.group == group }}",
         "nonplanar #{polygons.count { |polygon| @nonplanar.include?(polygon.number) }}",
         "faces #{ids.length}", "area #{real(area(ids.map { |index| @faces[index] }, @points))}",
         "components #{listing(components)}"]
      end
    end

    def section_contacts
      lines = ['[contacts]']
      @components.combination(2) do |first, second|
        intersects = 3.times.all? do |axis|
          first[:bbox][axis] <= second[:bbox][axis + 3] && second[:bbox][axis] <= first[:bbox][axis + 3]
        end
        next unless intersects

        gap = nil
        first[:vertices].each do |u|
          second[:vertices].each do |v|
            next if u == v

            distance = edge_length_squared([u, v], @points)
            gap = distance if gap.nil? || distance < gap
          end
        end
        shared = (first[:vertices] & second[:vertices]).length
        lines << "contact #{first[:number]} #{second[:number]} shared #{shared} gap2 #{gap}"
      end
      lines
    end

    def section_edges
      counts = @edge_details.values.map { |detail| detail[:kind] }.tally
      shapes = @edge_details.values.map { |detail| detail[:shape] }.tally
      shortest = @edge_details.keys.min_by { |edge| [@edge_details[edge][:len2], *edge] }
      longest = @edge_details.keys.min_by { |edge| [-@edge_details[edge][:len2], *edge] }
      ['[edges]', "edges #{@edge_details.length}", "boundary #{counts.fetch('boundary', 0)}",
       "manifold #{counts.fetch('manifold', 0)}", "nonmanifold #{counts.fetch('nonmanifold', 0)}",
       "max_faces #{@mesh[:edges].values.map(&:length).max}", "convex #{shapes.fetch('convex', 0)}",
       "concave #{shapes.fetch('concave', 0)}", "flat #{shapes.fetch('flat', 0)}",
       "inconsistent #{shapes.fetch('inconsistent', 0)}",
       "shortest #{listing(shortest)} len2 #{@edge_details[shortest][:len2]}",
       "longest #{listing(longest)} len2 #{@edge_details[longest][:len2]}"]
    end

    def section_valence
      degrees = @neighbors.drop(1).map(&:length).select(&:positive?)
      lines = ['[valence]', "used #{degrees.length}", "isolated #{@points.length - 1 - degrees.length}",
               "min #{degrees.min}", "max #{degrees.max}", "mean #{fraction(degrees.sum, degrees.length)}"]
      degrees.tally.sort.each { |degree, count| lines << "degree #{degree} #{count}" }
      lines
    end

    def query_vertex(number)
      return "vertex #{number} invalid" unless number >= 1 && number < @points.length

      ids = @faces.each_index.select { |index| @faces[index].vertices.include?(number) }
      boundary = @mesh[:edges].any? { |edge, adjacent| edge.include?(number) && adjacent.length == 1 }
      components = ids.map { |index| @mesh[:face_components][index + 1] }.uniq.sort
      "vertex #{number} at #{listing(@points[number])} faces #{ids.length} valence #{@neighbors[number].length} " \
        "fans #{@mesh[:fans].fetch(number, []).length} boundary #{yes(boundary)} components #{listing(components)}"
    end

    def query_face(number)
      return "face #{number} invalid" unless number >= 1 && number <= @faces.length

      face = @faces[number - 1]
      neighbors = Topology.directed_edges(face.vertices).map do |a, b|
        ids = @mesh[:edges][Topology.key_edge(a, b)]
        if ids.length == 1
          '-'
        elsif ids.length >= 3
          '*'
        else
          ids.find { |id| id != number }
        end
      end
      "face #{number} vertices #{listing(face.vertices)} group #{face.group} polygon #{face.polygon || '-'} " \
        "line #{face.line || '-'} component #{@mesh[:face_components][number]} " \
        "normal #{listing(normal(face, @points))} area #{real(area([face], @points))} neighbors #{listing(neighbors)}"
    end

    def query_edge(first, last)
      edge = Topology.key_edge(first, last)
      detail = @edge_details[edge]
      return "edge #{listing(edge)} none" if detail.nil?

      "edge #{listing(edge)} faces #{listing(@mesh[:edges][edge])} kind #{detail[:kind]} " \
        "shape #{detail[:shape]} len2 #{detail[:len2]}"
    end

    def query_point(point)
      inside, total = [], 0
      @components.each do |component|
        next unless component[:solid]

        winding = winding_number(component[:faces], @faces, @points, point)
        unless winding.zero?
          inside << component[:number]
          total += winding
        end
      end
      "point #{listing(point)} inside #{listing(inside)} winding #{total}"
    end

    def query_path(first, last)
      unless [first, last].all? { |vertex| vertex >= 1 && vertex < @points.length }
        return "path #{first} #{last} invalid"
      end
      parent = { first => nil }
      queue = [first]
      index = 0
      while index < queue.length
        current = queue[index]
        index += 1
        @neighbors[current].each do |other|
          next if parent.key?(other)

          parent[other] = current
          queue << other
        end
      end
      return "path #{first} #{last} none" unless parent.key?(last)

      path = []
      cursor = last
      until cursor.nil?
        path << cursor
        cursor = parent[cursor]
      end
      path.reverse!
      "path #{first} #{last} hops #{path.length - 1} vertices #{listing(path)}"
    end

    def query_view(direction)
      scores = @faces.map { |face| dot(normal(face, @points), direction) }
      silhouette = @mesh[:edges].count do |_, ids|
        next false unless ids.length == 2

        a, b = ids.map { |id| scores[id - 1] }
        (a.positive? && b.negative?) || (a.negative? && b.positive?)
      end
      "view #{listing(direction)} front #{scores.count(&:positive?)} back #{scores.count(&:negative?)} " \
        "side #{scores.count(&:zero?)} silhouette #{silhouette}"
    end

    def section_queries
      lines = ['[queries]']
      @settings[:queries].each do |kind, args|
        lines << case kind
                 when 'vertex' then query_vertex(args[0])
                 when 'face' then query_face(args[0])
                 when 'edge' then query_edge(*args)
                 when 'point' then query_point(args)
                 when 'path' then query_path(*args)
                 when 'view' then query_view(args)
                 end
      end
      lines
    end

    def report
      @settings[:sections].flat_map { |section| public_send("section_#{section}") }
    end

    def components_csv
      rows = @components.map do |component|
        [component[:number], component[:faces].length, component[:vertices].length,
         yes(component[:closed]), component[:euler], component.fetch(:genus, '-'),
         component[:solid] ? component[:volume6] : '-', real(component[:area])].join(',')
      end
      ['component,faces,vertices,closed,euler,genus,volume6,area', *rows]
    end

    def boundaries_report
      lines = ["loops #{@loops_before.length}"]
      @loops_before.each do |loop|
        lines << "loop #{loop.number} component #{loop.component} length #{loop.length} #{loop.kind} " \
                 "#{loop.filled ? 'filled' : 'kept'} vertices #{listing(loop.vertices)}"
      end
      nonmanifold = @mesh_before[:edges].select { |_, ids| ids.length >= 3 }
      lines << "nonmanifold_edges #{nonmanifold.length}"
      nonmanifold.each { |edge, ids| lines << "edge #{listing(edge)} faces #{listing(ids)}" }
      vertices = @mesh_before[:nonmanifold_vertices]
      lines << "nonmanifold_vertices #{vertices.length}"
      vertices.each do |vertex|
        fans = @mesh_before[:fans][vertex]
        components = fans.map { |fan| @mesh_before[:face_components][fan.first] }.uniq.sort
        lines << "vertex #{vertex} fans #{fans.length} components #{listing(components)}"
      end
      lines << "inconsistent_edges #{@inconsistent_after.length}"
      @inconsistent_after.each do |edge|
        lines << "edge #{listing(edge)} faces #{listing(@mesh_before[:edges][edge])}"
      end
      lines
    end

    def self.write_lines(name, lines)
      File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
    end

    def self.run
      analyzer = new(ObjIO.read(File.join('input', 'model.obj')), read_parameters(File.join('input', 'params.txt')))
      FileUtils.mkdir_p('output')
      write_lines('report.txt', analyzer.report)
      write_lines('components.csv', analyzer.components_csv)
      write_lines('boundaries.txt', analyzer.boundaries_report)
      analyzer.write_obj
    end

    def write_obj
      self.class.write_lines('repaired.obj', ObjIO.repaired_lines(@points, @faces))
    end
  end
end

MeshAnalyzer::Analyzer.run if $PROGRAM_NAME == __FILE__
