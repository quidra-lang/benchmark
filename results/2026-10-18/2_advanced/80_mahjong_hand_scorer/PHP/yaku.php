<?php

namespace Yaku;

const ORDINARY = [
    ['riichi',          1, null],
    ['double_riichi',   2, null],
    ['ippatsu',         1, null],
    ['menzen_tsumo',    1, null],
    ['pinfu',           1, null],
    ['tanyao',          1, 1],
    ['iipeikou',        1, null],
    ['haku',            1, 1],
    ['hatsu',           1, 1],
    ['chun',            1, 1],
    ['jikaze',          1, 1],
    ['bakaze',          1, 1],
    ['haitei',          1, 1],
    ['houtei',          1, 1],
    ['rinshan',         1, 1],
    ['chankan',         1, 1],
    ['chiitoitsu',      2, null],
    ['toitoi',          2, 2],
    ['sanankou',        2, 2],
    ['sanshoku_doujun', 2, 1],
    ['sanshoku_doukou', 2, 2],
    ['ittsu',           2, 1],
    ['chanta',          2, 1],
    ['sankantsu',       2, 2],
    ['shousangen',      2, 2],
    ['honroutou',       2, 2],
    ['honitsu',         3, 2],
    ['junchan',         3, 2],
    ['ryanpeikou',      3, null],
    ['chinitsu',        6, 5],
];

const YAKUMAN = [
    ['tenhou', 1],
    ['chiihou', 1],
    ['kokushi', 1],
    ['kokushi_13', 2],
    ['suuankou', 1],
    ['suuankou_tanki', 2],
    ['daisangen', 1],
    ['shousuushii', 1],
    ['daisuushii', 2],
    ['tsuuiisou', 1],
    ['chinroutou', 1],
    ['ryuuiisou', 1],
    ['chuuren', 1],
    ['junsei_chuuren', 2],
    ['suukantsu', 1],
];

const FLAGS = [
    'riichi',
    'double_riichi',
    'ippatsu',
    'haitei',
    'houtei',
    'rinshan',
    'chankan',
    'tenhou',
    'chiihou',
];

const CATEGORIES = ['none', 'mangan', 'haneman', 'baiman', 'sanbaiman', 'kazoe_yakuman', 'yakuman'];

function ordinary(array $names, bool $closed): array
{
    $result = [];
    foreach (ORDINARY as [$name, $hidden, $open])
        if (in_array($name, $names, true) && ($closed || $open !== null))
            $result[] = [$name, $closed ? $hidden : $open];
    return $result;
}

function yakuman(array $names, bool $double): array
{
    $result = [];
    foreach (YAKUMAN as [$name, $multiplier])
        if (in_array($name, $names, true))
            $result[] = [$name, $double ? $multiplier : 1];
    return $result;
}
