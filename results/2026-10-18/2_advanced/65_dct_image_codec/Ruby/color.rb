module Color
  module_function

  def to_ycbcr(pixel)
    r, g, b = pixel
    [(19595 * r + 38470 * g + 7471 * b + 32768) / 65536,
     (-11059 * r - 21709 * g + 32768 * b + 8421375) / 65536,
     (32768 * r - 27439 * g - 5329 * b + 8421375) / 65536]
  end

  def to_rgb(y, cb, cr)
    [(y + (91881 * (cr - 128) + 32768) / 65536).clamp(0, 255),
     (y + (-22554 * (cb - 128) - 46802 * (cr - 128) + 32768) / 65536).clamp(0, 255),
     (y + (116130 * (cb - 128) + 32768) / 65536).clamp(0, 255)]
  end

  def split_planes(image)
    planes = Array.new(3) { Array.new(image.length) { Array.new(image.first.length) } }
    image.each_with_index do |row, y|
      row.each_with_index { |pixel, x| to_ycbcr(pixel).each_with_index { |v, c| planes[c][y][x] = v } }
    end
    planes
  end

  def component_planes(planes, factors, mx, my)
    width, height = planes.first.first.length, planes.first.length
    hmax, vmax = factors.map(&:first).max, factors.map(&:last).max
    planes.each_with_index.map do |plane, c|
      h, v = factors[c]
      fx, fy = hmax / h, vmax / v
      Array.new(8 * v * my) do |y|
        Array.new(8 * h * mx) do |x|
          total = 0
          fy.times do |j|
            fx.times { |i| total += plane[[fy * y + j, height - 1].min][[fx * x + i, width - 1].min] }
          end
          total / (fx * fy)
        end
      end
    end
  end

  def upsample(planes, factors, width, height)
    hmax, vmax = factors.map(&:first).max, factors.map(&:last).max
    planes.each_with_index.map do |plane, c|
      h, v = factors[c]
      Array.new(height) { |y| Array.new(width) { |x| plane[y * v / vmax][x * h / hmax] } }
    end
  end

  def combine_rgb(planes)
    Array.new(planes.first.length) do |y|
      Array.new(planes.first.first.length) { |x| to_rgb(*planes.map { |p| p[y][x] }) }
    end
  end
end
