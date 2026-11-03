"""Ordered ordinary yaku, yakuman, situation flags and score categories."""


YAKU = (
    ("riichi", 1, None),
    ("double_riichi", 2, None),
    ("ippatsu", 1, None),
    ("menzen_tsumo", 1, None),
    ("pinfu", 1, None),
    ("tanyao", 1, 1),
    ("iipeikou", 1, None),
    ("haku", 1, 1),
    ("hatsu", 1, 1),
    ("chun", 1, 1),
    ("jikaze", 1, 1),
    ("bakaze", 1, 1),
    ("haitei", 1, 1),
    ("houtei", 1, 1),
    ("rinshan", 1, 1),
    ("chankan", 1, 1),
    ("chiitoitsu", 2, None),
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
    ("ryanpeikou", 3, None),
    ("chinitsu", 6, 5),
)
YAKUMAN = (
    ("tenhou", 1), ("chiihou", 1), ("kokushi", 1), ("kokushi_13", 2),
    ("suuankou", 1), ("suuankou_tanki", 2), ("daisangen", 1),
    ("shousuushii", 1), ("daisuushii", 2), ("tsuuiisou", 1),
    ("chinroutou", 1), ("ryuuiisou", 1), ("chuuren", 1),
    ("junsei_chuuren", 2), ("suukantsu", 1),
)
FLAGS = ("riichi", "double_riichi", "ippatsu", "haitei", "houtei",
         "rinshan", "chankan", "tenhou", "chiihou")
CATEGORIES = ("none", "mangan", "haneman", "baiman", "sanbaiman", "kazoe_yakuman", "yakuman")


def ordinary(names, closed):
    return [(name, concealed if closed else opened) for name, concealed, opened in YAKU
            if name in names and (closed or opened is not None)]


def yakuman(names, double):
    return [(name, multiplier if double else 1) for name, multiplier in YAKUMAN if name in names]
