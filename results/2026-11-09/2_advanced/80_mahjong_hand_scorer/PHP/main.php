<?php

foreach (['tiles', 'decomposition', 'yaku', 'scoring', 'shanten'] as $module)
    require_once __DIR__ . "/$module.php";
const WAIT_ORDER = ['ryanmen', 'kanchan', 'penchan', 'shanpon', 'tanki', 'single', 'thirteen'];

const WIN_ORDER = ['dealer_ron', 'dealer_tsumo', 'nondealer_ron', 'nondealer_tsumo'];

function records(string $file): array
{
    $records = [];
    foreach (file("input/$file", FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $label = array_shift($parts);
        $fields = [];
        foreach ($parts as $part) {
            [$k, $v] = explode('=', $part, 2);
            $fields[$k] = $v;
        }
        $records[] = [$label, $fields];
    }
    return $records;
}

function situation(string $label, array $f, array $rules): array
{
    $s = [
        'label' => $label,
        'rule_name' => $f['rules'],
        'rules' => $rules[$f['rules']],
        'by' => $f['by'],
        'seat' => $f['seat'],
        'discarder' => $f['from'],
        'round' => $f['round'],
        'seat_tile' => Tiles\wind($f['seat']),
        'round_tile' => Tiles\wind($f['round']),
        'honba' => (int) $f['honba'],
        'sticks' => (int) $f['sticks'],
    ];
    foreach (['hand', 'win', 'dora', 'ura', 'discards'] as $key)
        $s[$key] = Tiles\parse($f[$key], in_array($key, ['ura', 'discards'], true));
    $s['melds'] = [];
    $s['closed'] = true;
    $s['kan_count'] = 0;
    foreach ($f['melds'] === '-' ? [] : explode(',', $f['melds']) as $text) {
        $tiles = Tiles\parse(substr($text, 1));
        $block = $tiles === null ? [] : array_column($tiles, 'kind');
        sort($block, SORT_NUMERIC);
        $s['melds'][] = ['type' => $text[0], 'tiles' => $tiles, 'block' => $block];
        if ($text[0] !== 'A')
            $s['closed'] = false;
        if (in_array($text[0], ['K', 'A'], true))
            ++$s['kan_count'];
    }
    $s['flags'] = $f['flags'] === '-' ? [] : explode(',', $f['flags']);
    $s['riichi'] = (bool) array_intersect($s['flags'], ['riichi', 'double_riichi']);
    return $s;
}

function prepare(array &$s): void
{
    $s['winning_tile'] = $s['win'][0]['kind'];
    $s['hand_counts'] = Tiles\counts($s['hand']);
    $s['concealed_counts'] = Tiles\counts([...$s['hand'], ...$s['win']]);
    $meldTiles = [];
    foreach ($s['melds'] as $m)
        array_push($meldTiles, ...$m['tiles']);
    $s['meld_counts'] = Tiles\counts($meldTiles);
    $s['all_tiles'] = [...$s['hand'], ...$s['win'], ...$meldTiles];
    $s['all_counts'] = Tiles\counts($s['all_tiles']);
}

function copyError(array $tiles, array $rules): ?string
{
    $reds = [0, 0, 0];
    foreach ($tiles as $t)
        if ($t['red'])
            ++$reds[intdiv($t['kind'], 9)];
    if (!$rules['red_fives'] && array_sum($reds))
        return 'red five not allowed';
    foreach (Tiles\counts($tiles) as $k => $n)
        if ($n >= 5)
            return 'too many copies of ' . Tiles\name($k);
    foreach ($reds as $i => $n)
        if ($n >= 2)
            return 'too many copies of 0' . 'mps'[$i];
    return null;
}

function validate(array &$s): ?string
{
    foreach (['hand', 'win', 'dora', 'ura', 'discards'] as $key)
        if ($s[$key] === null)
            return 'bad tile notation';
    foreach ($s['melds'] as $m)
        if ($m['tiles'] === null)
            return 'bad tile notation';
    if (count($s['win']) !== 1)
        return 'bad tile notation';
    if (count($s['melds']) >= 5)
        return 'bad meld';
    foreach ($s['melds'] as $m) {
        $b = $m['block'];
        if ($m['type'] === 'C')
            $valid =
                count($b) === 3 && $b[0] < 27 && ($b[0] % 9) <= 6 && $b === [$b[0], $b[0] + 1, $b[0] + 2];
        else
            $valid =
                in_array($m['type'], ['P', 'K', 'A'], true)
                && count($b) === ($m['type'] === 'P' ? 3 : 4)
                && count(array_unique($b)) === 1;
        if (!$valid)
            return 'bad meld';
    }
    if (count($s['hand']) !== (13 - (3 * count($s['melds']))))
        return 'wrong tile count';
    prepare($s);
    if (
        ($error = copyError([
            ...$s['all_tiles'],
            ...$s['dora'],
            ...$s['ura'],
            ...$s['discards'],
        ], $s['rules'])) !== null
    )
        return $error;
    if (
        $s['by'] === 'tsumo' && $s['discarder'] !== '-'
        || $s['by'] === 'ron' && in_array($s['discarder'], ['-', $s['seat']], true)
    )
        return 'invalid discarder';
    $has = fn($name) => in_array($name, $s['flags'], true);
    $valid = [
        'riichi' => $s['closed'],
        'double_riichi' => $s['closed'] && !$has('riichi'),
        'ippatsu' => $s['riichi'] && !$has('rinshan'),
        'haitei' => $s['by'] === 'tsumo' && !$has('rinshan'),
        'houtei' => $s['by'] === 'ron' && !$has('chankan'),
        'rinshan' => $s['by'] === 'tsumo' && $s['kan_count'] >= 1,
        'chankan' => $s['by'] === 'ron',
        'tenhou' => $s['seat'] === 'E' && $s['by'] === 'tsumo' && !$s['melds'] && $s['flags'] === ['tenhou'],
        'chiihou' =>
            $s['seat'] !== 'E' && $s['by'] === 'tsumo' && !$s['melds'] && $s['flags'] === ['chiihou'],
    ];
    foreach (Yaku\FLAGS as $flag)
        if ($has($flag) && !$valid[$flag])
            return 'invalid flag ' . $flag;
    if (count($s['dora']) !== (1 + $s['kan_count']))
        return 'invalid dora indicators';
    if ($s['riichi'] && count($s['ura']) !== count($s['dora']) || !$s['riichi'] && $s['ura'])
        return 'invalid ura indicators';
    if ($s['riichi'] && $s['sticks'] === 0)
        return 'invalid sticks';
    if (!Decomposition\winning($s['concealed_counts'], count($s['melds'])))
        return 'not a winning hand';
    return null;
}

function candidate(string $type, ?int $pair, array $sets, ?array $block, string $form, string $wait): array
{
    return [
        'type' => $type,
        'pair' => $pair,
        'sets' => $sets,
        'block' => $block,
        'form' => $form,
        'wait' => $wait,
        'yaku' => [],
        'yakuman' => [],
        'fu_items' => [],
        'multiplier' => 0,
        'han' => 0,
        'fu' => 0,
        'fu_total' => 0,
        'base' => 0,
        'dora' => 0,
        'aka' => 0,
        'ura' => 0,
        'category' => 'none',
    ];
}

function candidates(array $s): array
{
    $result = [];
    $winning = $s['winning_tile'];
    $counts = $s['concealed_counts'];
    foreach (Decomposition\standard($counts, count($s['melds'])) as [$pair, $sets]) {
        $blocks = [[$pair, $pair], ...$sets];
        $choices = [];
        foreach ($blocks as $b)
            if (in_array($winning, $b, true) && !in_array($b, $choices, true))
                $choices[] = $b;
        foreach ($choices as $chosen) {
            $parts = ['standard'];
            $marked = false;
            foreach ($blocks as $b) {
                $text = Tiles\block($b);
                if ($b === $chosen && !$marked) {
                    $text .= '*';
                    $marked = true;
                }
                $parts[] = $text;
            }
            foreach ($s['melds'] as $m)
                $parts[] = $m['type'] . Tiles\block($m['block']);
            $result[] = candidate(
                'standard',
                $pair,
                $sets,
                $chosen,
                implode(' ', $parts),
                Decomposition\waitShape('standard', $chosen, $winning, $s['hand_counts']),
            );
        }
    }
    if (!$s['melds'] && Decomposition\sevenPairs($counts)) {
        $parts = ['chiitoitsu'];
        foreach ($counts as $k => $n)
            if ($n)
                $parts[] = Tiles\block([$k, $k]) . ($k === $winning ? '*' : '');
        $result[] = candidate('chiitoitsu', null, [], null, implode(' ', $parts), 'tanki');
    }
    if (!$s['melds'] && Decomposition\thirteenOrphans($counts)) {
        $parts = ['kokushi'];
        foreach (Tiles\YAOCHUU as $k)
            $parts[] = Tiles\block(array_fill(0, $counts[$k], $k)) . ($k === $winning ? '*' : '');
        $result[] = candidate(
            'kokushi',
            null,
            [],
            null,
            implode(' ', $parts),
            Decomposition\waitShape('kokushi', null, $winning, $s['hand_counts']),
        );
    }
    usort($result, fn($a, $b) => strcmp($a['form'], $b['form']));
    return $result;
}

function blockFacts(array $s, array $c): array
{
    $triplets = $sequences = $concealed = [];
    foreach ($c['sets'] as $b) {
        if ($b[0] === $b[2])
            $triplets[] = [$b, $s['by'] === 'tsumo' || $b !== $c['block'], false];
        else {
            $sequences[] = $b[0];
            $concealed[] = $b;
        }
    }
    foreach ($s['melds'] as $m) {
        if ($m['type'] === 'C')
            $sequences[] = $m['block'][0];
        else
            $triplets[] = [$m['block'], $m['type'] === 'A', in_array($m['type'], ['K', 'A'], true)];
    }
    return [$triplets, $sequences, $concealed];
}

function yakumanNames(array $s, array $c, array $kinds, array $triplets): array
{
    $names = array_values(array_intersect($s['flags'], ['tenhou', 'chiihou']));
    if (array_all($kinds, Tiles\honor(...)))
        $names[] = 'tsuuiisou';
    if (array_all($kinds, Tiles\terminal(...)))
        $names[] = 'chinroutou';
    if (!array_diff($kinds, Tiles\GREEN))
        $names[] = 'ryuuiisou';
    $suits = array_unique(array_map(fn($k) => intdiv($k, 9), $kinds));
    if (!$s['melds'] && count($suits) === 1 && !array_any($kinds, Tiles\honor(...))) {
        $start = reset($suits) * 9;
        $n = array_slice($s['all_counts'], $start, 9);
        if ($n[0] >= 3 && $n[8] >= 3 && min(array_slice($n, 1, 7)) >= 1)
            $names[] = array_slice($s['hand_counts'], $start, 9) === [3, 1, 1, 1, 1, 1, 1, 1, 3]
                ? 'junsei_chuuren'
                : 'chuuren';
    }
    if ($c['type'] === 'kokushi')
        $names[] = $c['wait'] === 'thirteen' ? 'kokushi_13' : 'kokushi';
    if ($c['type'] === 'standard') {
        $hidden = count(array_filter($triplets, fn($t) => $t[1]));
        $tk = array_map(fn($t) => $t[0][0], $triplets);
        $dragons = count(array_intersect($tk, [31, 32, 33]));
        $winds = count(array_intersect($tk, [27, 28, 29, 30]));
        if ($hidden === 4)
            $names[] = $c['wait'] === 'tanki' ? 'suuankou_tanki' : 'suuankou';
        if ($dragons === 3)
            $names[] = 'daisangen';
        if ($winds === 4)
            $names[] = 'daisuushii';
        if ($winds === 3 && $c['pair'] >= 27 && $c['pair'] <= 30)
            $names[] = 'shousuushii';
        if (count(array_filter($triplets, fn($t) => $t[2])) === 4)
            $names[] = 'suukantsu';
    }
    return $names;
}

function ordinaryNames(
    array $s,
    array $c,
    array $kinds,
    array $triplets,
    array $sequences,
    array $concealed,
): array {
    $names = array_values(array_intersect($s['flags'], array_slice(Yaku\FLAGS, 0, 7)));
    if ($s['closed'] && $s['by'] === 'tsumo')
        $names[] = 'menzen_tsumo';
    if (!array_any($kinds, Tiles\yaochuu(...)) && ($s['closed'] || $s['rules']['open_tanyao']))
        $names[] = 'tanyao';
    if (array_all($kinds, Tiles\yaochuu(...)))
        $names[] = 'honroutou';
    $suits = array_unique(array_map(fn($k) => intdiv($k, 9), array_filter($kinds, fn($k) => $k < 27)));
    $honors = array_any($kinds, Tiles\honor(...));
    if (count($suits) === 1)
        $names[] = $honors ? 'honitsu' : 'chinitsu';
    if ($c['type'] === 'chiitoitsu')
        $names[] = 'chiitoitsu';
    if ($c['type'] !== 'standard')
        return $names;
    $pair = $c['pair'];
    $yakuhai = $pair >= 31 || in_array($pair, [$s['seat_tile'], $s['round_tile']], true);
    if ($s['closed'] && !$s['melds'] && count($concealed) === 4 && !$yakuhai && $c['wait'] === 'ryanmen')
        $names[] = 'pinfu';
    $repeated = array_count_values(array_map(fn($b) => implode(',', $b), $concealed));
    if (
        $s['closed']
        && count($concealed) === 4
        && array_sum(array_map(fn($n) => intdiv($n, 2), $repeated)) === 2
    )
        $names[] = 'ryanpeikou';
    elseif ($s['closed'] && array_any($repeated, fn($n) => $n >= 2))
        $names[] = 'iipeikou';
    $tk = array_unique(array_map(fn($t) => $t[0][0], $triplets));
    foreach ([
        [31, 'haku'],
        [32, 'hatsu'],
        [33, 'chun'],
        [$s['seat_tile'], 'jikaze'],
        [$s['round_tile'], 'bakaze'],
    ] as [$k, $name])
        if (in_array($k, $tk, true))
            $names[] = $name;
    if (count($triplets) === 4)
        $names[] = 'toitoi';
    if (count(array_filter($triplets, fn($t) => $t[1])) === 3)
        $names[] = 'sanankou';
    for ($n = 0; $n < 7; ++$n)
        if (
            in_array($n, $sequences, true)
            && in_array($n + 9, $sequences, true)
            && in_array($n + 18, $sequences, true)
        ) {
            $names[] = 'sanshoku_doujun';
            break;
        }
    for ($n = 0; $n < 9; ++$n)
        if (in_array($n, $tk, true) && in_array($n + 9, $tk, true) && in_array($n + 18, $tk, true)) {
            $names[] = 'sanshoku_doukou';
            break;
        }
    for ($suit = 0; $suit < 3; ++$suit)
        if (
            in_array($suit * 9, $sequences, true)
            && in_array(($suit * 9) + 3, $sequences, true)
            && in_array(($suit * 9) + 6, $sequences, true)
        ) {
            $names[] = 'ittsu';
            break;
        }
    $blocks = [[$pair, $pair], ...$c['sets'], ...array_column($s['melds'], 'block')];
    if ($sequences && array_all($blocks, fn($b) => array_any($b, Tiles\yaochuu(...))))
        $names[] = $honors ? 'chanta' : 'junchan';
    if (count(array_filter($triplets, fn($t) => $t[2])) === 3)
        $names[] = 'sankantsu';
    if (count(array_intersect($tk, [31, 32, 33])) === 2 && $pair >= 31)
        $names[] = 'shousangen';
    return $names;
}

function evaluate(array $s): array
{
    $result = [];
    $kinds = array_keys(array_filter($s['all_counts']));
    foreach (candidates($s) as $c) {
        [$triplets, $sequences, $concealed] = blockFacts($s, $c);
        $c['yakuman'] = Yaku\yakuman(yakumanNames($s, $c, $kinds, $triplets), $s['rules']['double_yakuman']);
        if ($c['yakuman']) {
            $c['multiplier'] = array_sum(array_column($c['yakuman'], 1));
            $c['base'] = 8000 * $c['multiplier'];
            $c['category'] = 'yakuman';
        } else {
            $names = ordinaryNames($s, $c, $kinds, $triplets, $sequences, $concealed);
            $c['yaku'] = Yaku\ordinary($names, $s['closed']);
            foreach (['dora', 'ura'] as $key)
                $c[$key] = array_sum(array_map(
                    fn($t) => $s['all_counts'][Tiles\nextDora($t['kind'])],
                    $s[$key],
                ));
            $c['aka'] = count(array_filter($s['all_tiles'], fn($t) => $t['red']));
            [$c['fu_items'], $c['fu_total'], $c['fu']] = Scoring\fuBreakdown(
                $c['type'],
                $c['pair'],
                $triplets,
                $c['wait'],
                $s['closed'],
                $s['by'],
                $s['seat_tile'],
                $s['round_tile'],
                in_array('pinfu', $names, true),
            );
            if ($c['yaku']) {
                $c['han'] = array_sum(array_column($c['yaku'], 1)) + $c['dora'] + $c['aka'] + $c['ura'];
                [$c['category'], $c['base']] = Scoring\limit($c['han'], $c['fu'], $s['rules']);
            }
        }
        $result[] = $c;
    }
    return $result;
}

function bestCandidate(array $candidates): ?array
{
    $eligible = array_values(array_filter($candidates, fn($c) => $c['base'] > 0));
    usort($eligible, function ($a, $b) {
        return (
            $b['base'] <=> $a['base'] ?: (bool) $b['yakuman'] <=> (bool) $a['yakuman'] ?: (
                !$a['yakuman'] && !$b['yakuman'] ? ($b['han'] <=> $a['han'] ?: $b['fu'] <=> $a['fu']) : 0
            ) ?: strcmp($a['form'], $b['form'])
        );
    });
    return $eligible[0] ?? null;
}

function candidateLine(array $c): string
{
    if ($c['yakuman'])
        $e =
            "yakuman {$c['multiplier']} base {$c['base']} yaku "
            . implode(',', array_column($c['yakuman'], 0));
    elseif (!$c['yaku'])
        $e = 'no_yaku';
    else
        $e =
            "han {$c['han']} fu {$c['fu']} base {$c['base']} yaku "
            . implode(',', array_column($c['yaku'], 0));
    return "CANDIDATE {$c['form']} = {$c['wait']} $e";
}

function winningLines(array $s, array $c): array
{
    $lines = ['FORM ' . $c['form'], 'WAIT ' . $c['wait']];
    if ($c['yakuman']) {
        foreach ($c['yakuman'] as [$name, $n])
            $lines[] = "YAKUMAN $name $n";
        $lines[] = "SCORE yakuman {$c['multiplier']} base {$c['base']}";
    } else {
        foreach ($c['yaku'] as [$name, $n])
            $lines[] = "YAKU $name $n";
        $lines[] = "DORA dora {$c['dora']} aka {$c['aka']} ura {$c['ura']}";
        foreach ($c['fu_items'] as [$item, $value])
            $lines[] = "FU $item $value";
        $lines[] = "FU total {$c['fu_total']} {$c['fu']}";
        $lines[] = "SCORE han {$c['han']} fu {$c['fu']} limit {$c['category']} base {$c['base']}";
    }
    [$ron, $dealer, $other, $points] = Scoring\payments($c['base'], $s['seat'] === 'E', $s['by']);
    $lines[] = $s['by'] === 'ron'
        ? "PAY ron $ron"
        : ($s['seat'] === 'E' ? "PAY tsumo all $other" : "PAY tsumo dealer $dealer nondealer $other");
    $honba = $s['honba'] * $s['rules']['honba'];
    $sticks = $s['sticks'] * 1000;
    $gain = $points + $honba + $sticks;
    $lines[] = "BONUS honba $honba sticks $sticks";
    $lines[] = "TOTAL points $points gain $gain";
    $delta = array_fill_keys(str_split(Tiles\WINDS), 0);
    if ($s['by'] === 'ron')
        $delta[$s['discarder']] = -$ron - $honba;
    else
        foreach ($delta as $wind => $unused)
            if ($wind !== $s['seat'])
                $delta[$wind] = -($wind === 'E' ? $dealer : $other) - intdiv($honba, 3);
    $delta[$s['seat']] = $gain;
    $parts = [];
    foreach ($delta as $wind => $n)
        $parts[] = $wind . ' ' . ($n > 0 ? '+' : '') . $n;
    $lines[] = 'DELTA ' . implode(' ', $parts);
    return [$lines, $points];
}

function hypothetical(string $label, array $fields, int $kind, string $method, array $rules): array
{
    $fields = array_replace($fields, [
        'melds' => '-',
        'win' => Tiles\name($kind),
        'by' => $method,
        'from' => $method === 'tsumo' ? '-' : ($fields['seat'] === 'E' ? 'S' : 'E'),
        'flags' => $fields['riichi'] === 'yes' ? 'riichi' : '-',
        'ura' => '-',
        'honba' => '0',
        'sticks' => '0',
    ]);
    $s = situation($label, $fields, $rules);
    prepare($s);
    return $s;
}

function increment(array &$counts, string|int $key, int $n = 1): void
{
    $counts[$key] = ($counts[$key] ?? 0) + $n;
}

function main(): void
{
    $rules = [];
    foreach (records('rules.txt') as [$name, $fields]) {
        foreach ($fields as $k => $v)
            $fields[$k] = $k === 'honba' ? (int) $v : $v === 'yes';
        $rules[$name] = $fields;
    }
    $situations = records('hands.txt');
    $hands = records('waits.txt');
    $scores = [];
    $summary = ['hand,han,fu,points,yaku'];
    $stats = array_fill_keys(['wins', 'furiten', 'no_yaku', 'errors', 'points'], 0);
    $wins = $waits = $han = $fu = $limits = $yakuCounts = [];
    $ruleCounts = array_fill_keys(array_keys($rules), ['hands' => 0, 'wins' => 0, 'points' => 0]);
    $maximum = 0;
    $maximumHand = '-';
    foreach ($situations as [$label, $fields]) {
        $s = situation($label, $fields, $rules);
        ++$ruleCounts[$s['rule_name']]['hands'];
        $scores[] = 'HAND ' . $label;
        if (($error = validate($s)) !== null) {
            ++$stats['errors'];
            $scores[] = 'ERROR ' . $error;
            $summary[] = "$label,-,-,0,ERROR";
            continue;
        }
        $waiting = Decomposition\waitingTiles($s['hand_counts'], $s['meld_counts'], count($s['melds']));
        $scores[] = 'WAITS ' . implode(' ', array_map(Tiles\name(...), $waiting));
        $evaluated = evaluate($s);
        foreach ($evaluated as $c)
            $scores[] = candidateLine($c);
        if ($s['by'] === 'ron' && array_any($s['discards'], fn($t) => in_array($t['kind'], $waiting, true))) {
            ++$stats['furiten'];
            $scores[] = 'RESULT furiten';
            $summary[] = "$label,-,-,0,FURITEN";
            continue;
        }
        $c = bestCandidate($evaluated);
        if ($c === null) {
            ++$stats['no_yaku'];
            $scores[] = 'RESULT no_yaku';
            $summary[] = "$label,-,-,0,NO_YAKU";
            continue;
        }
        [$lines, $points] = winningLines($s, $c);
        array_push($scores, ...$lines);
        ++$stats['wins'];
        $stats['points'] += $points;
        ++$ruleCounts[$s['rule_name']]['wins'];
        $ruleCounts[$s['rule_name']]['points'] += $points;
        increment($wins, ($s['seat'] === 'E' ? 'dealer_' : 'nondealer_') . $s['by']);
        increment($waits, $c['wait']);
        increment($limits, $c['category']);
        $names = $c['yakuman'] ?: $c['yaku'];
        foreach ($names as [$name, $n])
            increment($yakuCounts, $name);
        if ($c['yakuman']) {
            $h = 'Y' . $c['multiplier'];
            $f = '-';
        } else {
            $h = $c['han'];
            $f = $c['fu'];
            increment($han, $h);
            increment($fu, $f);
        }
        $summary[] = "$label,$h,$f,$points," . implode(';', array_column($names, 0));
        if ($points > $maximum) {
            $maximum = $points;
            $maximumHand = $label;
        }
    }
    $scores[] =
        'STATS hands '
        . count($situations)
        . " wins {$stats['wins']} furiten {$stats['furiten']} no_yaku {$stats['no_yaku']} errors {$stats['errors']}";
    foreach ([
        ['WINS',       WIN_ORDER,  $wins],
        ['WAIT_COUNT', WAIT_ORDER, $waits],
    ] as [$prefix, $order, $counts]) {
        $parts = [$prefix];
        foreach ($order as $name)
            $parts[] = $name . ' ' . ($counts[$name] ?? 0);
        $scores[] = implode(' ', $parts);
    }
    foreach ([['HAN_COUNT', $han], ['FU_COUNT', $fu]] as [$prefix, $counts]) {
        ksort($counts, SORT_NUMERIC);
        foreach ($counts as $n => $count)
            $scores[] = "$prefix $n $count";
    }
    foreach (Yaku\CATEGORIES as $name)
        $scores[] = 'LIMIT ' . $name . ' ' . ($limits[$name] ?? 0);
    foreach ([...array_column(Yaku\ORDINARY, 0), ...array_column(Yaku\YAKUMAN, 0)] as $name)
        if ($yakuCounts[$name] ?? 0)
            $scores[] = "YAKU_COUNT $name {$yakuCounts[$name]}";
    $scores[] = "POINTS total {$stats['points']} max $maximum hand $maximumHand";
    foreach ($ruleCounts as $name => $counts)
        $scores[] = "RULE $name hands {$counts['hands']} wins {$counts['wins']} points {$counts['points']}";
    $lines = [];
    $stats = array_fill_keys(['errors', 'tenpai', 'furiten'], 0);
    $shantenCounts = [];
    foreach ($hands as [$label, $fields]) {
        $lines[] = 'HAND ' . $label;
        $parsed = [];
        foreach (['hand', 'dora', 'discards', 'visible'] as $key)
            $parsed[$key] = Tiles\parse($fields[$key], in_array($key, ['discards', 'visible'], true));
        $error = null;
        if (in_array(null, $parsed, true))
            $error = 'bad tile notation';
        elseif (count($parsed['hand']) !== 13)
            $error = 'wrong tile count';
        else {
            $known = [...$parsed['hand'], ...$parsed['dora'], ...$parsed['discards'], ...$parsed['visible']];
            $error = copyError($known, $rules[$fields['rules']]);
        }
        if ($error !== null) {
            ++$stats['errors'];
            $lines[] = 'ERROR ' . $error;
            continue;
        }
        $counts = Tiles\counts($parsed['hand']);
        $knownCounts = Tiles\counts($known);
        [$standard, $seven, $orphans] = Shanten\numbers($counts);
        $current = min($standard, $seven, $orphans);
        increment($shantenCounts, $current);
        $lines[] = "SHANTEN standard $standard chiitoitsu $seven kokushi $orphans";
        $accepted = [];
        for ($k = 0; $k < 34; ++$k)
            if ($counts[$k] < 4) {
                ++$counts[$k];
                $advancing = min(Shanten\numbers($counts)) < $current;
                --$counts[$k];
                if ($advancing)
                    $accepted[] = [$k, 4 - $knownCounts[$k]];
            }
        $total = array_sum(array_column($accepted, 1));
        $kinds = count($accepted);
        if ($current !== 0) {
            $text = "ACCEPT kinds $kinds tiles $total";
            foreach ($accepted as [$k, $remaining])
                $text .= ' ' . Tiles\name($k) . ':' . $remaining;
            $lines[] = $text;
            continue;
        }
        ++$stats['tenpai'];
        $discarded = array_column($parsed['discards'], 'kind');
        $furiten = array_any($accepted, fn($a) => in_array($a[0], $discarded, true));
        $stats['furiten'] += (int) $furiten;
        $lines[] = "TENPAI kinds $kinds tiles $total furiten " . ($furiten ? 'yes' : 'no');
        $best = ['ron' => null, 'tsumo' => null];
        foreach ($accepted as [$k, $remaining]) {
            $result = [];
            foreach (['ron', 'tsumo'] as $method) {
                if ($method === 'ron' && $furiten) {
                    $result[$method] = 'furiten';
                    continue;
                }
                $s = hypothetical($label, $fields, $k, $method, $rules);
                $c = bestCandidate(evaluate($s));
                if ($c === null) {
                    $result[$method] = 'no_yaku';
                    continue;
                }
                $points = Scoring\payments($c['base'], $s['seat'] === 'E', $method)[3];
                $result[$method] = (string) $points;
                if ($best[$method] === null || $points > $best[$method][1])
                    $best[$method] = [$k, $points];
            }
            $lines[] =
                'WAIT ' . Tiles\name($k) . " left $remaining ron {$result['ron']} tsumo {$result['tsumo']}";
        }
        $choice = [];
        foreach ($best as $method => $value)
            $choice[$method] = $value === null ? 'none' : Tiles\name($value[0]) . ' ' . $value[1];
        $lines[] = "BEST ron {$choice['ron']} tsumo {$choice['tsumo']}";
    }
    $lines[] =
        'STATS hands '
        . count($hands)
        . " errors {$stats['errors']} tenpai {$stats['tenpai']} furiten {$stats['furiten']}";
    for ($k = 0; $k <= 6; ++$k)
        $lines[] = "SHANTEN_COUNT $k " . ($shantenCounts[$k] ?? 0);
    if (!is_dir('output'))
        mkdir('output');
    foreach (['scores.txt' => $scores, 'waits.txt' => $lines, 'summary.csv' => $summary] as $file => $content)
        file_put_contents('output/' . $file, implode("\n", $content) . "\n");
}

main();
