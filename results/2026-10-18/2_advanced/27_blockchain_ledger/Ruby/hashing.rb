module Ledger
  module Hashing
    MODULUS = 2_147_483_647
    LANES = [[1_000_003, 11], [1_500_007, 23], [2_750_159, 37], [4_194_301, 53]].freeze

    module_function

    def digest(text)
      LANES.map do |base, initial|
        value = initial
        text.each_byte { |byte| value = (value * base + byte) % MODULUS }
        [text.bytesize, 0, 0].each { |part| value = (value * base + part) % MODULUS }
        value.to_s(16).rjust(8, '0')
      end.join
    end

    def merkle(values)
      level = values.dup
      while level.length > 1
        level << level.last if level.length.odd?
        level = level.each_slice(2).map { |first, second| digest(first + second) }
      end
      level.first
    end

    def short(value)
      value[0, 8]
    end
  end
end
