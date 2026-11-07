<?php
const DESCRIPTORS = ['MI' => 'shallow', 'BC' => 'patches', 'PR' => 'partial', 'DR' => 'low drifting', 'BL' => 'blowing', 'SH' => 'showers', 'TS' => 'thunderstorm', 'FZ' => 'freezing'];
const PHENOMENA = ['DZ' => 'drizzle', 'RA' => 'rain', 'SN' => 'snow', 'SG' => 'snow grains', 'IC' => 'ice crystals', 'PL' => 'ice pellets', 'GR' => 'hail', 'GS' => 'small hail', 'UP' => 'unknown precipitation', 'BR' => 'mist', 'FG' => 'fog', 'FU' => 'smoke', 'VA' => 'volcanic ash', 'DU' => 'dust', 'SA' => 'sand', 'HZ' => 'haze', 'PY' => 'spray', 'PO' => 'dust whirls', 'SQ' => 'squalls', 'FC' => 'funnel cloud', 'SS' => 'sandstorm', 'DS' => 'duststorm'];
const PRECIP = ['DZ', 'RA', 'SN', 'SG', 'IC', 'PL', 'GR', 'GS', 'UP'];
const AMOUNTS = ['FEW' => 'few', 'SCT' => 'scattered', 'BKN' => 'broken', 'OVC' => 'overcast'];
const CLEAR = ['SKC' => 'sky clear', 'CLR' => 'clear below 12000 ft', 'NSC' => 'no significant cloud'];
function recognize(string $k, string $s): ?array {
    switch ($k) {
        case 'modifier': return in_array($s, ['AUTO', 'COR'], true) ? ['code' => $s] : null;
        case 'wind':
            if (preg_match('/\A(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)\z/', $s, $m)) {
                return ['direction' => $m[1] === 'VRB' ? 'VRB' : (int)$m[1], 'speed' => (int)$m[2], 'gust' => $m[3] !== '' ? (int)$m[3] : null, 'unit' => $m[4]];
            }
            break;
        case 'variation':
            if (preg_match('/\A(\d{3})V(\d{3})\z/', $s, $m)) return ['first' => (int)$m[1], 'last' => (int)$m[2]];
            break;
        case 'visibility':
            if ($s === 'CAVOK') return ['kind' => 'cavok', 'value' => 10000, 'qualifier' => 'P'];
            if (preg_match('/\A\d{4}\z/', $s)) return ['kind' => 'meters', 'value' => $s === '9999' ? 10000 : (int)$s, 'qualifier' => $s === '9999' ? 'P' : ''];
            if (preg_match('/\A([MP]?)(\d{1,2})SM\z/', $s, $m)) return ['kind' => 'miles', 'whole' => (int)$m[2], 'num' => 0, 'den' => 1, 'qualifier' => $m[1], 'mixed' => false, 'fraction' => false];
            if (preg_match('/\A([MP]?)(\d)\/(\d{1,2})SM\z/', $s, $m)) return ['kind' => 'miles', 'whole' => 0, 'num' => (int)$m[2], 'den' => (int)$m[3], 'qualifier' => $m[1], 'mixed' => false, 'fraction' => true];
            if (preg_match('/\A(\d) (\d)\/(\d{1,2})SM\z/', $s, $m)) return ['kind' => 'miles', 'whole' => (int)$m[1], 'num' => (int)$m[2], 'den' => (int)$m[3], 'qualifier' => '', 'mixed' => true, 'fraction' => true];
            break;
        case 'rvr':
            if (preg_match('/\AR(\d{2}[LCR]?)\/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?\z/', $s, $m)) {
                $r = [[$m[2], (int)$m[3]]];
                if (($m[5] ?? '') !== '') $r[] = [$m[4], (int)$m[5]];
                return ['runway' => $m[1], 'readings' => $r, 'unit' => ($m[6] ?? '') === 'FT' ? 'ft' : 'm', 'trend' => $m[7] ?? ''];
            }
            break;
        case 'weather':
            if ($s === 'NSW') return ['raw' => $s, 'nsw' => true, 'descriptor' => null, 'phenomena' => []];
            $pattern = '/\A(-|\+|VC)?((?:' . implode('|', array_merge(array_keys(DESCRIPTORS), array_keys(PHENOMENA))) . ')+)\z/';
            if (preg_match($pattern, $s, $m)) {
                $codes = str_split($m[2], 2);
                $d = isset(DESCRIPTORS[$codes[0]]) ? array_shift($codes) : null;
                return ['raw' => $s, 'nsw' => false, 'intensity' => $m[1], 'descriptor' => $d, 'phenomena' => $codes];
            }
            break;
        case 'cloud':
            if (preg_match('/\A(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?\z/', $s, $m)) return ['amount' => $m[1], 'height' => (int)$m[2] * 100, 'extra' => $m[3] ?? '', 'layer' => true];
            if (preg_match('/\AVV(\d{3})\z/', $s, $m)) return ['amount' => 'VV', 'height' => (int)$m[1] * 100, 'extra' => '', 'layer' => false];
            if (isset(CLEAR[$s])) return ['amount' => $s, 'height' => null, 'extra' => '', 'layer' => false];
            break;
        case 'temperature':
            if (preg_match('/\A(M?)(\d{2})\/(M?)(\d{2})\z/', $s, $m)) return ['temperature' => (int)$m[2] * ($m[1] === 'M' ? - 1 : 1), 'dew' => (int)$m[4] * ($m[3] === 'M' ? - 1 : 1)];
            break;
        case 'pressure':
            if (preg_match('/\A([AQ])(\d{4})\z/', $s, $m)) return ['unit' => $m[1], 'value' => (int)$m[2]];
            break;
        case 'nosig': return $s === 'NOSIG' ? ['code' => $s] : null;
    }
    return null;
}

function validGroup(string $k, array $v, array $s, array $station, bool $change): bool {
    switch ($k) {
        case 'wind':
            $d = $v['direction'];
            $w = $v['speed'];
            $g = $v['gust'];
            if ($d === 'VRB') {
                if ($w < 1) return false;
            } elseif ($d > 360 || $d % 10 !== 0 || (($d === 0) !== ($w === 0)) || ($d === 0 && $g !== null)) return false;
            return $g === null || $g > $w;
        case 'variation':
            $a = $v['first'];
            $b = $v['last'];
            $w = $s['wind'] ?? null;
            return $a >= 10 && $a <= 360 && $b >= 10 && $b <= 360 && $a % 10 === 0 && $b % 10 === 0 && $a !== $b && $w !== null && $w['direction'] !== 'VRB'  && $w['direction'] !== 0;
        case 'visibility':
            if ($v['kind'] !== 'miles') return true;
            if (!$v['fraction']) return $v['whole'] >= 1;
            return in_array($v['den'], [2, 4, 8, 16], true) && $v['num'] >= 1 && $v['num'] < $v['den'] && (!$v['mixed'] || $v['whole'] >= 1);
        case 'rvr':
            return in_array($v['runway'], array_column($station['runways'], 'name'), true) && (count($v['readings']) === 1 || $v['readings'][0][1] < $v['readings'][1][1]);
        case 'weather':
            $previous = $s['weather'] ?? [];
            if (count($previous) >= 3 || array_filter($previous, fn($x) => $x['nsw'])) return false;
            if ($v['nsw']) return $change && !$previous;
            $p = $v['phenomena'];
            if (array_diff($p, array_keys(PHENOMENA)) || count(array_unique($p)) !== count($p)) return false;
            if (!$p && !in_array($v['descriptor'], ['TS', 'SH'], true)) return false;
            if (in_array($v['intensity'], ['-', '+'], true) && !array_intersect($p, PRECIP)) return false;
            return count($p) < 2 || !array_diff($p, PRECIP);
        case 'cloud':
            $p = $s['cloud'] ?? [];
            return !$p || ($v['layer'] && $p[count($p) - 1]['layer'] && $v['height'] > $p[count($p) - 1]['height']);
        case 'temperature': return $v['dew'] <= $v['temperature'];
        case 'pressure': return $v['value'] >= ($v['unit'] === 'A' ? 2500 : 850) && $v['value'] <= ($v['unit'] === 'A' ? 3150 : 1070);
    }
    return true;
}

function recordGroup(array &$s, string $k, array $v, bool $repeat): void {
    if ($k === 'wind'  && $v['unit'] === 'MPS') {
        $v['speed'] = knots($v['speed']);
        if ($v['gust'] !== null) $v['gust'] = knots($v['gust']);
        $v['unit'] = 'KT';
    }
    if ($k === 'pressure') {
        $v['inhg'] = $v['unit'] === 'A' ? $v['value'] : inhg($v['value']);
        $v['hpa'] = $v['unit'] === 'Q' ? $v['value'] : hpa($v['value']);
    }
    if ($repeat) $s[$k][] = $v;
    else $s[$k] = $v;
}
