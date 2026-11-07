part of 'main.dart';

class Award {
  final String name;
  final int value;
  Award(this.name, this.value);
}

const yakuTable = [
  ('riichi', 1, 0),
  ('double_riichi', 2, 0),
  ('ippatsu', 1, 0),
  ('menzen_tsumo', 1, 0),
  ('pinfu', 1, 0),
  ('tanyao', 1, 1),
  ('iipeikou', 1, 0),
  ('haku', 1, 1),
  ('hatsu', 1, 1),
  ('chun', 1, 1),
  ('jikaze', 1, 1),
  ('bakaze', 1, 1),
  ('haitei', 1, 1),
  ('houtei', 1, 1),
  ('rinshan', 1, 1),
  ('chankan', 1, 1),
  ('chiitoitsu', 2, 0),
  ('toitoi', 2, 2),
  ('sanankou', 2, 2),
  ('sanshoku_doujun', 2, 1),
  ('sanshoku_doukou', 2, 2),
  ('ittsu', 2, 1),
  ('chanta', 2, 1),
  ('sankantsu', 2, 2),
  ('shousangen', 2, 2),
  ('honroutou', 2, 2),
  ('honitsu', 3, 2),
  ('junchan', 3, 2),
  ('ryanpeikou', 3, 0),
  ('chinitsu', 6, 5),
];
const yakumanTable = [
  ('tenhou', 1),
  ('chiihou', 1),
  ('kokushi', 1),
  ('kokushi_13', 2),
  ('suuankou', 1),
  ('suuankou_tanki', 2),
  ('daisangen', 1),
  ('shousuushii', 1),
  ('daisuushii', 2),
  ('tsuuiisou', 1),
  ('chinroutou', 1),
  ('ryuuiisou', 1),
  ('chuuren', 1),
  ('junsei_chuuren', 2),
  ('suukantsu', 1),
];
const flagsOrder = [
      'riichi',
      'double_riichi',
      'ippatsu',
      'haitei',
      'houtei',
      'rinshan',
      'chankan',
      'tenhou',
      'chiihou',
    ],
    categories = [
      'none',
      'mangan',
      'haneman',
      'baiman',
      'sanbaiman',
      'kazoe_yakuman',
      'yakuman',
    ],
    waitShapes = [
      'ryanmen',
      'kanchan',
      'penchan',
      'shanpon',
      'tanki',
      'single',
      'thirteen',
    ];
List<Award> yakuAwards(Set<String> holds, bool closed) => [
  for (final definition in yakuTable)
    if (holds.contains(definition.$1) &&
        (closed ? definition.$2 : definition.$3) > 0)
      Award(definition.$1, closed ? definition.$2 : definition.$3),
];
List<Award> yakumanAwards(Set<String> holds, bool doubleEnabled) => [
  for (final award in yakumanTable)
    if (holds.contains(award.$1)) Award(award.$1, doubleEnabled ? award.$2 : 1),
];
