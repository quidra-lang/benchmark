module Relocator
  TYPES = %w[ABS32 REL32 ABS16 HI16 LO16 GPREL16 CALL24].freeze
  WIDTHS = {'ABS32' => 4, 'REL32' => 4, 'ABS16' => 2, 'HI16' => 2,
            'LO16' => 2, 'GPREL16' => 2, 'CALL24' => 3}.freeze
  RANGES = {'ABS32' => [-(2**31), 2**32], 'REL32' => [-(2**31), 2**31],
            'ABS16' => [-(2**15), 2**16], 'HI16' => [-(2**31), 2**32],
            'GPREL16' => [-(2**15), 2**15], 'CALL24' => [-(2**25), 2**25]}.freeze
  module_function

  def unpaired_hi16?(relocations, index)
    current = relocations[index]
    return false unless current.type == 'HI16'
    following = relocations[index + 1]
    !following || following.type != 'LO16' || !following.symbol.equal?(current.symbol) || following.addend != current.addend
  end

  def calculate(type, symbol, addend, place, gp)
    value = symbol + addend
    value -= place if %w[REL32 CALL24].include?(type)
    value -= gp if type == 'GPREL16'
    field = case type
            when 'HI16' then ((value % 2**32 + 32768) / 65536) % 65536
            when 'CALL24' then (value / 4) % 2**24
            else value % 2**(8 * WIDTHS.fetch(type))
            end
    range = RANGES[type]
    [value, field, !range || range[0] <= value && value < range[1]]
  end
end
