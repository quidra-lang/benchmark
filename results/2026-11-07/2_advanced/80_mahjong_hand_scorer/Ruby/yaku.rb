module Yaku
  YAKU = [
    ['riichi', 1, nil], ['double_riichi', 2, nil], ['ippatsu', 1, nil],
    ['menzen_tsumo', 1, nil], ['pinfu', 1, nil], ['tanyao', 1, 1],
    ['iipeikou', 1, nil], ['haku', 1, 1], ['hatsu', 1, 1], ['chun', 1, 1],
    ['jikaze', 1, 1], ['bakaze', 1, 1], ['haitei', 1, 1], ['houtei', 1, 1],
    ['rinshan', 1, 1], ['chankan', 1, 1], ['chiitoitsu', 2, nil],
    ['toitoi', 2, 2], ['sanankou', 2, 2], ['sanshoku_doujun', 2, 1],
    ['sanshoku_doukou', 2, 2], ['ittsu', 2, 1], ['chanta', 2, 1],
    ['sankantsu', 2, 2], ['shousangen', 2, 2], ['honroutou', 2, 2],
    ['honitsu', 3, 2], ['junchan', 3, 2], ['ryanpeikou', 3, nil], ['chinitsu', 6, 5]
  ].freeze
  YAKUMAN = [
    ['tenhou', 1], ['chiihou', 1], ['kokushi', 1], ['kokushi_13', 2],
    ['suuankou', 1], ['suuankou_tanki', 2], ['daisangen', 1], ['shousuushii', 1],
    ['daisuushii', 2], ['tsuuiisou', 1], ['chinroutou', 1], ['ryuuiisou', 1],
    ['chuuren', 1], ['junsei_chuuren', 2], ['suukantsu', 1]
  ].freeze
  FLAGS = %w[riichi double_riichi ippatsu haitei houtei rinshan chankan tenhou chiihou].freeze
  CATEGORIES = %w[none mangan haneman baiman sanbaiman kazoe_yakuman yakuman].freeze

  def self.ordinary(names, closed)
    YAKU.filter_map do |name, hidden, open|
      han = closed ? hidden : open
      [name, han] if han && names.include?(name)
    end
  end

  def self.yakuman(names, double)
    YAKUMAN.filter_map { |name, multiplier| [name, double ? multiplier : 1] if names.include?(name) }
  end
end
