<?php
const TAF_SLOTS = [['wind', false], ['visibility', false], ['weather', true], ['cloud', true]];
const ELEMENTS = ['wind', 'visibility', 'weather', 'cloud'];
function indicator(string $s): bool {
    return in_array($s, ['BECMG', 'TEMPO', 'PROB30', 'PROB40'], true) || preg_match('/\AFM\d{6}\z/', $s) === 1;
}

function splitTaf(array $groups, array $r, Calendar $cal, callable $error): array {
    $first = count($groups);
    foreach ($groups as $i => $g) if (indicator($g['text'])) {
        $first = $i;
        break;
    }
    $changes = [];
    for ($i = $first;$i < count($groups);$i = $end) {
        $g = $groups[$i];
        $kind = $g['text'];
        $j = $i + 1;
        if (in_array($kind, ['PROB30', 'PROB40'], true) && ($groups[$j]['text'] ?? null) === 'TEMPO') {
            $kind .= ' TEMPO';
            ++$j;
        }
        $end = $j;
        while ($end < count($groups) && !indicator($groups[$end]['text'])) ++$end;
        $body = array_slice($groups, $j, $end - $j);
        $c = ['kind' => $kind];
        if (str_starts_with($kind, 'FM')) {
            $day = (int)substr($kind, 2, 2);
            $h = (int)substr($kind, 4, 2);
            $m = (int)substr($kind, 6, 2);
            $t = $cal->dayTime($day, $h, $m, $r['issueDay']);
            if ($h > 23 || $m > 59 || $t === null || $t < $r['start'] || $t >= $r['end']) {
                $error($g, 'invalid period');
                continue;
            }
            $c['kind'] = 'FM';
            $c['time'] = $t;
        } else {
            if (!$body || !preg_match('/\A\d{4}\/\d{4}\z/', $body[0]['text'])) {
                $g['text'] = $kind;
                $error($g, 'missing period');
                continue;
            }
            $p = $cal->period($body[0]['text'], $r['issueDay']);
            if ($p === null || $p[0] < $r['start'] || $p[1] > $r['end']) {
                $error($body[0], 'invalid period');
                continue;
            }
            [$c['start'], $c['end']] = $p;
            array_shift($body);
        }
        $c['groups'] = $body;
        $changes[] = $c;
    }
    return ['base' => array_slice($groups, 0, $first), 'changes' => $changes];
}

function overlay(array $base, array $change, bool $replace = false): array {
    foreach (ELEMENTS as $k) if ($replace || array_key_exists($k, $change)) {
        if (array_key_exists($k, $change)) $base[$k] = $change[$k];
        else unset($base[$k]);
    }
    return $base;
}

function expandTaf(array $r): array {
    $hours = [];
    for ($h = $r['start'];$h < $r['end'];$h += 60) {
        $s = $r['base'];
        foreach ($r['changes'] as $c) {
            if ($c['kind'] === 'FM'  && $c['time'] <= $h) $s = overlay($s, $c['state'], true);
            elseif ($c['kind'] === 'BECMG'  && $c['end'] <= $h) $s = overlay($s, $c['state']);
        }
        $s = describeState($s);
        $temp = [];
        foreach ($r['changes'] as $c) if (!in_array($c['kind'], ['FM', 'BECMG'], true) && $c['start'] <= $h && $h < $c['end']) $temp[] = ['kind' => $c['kind'], 'state' => describeState(overlay($s, $c['state']))];
        $hours[$h] = ['state' => $s, 'temporary' => $temp];
    }
    return $hours;
}
