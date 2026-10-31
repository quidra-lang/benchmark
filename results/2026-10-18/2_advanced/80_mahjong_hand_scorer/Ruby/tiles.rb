module Tiles
  WINDS = %w[E S W N].freeze
  WIND_TILES = WINDS.zip((27..30).to_a).to_h.freeze
  YAOCHUU = (0...34).select { |k| k >= 27 || [0, 8].include?(k % 9) }.freeze
  GREEN = [19, 20, 21, 23, 25, 32].freeze
  Tile = Data.define(:kind, :red)

  def self.parse(text, empty: false)
    return [] if empty && text == '-'
    return nil unless /\A(?:[0-9]+[mps]|[1-7]+z)+\z/.match?(text)

    text.scan(/([0-9]+)([mpsz])/).flat_map do |digits, suit|
      offset = 'mpsz'.index(suit) * 9
      digits.chars.map { |d| Tile.new(offset + (d == '0' ? 4 : d.to_i - 1), d == '0') }
    end
  end

  def self.name(kind) = "#{kind % 9 + 1}#{'mpsz'[kind / 9]}"
  def self.block(kinds) = kinds.sort.map { |k| k % 9 + 1 }.join + 'mpsz'[kinds.first / 9]
  def self.honor?(kind) = kind >= 27
  def self.terminal?(kind) = kind < 27 && [0, 8].include?(kind % 9)
  def self.yaochuu?(kind) = honor?(kind) || terminal?(kind)

  def self.next_dora(kind)
    return kind / 9 * 9 + (kind + 1) % 9 if kind < 27
    return 27 + (kind - 26) % 4 if kind < 31

    31 + (kind - 30) % 3
  end

  def self.counts(tiles)
    tiles.each_with_object(Array.new(34, 0)) { |t, counts| counts[t.kind] += 1 }
  end
end
