YAKU_TABLE <- list(
    list(name = "riichi", concealed = 1L, opened = 0L),
    list(name = "double_riichi", concealed = 2L, opened = 0L),
    list(name = "ippatsu", concealed = 1L, opened = 0L),
    list(name = "menzen_tsumo", concealed = 1L, opened = 0L),
    list(name = "pinfu", concealed = 1L, opened = 0L),
    list(name = "tanyao", concealed = 1L, opened = 1L),
    list(name = "iipeikou", concealed = 1L, opened = 0L),
    list(name = "haku", concealed = 1L, opened = 1L),
    list(name = "hatsu", concealed = 1L, opened = 1L),
    list(name = "chun", concealed = 1L, opened = 1L),
    list(name = "jikaze", concealed = 1L, opened = 1L),
    list(name = "bakaze", concealed = 1L, opened = 1L),
    list(name = "haitei", concealed = 1L, opened = 1L),
    list(name = "houtei", concealed = 1L, opened = 1L),
    list(name = "rinshan", concealed = 1L, opened = 1L),
    list(name = "chankan", concealed = 1L, opened = 1L),
    list(name = "chiitoitsu", concealed = 2L, opened = 0L),
    list(name = "toitoi", concealed = 2L, opened = 2L),
    list(name = "sanankou", concealed = 2L, opened = 2L),
    list(name = "sanshoku_doujun", concealed = 2L, opened = 1L),
    list(name = "sanshoku_doukou", concealed = 2L, opened = 2L),
    list(name = "ittsu", concealed = 2L, opened = 1L),
    list(name = "chanta", concealed = 2L, opened = 1L),
    list(name = "sankantsu", concealed = 2L, opened = 2L),
    list(name = "shousangen", concealed = 2L, opened = 2L),
    list(name = "honroutou", concealed = 2L, opened = 2L),
    list(name = "honitsu", concealed = 3L, opened = 2L),
    list(name = "junchan", concealed = 3L, opened = 2L),
    list(name = "ryanpeikou", concealed = 3L, opened = 0L),
    list(name = "chinitsu", concealed = 6L, opened = 5L)
)
YAKUMAN_TABLE <- list(
    list(name = "tenhou", multiplier = 1L),
    list(name = "chiihou", multiplier = 1L),
    list(name = "kokushi", multiplier = 1L),
    list(name = "kokushi_13", multiplier = 2L),
    list(name = "suuankou", multiplier = 1L),
    list(name = "suuankou_tanki", multiplier = 2L),
    list(name = "daisangen", multiplier = 1L),
    list(name = "shousuushii", multiplier = 1L),
    list(name = "daisuushii", multiplier = 2L),
    list(name = "tsuuiisou", multiplier = 1L),
    list(name = "chinroutou", multiplier = 1L),
    list(name = "ryuuiisou", multiplier = 1L),
    list(name = "chuuren", multiplier = 1L),
    list(name = "junsei_chuuren", multiplier = 2L),
    list(name = "suukantsu", multiplier = 1L)
)
SITUATION_FLAGS <- c(
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
SCORE_CATEGORIES <- c("none", "mangan", "haneman", "baiman", "sanbaiman", "kazoe_yakuman", "yakuman")

ordered_yaku <- function(names, closed) {
    lapply(
        Filter(function(row) row$name %in% names && (closed || row$opened != 0L), YAKU_TABLE),
        function(row) list(name = row$name, value = if (closed) row$concealed else row$opened)
    )
}
ordered_yakuman <- function(names, double) {
    lapply(
        Filter(function(row) row$name %in% names, YAKUMAN_TABLE),
        function(row) list(name = row$name, value = if (double) row$multiplier else 1L)
    )
}
