<?php
const PRECS = ['GEOHASH' => [1,2,3,4,5,6,7,8,9], 'MAIDENHEAD' => [2,4,6,8], 'PLUSCODE' => [2,4,6,8,10,11], 'GARS' => [5,6,7], 'GEOREF' => [2,4,8,10,12], 'MESH' => [4,6,8,9,10,11]];
const GH = '0123456789bcdefghjkmnpqrstuvwxyz';
const L24 = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const PC = '23456789CFGHJMPQRVWX';
const MH = ['ABCDEFGHIJKLMNOPQR', '0123456789', 'abcdefghijklmnopqrstuvwx', '0123456789'];
const BANDS = 'CDEFGHJKLMNPQRSTUVWX';
const OS = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';
const COLS = ['STUVWXYZ', 'ABCDEFGH', 'JKLMNPQR'];
const ROWS = 'ABCDEFGHJKLMNPQRSTUV';
function invalid(): never { throw new InvalidArgumentException(); }
function fd(int $a, int $b): int
{
    $q = intdiv($a, $b);
    return $a < 0 && $a % $b !== 0 ? $q - 1 : $q;
}
function md(int $a, int $b): int { return ($a % $b + $b) % $b; }
function integer(string $text, int $lo, int $hi): int
{
    if (!preg_match('/^-?[0-9]{1,9}$/D', $text)) invalid();
    $v = (int) $text;
    if ($v < $lo || $v > $hi) invalid();
    return $v;
}
function coordinate(string $text, bool $latitude): int
{
    if (!preg_match('/^(-?)([0-9]{1,3})(?:\.([0-9]{1,6}))?$/D', $text, $parts)) invalid();
    $v = (int) $parts[2] * 1000000 + (int) str_pad($parts[3] ?? '', 6, '0');
    if ($parts[1] === '-') $v = -$v;
    if ($latitude ? ($v < -90000000 || $v > 90000000) : ($v < -180000000 || $v >= 180000000)) invalid();
    return $v;
}
function system_name(string $sys): string
{
    if (!isset(PRECS[$sys])) invalid();
    return $sys;
}
function precision(string $sys, string $text): int
{
    $p = integer($text, 1, 12);
    if (!in_array($p, PRECS[$sys], true)) invalid();
    return $p;
}
function grid(string $sys, int $p): array
{
    return match ($sys) {
        'GEOHASH' => [2 ** intdiv(5 * $p + 1, 2), 2 ** intdiv(5 * $p, 2)],
        'MAIDENHEAD' => match ($p) {2 => [18,18], 4 => [180,180], 6 => [4320,4320], 8 => [43200,43200]},
        'PLUSCODE' => match ($p) {2 => [18,9], 4 => [360,180], 6 => [7200,3600], 8 => [144000,72000], 10 => [2880000,1440000], 11 => [11520000,7200000]},
        'GARS' => match ($p) {5 => [720,360], 6 => [1440,720], 7 => [4320,2160]},
        'GEOREF' => match ($p) {2 => [24,12], 4 => [360,180], 8 => [21600,10800], 10 => [216000,108000], 12 => [2160000,1080000]},
        'MESH' => match ($p) {4 => [360,270], 6 => [2880,2160], 8 => [28800,21600], 9 => [57600,43200], 10 => [115200,86400], 11 => [230400,172800]}
    };
}
function digits(int $v, array $radices): array
{
    $out = array_fill(0, count($radices), 0);
    for ($i = count($radices) - 1; $i >= 0; --$i) {
        $out[$i] = $v % $radices[$i];
        $v = intdiv($v, $radices[$i]);
    }
    return $out;
}
function index_char(string $set, string $char): int
{
    $i = strpos($set, $char);
    if ($char === '' || $i === false) invalid();
    return $i;
}
function encode(string $sys, int $p, int $x, int $y): string
{
    if ($sys === 'GEOHASH') {
        $a = intdiv(5 * $p + 1, 2);
        $b = intdiv(5 * $p, 2);
        $value = 0;
        $out = '';
        for ($i = 0; $i < 5 * $p; ++$i) {
            if ($i % 2 === 0) {
                --$a;
                $bit = intdiv($x, 2 ** $a) % 2;
            } else {
                --$b;
                $bit = intdiv($y, 2 ** $b) % 2;
            }
            $value = 2 * $value + $bit;
            if ($i % 5 === 4) {
                $out .= GH[$value];
                $value = 0;
            }
        }
        return $out;
    }
    if ($sys === 'MAIDENHEAD') {
        $k = intdiv($p, 2);
        $radices = array_slice([18,10,24,10], 0, $k);
        $xs = digits($x, $radices);
        $ys = digits($y, $radices);
        $out = '';
        for ($i = 0; $i < $k; ++$i) $out .= MH[$i][$xs[$i]] . MH[$i][$ys[$i]];
        return $out;
    }
    if ($sys === 'PLUSCODE') {
        $tail = '';
        if ($p === 11) {
            $tail = PC[4 * ($y % 5) + $x % 4];
            $x = intdiv($x, 4);
            $y = intdiv($y, 5);
        }
        $k = intdiv(min($p, 10), 2);
        $radices = array_fill(0, $k, 20);
        $radices[0] = 18;
        $xs = digits($x, $radices);
        $radices[0] = 9;
        $ys = digits($y, $radices);
        $out = '';
        for ($i = 0; $i < $k; ++$i) $out .= PC[$ys[$i]] . PC[$xs[$i]];
        $out .= $tail;
        if ($p < 8) return $out . str_repeat('0', 8 - $p) . '+';
        return substr($out, 0, 8) . '+' . substr($out, 8);
    }
    if ($sys === 'GARS') {
        $tail = '';
        if ($p === 7) {
            $tail = (string) (1 + $x % 3 + 3 * (2 - $y % 3));
            $x = intdiv($x, 3);
            $y = intdiv($y, 3);
        }
        if ($p >= 6) {
            $tail = (1 + $x % 2 + 2 * (1 - $y % 2)) . $tail;
            $x = intdiv($x, 2);
            $y = intdiv($y, 2);
        }
        return sprintf('%03d', $x + 1) . L24[intdiv($y, 24)] . L24[$y % 24] . $tail;
    }
    if ($sys === 'GEOREF') {
        $tail = '';
        if ($p >= 8) {
            $m = intdiv($p - 4, 2);
            $scale = 6 * 10 ** ($m - 1);
            $tail = sprintf('%0*d%0*d', $m, $x % $scale, $m, $y % $scale);
            $x = intdiv($x, $scale);
            $y = intdiv($y, $scale);
        }
        if ($p >= 4) {
            $tail = L24[$x % 15] . L24[$y % 15] . $tail;
            $x = intdiv($x, 15);
            $y = intdiv($y, 15);
        }
        return L24[$x] . L24[$y] . $tail;
    }
    $level = array_search($p, PRECS['MESH'], true);
    $scale = [1,8,80,160,320,640][$level];
    $u = $x - 280 * $scale;
    $v = $y - 135 * $scale;
    if ($u < 0 || $u >= 80 * $scale || $v < 0 || $v >= 100 * $scale) return '-';
    $radices = array_slice([80,8,10,2,2,2], 0, $level + 1);
    $us = digits($u, $radices);
    $radices[0] = 100;
    $vs = digits($v, $radices);
    $out = sprintf('%02d%02d', $vs[0], $us[0]);
    for ($i = 1; $i <= $level; ++$i) {
        if ($i <= 2) $out .= $vs[$i] . $us[$i];
        else $out .= 1 + $us[$i] + 2 * $vs[$i];
    }
    return $out;
}
function decode(string $sys, string $code): array
{
    $p = strlen($code);
    $x = 0;
    $y = 0;
    if ($sys !== 'PLUSCODE' && !in_array($p, PRECS[$sys], true)) invalid();
    if ($sys === 'GEOHASH') {
        $bitIndex = 0;
        foreach (str_split($code) as $char) {
            $value = index_char(GH, $char);
            for ($i = 4; $i >= 0; --$i) {
                $bit = intdiv($value, 2 ** $i) % 2;
                if ($bitIndex % 2 === 0) $x = 2 * $x + $bit;
                else $y = 2 * $y + $bit;
                ++$bitIndex;
            }
        }
    } elseif ($sys === 'MAIDENHEAD') {
        for ($i = 0; $i < intdiv($p, 2); ++$i) {
            $radix = strlen(MH[$i]);
            $x = $x * $radix + index_char(MH[$i], $code[2 * $i]);
            $y = $y * $radix + index_char(MH[$i], $code[2 * $i + 1]);
        }
    } elseif ($sys === 'PLUSCODE') {
        if (substr_count($code, '+') !== 1 || strpos($code, '+') !== 8) invalid();
        $before = substr($code, 0, 8);
        $after = substr($code, 9);
        $prefix = strcspn($before, '0');
        if (!in_array($prefix, [2,4,6,8], true)) invalid();
        if ($prefix < 8 && (substr($before, $prefix) !== str_repeat('0', 8 - $prefix) || $after !== '')) invalid();
        if ($prefix === 8 && !in_array(strlen($after), [0,2,3], true)) invalid();
        $sequence = substr($before, 0, $prefix) . $after;
        $p = strlen($sequence);
        $values = array_map(fn($char) => index_char(PC, $char), str_split($sequence));
        if ($values[0] > 8 || $values[1] > 17) invalid();
        for ($i = 0; $i < intdiv(min($p, 10), 2); ++$i) {
            $y = $y * ($i === 0 ? 9 : 20) + $values[2 * $i];
            $x = $x * ($i === 0 ? 18 : 20) + $values[2 * $i + 1];
        }
        if ($p === 11) {
            $x = 4 * $x + $values[10] % 4;
            $y = 5 * $y + intdiv($values[10], 4);
        }
    } elseif ($sys === 'GARS') {
        if (!preg_match('/^[0-9]{3}/D', $code)) invalid();
        $x = (int) substr($code, 0, 3) - 1;
        $y = 24 * index_char(substr(L24, 0, 15), $code[3]) + index_char(L24, $code[4]);
        if ($p >= 6) {
            $q = index_char('1234', $code[5]);
            $x = 2 * $x + $q % 2;
            $y = 2 * $y + 1 - intdiv($q, 2);
        }
        if ($p === 7) {
            $q = index_char('123456789', $code[6]);
            $x = 3 * $x + $q % 3;
            $y = 3 * $y + 2 - intdiv($q, 3);
        }
    } elseif ($sys === 'GEOREF') {
        $x = index_char(L24, $code[0]);
        $y = index_char(substr(L24, 0, 12), $code[1]);
        if ($p >= 4) {
            $x = 15 * $x + index_char(substr(L24, 0, 15), $code[2]);
            $y = 15 * $y + index_char(substr(L24, 0, 15), $code[3]);
        }
        if ($p >= 8) {
            $m = intdiv($p - 4, 2);
            $tail = substr($code, 4);
            if (!preg_match('/^[0-9]+$/D', $tail)) invalid();
            $scale = 6 * 10 ** ($m - 1);
            $e = (int) substr($tail, 0, $m);
            $n = (int) substr($tail, $m);
            if ($e >= $scale || $n >= $scale) invalid();
            $x = $x * $scale + $e;
            $y = $y * $scale + $n;
        }
    } else {
        if (!preg_match('/^[0-9]+$/D', $code)) invalid();
        $level = array_search($p, PRECS['MESH'], true);
        $u = (int) substr($code, 2, 2);
        $v = (int) substr($code, 0, 2);
        if ($u > 79) invalid();
        for ($i = 1; $i <= $level; ++$i) {
            if ($i <= 2) {
                $base = $i === 1 ? 8 : 10;
                $a = (int) $code[2 + 2 * $i];
                $b = (int) $code[3 + 2 * $i];
                if ($a >= $base || $b >= $base) invalid();
                $v = $v * $base + $a;
                $u = $u * $base + $b;
            } else {
                $q = index_char('1234', $code[$i + 5]);
                $u = 2 * $u + $q % 2;
                $v = 2 * $v + intdiv($q, 2);
            }
        }
        $scale = [1,8,80,160,320,640][$level];
        $x = $u + 280 * $scale;
        $y = $v + 135 * $scale;
    }
    [$w, $h] = grid($sys, $p);
    if ($x < 0 || $x >= $w || $y < 0 || $y >= $h || encode($sys, $p, $x, $y) !== $code) invalid();
    return [$p, $x, $y];
}
function point_cell(string $sys, int $p, int $lat, int $lon): array
{
    [$w, $h] = grid($sys, $p);
    return [intdiv(($lon + 180000000) * $w, 360000000), min(intdiv(($lat + 90000000) * $h, 180000000), $h - 1)];
}
function ancestor(string $sys, array $cell, int $q): array
{
    [$p, $x, $y] = $cell;
    [$w, $h] = grid($sys, $p);
    [$v, $u] = grid($sys, $q);
    return [$q, intdiv($x * $v, $w), intdiv($y * $u, $h)];
}
function cell_code(string $sys, array $cell): string { return encode($sys, ...$cell); }
function coord_text(int $v): string
{
    return ($v < 0 ? '-' : '') . intdiv(abs($v), 1000000) . '.' . sprintf('%06d', abs($v) % 1000000);
}
function decimal_suffix(int $e, int $n, int $d): string
{
    if ($d === 0) return '';
    return ' ' . substr(sprintf('%05d', $e % 100000), 0, $d) . ' ' . substr(sprintf('%05d', $n % 100000), 0, $d);
}
function square_digits(array $args, int $offset): array
{
    if (count($args) === $offset) return [0,0,100000];
    $a = $args[$offset];
    $b = $args[$offset + 1];
    if (!preg_match('/^[0-9]{1,5}$/D', $a) || !preg_match('/^[0-9]{1,5}$/D', $b) || strlen($a) !== strlen($b)) invalid();
    $size = 10 ** (5 - strlen($a));
    return [(int) $a * $size, (int) $b * $size, $size];
}
function compact_cells(string $sys, array $cells): array
{
    $set = [];
    foreach ($cells as $cell) $set[implode(':', $cell)] = $cell;
    do {
        $changed = false;
        foreach ($set as $key => $cell) {
            $index = array_search($cell[0], PRECS[$sys], true);
            for ($i = 0; $i < $index; ++$i) {
                if (isset($set[implode(':', ancestor($sys, $cell, PRECS[$sys][$i]))])) {
                    unset($set[$key]);
                    $changed = true;
                    break;
                }
            }
        }
        for ($index = count(PRECS[$sys]) - 1; $index >= 1; --$index) {
            [$p, $q] = [PRECS[$sys][$index], PRECS[$sys][$index - 1]];
            [$w, $h] = grid($sys, $p);
            [$v, $u] = grid($sys, $q);
            $needed = intdiv($w, $v) * intdiv($h, $u);
            $groups = [];
            foreach ($set as $key => $cell) {
                if ($cell[0] === $p) {
                    $parent = ancestor($sys, $cell, $q);
                    $pk = implode(':', $parent);
                    $groups[$pk]['parent'] = $parent;
                    $groups[$pk]['keys'][] = $key;
                }
            }
            foreach ($groups as $key => $group) {
                if (count($group['keys']) === $needed) {
                    foreach ($group['keys'] as $child) unset($set[$child]);
                    $set[$key] = $group['parent'];
                    $changed = true;
                }
            }
        }
    } while ($changed);
    $cells = array_values($set);
    usort($cells, fn($a, $b) => [$a[0], -$a[2], $a[1]] <=> [$b[0], -$b[2], $b[1]]);
    return $cells;
}
function execute(string $line): string
{
    $t = explode(' ', $line);
    $command = array_shift($t);
    $counts = ['ENCODE'=>[4], 'DECODE'=>[2], 'NEIGHBORS'=>[2], 'PARENT'=>[2], 'CHILDREN'=>[2], 'COMMON'=>[3], 'CONTAINS'=>[4], 'COVER'=>[6], 'CONVERT'=>[5], 'STEPS'=>[3], 'PATH'=>[3], 'RELATE'=>[4], 'SIZE'=>[2], 'SHORTEN'=>[3], 'RECOVER'=>[3], 'UTMZONE'=>[2], 'OSGB'=>[3], 'UNOSGB'=>[1,3], 'MGRS'=>[5], 'UNMGRS'=>[2,4], 'QUADKEY'=>[3], 'UNQUADKEY'=>[1]];
    if ($command === 'COMPACT') {
        if (count($t) < 2 || count($t) > 101) invalid();
    } elseif (!isset($counts[$command]) || !in_array(count($t), $counts[$command], true)) invalid();
    if ($command === 'UTMZONE') {
        $lat = coordinate($t[0], true);
        $lon = coordinate($t[1], false);
        if ($lat < -80000000 || $lat >= 84000000) return 'NONE';
        $band = BANDS[min(intdiv($lat + 80000000, 8000000), 19)];
        $zone = intdiv($lon + 180000000, 6000000) + 1;
        if ($band === 'V' && $lon >= 3000000 && $lon < 12000000) $zone = 32;
        if ($band === 'X' && $lon >= 0 && $lon < 42000000) {
            if ($lon < 9000000) $zone = 31;
            elseif ($lon < 21000000) $zone = 33;
            elseif ($lon < 33000000) $zone = 35;
            else $zone = 37;
        }
        return $zone . $band;
    }
    if ($command === 'OSGB') {
        $e = integer($t[0], 0, 699999);
        $n = integer($t[1], 0, 1299999);
        $d = integer($t[2], 0, 5);
        $letters = OS[5 * (3 - intdiv($n, 500000)) + 2 + intdiv($e, 500000)] . OS[5 * (4 - intdiv($n, 100000) % 5) + intdiv($e, 100000) % 5];
        return $letters . decimal_suffix($e, $n, $d);
    }
    if ($command === 'UNOSGB') {
        if (strlen($t[0]) !== 2) invalid();
        $a = index_char(OS, $t[0][0]);
        $b = index_char(OS, $t[0][1]);
        $e = 500000 * ($a % 5 - 2) + 100000 * ($b % 5);
        $n = 500000 * (3 - intdiv($a, 5)) + 100000 * (4 - intdiv($b, 5));
        if ($e < 0 || $e >= 700000 || $n < 0 || $n >= 1300000) invalid();
        [$de, $dn, $size] = square_digits($t, 1);
        return 'sw=' . ($e + $de) . ',' . ($n + $dn) . " size=$size";
    }
    if ($command === 'MGRS') {
        $zone = integer($t[0], 1, 60);
        if (strlen($t[1]) !== 1) invalid();
        index_char(BANDS, $t[1]);
        $e = integer($t[2], 100000, 899999);
        $n = integer($t[3], 0, 9999999);
        $d = integer($t[4], 0, 5);
        $letters = COLS[$zone % 3][intdiv($e, 100000) - 1] . ROWS[(intdiv($n, 100000) + ($zone % 2 === 0 ? 5 : 0)) % 20];
        return $zone . $t[1] . ' ' . $letters . decimal_suffix($e, $n, $d);
    }
    if ($command === 'UNMGRS') {
        if (!preg_match('/^([1-9][0-9]?)([CDEFGHJKLMNPQRSTUVWX])$/D', $t[0], $parts)) invalid();
        $zone = (int) $parts[1];
        if ($zone > 60 || strlen($t[1]) !== 2) invalid();
        $c = index_char(COLS[$zone % 3], $t[1][0]);
        $r = index_char(ROWS, $t[1][1]);
        $e = 100000 * ($c + 1);
        $n = 100000 * md($r - ($zone % 2 === 0 ? 5 : 0), 20);
        [$de, $dn, $size] = square_digits($t, 2);
        return $t[0] . ' sw=' . ($e + $de) . ',' . ($n + $dn) . " size=$size";
    }
    if ($command === 'QUADKEY') {
        $z = integer($t[2], 1, 23);
        $x = integer($t[0], 0, 2 ** $z - 1);
        $y = integer($t[1], 0, 2 ** $z - 1);
        $out = '';
        for ($i = $z - 1; $i >= 0; --$i) $out .= intdiv($x, 2 ** $i) % 2 + 2 * (intdiv($y, 2 ** $i) % 2);
        return $out;
    }
    if ($command === 'UNQUADKEY') {
        if (!preg_match('/^[0-3]{1,23}$/D', $t[0])) invalid();
        $x = 0;
        $y = 0;
        foreach (str_split($t[0]) as $char) {
            $v = (int) $char;
            $x = 2 * $x + $v % 2;
            $y = 2 * $y + intdiv($v, 2);
        }
        return "x=$x y=$y z=" . strlen($t[0]);
    }
    if ($command === 'SHORTEN' || $command === 'RECOVER') {
        $lat = coordinate($t[1], true);
        $lon = coordinate($t[2], false);
        if ($command === 'SHORTEN') {
            [$p, $x, $y] = decode('PLUSCODE', $t[0]);
            if ($p < 8) invalid();
            [$w, $h] = grid('PLUSCODE', $p);
            $dy = abs((-90000000 - $lat) * 2 * $h + 180000000 * (2 * $y + 1));
            $dx = abs((-180000000 - $lon) * 2 * $w + 360000000 * (2 * $x + 1));
            if ($dy < 15000 * 2 * $h && $dx < 15000 * 2 * $w) return substr($t[0], 6);
            if ($dy < 300000 * 2 * $h && $dx < 300000 * 2 * $w) return substr($t[0], 4);
            return $t[0];
        }
        if (!preg_match('/^([23456789CFGHJMPQRVWX]{2}|[23456789CFGHJMPQRVWX]{4})\+([23456789CFGHJMPQRVWX]{2,3})?$/D', $t[0])) invalid();
        $r = 8 - strpos($t[0], '+');
        [$px, $py] = point_cell('PLUSCODE', 10, $lat, $lon);
        $full = substr(encode('PLUSCODE', 10, $px, $py), 0, $r) . $t[0];
        [$p, $x, $y] = decode('PLUSCODE', $full);
        [$w, $h] = grid('PLUSCODE', $p);
        $d = $r === 4 ? 1000000 : 50000;
        $my = intdiv($d * $h, 180000000);
        $mx = intdiv($d * $w, 360000000);
        $cy = 180000000 * (2 * $y + 1);
        $cx = 360000000 * (2 * $x + 1);
        if (($lat + intdiv($d, 2) + 90000000) * 2 * $h < $cy && $cy >= $d * 2 * $h) $y -= $my;
        elseif (($lat - intdiv($d, 2) + 90000000) * 2 * $h > $cy && $cy <= (180000000 - $d) * 2 * $h) $y += $my;
        if (($lon + intdiv($d, 2) + 180000000) * 2 * $w < $cx) $x = md($x - $mx, $w);
        elseif (($lon - intdiv($d, 2) + 180000000) * 2 * $w > $cx) $x = md($x + $mx, $w);
        return encode('PLUSCODE', $p, $x, $y);
    }
    $sys = system_name($t[0]);
    if ($command === 'SIZE' || $command === 'ENCODE' || $command === 'COVER') {
        $p = precision($sys, $t[$command === 'ENCODE' ? 3 : 1]);
        [$w, $h] = grid($sys, $p);
        if ($command === 'SIZE') {
            $cells = $w * $h;
            if ($sys === 'MESH') {
                $scale = [1,8,80,160,320,640][array_search($p, PRECS[$sys], true)];
                $cells = 8000 * $scale * $scale;
            }
            return 'w=' . coord_text(intdiv(360000000, $w)) . ' h=' . coord_text(intdiv(180000000, $h)) . " cells=$cells";
        }
        if ($command === 'ENCODE') {
            [$x, $y] = point_cell($sys, $p, coordinate($t[1], true), coordinate($t[2], false));
            $code = encode($sys, $p, $x, $y);
            return $code === '-' ? 'OUT OF AREA' : $code;
        }
        $lat1 = coordinate($t[2], true);
        $lon1 = coordinate($t[3], false);
        $lat2 = coordinate($t[4], true);
        $lon2 = coordinate($t[5], false);
        if ($lat1 > $lat2) invalid();
        [$x1, $y1] = point_cell($sys, $p, $lat1, $lon1);
        [$x2, $y2] = point_cell($sys, $p, $lat2, $lon2);
        $columns = $lon1 <= $lon2 ? $x2 - $x1 + 1 : min($w, $x2 - $x1 + 1 + $w);
        if (($y2 - $y1 + 1) * $columns > 100) return 'TOO MANY';
        $codes = [];
        for ($y = $y2; $y >= $y1; --$y) {
            for ($i = 0; $i < $columns; ++$i) $codes[] = encode($sys, $p, ($x1 + $i) % $w, $y);
        }
        return implode(' ', $codes);
    }
    if ($command === 'COMPACT') {
        $cells = array_map(fn($code) => decode($sys, $code), array_slice($t, 1));
        return implode(' ', array_map(fn($cell) => cell_code($sys, $cell), compact_cells($sys, $cells)));
    }
    $cell = decode($sys, $t[1]);
    [$p, $x, $y] = $cell;
    [$w, $h] = grid($sys, $p);
    $index = array_search($p, PRECS[$sys], true);
    if ($command === 'DECODE') {
        $south = -90000000 + intdiv(180000000 * $y, $h);
        $west = -180000000 + intdiv(360000000 * $x, $w);
        $north = -90000000 + intdiv(180000000 * ($y + 1), $h);
        $east = -180000000 + intdiv(360000000 * ($x + 1), $w);
        $cy = -90000000 + intdiv(180000000 * (2 * $y + 1), 2 * $h);
        $cx = -180000000 + intdiv(360000000 * (2 * $x + 1), 2 * $w);
        return 'sw=' . coord_text($south) . ',' . coord_text($west) . ' ne=' . coord_text($north) . ',' . coord_text($east) . ' c=' . coord_text($cy) . ',' . coord_text($cx);
    }
    if ($command === 'CONTAINS') {
        [$a, $b] = point_cell($sys, $p, coordinate($t[2], true), coordinate($t[3], false));
        return $a === $x && $b === $y ? 'YES' : 'NO';
    }
    if ($command === 'NEIGHBORS') {
        $out = [];
        foreach ([[0,1],[1,1],[1,0],[1,-1],[0,-1],[-1,-1],[-1,0],[-1,1]] as [$dx, $dy]) {
            $out[] = $y + $dy < 0 || $y + $dy >= $h ? '-' : encode($sys, $p, md($x + $dx, $w), $y + $dy);
        }
        return implode(' ', $out);
    }
    if ($command === 'PARENT') return $index === 0 ? 'NONE' : cell_code($sys, ancestor($sys, $cell, PRECS[$sys][$index - 1]));
    if ($command === 'CHILDREN') {
        if ($index + 1 === count(PRECS[$sys])) return 'NONE';
        $q = PRECS[$sys][$index + 1];
        [$v, $u] = grid($sys, $q);
        $rx = intdiv($v, $w);
        $ry = intdiv($u, $h);
        if ($rx * $ry > 100) return 'TOO MANY';
        $out = [];
        for ($j = $ry - 1; $j >= 0; --$j) {
            for ($i = 0; $i < $rx; ++$i) $out[] = encode($sys, $q, $rx * $x + $i, $ry * $y + $j);
        }
        return implode(' ', $out);
    }
    if ($command === 'CONVERT') {
        if ($t[2] !== 'TO') invalid();
        $sys2 = system_name($t[3]);
        $q = precision($sys2, $t[4]);
        [$v, $u] = grid($sys2, $q);
        $code = encode($sys2, $q, intdiv((2 * $x + 1) * $v, 2 * $w), intdiv((2 * $y + 1) * $u, 2 * $h));
        return $code === '-' ? 'OUT OF AREA' : $code;
    }
    if ($command === 'RELATE') {
        $sys2 = system_name($t[2]);
        [$q, $a, $b] = decode($sys2, $t[3]);
        [$v, $u] = grid($sys2, $q);
        [$l1,$r1,$l2,$r2] = [$x*$v,($x+1)*$v,$a*$w,($a+1)*$w];
        [$s1,$n1,$s2,$n2] = [$y*$u,($y+1)*$u,$b*$h,($b+1)*$h];
        if ($l1 === $l2 && $r1 === $r2 && $s1 === $s2 && $n1 === $n2) return 'EQUAL';
        if ($l1 >= $l2 && $r1 <= $r2 && $s1 >= $s2 && $n1 <= $n2) return 'INSIDE';
        if ($l2 >= $l1 && $r2 <= $r1 && $s2 >= $s1 && $n2 <= $n1) return 'CONTAINS';
        if (max($l1,$l2) < min($r1,$r2) && max($s1,$s2) < min($n1,$n2)) return 'OVERLAP';
        $latitudeTouch = max($s1,$s2) <= min($n1,$n2);
        $dateLine = ($x === 0 && $a + 1 === $v) || ($a === 0 && $x + 1 === $w);
        if ($latitudeTouch && (max($l1,$l2) <= min($r1,$r2) || $dateLine)) return 'TOUCH';
        return 'DISJOINT';
    }
    $second = decode($sys, $t[2]);
    if ($command === 'COMMON') {
        $limit = min($index, array_search($second[0], PRECS[$sys], true));
        for ($i = $limit; $i >= 0; --$i) {
            $a = ancestor($sys, $cell, PRECS[$sys][$i]);
            if ($a === ancestor($sys, $second, PRECS[$sys][$i])) return cell_code($sys, $a);
        }
        return 'NONE';
    }
    if ($p !== $second[0]) return 'MISMATCH';
    $dx = md($second[1] - $x, $w);
    if (2 * $dx > $w) $dx -= $w;
    $dy = $second[2] - $y;
    if ($command === 'STEPS') return "dx=$dx dy=$dy";
    $n = max(abs($dx), abs($dy));
    if ($n + 1 > 100) return 'TOO MANY';
    if ($n === 0) return cell_code($sys, $cell);
    $out = [];
    for ($i = 0; $i <= $n; ++$i) $out[] = encode($sys, $p, md($x + fd(2 * $i * $dx + $n, 2 * $n), $w), $y + fd(2 * $i * $dy + $n, 2 * $n));
    return implode(' ', $out);
}
$count = (int) fgets(STDIN);
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        echo execute($line), "\n";
    } catch (InvalidArgumentException $error) {
        echo "INVALID\n";
    }
}
