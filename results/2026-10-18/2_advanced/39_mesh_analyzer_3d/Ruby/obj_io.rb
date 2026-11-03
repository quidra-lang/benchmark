module MeshAnalyzer
  Polygon = Data.define(:number, :line, :group, :vertices)
  Model = Data.define(:line_count, :vertices, :polygons, :errors, :ignored)

  module ObjIO
    extend self

    IGNORED = %w[vt vn s o usemtl mtllib].freeze

    def integer_word?(word) = /\A-?[0-9]+\z/.match?(word)

    def read(path)
      lines = File.readlines(path, chomp: true)
      vertices, polygons, errors = [nil], [], []
      ignored = 0
      group = 'default'
      lines.each_with_index do |text, index|
        next if text.empty? || text.start_with?('#')

        keyword, *args = text.split(' ')
        case keyword
        when 'v'
          if args.length == 3 && args.all? { |word| integer_word?(word) }
            vertices << args.map(&:to_i)
          else
            errors << [index + 1, 'bad_vertex']
          end
        when 'f'
          if args.length < 3
            errors << [index + 1, 'short_face']
            next
          end
          resolved = []
          error = nil
          args.each do |reference|
            word = reference.partition('/').first
            unless integer_word?(word) && !word.to_i.zero?
              error = 'bad_index'
              break
            end
            number = word.to_i
            number += vertices.length if number.negative?
            unless number >= 1 && number < vertices.length
              error = 'out_of_range'
              break
            end
            resolved << number
          end
          if error
            errors << [index + 1, error]
          else
            polygons << Polygon.new(polygons.length + 1, index + 1, group, resolved)
          end
        when 'g' then group = args.first || 'default'
        when *IGNORED then ignored += 1
        else errors << [index + 1, 'unknown_keyword']
        end
      end
      Model.new(lines.length, vertices, polygons, errors, ignored)
    end

    def repaired_lines(points, faces)
      lines = ["# vertices #{points.length - 1} faces #{faces.length}"]
      points.drop(1).each { |point| lines << "v #{point.join(' ')}" }
      previous_group = nil
      faces.each do |face|
        if face.group != previous_group
          lines << "g #{face.group}"
          previous_group = face.group
        end
        lines << "f #{face.vertices.join(' ')}"
      end
      lines
    end
  end
end
