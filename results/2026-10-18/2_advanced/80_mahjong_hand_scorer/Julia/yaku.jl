const YAKU_TABLE = [
    ("riichi", 1, 0),
    ("double_riichi", 2, 0),
    ("ippatsu", 1, 0),
    ("menzen_tsumo", 1, 0),
    ("pinfu", 1, 0),
    ("tanyao", 1, 1),
    ("iipeikou", 1, 0),
    ("haku", 1, 1),
    ("hatsu", 1, 1),
    ("chun", 1, 1),
    ("jikaze", 1, 1),
    ("bakaze", 1, 1),
    ("haitei", 1, 1),
    ("houtei", 1, 1),
    ("rinshan", 1, 1),
    ("chankan", 1, 1),
    ("chiitoitsu", 2, 0),
    ("toitoi", 2, 2),
    ("sanankou", 2, 2),
    ("sanshoku_doujun", 2, 1),
    ("sanshoku_doukou", 2, 2),
    ("ittsu", 2, 1),
    ("chanta", 2, 1),
    ("sankantsu", 2, 2),
    ("shousangen", 2, 2),
    ("honroutou", 2, 2),
    ("honitsu", 3, 2),
    ("junchan", 3, 2),
    ("ryanpeikou", 3, 0),
    ("chinitsu", 6, 5),
]
const YAKUMAN_TABLE = [
    ("tenhou", 1),
    ("chiihou", 1),
    ("kokushi", 1),
    ("kokushi_13", 2),
    ("suuankou", 1),
    ("suuankou_tanki", 2),
    ("daisangen", 1),
    ("shousuushii", 1),
    ("daisuushii", 2),
    ("tsuuiisou", 1),
    ("chinroutou", 1),
    ("ryuuiisou", 1),
    ("chuuren", 1),
    ("junsei_chuuren", 2),
    ("suukantsu", 1),
]
const SITUATION_FLAGS = (
    "riichi",
    "double_riichi",
    "ippatsu",
    "haitei",
    "houtei",
    "rinshan",
    "chankan",
    "tenhou",
    "chiihou"
)
const SCORE_CATEGORIES = ("none", "mangan", "haneman", "baiman", "sanbaiman", "kazoe_yakuman", "yakuman")

ordered_yaku(names, closed) = [(
    name,
    closed ? concealed : opened
) for (name, concealed, opened) in YAKU_TABLE if name in names && (closed || opened != 0)]
ordered_yakuman(names, double) = [(
    name,
    double ? multiplier : 1
) for (name, multiplier) in YAKUMAN_TABLE if name in names]
