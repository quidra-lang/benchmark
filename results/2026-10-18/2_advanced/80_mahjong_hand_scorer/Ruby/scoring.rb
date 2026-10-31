require_relative 'tiles'

module Scoring
  def self.triplet_fu(block, concealed, kan)
    type, value = if kan
                    concealed ? ['closed_kan', 16] : ['open_kan', 8]
                  else
                    concealed ? ['closed_triplet', 4] : ['open_triplet', 2]
                  end
    ["#{type} #{Tiles.block(block)}", value * (Tiles.yaochuu?(block.first) ? 2 : 1)]
  end

  def self.fu(form, pair, triplets, wait, closed, method, seat, round, pinfu)
    return [[['chiitoitsu', 25]], 25, 25] if form == 'chiitoitsu'

    items = [['base', 20]]
    items << ['closed_ron', 10] if closed && method == 'ron'
    items << ['tsumo', 2] if method == 'tsumo' && !pinfu
    pair_fu = [pair >= 31, pair == seat, pair == round].count(true) * 2
    items << ["pair #{Tiles.block([pair, pair])}", pair_fu] if pair_fu.positive?
    triplets.each { |block, hidden, kan| items << triplet_fu(block, hidden, kan) }
    items << ["wait #{wait}", 2] if %w[kanchan penchan tanki].include?(wait)
    total = items.sum(&:last)
    if !closed && total == 20
      items << ['open_pinfu', 10]
      total += 10
    end
    [items, total, (total + 9) / 10 * 10]
  end

  def self.limit(han, fu, rules)
    return ['kazoe_yakuman', 8000] if han >= 13 && rules['kazoe_yakuman']
    return ['sanbaiman', 6000] if han >= 11
    return ['baiman', 4000] if han >= 8
    return ['haneman', 3000] if han >= 6

    base = fu * 2**(han + 2)
    return ['mangan', 2000] if han == 5 || base >= 2000 || (rules['kiriage'] && base == 1920)

    ['none', base]
  end

  def self.round_hundred(value) = (value + 99) / 100 * 100

  def self.payments(base, dealer, method)
    if method == 'ron'
      ron = round_hundred(base * (dealer ? 6 : 4))
      [ron, 0, 0, ron]
    elsif dealer
      other = round_hundred(base * 2)
      [0, 0, other, other * 3]
    else
      dealer_pay = round_hundred(base * 2)
      other = round_hundred(base)
      [0, dealer_pay, other, dealer_pay + 2 * other]
    end
  end
end
