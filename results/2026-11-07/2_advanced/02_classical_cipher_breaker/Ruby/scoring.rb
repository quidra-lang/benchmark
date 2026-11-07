# frozen_string_literal: true

module Scoring
  module_function

  def letter_value(byte)
    return byte - 65 if byte.between?(65, 90)
    return byte - 97 if byte.between?(97, 122)

    nil
  end

  def letters(text)
    result = String.new(encoding: Encoding::ASCII_8BIT)
    text.each_byte do |byte|
      value = letter_value(byte)
      result << value + 65 unless value.nil?
    end
    result
  end

  class Weights
    attr_reader :monograms, :bigrams

    def initialize(lines)
      @monograms = lines[1].split.map(&:to_i)
      @bigrams = lines[3, 26].map { |line| line.split.map(&:to_i) }
    end

    def monogram(text)
      total = 0
      text.each_byte { |byte| total += @monograms[byte - 65] }
      total
    end

    def bigram(text)
      total = 0
      previous = nil
      text.each_byte do |byte|
        value = byte - 65
        total += @bigrams[previous][value] unless previous.nil?
        previous = value
      end
      total
    end
  end
end
