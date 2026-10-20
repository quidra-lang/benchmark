module Filters
  module_function

  def at(image, x, y)
    image[y.clamp(0, image.length - 1)][x.clamp(0, image.first.length - 1)]
  end

  def smoothing(image, size, kernel, divisor)
    half = size / 2
    Array.new(image.length) do |y|
      Array.new(image.first.length) do |x|
        total = 0
        size.times do |j|
          size.times { |i| total += kernel[j * size + i] * at(image, x + i - half, y + j - half) }
        end
        total / divisor
      end
    end
  end

  def gradient(image)
    gx, gy, magnitude = Array.new(3) { Array.new(image.length) { Array.new(image.first.length, 0) } }
    image.each_index do |y|
      image[y].each_index do |x|
        q = (-1..1).flat_map { |dy| (-1..1).map { |dx| at(image, x + dx, y + dy) } }
        gx[y][x] = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6]
        gy[y][x] = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2]
        magnitude[y][x] = gx[y][x].abs + gy[y][x].abs
      end
    end
    [gx, gy, magnitude]
  end
end
