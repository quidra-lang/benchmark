# frozen_string_literal: true

module Canvas
  Pixel = Struct.new(:color, :line)
  Layer = Struct.new(:number, :name, :opacity, :mode, :body, :pixels, :commands, :errors, keyword_init: true)

  def self.round(numerator, denominator)
    numerator, denominator = -numerator, -denominator if denominator.negative?
    (2 * numerator + denominator) / (2 * denominator)
  end

  def self.alpha(layer, index)
    pixel = layer.pixels[index]
    pixel ? round(pixel.color[3] * layer.opacity, 255) : 0
  end

  def self.composite(layers, width, height, background)
    Array.new(width * height) do |index|
      rgb = background.take(3)
      layers.each do |layer|
        pixel = layer.pixels[index]
        next unless pixel

        alpha = self.alpha(layer, index)
        3.times do |channel|
          source = pixel.color[channel]
          previous = rgb[channel]
          source = round(source * previous, 255) if layer.mode == 'multiply'
          source = 255 - round((255 - source) * (255 - previous), 255) if layer.mode == 'screen'
          rgb[channel] = round(alpha * source + (255 - alpha) * previous, 255)
        end
      end
      rgb
    end
  end
end
