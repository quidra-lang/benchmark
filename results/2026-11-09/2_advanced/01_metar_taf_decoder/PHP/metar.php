<?php
const METAR_SLOTS = [['modifier', false], ['wind', false], ['variation', false], ['visibility', false], ['rvr', true], ['weather', true], ['cloud', true], ['temperature', false], ['pressure', false], ['nosig', false]];
function metarSlotValue(string $kind, string $text): ?array {
    return recognize($kind, $text);
}

function trendTime(array $g): ?array {
    if (!preg_match('/\A(FM|TL|AT)(\d{2})(\d{2})\z/', $g['text'], $m)) return null;
    return ['kind' => $m[1], 'hour' => (int)$m[2], 'minute' => (int)$m[3], 'group' => $g];
}

function splitMetar(array $groups, callable $error): array {
    $rmk = count($groups);
    foreach ($groups as $i => $g) if ($g['text'] === 'RMK') {
        $rmk = $i;
        break;
    }
    $before = array_slice($groups, 0, $rmk);
    $remarks = array_slice($groups, $rmk + 1);
    $first = count($before);
    foreach ($before as $i => $g) if (in_array($g['text'], ['BECMG', 'TEMPO'], true)) {
        $first = $i;
        break;
    }
    $trends = [];
    for ($i = $first;$i < count($before);$i = $end) {
        $end = $i + 1;
        while ($end < count($before) && !in_array($before[$end]['text'], ['BECMG', 'TEMPO'], true)) ++$end;
        $body = array_slice($before, $i + 1, $end - $i - 1);
        $times = [];
        if ($body && ($t = trendTime($body[0])) !== null) {
            $times[] = $t;
            array_shift($body);
            if ($t['kind'] === 'FM'  && $body && ($u = trendTime($body[0])) !== null && $u['kind'] === 'TL') {
                $times[] = $u;
                array_shift($body);
            }
        }
        $bad = null;
        foreach ($times as $t) if ($t['hour'] > 23 || $t['minute'] > 59) {
            $bad = $t;
            break;
        }
        if ($bad !== null) $error($bad['group'], 'invalid period');
        else $trends[] = ['kind' => $before[$i]['text'], 'times' => $times, 'groups' => $body];
    }
    $sea = [];
    $temp = [];
    foreach ($remarks as $g) {
        if (preg_match('/\ASLP(\d{3})\z/', $g['text'], $m)) {
            $v = (int)$m[1];
            $sea[] = ($v >= 500 ? 9000 : 10000) + $v;
        }
        elseif (preg_match('/\AT([01])(\d{3})([01])(\d{3})\z/', $g['text'], $m)) $temp[] = [(int)$m[2] * ($m[1] === '1' ? - 1 : 1), (int)$m[4] * ($m[3] === '1' ? - 1 : 1)];
    }
    return ['main' => array_slice($before, 0, $first), 'trends' => $trends, 'sea' => $sea, 'precise' => $temp];
}
