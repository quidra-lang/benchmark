<?php
require_once __DIR__ . '/units.php';
require_once __DIR__ . '/groups.php';
require_once __DIR__ . '/metar.php';
require_once __DIR__ . '/taf.php';
require_once __DIR__ . '/verification.php';
function groupError(array &$errors, int $report, array $group, string $reason): void {
    $errors[] = [$report, $group['position'], $reason . ' "' . $group['text'] . '"'];
}

function joinGroups(array $words, int $start): array {
    $groups = [];
    for ($i = $start;$i < count($words);++$i) {
        $position = $i + 1;
        $text = $words[$i];
        if (preg_match('/\A\d\z/', $text) && isset($words[$i + 1]) && preg_match('/\A\d\/\d{1,2}SM\z/', $words[$i + 1])) $text .= ' ' . $words[++$i];
        $groups[] = ['position' => $position, 'text' => $text];
    }
    return $groups;
}

function parseHeader(array $words, int $number, array $stations, Calendar $cal, array &$errors): ?array {
    $kind = $words[0];
    if (!in_array($kind, ['METAR', 'SPECI', 'TAF'], true)) {
        $errors[] = [$number, 1, 'rejected report, invalid type "' . $kind . '"'];
        return null;
    }
    $i = 1;
    $r = ['number' => $number, 'kind' => $kind];
    if ($kind === 'TAF'  && in_array($words[$i] ?? '', ['AMD', 'COR'], true)) $r['modifier'] = $words[$i++];
    foreach ($kind === 'TAF' ? ['station', 'time', 'validity'] : ['station', 'time'] as $field) {
        if (!isset($words[$i])) {
            $errors[] = [$number, count($words) + 1, 'rejected report, missing ' . $field];
            return null;
        }
        $text = $words[$i];
        $value = null;
        if ($field === 'station') $value = $stations[$text] ?? null;
        elseif ($field === 'time') $value = $cal->reportTime($text);
        else $value = $cal->period($text, $r['issueDay'], 1800);
        if ($value === null) {
            $errors[] = [$number, $i + 1, 'rejected report, invalid ' . $field . ' "' . $text . '"'];
            return null;
        }
        if ($field === 'validity') [$r['start'], $r['end']] = $value;
        else $r[$field] = $value;
        if ($field === 'time') $r['issueDay'] = intdiv($value, 1440) + 1;
        ++$i;
    }
    $r['groups'] = joinGroups($words, $i);
    return $r;
}

function matchSection(array $groups, array $slots, array $r, bool $change, array &$errors): array {
    $s = [];
    $current = 0;
    $recognizer = $slots === METAR_SLOTS ? 'metarSlotValue' : 'recognize';
    foreach ($groups as $g) {
        $found = null;
        $v = null;
        for ($i = $current;$i < count($slots);++$i) if (($v = $recognizer($slots[$i][0], $g['text'])) !== null) {
            $found = $i;
            break;
        }
        if ($found === null) {
            $earlier = false;
            for ($i = 0;$i < $current;++$i) if ($recognizer($slots[$i][0], $g['text']) !== null) {
                $earlier = true;
                break;
            }
            groupError($errors, $r['number'], $g, $earlier ? 'out of order group' : 'unknown group');
            continue;
        }
        [$k, $repeat] = $slots[$found];
        if (!validGroup($k, $v, $s, $r['station'], $change)) {
            groupError($errors, $r['number'], $g, 'invalid group');
            continue;
        }
        recordGroup($s, $k, $v, $repeat);
        $current = $repeat ? $found : $found + 1;
        if ($k === 'visibility'  && $v['kind'] === 'cavok') {
            $s['weather'] = [];
            $s['cloud'] = [];
            foreach ($slots as $i => $slot) if ($slot[0] === 'cloud') $current = $i + 1;
        }
    }
    return $s;
}

function describeState(array $s): array {
    $ceiling = null;
    foreach ($s['cloud'] ?? [] as $c) if (in_array($c['amount'], ['BKN', 'OVC', 'VV'], true)) {
        $ceiling = $c['height'];
        break;
    }
    [$n, $d] = isset($s['visibility']) ? miles($s['visibility']) : [0, 0];
    $cat = 'VFR';
    if (($ceiling !== null && $ceiling < 500) || ($d && $n < $d)) $cat = 'LIFR';
    elseif (($ceiling !== null && $ceiling < 1000) || ($d && $n < 3 * $d)) $cat = 'IFR';
    elseif (($ceiling !== null && $ceiling <= 3000) || ($d && $n <= 5 * $d)) $cat = 'MVFR';
    $s['ceiling'] = $ceiling;
    $s['category'] = $cat;
    return $s;
}

function components(int $speed, int $direction, int $heading): array {
    return [divfloor($speed * cosine($direction - $heading), 1000), divfloor($speed * sine($direction - $heading), 1000)];
}

function deriveObservation(array &$r, array $settings): void {
    $s = $r['state'];
    $p = $s['pressure'] ?? null;
    $t = $s['temperature'] ?? null;
    if ($p !== null) {
        $a = $r['station']['elevation'] + (2992 - $p['inhg']) * 10;
        $r['pressureAltitude'] = $a;
        if ($t !== null) $r['densityAltitude'] = $a + divfloor(120 * (1000 * $t['temperature'] - 15000 + 2 * $a), 1000);
    }
    $w = $s['wind'] ?? null;
    if ($w === null || $w['direction'] === 'VRB'  || $w['direction'] === 0) return;
    $r['components'] = [];
    $r['usable'] = [];
    $preferred = null;
    foreach ($r['station']['runways'] as $runway) {
        $mean = components($w['speed'], $w['direction'], $runway['heading']);
        $gust = $w['gust'] !== null ? components($w['gust'], $w['direction'], $runway['heading']) : null;
        $d = $gust ?? $mean;
        $name = $runway['name'];
        $r['components'][] = ['name' => $name, 'mean' => $mean, 'gust' => $gust];
        if (abs($d[1]) <= $settings['CROSSWIND_LIMIT'] && - $d[0] <= $settings['TAILWIND_LIMIT']) {
            $r['usable'][] = $name;
            if ($preferred === null || $mean[0] > $preferred['head']) $preferred = ['name' => $name, 'head' => $mean[0]];
        }
    }
    $r['preferred'] = $preferred['name'] ?? 'none';
}

function windChanges(?array $a, ?array $b, int $angle): array {
    if ($a === null || $b === null) return [];
    $result = [];
    if (!in_array($a['direction'], ['VRB', 0], true) && !in_array($b['direction'], ['VRB', 0], true)) {
        $d = abs($a['direction'] - $b['direction']) % 360;
        if (max($a['speed'], $b['speed']) >= 10 && min($d, 360 - $d) >= $angle) $result[] = 'wind shift';
    }
    if (abs($a['speed'] - $b['speed']) >= 10) $result[] = 'wind speed';
    return $result;
}

function weatherPresent(array $s, string $kind): bool {
    foreach ($s['weather'] ?? [] as $w) {
        if ($kind === 'TS'  && $w['descriptor'] === 'TS') return true;
        if ($kind === 'FZ'  && $w['descriptor'] === 'FZ'  && array_intersect($w['phenomena'], ['DZ', 'RA'])) return true;
    }
    return false;
}

function speciCheck(?array $previous, array $r): string {
    if ($previous === null) return 'no previous report';
    $a = $previous['state'];
    $b = $r['state'];
    $reasons = [];
    if ($a['category'] !== $b['category']) $reasons[] = 'category ' . $a['category'] . ' to ' . $b['category'];
    $reasons = array_merge($reasons, windChanges($a['wind'] ?? null, $b['wind'] ?? null, 45));
    foreach (['TS' => 'thunderstorm', 'FZ' => 'freezing precipitation'] as $k => $text) {
        $before = weatherPresent($a, $k);
        $after = weatherPresent($b, $k);
        if ($before !== $after) $reasons[] = $text . ($after ? ' began' : ' ended');
    }
    return $reasons ? implode(', ', $reasons) : 'no criteria met';
}

function windPhrase(array $w): string {
    if ($w['direction'] === 0) return 'calm';
    $s = $w['direction'] === 'VRB' ? 'variable at ' . $w['speed'] . ' KT' : sprintf('%03d degrees at %d KT', $w['direction'], $w['speed']);
    return $s . ($w['gust'] !== null ? ' gusting ' . $w['gust'] . ' KT' : '');
}

function visibilityNumber(array $v): string {
    if (!$v['fraction']) return (string)$v['whole'];
    return ($v['whole'] ? $v['whole'] . ' ' : '') . $v['num'] . '/' . $v['den'];
}

function visibilityPhrase(array $v): string {
    if ($v['kind'] === 'cavok') return '10 km or more (CAVOK)';
    if ($v['kind'] === 'meters') return $v['value'] === 10000 ? '10 km or more' : $v['value'] . ' m';
    return (['M' => 'less than ', 'P' => 'more than '][$v['qualifier']] ?? '') . visibilityNumber($v) . ' SM';
}

function weatherPhrase(array $w): string {
    if ($w['nsw']) return 'no significant weather';
    return implode(' ', array_filter([['-' => 'light', '+' => 'heavy', 'VC' => 'nearby'][$w['intensity']] ?? '', DESCRIPTORS[$w['descriptor']] ?? '', implode(' and ', array_map(fn($p) => PHENOMENA[$p], $w['phenomena']))], fn($s) => $s !== ''));
}

function cloudPhrase(array $c): string {
    if (isset(CLEAR[$c['amount']])) return CLEAR[$c['amount']];
    if ($c['amount'] === 'VV') return 'vertical visibility ' . $c['height'] . ' ft';
    return AMOUNTS[$c['amount']] . ' at ' . $c['height'] . ' ft' . (['CB' => ' cumulonimbus', 'TCU' => ' towering cumulus'][$c['extra']] ?? '');
}

function summary(array $s): string {
    $parts = [];
    if (isset($s['wind'])) $parts[] = 'wind ' . windPhrase($s['wind']);
    if (isset($s['visibility'])) $parts[] = 'visibility ' . visibilityPhrase($s['visibility']);
    if ($s['weather'] ?? []) $parts[] = 'weather ' . implode(', ', array_map('weatherPhrase', $s['weather']));
    if ($s['cloud'] ?? []) $parts[] = 'cloud ' . implode(', ', array_map('cloudPhrase', $s['cloud']));
    return $parts ? implode('; ', $parts) : 'no conditions';
}

function windCode(array $w): string {
    if ($w['direction'] === 0) return '00000KT';
    return ($w['direction'] === 'VRB' ? 'VRB' : sprintf('%03d', $w['direction'])) . sprintf('%02d', $w['speed']) . ($w['gust'] !== null ? sprintf('G%02d', $w['gust']) : '') . 'KT';
}

function visibilityCode(array $v): string {
    if ($v['kind'] === 'cavok') return 'CAVOK';
    if ($v['kind'] === 'meters') return sprintf('%04d', $v['value'] === 10000 ? 9999 : $v['value']);
    return $v['qualifier'] . visibilityNumber($v) . 'SM';
}

function tokens(array $s): string {
    $words = [];
    if (isset($s['wind'])) $words[] = windCode($s['wind']);
    if (isset($s['visibility'])) $words[] = visibilityCode($s['visibility']);
    foreach ($s['weather'] ?? [] as $w) if (!$w['nsw']) $words[] = $w['raw'];
    foreach ($s['cloud'] ?? [] as $c) $words[] = isset(CLEAR[$c['amount']]) ? $c['amount'] : $c['amount'] . sprintf('%03d', intdiv($c['height'], 100)) . $c['extra'];
    $words[] = $s['category'];
    return implode(' ', $words);
}

function tenths(int $v): string {
    return ($v < 0 ? '-' : '') . intdiv(abs($v), 10) . '.' . (abs($v) % 10);
}

function inhgText(int $v): string {
    return sprintf('%d.%02d', intdiv($v, 100), $v % 100);
}

function componentPhrase(array $v): string {
    [$h, $c] = $v;
    return ($h < 0 ? 'tailwind ' . ( - $h) : 'headwind ' . $h) . ' KT, crosswind ' . abs($c) . ' KT' . ($c > 0 ? ' from right' : ($c < 0 ? ' from left' : ''));
}

function rvrPhrase(array $v): string {
    $readings = array_map(fn($r) => (['M' => 'less than ', 'P' => 'more than '][$r[0]] ?? '') . $r[1], $v['readings']);
    return 'runway ' . $v['runway'] . ' ' . (count($readings) === 1 ? $readings[0] : 'between ' . $readings[0] . ' and ' . $readings[1]) . ' ' . $v['unit'] . ($v['trend'] !== '' ? ', ' . ['U' => 'rising', 'D' => 'falling', 'N' => 'no change'][$v['trend']] : '');
}

function decoded(array $r, Calendar $cal): array {
    $header = 'REPORT ' . $r['number'] . ': ' . $r['kind'] . ' ' . $r['station']['code'] . ' (' . $r['station']['name'] . ')';
    $lines = [];
    if ($r['kind'] === 'TAF') {
        $lines[] = 'issued: ' . $cal->stamp($r['time']);
        if (isset($r['modifier'])) $lines[] = 'modifier: ' . ($r['modifier'] === 'AMD' ? 'amended' : 'corrected');
        $lines[] = 'valid: ' . $cal->stamp($r['start']) . ' to ' . $cal->stamp($r['end']);
        $lines[] = 'base: ' . summary($r['base']);
        foreach ($r['changes'] as $c) $lines[] = $c['kind'] . ' ' . ($c['kind'] === 'FM' ? $cal->stamp($c['time']) : $cal->stamp($c['start']) . ' to ' . $cal->stamp($c['end'])) . ': ' . summary($c['state']);
    } else {
        $s = $r['state'];
        $lines[] = 'time: ' . $cal->stamp($r['time']);
        if (isset($s['modifier'])) $lines[] = 'modifier: ' . ($s['modifier']['code'] === 'AUTO' ? 'automated' : 'corrected');
        $w = isset($s['wind']) ? windPhrase($s['wind']) : 'not reported';
        if (isset($s['variation'])) $w .= sprintf(', varying between %03d and %03d degrees', $s['variation']['first'], $s['variation']['last']);
        $lines[] = 'wind: ' . $w;
        $lines[] = 'visibility: ' . (isset($s['visibility']) ? visibilityPhrase($s['visibility']) : 'not reported');
        foreach ($s['rvr'] ?? [] as $v) $lines[] = 'runway visual range: ' . rvrPhrase($v);
        foreach ($s['weather'] ?? [] as $v) $lines[] = 'weather: ' . weatherPhrase($v);
        if (($s['visibility']['kind'] ?? '') === 'cavok') $lines[] = 'cloud: no significant cloud';
        elseif (!isset($s['cloud'])) $lines[] = 'cloud: not reported';
        else foreach ($s['cloud'] as $c) $lines[] = 'cloud: ' . cloudPhrase($c);
        $t = $s['temperature'] ?? null;
        $lines[] = $t === null ? 'temperature: not reported' : 'temperature: ' . $t['temperature'] . ' C, dew point ' . $t['dew'] . ' C, spread ' . ($t['temperature'] - $t['dew']) . ' C';
        $p = $s['pressure'] ?? null;
        $lines[] = $p === null ? 'altimeter: not reported' : 'altimeter: ' . ($p['unit'] === 'A' ? inhgText($p['inhg']) . ' inHg (' . $p['hpa'] . ' hPa)' : $p['hpa'] . ' hPa (' . inhgText($p['inhg']) . ' inHg)');
        if (isset($s['nosig'])) $lines[] = 'trend: no significant change';
        foreach ($r['trends'] as $trend) {
            $text = $trend['kind'] === 'BECMG' ? 'becoming' : 'temporarily';
            foreach ($trend['times'] as $t) $text .= ' ' . ['FM' => 'from', 'TL' => 'until', 'AT' => 'at'][$t['kind']] . sprintf(' %02d:%02dZ', $t['hour'], $t['minute']);
            $lines[] = 'trend: ' . $text . ': ' . summary($trend['state']);
        }
        foreach ($r['sea'] as $v) $lines[] = 'sea level pressure: ' . tenths($v) . ' hPa';
        foreach ($r['precise'] as [$t, $d]) $lines[] = 'precise temperature: ' . tenths($t) . ' C, dew point ' . tenths($d) . ' C';
        $lines[] = 'ceiling: ' . ($s['ceiling'] !== null ? $s['ceiling'] . ' ft' : 'none');
        $lines[] = 'flight category: ' . $s['category'];
        foreach (['pressureAltitude' => 'pressure altitude', 'densityAltitude' => 'density altitude'] as $key => $label) $lines[] = $label . ': ' . (isset($r[$key]) ? $r[$key] . ' ft' : 'not available');
        if (isset($r['components'])) {
            foreach ($r['components'] as $v) $lines[] = 'runway ' . $v['name'] . ': ' . componentPhrase($v['mean']) . ($v['gust'] !== null ? '; gusts ' . componentPhrase($v['gust']) : '');
            $lines[] = 'usable runways: ' . ($r['usable'] ? implode(' ', $r['usable']) : 'none');
            $lines[] = 'preferred runway: ' . $r['preferred'];
        } else $lines[] = 'runway wind: not computed';
        if ($r['kind'] === 'SPECI') $lines[] = 'speci check: ' . $r['speci'];
    }
    return array_merge([$header], array_map(fn($line) => '  ' . $line, $lines));
}

function categoryCounts(array $states): string {
    return implode(', ', array_map(fn($cat) => $cat . ' ' . count(array_filter($states, fn($s) => $s['category'] === $cat)), CATEGORIES));
}

function timeline(array $r, Calendar $cal): array {
    $lines = ['TAF ' . $r['station']['code'] . ' issued ' . $cal->stamp($r['time']) . ' valid ' . $cal->stamp($r['start']) . ' to ' . $cal->stamp($r['end'])];
    foreach ($r['hours'] as $h => $states) {
        $line = $cal->stamp($h) . ' ' . tokens($states['state']);
        foreach ($states['temporary'] as $c) $line .= ' | ' . $c['kind'] . ' ' . tokens($c['state']);
        $lines[] = $line;
    }
    $lines[] = 'summary: ' . categoryCounts(array_column($r['hours'], 'state'));
    return $lines;
}

function extreme(array $observations, callable $value, bool $maximum = false, bool $ratio = false): ?array {
    $chosen = null;
    $best = null;
    foreach ($observations as $o) {
        $v = $value($o);
        if ($v === null) continue;
        $cmp = $chosen === null ? 0 : ($ratio ? $v[0] * $best[1] <=> $best[0] * $v[1] : $v <=> $best);
        if ($chosen === null || ($maximum ? $cmp > 0 : $cmp < 0)) {
            $chosen = $o;
            $best = $v;
        }
    }
    return $chosen;
}

function extremeLine(string $label, ?array $o, callable $phrase, Calendar $cal): string {
    return $label . ': ' . ($o === null ? 'not available' : $phrase($o) . ' at ' . $cal->stamp($o['time']));
}

function verificationLines(array $station, array $reports, Calendar $cal): array {
    $observations = [];
    $forecasts = [];
    foreach ($reports as $r) if ($r['station']['code'] === $station['code']) {
        if ($r['kind'] === 'TAF') $forecasts[] = $r;
        else $observations[] = $r;
    }
    $v = compareForecasts($observations, $forecasts);
    $temperature = fn($o) => $o['state']['temperature']['temperature'] ?? null;
    $lines = ['station ' . $station['code'] . ' (' . $station['name'] . ')'];
    $lines[] = 'reports: METAR ' . count(array_filter($observations, fn($o) => $o['kind'] === 'METAR')) . ', SPECI ' . count(array_filter($observations, fn($o) => $o['kind'] === 'SPECI'));
    $lines[] = 'observed categories: ' . categoryCounts(array_column($observations, 'state'));
    $lines[] = extremeLine('lowest temperature', extreme($observations, $temperature), fn($o) => $temperature($o) . ' C', $cal);
    $lines[] = extremeLine('highest temperature', extreme($observations, $temperature, true), fn($o) => $temperature($o) . ' C', $cal);
    $lines[] = extremeLine('strongest wind', extreme($observations, fn($o) => isset($o['state']['wind']) ? ($o['state']['wind']['gust'] ?? $o['state']['wind']['speed']) : null, true), fn($o) => windPhrase($o['state']['wind']), $cal);
    $lines[] = extremeLine('lowest ceiling', extreme($observations, fn($o) => $o['state']['ceiling']), fn($o) => $o['state']['ceiling'] . ' ft', $cal);
    $lines[] = extremeLine('lowest visibility', extreme($observations, fn($o) => isset($o['state']['visibility']) ? miles($o['state']['visibility']) : null, false, true), fn($o) => visibilityPhrase($o['state']['visibility']), $cal);
    $lines[] = 'verified: ' . $v['total'];
    $lines[] = 'no forecast: ' . $v['noForecast'];
    $row = fn($name, $values) => str_pad($name, 8) . implode('', array_map(fn($x) => str_pad((string)$x, 6, ' ', STR_PAD_LEFT), $values));
    $lines[] = $row('forecast', array_merge(CATEGORIES, ['total']));
    foreach (CATEGORIES as $i => $cat) $lines[] = $row($cat, array_merge($v['table'][$i], [$v['rows'][$i]]));
    $lines[] = $row('total', array_merge($v['columns'], [$v['total']]));
    $lines[] = 'hit rate: ' . fraction($v['hits'], $v['total']);
    $lines[] = 'hit rate with temporary groups: ' . fraction($v['temporaryHits'], $v['total']);
    $lines[] = 'heidke skill score: ' . fraction(...$v['skill']);
    foreach (CATEGORIES as $i => $cat) $lines[] = $cat . ': pod ' . fraction(...$v['pod'][$i]) . ', far ' . fraction(...$v['far'][$i]);
    $buckets = array_fill(0, 5, [0, 0]);
    foreach ($forecasts as $f) foreach ($observations as $o) if (covers($f, $o)) {
        $h = $o['time'] - $o['time'] % 60;
        $i = intdiv($h - $f['start'], 360);
        ++$buckets[$i][1];
        if ($f['hours'][$h]['state']['category'] === $o['state']['category']) ++$buckets[$i][0];
    }
    foreach ($buckets as $i => $b) $lines[] = 'hours ' . ($i * 6) . '-' . ($i * 6 + 5) . ': ' . fraction(...$b);
    foreach ($v['selected'] as $choice) {
        $o = $choice['observation'];
        $actual = $o['state'];
        $forecast = $choice['states']['state'];
        $reasons = [];
        if (!in_array($actual['category'], $choice['possible'], true)) $reasons[] = 'category ' . $actual['category'] . ', forecast ' . $forecast['category'];
        if (windChanges($forecast['wind'] ?? null, $actual['wind'] ?? null, 60)) $reasons[] = 'wind ' . windCode($actual['wind']) . ', forecast ' . windCode($forecast['wind']);
        if ($reasons) $lines[] = 'amendment ' . $cal->stamp($o['time']) . ': ' . implode('; ', $reasons);
    }
    return $lines;
}

function writeLines(string $path, array $lines): void {
    file_put_contents($path, $lines ? implode("\n", $lines) . "\n" : '');
}

function writeBlocks(string $path, array $blocks): void {
    file_put_contents($path, $blocks ? implode("\n\n", array_map(fn($b) => implode("\n", $b), $blocks)) . "\n" : '');
}
$stations = [];
foreach (file('input/stations.txt', FILE_IGNORE_NEW_LINES) as $line) {
    [$code, $elevation, $runways, $name] = explode(' ', $line, 4);
    $r = [];
    foreach (explode(',', $runways) as $entry) {
        [$n, $h] = explode('/', $entry);
        $r[] = ['name' => $n, 'heading' => (int)$h];
    }
    $stations[$code] = ['code' => $code, 'elevation' => (int)$elevation, 'runways' => $r, 'name' => $name];
}
$settings = [];
foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
    $p = explode(' ', $line);
    $key = array_shift($p);
    $settings[$key] = $key === 'VERIFY' ? $p : (int)$p[0];
}
$cal = new Calendar($settings['YEAR'], $settings['MONTH']);
$words = [];
foreach (file('input/reports.txt', FILE_IGNORE_NEW_LINES) as $line) {
    $tokens = explode(' ', ltrim($line, ' '));
    if ($line[0] === ' ') $words[count($words) - 1] = array_merge($words[count($words) - 1], $tokens);
    else $words[] = $tokens;
}
$errors = [];
$reports = [];
$previous = [];
foreach ($words as $i => $w) {
    $r = parseHeader($w, $i + 1, $stations, $cal, $errors);
    if ($r === null) continue;
    $error = function($g, $reason) use (&$errors, $r) {
        groupError($errors, $r['number'], $g, $reason);
    };
    if ($r['kind'] === 'TAF') {
        $parts = splitTaf($r['groups'], $r, $cal, $error);
        $r['base'] = matchSection($parts['base'], TAF_SLOTS, $r, false, $errors);
        $r['changes'] = [];
        foreach ($parts['changes'] as $c) {
            $c['state'] = matchSection($c['groups'], TAF_SLOTS, $r, true, $errors);
            $r['changes'][] = $c;
        }
        $r['hours'] = expandTaf($r);
    } else {
        $parts = splitMetar($r['groups'], $error);
        $r['state'] = describeState(matchSection($parts['main'], METAR_SLOTS, $r, false, $errors));
        $r['trends'] = [];
        foreach ($parts['trends'] as $t) {
            $t['state'] = matchSection($t['groups'], TAF_SLOTS, $r, true, $errors);
            $r['trends'][] = $t;
        }
        $r['sea'] = $parts['sea'];
        $r['precise'] = $parts['precise'];
        deriveObservation($r, $settings);
        $code = $r['station']['code'];
        if ($r['kind'] === 'SPECI') $r['speci'] = speciCheck($previous[$code] ?? null, $r);
        $previous[$code] = $r;
    }
    $reports[] = $r;
}
if (!is_dir('output')) mkdir('output');
writeBlocks('output/decoded.txt', array_map(fn($r) => decoded($r, $cal), $reports));
$categories = ['station,time,ceiling,visibility,category'];
$timelines = [];
foreach ($reports as $r) {
    if ($r['kind'] === 'TAF') {
        $timelines[] = timeline($r, $cal);
        continue;
    }
    $s = $r['state'];
    $visibility = isset($s['visibility']) ? $s['visibility']['qualifier'] . meters($s['visibility']) : 'NONE';
    $categories[] = implode(',', [$r['station']['code'], $cal->stamp($r['time']), $s['ceiling'] ?? 'NONE', $visibility, $s['category']]);
}
writeLines('output/categories.csv', $categories);
writeBlocks('output/taf_timeline.txt', $timelines);
writeBlocks('output/verification.txt', array_map(fn($code) => verificationLines($stations[$code], $reports, $cal), $settings['VERIFY']));
usort($errors, fn($a, $b) => [$a[0], $a[1]] <=> [$b[0], $b[1]]);
writeLines('output/errors.txt', array_map(fn($e) => 'report ' . $e[0] . ' word ' . $e[1] . ': ' . $e[2], $errors));
