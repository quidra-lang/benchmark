module Bitstream
  ALPHANUMERIC = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:'.freeze
  VALUES = ALPHANUMERIC.chars.each_with_index.to_h.freeze

  def self.binary(value, width) = value.to_s(2).rjust(width, '0')
  def self.from_codewords(words) = words.map { |value| binary(value, 8) }.join
  def self.to_codewords(bits) = bits.scan(/.{8}/).map { |part| part.to_i(2) }
  def self.hexadecimal(words) = words.map { |value| '%02x' % value }.join

  class Writer
    attr_reader :bits

    def initialize = @bits = +''
    def write(value, width) = @bits << Bitstream.binary(value, width)
  end

  class Reader
    attr_reader :position

    def initialize(bits)
      @bits, @position = bits, 0
    end

    def remaining = @bits.length - @position

    def read(width)
      value = @bits[@position, width].to_i(2)
      @position += width
      value
    end
  end
end
