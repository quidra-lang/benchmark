# frozen_string_literal: true

require_relative 'scoring'

module Substitution
  AFFINE_MULTIPLIERS = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25].freeze

  module_function

  def inverse(multiplier)
    (1..25).find { |value| (multiplier * value) % 26 == 1 }
  end

  def transform(text, cipher, key, decrypt: false)
    shift = key.to_i if cipher == 'caesar'
    if cipher == 'affine'
      multiplier, offset = key.split(',').map(&:to_i)
      reciprocal = inverse(multiplier) if decrypt
    end
    seed = key.bytes.map { |byte| byte - 65 } if %w[vigenere autokey].include?(cipher)
    plaintext = []
    index = 0
    result = String.new(encoding: Encoding::ASCII_8BIT)
    text.each_byte do |byte|
      value = Scoring.letter_value(byte)
      if value.nil?
        result << byte
        next
      end
      transformed = case cipher
                    when 'caesar'
                      (value + (decrypt ? -shift : shift)) % 26
                    when 'affine'
                      decrypt ? reciprocal * (value - offset) % 26 : (multiplier * value + offset) % 26
                    when 'vigenere'
                      amount = seed[index % seed.length]
                      (value + (decrypt ? -amount : amount)) % 26
                    when 'autokey'
                      amount = index < seed.length ? seed[index] : plaintext[index - seed.length]
                      (value + (decrypt ? -amount : amount)) % 26
                    end
      plaintext << (decrypt ? transformed : value) if cipher == 'autokey'
      result << transformed + (byte.between?(65, 90) ? 65 : 97)
      index += 1
    end
    result
  end
end
