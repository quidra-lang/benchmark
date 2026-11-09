module Canvas
  def self.walk(box, x, y, level = 0, role = '', &block)
    yield box, x, y, level, role
    box.children.each do |child, dx, dy, child_role|
      walk(child, x + dx, y + dy, level + 1, child_role, &block)
    end
  end

  def self.draw(roots, width, height)
    grid = Array.new(height) { ' ' * width }
    roots.each do |root, x, y|
      walk(root, x, y) do |box, bx, by, _, _|
        box.strings.each do |text, dx, dy|
          text.each_char.with_index { |ch, i| grid[by + dy][bx + dx + i] = ch unless ch == ' ' }
        end
      end
    end
    grid.map(&:rstrip)
  end

  def self.box_lines(roots)
    result = []
    roots.each do |root, x, y|
      walk(root, x, y) do |box, bx, by, level, role|
        text = '  ' * level + role + box.description + " x=#{bx} y=#{by} w=#{box.width} h=#{box.height} b=#{box.baseline}"
        result << [text, level, box.description.split(' ', 2)[0]]
      end
    end
    result
  end
end
