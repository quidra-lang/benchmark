YakuNames =: ;:'riichi double_riichi ippatsu menzen_tsumo pinfu tanyao iipeikou haku hatsu'
YakuNames =: YakuNames,;:'chun jikaze bakaze haitei houtei rinshan chankan chiitoitsu toitoi'
YakuNames =: YakuNames,;:'sanankou sanshoku_doujun sanshoku_doukou ittsu chanta sankantsu shousangen honroutou honitsu'
YakuNames =: YakuNames,;:'junchan ryanpeikou chinitsu'
ClosedHan =: 1 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 3 3 3 6
OpenHan =: _1 _1 _1 _1 _1 1 _1 1 1 1 1 1 1 1 1 1 _1 2 2 1 2 1 1 2 2 2 2 2 _1 5
YakumanNames =: ;:'tenhou chiihou kokushi kokushi_13 suuankou suuankou_tanki daisangen shousuushii daisuushii tsuuiisou chinroutou ryuuiisou chuuren junsei_chuuren suukantsu'
YakumanMultipliers =: 1 1 1 2 1 2 1 1 2 1 1 1 1 2 1
FlagNames =: ;:'riichi double_riichi ippatsu haitei houtei rinshan chankan tenhou chiihou'
Categories =: ;:'none mangan haneman baiman sanbaiman kazoe_yakuman yakuman'
ordinary_yaku =: 4 : 0
    han =. OpenHan
    if. x do.
        han =. ClosedHan
    end.
    result =. 0$a:
    for_i. i.#YakuNames do.
        if. ((i{YakuNames)e.y)*.(i{han)>0 do.
            result =. result,<(i{YakuNames),<i{han
        end.
    end.
    result
)
yakuman_yaku =: 4 : 0
    result =. 0$a:
    for_i. i.#YakumanNames do.
        if. (i{YakumanNames)e.y do.
            multiplier =. 1
            if. x do.
                multiplier =. i{YakumanMultipliers
            end.
            result =. result,<(i{YakumanNames),<multiplier
        end.
    end.
    result
)
