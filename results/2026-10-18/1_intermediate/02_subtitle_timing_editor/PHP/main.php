<?php
const SCHEMAS = [
    'LIST' => '', 'VALIDATE' => '', 'SEARCH' => 'string', 'AT' => 'time', 'GAPS' => '0:60000',
    'STATS' => '', 'PRINT' => '', 'TOVTT' => '', 'TOASS' => '', 'FRAMES' => 'fps',
    'SHIFT' => 'signed', 'SHIFTFROM' => 'pos signed', 'SCALE' => '1:100000 1:100000',
    'SYNC' => 'pos time pos time', 'SNAP' => 'fps', 'FIXOVERLAP' => '0:60000', 'EXTEND' => '1:60000',
    'TIME' => 'pos time time', 'SORT' => '', 'RENUMBER' => '', 'MERGE' => '0:60000', 'SPLIT' => '10:80',
    'INSERT' => 'pos time time text', 'DELETE' => 'delete', 'TEXT' => 'pos text', 'BALANCE' => '',
    'STRIP' => '', 'CLEANHI' => '', 'REPLACE' => 'replace', 'UNDO' => ''
];
const MODIFYING = ['SHIFT', 'SHIFTFROM', 'SCALE', 'SYNC', 'SNAP', 'FIXOVERLAP', 'EXTEND', 'TIME',
    'SORT', 'RENUMBER', 'MERGE', 'SPLIT', 'INSERT', 'DELETE', 'TEXT', 'BALANCE', 'STRIP', 'CLEANHI', 'REPLACE'];
const FORMAT_TAGS = ['<i>' => '{\i1}', '</i>' => '{\i0}', '<b>' => '{\b1}',
    '</b>' => '{\b0}', '<u>' => '{\u1}', '</u>' => '{\u0}'];

function fail(string $message): never
{
    throw new InvalidArgumentException($message);
}

function floor_div(int $n, int $d): int
{
    $q = intdiv($n, $d);
    return $n < 0 && $n % $d !== 0 ? $q - 1 : $q;
}

function round_ratio(int $n, int $d): int
{
    return floor_div(2 * $n + $d, 2 * $d);
}

function char_count(array $cue): int
{
    return array_sum(array_map('strlen', $cue['lines']));
}

function dialogue(array $cue): bool
{
    foreach ($cue['lines'] as $line) {
        if (str_starts_with($line, '- ')) {
            return true;
        }
    }
    return false;
}

function cue_words(array $lines): array
{
    return array_values(array_filter(explode(' ', implode(' ', $lines)), fn($word) => $word !== ''));
}

function two_decimal(int $value): string
{
    return sprintf('%d.%02d', intdiv($value, 100), $value % 100);
}

function time_value(string $text): int
{
    if (preg_match('/^([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})$/D', $text, $m) !== 1) {
        fail('bad arguments');
    }
    if ((int) $m[2] > 59 || (int) $m[3] > 59) {
        fail('bad arguments');
    }
    return (int) $m[1] * 3600000 + (int) $m[2] * 60000 + (int) $m[3] * 1000 + (int) $m[4];
}

function time_text(int $t, string $kind = 'SRT'): string
{
    if ($kind === 'ASS') {
        $c = intdiv($t + 5, 10);
        return sprintf('%d:%02d:%02d.%02d', intdiv($c, 360000), intdiv($c, 6000) % 60, intdiv($c, 100) % 60, $c % 100);
    }
    return sprintf('%02d:%02d:%02d%s%03d', intdiv($t, 3600000), intdiv($t, 60000) % 60, intdiv($t, 1000) % 60,
        $kind === 'VTT' ? '.' : ',', $t % 1000);
}

function unsigned_arg(string $text, int $low = 0, int $high = 999999999): int
{
    if (preg_match('/^[0-9]{1,9}$/D', $text) !== 1) {
        fail('bad arguments');
    }
    $value = (int) $text;
    if ($value < $low || $value > $high) {
        fail('bad arguments');
    }
    return $value;
}

function typed_arg(string $text, string $kind): mixed
{
    if ($kind === 'string') {
        return $text;
    }
    if ($kind === 'time') {
        return time_value($text);
    }
    if ($kind === 'pos') {
        return unsigned_arg($text, 1);
    }
    if ($kind === 'signed') {
        if (preg_match('/^-?[0-9]{1,9}$/D', $text) !== 1) {
            fail('bad arguments');
        }
        return (int) $text;
    }
    if ($kind === 'fps') {
        $parts = explode('/', $text);
        if (count($parts) > 2) {
            fail('bad arguments');
        }
        return [unsigned_arg($parts[0], 1, 100000), count($parts) === 1 ? 1 : unsigned_arg($parts[1], 1, 100000)];
    }
    if ($kind === 'text' || $kind === 'replace') {
        $parts = explode('|', $text);
        if (in_array('', $parts, true) || ($kind === 'replace' && count($parts) !== 2)) {
            fail('bad arguments');
        }
        return $parts;
    }
    [$low, $high] = array_map('intval', explode(':', $kind));
    return unsigned_arg($text, $low, $high);
}

function arguments(string $line, array $cues): array
{
    $command = explode(' ', $line, 2)[0];
    if (!array_key_exists($command, SCHEMAS)) {
        fail('unknown command');
    }
    if ($command === 'DELETE') {
        $raw = array_slice(explode(' ', $line), 1);
        if (count($raw) < 1 || count($raw) > 2) {
            fail('bad arguments');
        }
        $args = array_map(fn($text) => unsigned_arg($text, 1), $raw);
        if (count($args) === 2 && $args[1] < $args[0]) {
            fail('bad arguments');
        }
        $kinds = array_fill(0, count($args), 'pos');
    } else {
        $kinds = SCHEMAS[$command] === '' ? [] : explode(' ', SCHEMAS[$command]);
        $last = $kinds[count($kinds) - 1] ?? '';
        $parts = in_array($last, ['string', 'text', 'replace'], true)
            ? explode(' ', $line, count($kinds) + 1) : explode(' ', $line);
        if (count($parts) !== count($kinds) + 1) {
            fail('bad arguments');
        }
        $args = [];
        foreach ($kinds as $i => $kind) {
            $args[] = typed_arg($parts[$i + 1], $kind);
        }
    }
    foreach ($kinds as $i => $kind) {
        if ($kind === 'pos' && $args[$i] > count($cues) + ($command === 'INSERT' ? 1 : 0)) {
            fail('no cue ' . $args[$i]);
        }
    }
    if ($command === 'SYNC' && $cues[$args[0] - 1]['start'] === $cues[$args[2] - 1]['start']) {
        fail('sync points coincide');
    }
    return [$command, $args];
}

function wrap_lines(array $lines, int $width): array
{
    $output = [];
    foreach (cue_words($lines) as $word) {
        $last = count($output) - 1;
        if ($last >= 0 && strlen($output[$last]) + 1 + strlen($word) <= $width) {
            $output[$last] .= ' ' . $word;
        } else {
            $output[] = $word;
        }
    }
    return $output;
}

function markup(string $line): array
{
    $items = [];
    $p = 0;
    while ($p < strlen($line)) {
        $tag = null;
        foreach (FORMAT_TAGS as $text => $replacement) {
            if (substr($line, $p, strlen($text)) === $text) {
                $tag = $text;
                break;
            }
        }
        $rest = substr($line, $p);
        if ($tag !== null) {
            $items[] = ['format', $tag, 0];
            $p += strlen($tag);
        } elseif (str_starts_with($rest, '</font>')) {
            $items[] = ['font', '</font>', 0];
            $p += 7;
        } elseif (str_starts_with($rest, '<font') && in_array($line[$p + 5] ?? '', [' ', '>'], true)
            && ($ending = strpos($line, '>', $p + 5)) !== false) {
            $items[] = ['font', substr($line, $p, $ending - $p + 1), 0];
            $p = $ending + 1;
        } elseif (substr($line, $p, 4) === '{\an' && ($line[$p + 4] ?? '') >= '1'
            && ($line[$p + 4] ?? '') <= '9' && ($line[$p + 5] ?? '') === '}') {
            $items[] = ['position', substr($line, $p, 6), (int) $line[$p + 4]];
            $p += 6;
        } else {
            $items[] = ['ordinary', $line[$p], 0];
            ++$p;
        }
    }
    return $items;
}

function converted_line(string $line, string $mode): array
{
    $output = '';
    $tags = 0;
    $position = 0;
    foreach (markup($line) as [$kind, $text, $digit]) {
        if ($kind !== 'ordinary') {
            ++$tags;
        }
        if ($kind === 'position' && $position === 0) {
            $position = $digit;
        }
        if ($kind === 'ordinary') {
            $output .= $mode === 'VTT' ? strtr($text, ['&' => '&amp;', '<' => '&lt;', '>' => '&gt;']) : $text;
        } elseif ($mode === 'VTT' && $kind === 'format') {
            $output .= $text;
        } elseif ($mode === 'ASS' && $kind === 'format') {
            $output .= FORMAT_TAGS[$text];
        } elseif ($mode === 'ASS' && $kind === 'position') {
            $output .= $text;
        }
    }
    return [$mode === 'ASS' ? $output : trim($output, ' '), $tags, $position];
}

function clean_hi(string $line): array
{
    $output = '';
    $segments = 0;
    $p = 0;
    while ($p < strlen($line)) {
        $closing = match ($line[$p]) {
            '[' => ']', '(' => ')', default => null
        };
        $ending = $closing === null ? false : strpos($line, $closing, $p + 1);
        if ($ending !== false) {
            ++$segments;
            $p = $ending + 1;
        } else {
            $output .= $line[$p];
            ++$p;
        }
    }
    $normalize = fn($text) => trim(preg_replace('/ +/', ' ', $text), ' ');
    $result = $normalize($output);
    $prefix = str_starts_with($result, '- ') ? '- ' : '';
    $body = $prefix === '' ? $result : substr($result, 2);
    $labels = preg_match('/^[A-Z][A-Z0-9 ]*:/', $body, $matches);
    if ($labels === 1) {
        $result = $normalize($prefix . substr($body, strlen($matches[0])));
    }
    return [$result, $segments, $labels];
}

function list_line(array $cue, int $p): string
{
    return "$p $cue[index] " . time_text($cue['start']) . ' ' . time_text($cue['stop']) . ' ' . implode('|', $cue['lines']);
}

function inspect(string $command, array $args, array $cues): array
{
    $output = [];
    $n = count($cues);
    if ($command === 'LIST' || $command === 'AT') {
        foreach ($cues as $i => $cue) {
            if ($command === 'LIST' || ($cue['start'] <= $args[0] && $args[0] < $cue['stop'])) {
                $output[] = list_line($cue, $i + 1);
            }
        }
        if ($command === 'AT') {
            $output[] = 'AT active=' . count($output);
        }
    } elseif ($command === 'VALIDATE') {
        foreach ($cues as $i => $cue) {
            $p = $i + 1;
            $d = $cue['stop'] - $cue['start'];
            if ($cue['index'] !== $p) {
                $output[] = "cue $p: index $cue[index] (expected $p)";
            }
            if ($d <= 0) {
                $output[] = "cue $p: end not after start";
            }
            if ($i > 0 && $cue['start'] < $cues[$i - 1]['stop']) {
                $output[] = "cue $p: overlaps previous by " . ($cues[$i - 1]['stop'] - $cue['start']) . ' ms';
            }
            if ($d >= 1 && $d < 700) {
                $output[] = "cue $p: too short ($d ms)";
            } elseif ($d > 7000) {
                $output[] = "cue $p: too long ($d ms)";
            }
            foreach ($cue['lines'] as $j => $line) {
                if (strlen($line) > 42) {
                    $output[] = "cue $p: line " . ($j + 1) . ' too long (' . strlen($line) . ' chars)';
                }
            }
            if (count($cue['lines']) >= 3) {
                $output[] = "cue $p: too many lines (" . count($cue['lines']) . ')';
            }
            if ($d >= 1 && char_count($cue) * 1000 > 21 * $d) {
                $output[] = "cue $p: too fast (" . two_decimal(intdiv(char_count($cue) * 100000, $d)) . ' cps)';
            }
        }
        $output[] = 'VALIDATE problems=' . count($output);
    } elseif ($command === 'SEARCH') {
        foreach ($cues as $i => $cue) {
            foreach ($cue['lines'] as $line) {
                if (str_contains($line, $args[0])) {
                    $output[] = ($i + 1) . ' ' . time_text($cue['start']) . ' ' . $line;
                    break;
                }
            }
        }
        $output[] = 'SEARCH found=' . count($output);
    } elseif ($command === 'GAPS') {
        for ($i = 0; $i + 1 < $n; ++$i) {
            $gap = $cues[$i + 1]['start'] - $cues[$i]['stop'];
            if ($gap < $args[0]) {
                $output[] = ($i + 1) . ' ' . ($i + 2) . " $gap";
            }
        }
        $output[] = 'GAPS count=' . count($output);
    } elseif ($command === 'STATS') {
        $output[] = "STATS cues=$n";
        if ($n === 0) {
            return $output;
        }
        $durations = array_map(fn($cue) => max(0, $cue['stop'] - $cue['start']), $cues);
        $total = array_sum($durations);
        $characters = 0;
        foreach ($cues as $i => $cue) {
            if ($durations[$i] > 0) {
                $characters += char_count($cue);
            }
        }
        $output[] = 'duration total=' . time_text($total) . ' mean=' . time_text(intdiv($total, $n));
        $output[] = $total === 0 ? 'speed -' : 'speed ' . two_decimal(intdiv($characters * 100000, $total));
        $i = array_search(max($durations), $durations, true);
        $output[] = 'longest cue=' . ($i + 1) . ' duration=' . time_text($durations[$i]);
        if ($n === 1) {
            $output[] = 'gap none';
        } else {
            $gaps = [];
            for ($i = 0; $i + 1 < $n; ++$i) {
                $gaps[] = $cues[$i + 1]['start'] - $cues[$i]['stop'];
            }
            $i = array_search(max($gaps), $gaps, true);
            $output[] = 'gap cue=' . ($i + 1) . ' ms=' . $gaps[$i];
        }
    } elseif ($command === 'PRINT') {
        foreach ($cues as $cue) {
            $output = [...$output, (string) $cue['index'], time_text($cue['start']) . ' --> ' . time_text($cue['stop']), ...$cue['lines'], ''];
        }
    } elseif ($command === 'TOVTT') {
        $output = ['WEBVTT', ''];
        foreach ($cues as $cue) {
            $lines = [];
            $position = 0;
            foreach ($cue['lines'] as $line) {
                [$text, $tags, $digit] = converted_line($line, 'VTT');
                if ($position === 0 && $digit > 0) {
                    $position = $digit;
                }
                if ($text !== '') {
                    $lines[] = $text;
                }
            }
            if ($lines === []) {
                continue;
            }
            $settings = '';
            if ($position >= 7) {
                $settings .= ' line:0';
            } elseif ($position >= 4) {
                $settings .= ' line:50%';
            }
            if (in_array($position, [1, 4, 7], true)) {
                $settings .= ' align:start';
            } elseif (in_array($position, [3, 6, 9], true)) {
                $settings .= ' align:end';
            }
            $output = [...$output, (string) $cue['index'], time_text($cue['start'], 'VTT') . ' --> ' . time_text($cue['stop'], 'VTT') . $settings, ...$lines, ''];
        }
    } elseif ($command === 'TOASS') {
        $output = ['[Events]', 'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text'];
        foreach ($cues as $cue) {
            $text = implode('\N', array_map(fn($line) => converted_line($line, 'ASS')[0], $cue['lines']));
            $output[] = 'Dialogue: 0,' . time_text($cue['start'], 'ASS') . ',' . time_text($cue['stop'], 'ASS') . ',Default,,0,0,0,,' . $text;
        }
    } elseif ($command === 'FRAMES') {
        [$a, $b] = $args[0];
        foreach ($cues as $i => $cue) {
            $output[] = ($i + 1) . ' ' . intdiv($cue['start'] * $a, 1000 * $b) . ' ' . intdiv($cue['stop'] * $a, 1000 * $b);
        }
    }
    return $output;
}

function modify(string $command, array $args, array $cues): array
{
    $output = [];
    $n = count($cues);
    if (in_array($command, ['SHIFT', 'SHIFTFROM', 'SCALE', 'SYNC', 'SNAP'], true)) {
        $first = $command === 'SHIFTFROM' ? $args[0] - 1 : 0;
        $clamped = 0;
        $changed = 0;
        if ($command === 'SYNC') {
            [$p1, $t1, $p2, $t2] = $args;
            $s1 = $cues[$p1 - 1]['start'];
            $den = $cues[$p2 - 1]['start'] - $s1;
            $transform = function($t) use ($t1, $t2, $s1, $den) {
                $num = $t1 * $den + ($t - $s1) * ($t2 - $t1);
                return $den > 0 ? round_ratio($num, $den) : round_ratio(-$num, -$den);
            };
        } elseif ($command === 'SCALE') {
            $transform = fn($t) => round_ratio($t * $args[0], $args[1]);
        } elseif ($command === 'SNAP') {
            [$a, $b] = $args[0];
            $transform = fn($t) => round_ratio(round_ratio($t * $a, 1000 * $b) * 1000 * $b, $a);
        } else {
            $delta = $command === 'SHIFT' ? $args[0] : $args[1];
            $transform = fn($t) => $t + $delta;
        }
        for ($i = $first; $i < $n; ++$i) {
            $start = $transform($cues[$i]['start']);
            $stop = $transform($cues[$i]['stop']);
            $clamped += $start < 0 || $stop < 0 ? 1 : 0;
            $start = max(0, $start);
            $stop = max(0, $stop);
            $changed += ($start !== $cues[$i]['start'] ? 1 : 0) + ($stop !== $cues[$i]['stop'] ? 1 : 0);
            $cues[$i]['start'] = $start;
            $cues[$i]['stop'] = $stop;
        }
        if ($command === 'SNAP') {
            $output[] = "SNAP changed=$changed";
        } elseif ($command === 'SCALE') {
            $output[] = "SCALE cues=$n";
        } else {
            $output[] = "$command cues=" . ($n - $first) . " clamped=$clamped";
        }
    } elseif ($command === 'FIXOVERLAP') {
        $fixed = 0;
        $failed = 0;
        for ($i = 0; $i + 1 < $n; ++$i) {
            $candidate = $cues[$i + 1]['start'] - $args[0];
            if ($cues[$i]['stop'] > $candidate) {
                if ($candidate > $cues[$i]['start']) {
                    $cues[$i]['stop'] = $candidate;
                    ++$fixed;
                } else {
                    $output[] = 'cue ' . ($i + 1) . ': cannot fix';
                    ++$failed;
                }
            }
        }
        $output[] = "FIXOVERLAP fixed=$fixed failed=$failed";
    } elseif ($command === 'EXTEND') {
        $extended = 0;
        foreach ($cues as $i => $cue) {
            if ($cue['stop'] - $cue['start'] < $args[0]) {
                $candidate = $cue['start'] + $args[0];
                if ($i + 1 < $n) {
                    $candidate = min($candidate, $cues[$i + 1]['start']);
                }
                if ($candidate > $cue['stop']) {
                    $cues[$i]['stop'] = $candidate;
                    ++$extended;
                }
            }
        }
        $short = count(array_filter($cues, fn($cue) => $cue['stop'] - $cue['start'] < $args[0]));
        $output[] = "EXTEND extended=$extended short=$short";
    } elseif ($command === 'TIME') {
        [$p, $start, $stop] = $args;
        $cues[$p - 1]['start'] = $start;
        $cues[$p - 1]['stop'] = $stop;
        $output[] = "TIME cue=$p";
    } elseif ($command === 'SORT') {
        foreach ($cues as $i => $cue) {
            $cues[$i]['original'] = $i;
        }
        usort($cues, fn($a, $b) => [$a['start'], $a['stop'], $a['original']] <=> [$b['start'], $b['stop'], $b['original']]);
        $moved = 0;
        foreach ($cues as $i => $cue) {
            $moved += $cue['original'] !== $i ? 1 : 0;
            unset($cues[$i]['original']);
        }
        $output[] = "SORT moved=$moved";
    } elseif ($command === 'RENUMBER') {
        $changed = 0;
        foreach ($cues as $i => $cue) {
            $changed += $cue['index'] !== $i + 1 ? 1 : 0;
            $cues[$i]['index'] = $i + 1;
        }
        $output[] = "RENUMBER changed=$changed";
    } elseif ($command === 'MERGE') {
        $result = [];
        $merged = 0;
        foreach ($cues as $cue) {
            $last = count($result) - 1;
            if ($last >= 0 && $cue['start'] - $result[$last]['stop'] < $args[0] && !dialogue($result[$last]) && !dialogue($cue)) {
                $lines = wrap_lines([...$result[$last]['lines'], ...$cue['lines']], 42);
                if (count($lines) <= 2) {
                    $result[$last]['stop'] = max($result[$last]['stop'], $cue['stop']);
                    $result[$last]['lines'] = $lines;
                    ++$merged;
                    continue;
                }
            }
            $result[] = $cue;
        }
        $cues = $result;
        $output[] = "MERGE merged=$merged cues=" . count($cues);
    } elseif ($command === 'SPLIT') {
        $result = [];
        $split = 0;
        foreach ($cues as $cue) {
            $duration = $cue['stop'] - $cue['start'];
            if ($duration <= 0 || dialogue($cue)) {
                $result[] = $cue;
                continue;
            }
            $lines = wrap_lines($cue['lines'], $args[0]);
            if (count($lines) <= 2) {
                $cue['lines'] = $lines;
                $result[] = $cue;
                continue;
            }
            $parts = array_chunk($lines, 2);
            $weights = array_map(fn($part) => array_sum(array_map('strlen', $part)), $parts);
            $total = array_sum($weights);
            $allotted = array_map(fn($weight) => intdiv($duration * $weight, $total), $weights);
            $order = array_keys($parts);
            usort($order, function($a, $b) use ($duration, $weights, $total) {
                $ra = $duration * $weights[$a] % $total;
                $rb = $duration * $weights[$b] % $total;
                return $ra === $rb ? $a <=> $b : $rb <=> $ra;
            });
            $remaining = $duration - array_sum($allotted);
            for ($i = 0; $i < $remaining; ++$i) {
                ++$allotted[$order[$i]];
            }
            $start = $cue['start'];
            foreach ($parts as $i => $part) {
                $result[] = ['index' => $cue['index'], 'start' => $start, 'stop' => $start + $allotted[$i], 'lines' => $part];
                $start += $allotted[$i];
            }
            ++$split;
        }
        $cues = $result;
        $output[] = "SPLIT split=$split cues=" . count($cues);
    } elseif ($command === 'INSERT') {
        [$p, $start, $stop, $lines] = $args;
        array_splice($cues, $p - 1, 0, [['index' => $p, 'start' => $start, 'stop' => $stop, 'lines' => $lines]]);
        $output[] = "INSERT cue=$p cues=" . count($cues);
    } elseif ($command === 'DELETE') {
        $p = $args[0];
        $q = $args[1] ?? $p;
        array_splice($cues, $p - 1, $q - $p + 1);
        $output[] = 'DELETE removed=' . ($q - $p + 1) . ' cues=' . count($cues);
    } elseif ($command === 'TEXT') {
        [$p, $lines] = $args;
        $cues[$p - 1]['lines'] = $lines;
        $output[] = "TEXT cue=$p lines=" . count($lines);
    } elseif ($command === 'BALANCE') {
        $changed = 0;
        $skipped = 0;
        $dialogues = 0;
        foreach ($cues as $i => $cue) {
            if (dialogue($cue)) {
                ++$dialogues;
                continue;
            }
            $words = cue_words($cue['lines']);
            $text = implode(' ', $words);
            $candidate = null;
            $best = [PHP_INT_MAX, PHP_INT_MAX];
            if (strlen($text) <= 42) {
                $candidate = [$text];
            } else {
                for ($j = 1; $j < count($words); ++$j) {
                    $left = implode(' ', array_slice($words, 0, $j));
                    $right = implode(' ', array_slice($words, $j));
                    $key = [abs(strlen($left) - strlen($right)), strlen($left)];
                    if (strlen($left) <= 42 && strlen($right) <= 42 && $key < $best) {
                        $candidate = [$left, $right];
                        $best = $key;
                    }
                }
            }
            if ($candidate === null) {
                ++$skipped;
            } else {
                $changed += $cue['lines'] !== $candidate ? 1 : 0;
                $cues[$i]['lines'] = $candidate;
            }
        }
        $output[] = "BALANCE changed=$changed skipped=$skipped dialogue=$dialogues";
    } elseif ($command === 'STRIP' || $command === 'CLEANHI') {
        $result = [];
        $tags = 0;
        $labels = 0;
        $removedLines = 0;
        $removedCues = 0;
        foreach ($cues as $cue) {
            $lines = [];
            foreach ($cue['lines'] as $line) {
                if ($command === 'STRIP') {
                    [$text, $count] = converted_line($line, 'STRIP');
                    $tags += $count;
                } else {
                    [$text, $count, $speakers] = clean_hi($line);
                    $tags += $count;
                    $labels += $speakers;
                }
                if ($text === '' || ($command === 'CLEANHI' && $text === '-')) {
                    ++$removedLines;
                } else {
                    $lines[] = $text;
                }
            }
            if ($lines === []) {
                ++$removedCues;
            } else {
                $cue['lines'] = $lines;
                $result[] = $cue;
            }
        }
        $cues = $result;
        $prefix = $command === 'STRIP' ? "STRIP tags=$tags" : "CLEANHI segments=$tags labels=$labels";
        $output[] = "$prefix removed_lines=$removedLines removed_cues=$removedCues";
    } elseif ($command === 'REPLACE') {
        [$old, $new] = $args[0];
        $replacements = 0;
        $changed = 0;
        foreach ($cues as $i => $cue) {
            $local = 0;
            foreach ($cue['lines'] as $j => $line) {
                $cues[$i]['lines'][$j] = str_replace($old, $new, $line, $count);
                $local += $count;
            }
            $replacements += $local;
            $changed += $local > 0 ? 1 : 0;
        }
        $output[] = "REPLACE count=$replacements cues=$changed";
    }
    return [$cues, $output];
}

function load_block(array $block, int $k, array &$cues): ?string
{
    if (preg_match('/^[0-9]{1,6}$/D', $block[0]) !== 1) {
        return "BAD CUE $k: index";
    }
    try {
        if (!isset($block[1]) || strlen($block[1]) !== 29 || substr($block[1], 12, 5) !== ' --> ') {
            fail('bad arguments');
        }
        $start = time_value(substr($block[1], 0, 12));
        $stop = time_value(substr($block[1], 17, 12));
    } catch (InvalidArgumentException $exception) {
        return "BAD CUE $k: time";
    }
    if (count($block) < 3) {
        return "BAD CUE $k: no text";
    }
    $cues[] = ['index' => (int) $block[0], 'start' => $start, 'stop' => $stop, 'lines' => array_slice($block, 2)];
    return null;
}

$cues = [];
$block = [];
$blocks = 0;
$bad = 0;
while (true) {
    $line = rtrim(fgets(STDIN), "\r\n");
    if ($line === '' || $line === '###') {
        if ($block !== []) {
            $problem = load_block($block, ++$blocks, $cues);
            if ($problem !== null) {
                echo $problem, "\n";
                ++$bad;
            }
            $block = [];
        }
        if ($line === '###') {
            break;
        }
    } else {
        $block[] = $line;
    }
}
echo 'LOAD cues=', count($cues), " bad=$bad\n";
$history = [];
$count = (int) fgets(STDIN);
for ($i = 0; $i < $count; ++$i) {
    $line = rtrim(fgets(STDIN), "\r\n");
    try {
        [$command, $args] = arguments($line, $cues);
        if ($command === 'UNDO') {
            if ($history === []) {
                fail('nothing to undo');
            }
            [$previous, $cues] = array_pop($history);
            $output = ["UNDO command=$previous"];
        } elseif (in_array($command, MODIFYING, true)) {
            $history[] = [$command, $cues];
            [$cues, $output] = modify($command, $args, $cues);
        } else {
            $output = inspect($command, $args, $cues);
        }
        foreach ($output as $line) {
            echo $line, "\n";
        }
    } catch (InvalidArgumentException $exception) {
        echo 'ERROR ', $exception->getMessage(), "\n";
    }
}
