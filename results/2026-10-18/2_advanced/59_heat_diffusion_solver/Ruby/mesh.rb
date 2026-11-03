class Mesh
  attr_reader :width, :height, :dx, :thickness, :count, :codes, :neighbors
  FACE = { 'left' => 0, 'right' => 1, 'top' => 2, 'bottom' => 3 }.freeze

  def initialize(path = 'input/plate.txt')
    lines = File.readlines(path, chomp: true)
    w, h, dx, d = lines.shift.split
    @width, @height, @dx, @thickness = w.to_i, h.to_i, dx.to_f, d.to_f
    @count = @width * @height
    @codes = lines.join.chars
    @neighbors = Array.new(@count) do |p|
      r, c = p.divmod(@width)
      [c.positive? ? p - 1 : nil, c + 1 < @width ? p + 1 : nil,
       r.positive? ? p - @width : nil, r + 1 < @height ? p + @width : nil]
    end
  end

  def cell(row, column) = row * @width + column
  def coordinates(point) = point.divmod(@width).join(' ')

  def segment_faces(edge, first, last)
    (first..last).map do |i|
      p = case edge
          when 'left' then cell(i, 0)
          when 'right' then cell(i, @width - 1)
          when 'top' then cell(0, i)
          when 'bottom' then cell(@height - 1, i)
          end
      [p, FACE.fetch(edge)]
    end
  end

  def source_cells(r1, c1, r2, c2)
    (r1..r2).flat_map { |r| (c1..c2).map { |c| cell(r, c) } }
  end
end
