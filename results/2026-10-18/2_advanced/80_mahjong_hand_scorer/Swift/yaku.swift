enum Yaku {
    static let names = ["riichi", "double_riichi", "ippatsu", "menzen_tsumo", "pinfu", "tanyao", "iipeikou", "haku", "hatsu", "chun", "jikaze", "bakaze", "haitei", "houtei", "rinshan", "chankan", "chiitoitsu", "toitoi", "sanankou", "sanshoku_doujun", "sanshoku_doukou", "ittsu", "chanta", "sankantsu", "shousangen", "honroutou", "honitsu", "junchan", "ryanpeikou", "chinitsu"]
    static let closed = [1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,3,3,3,6]
    static let open = [0,0,0,0,0,1,0,1,1,1,1,1,1,1,1,1,0,2,2,1,2,1,1,2,2,2,2,2,0,5]
    static let yakuman = ["tenhou", "chiihou", "kokushi", "kokushi_13", "suuankou", "suuankou_tanki", "daisangen", "shousuushii", "daisuushii", "tsuuiisou", "chinroutou", "ryuuiisou", "chuuren", "junsei_chuuren", "suukantsu"]
    static let multipliers = [1,1,1,2,1,2,1,1,2,1,1,1,1,2,1]
    static let flags = ["riichi", "double_riichi", "ippatsu", "haitei", "houtei", "rinshan", "chankan", "tenhou", "chiihou"]
    static let categories = ["none", "mangan", "haneman", "baiman", "sanbaiman", "kazoe_yakuman", "yakuman"]
    static let waits = ["ryanmen", "kanchan", "penchan", "shanpon", "tanki", "single", "thirteen"]
    static func ordinary(_ holds: [Bool], closed: Bool) -> [(Int, Int)] { holds.indices.compactMap { let han = closed ? Self.closed[$0] : open[$0]; return holds[$0] && han > 0 ? ($0, han) : nil } }
    static func multipliers(_ holds: [Bool], double: Bool) -> [(Int, Int)] { holds.indices.filter { holds[$0] }.map { ($0, double ? multipliers[$0] : 1) } }
}
