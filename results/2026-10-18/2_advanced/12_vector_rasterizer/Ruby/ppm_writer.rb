# frozen_string_literal: true

module PPMWriter
  def self.write(image, width, height)
    lines = ['P3', "#{width} #{height}", '255']
    image.each_slice(width) { |row| lines << row.flatten.join(' ') }
    File.binwrite('output/image.ppm', lines.join("\n") + "\n")
    ramp = '@%#*+=-:,.'
    preview = Array.new(height / 4) do |row|
      Array.new(width / 2) do |column|
        brightness = 0
        4.times do |dy|
          2.times do |dx|
            red, green, blue = image[(row * 4 + dy) * width + column * 2 + dx]
            brightness += 299 * red + 587 * green + 114 * blue
          end
        end
        ramp[(brightness / 8000) * 10 / 256]
      end.join
    end
    File.binwrite('output/preview.txt', preview.join("\n") + "\n")
  end
end
