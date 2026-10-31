module Costs
  module_function

  def clamped(image, width, height, x, y)
    image[y.clamp(0, height - 1) * width + x.clamp(0, width - 1)]
  end

  def box_sum(image, width, height, window)
    radius = window / 2
    pw = width + 2 * radius
    ph = height + 2 * radius
    integral = Array.new(ph + 1) { Array.new(pw + 1, 0) }
    ph.times do |y|
      total = 0
      pw.times do |x|
        total += clamped(image, width, height, x - radius, y - radius)
        integral[y + 1][x + 1] = integral[y][x + 1] + total
      end
    end
    Array.new(width * height) do |p|
      y, x = p.divmod(width)
      integral[y + window][x + window] - integral[y][x + window] -
        integral[y + window][x] + integral[y][x]
    end
  end

  def census(image, width, height)
    Array.new(image.length) do |p|
      y, x = p.divmod(width)
      code = 0
      (-2..2).each do |dy|
        (-2..2).each do |dx|
          next if dx.zero? && dy.zero?
          code = (code << 1) | (clamped(image, width, height, x + dx, y + dy) < image[p] ? 1 : 0)
        end
      end
      code
    end
  end

  def texture(image, width, height, window)
    gradient = Array.new(image.length) do |p|
      y, x = p.divmod(width)
      (clamped(image, width, height, x + 1, y) - clamped(image, width, height, x - 1, y)).abs
    end
    box_sum(gradient, width, height, window)
  end

  def cost_volume(left, right, cl, cr, width, height, kind, window, minimum, maximum)
    volume = Array.new(left.length) { [] }
    (minimum..maximum).each do |d|
      pixels = Array.new(left.length) do |p|
        y, x = p.divmod(width)
        q = y * width + [x - d, 0].max
        if kind == 'census'
          bits = cl[p] ^ cr[q]
          count = 0
          until bits.zero?
            bits &= bits - 1
            count += 1
          end
          count
        else
          difference = left[p] - right[q]
          kind == 'sad' ? difference.abs : difference * difference
        end
      end
      box_sum(pixels, width, height, window).each_with_index { |v, p| volume[p] << v }
    end
    volume
  end
end
