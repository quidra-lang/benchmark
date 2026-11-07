# frozen_string_literal: true

module PGMReader
  Image = Struct.new(:name, :width, :height, :maximum, :pixels, keyword_init: true)

  def self.read
    words = File.readlines('input/images.txt').flat_map { |line| line.split('#', 2).first.split }
    images = []
    cursor = 0
    while cursor < words.length
      name = words[cursor + 1]
      width = words[cursor + 3].to_i
      height = words[cursor + 4].to_i
      maximum = words[cursor + 5].to_i
      pixels = words[cursor + 6, width * height].map(&:to_i)
      images << Image.new(name: name, width: width, height: height, maximum: maximum, pixels: pixels)
      cursor += 6 + width * height
    end
    images
  end
end
