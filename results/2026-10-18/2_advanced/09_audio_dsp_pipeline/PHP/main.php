<?php
require_once __DIR__ . '/signals.php';
require_once __DIR__ . '/effects.php';
require_once __DIR__ . '/filters.php';
require_once __DIR__ . '/dynamics.php';
require_once __DIR__ . '/analysis.php';

final class CommandError extends RuntimeException {}
final class ArgumentSpec {
    public function __construct(public string $name, public int|string|null $low = null, public int|string|null $high = null) {}
}
final class CommandSpec {
    public function __construct(public array $fixed, public array $repeated = [], public int $minimum = 0, public int $maximum = 0) {}
    public function accepts(int $count): bool {
        $extra = $count - count($this->fixed); $size = count($this->repeated);
        return $size === 0 ? $extra === 0 : $extra >= $this->minimum * $size && $extra <= $this->maximum * $size && $extra % $size === 0;
    }
    public function argument(int $index): ArgumentSpec { return $index < count($this->fixed) ? $this->fixed[$index] : $this->repeated[($index - count($this->fixed)) % count($this->repeated)]; }
}
function argument(string $name, int|string|null $low = null, int|string|null $high = null): ArgumentSpec { return new ArgumentSpec($name, $low, $high); }
function commands(): array {
    $dst = argument('dst'); $src = argument('src'); $rate = argument('rate', 1000, 48000); $count = argument('count', 1, 20000);
    $num = argument('num', -65536, 65536); $den = argument('den', 1, 65536); $attack = argument('attack', 1, 32768); $release = argument('release', 1, 32768);
    $minHz = argument('min_hz', 1, 'rate div 2 - 1'); $maxHz = argument('max_hz', 'min_hz + 1', 'rate div 2'); $start = argument('start', 0, 'L - 1');
    $test = [$dst, $rate, $count, argument('pos', 0, 'count - 1'), argument('amp', -32768, 32767)];
    $section = array_map(fn($name) => argument($name, -65536, 65536), ['b0', 'b1', 'b2', 'a1', 'a2']);
    return [
        'SET' => new CommandSpec([argument('var'), argument('value', -10000000, 10000000)], [argument('op'), argument('operand', -10000000, 10000000)], 0, 1),
        'IMPULSE' => new CommandSpec($test), 'STEP' => new CommandSpec($test), 'NOISE' => new CommandSpec([$dst, $rate, $count, argument('seed', 1, 2147483646)]),
        'GAIN' => new CommandSpec([$dst, $src, $num, $den]), 'MIX' => new CommandSpec([$dst, $den], [$src, argument('weight', -65536, 65536)], 1, 8),
        'DELAY' => new CommandSpec([$dst, $src, argument('samples', 0, 20000)]), 'ECHO' => new CommandSpec([$dst, $src, argument('delay', 1, 20000), $num, $den, argument('tail', 0, 20000)]),
        'RESAMPLE' => new CommandSpec([$dst, $src, argument('new_rate', 1000, 48000)]), 'FADE' => new CommandSpec([$dst, $src, argument('in', 0, 'L'), argument('out', 0, 'L')]),
        'TRIM' => new CommandSpec([$dst, $src, $start, argument('count', 1, 'L - start')]), 'CONCAT' => new CommandSpec([$dst], [$src], 2, 8),
        'FIR' => new CommandSpec([$dst, $src, argument('divisor', 1, 1000000)], [argument('tap', -32768, 32767)], 1, 64), 'BIQUAD' => new CommandSpec([$dst, $src], $section, 1, 4),
        'MOVAVG' => new CommandSpec([$dst, $src, argument('width', 1, 1000)]), 'DCBLOCK' => new CommandSpec([$dst, $src, argument('num', 0, 65535), argument('den', 'num + 1', 65536)]),
        'NORMALIZE' => new CommandSpec([$dst, $src, argument('target', 1, 32767)]), 'GATE' => new CommandSpec([$dst, $src, argument('threshold', 1, 32768), argument('hold', 0, 20000)]),
        'ENVELOPE' => new CommandSpec([$dst, $src, $attack, $release]), 'COMPRESS' => new CommandSpec([$dst, $src, argument('threshold', 1, 32767), argument('ratio_num', 1, 100), argument('ratio_den', 1, 'ratio_num'), $attack, $release]),
        'ANALYZE' => new CommandSpec([$src, $minHz, $maxHz]), 'COMPARE' => new CommandSpec([$src, $src]),
        'EXPECT' => new CommandSpec([$src, argument('metric'), argument('op'), argument('value', -1000000000, 1000000000)]),
        'SEGMENTS' => new CommandSpec([$src, argument('threshold', 1, 32768), argument('gap', 1, 20000), argument('min_length', 1, 20000)]),
        'ONSETS' => new CommandSpec([$src, $attack, $release, argument('threshold', 1, 32767), argument('min_gap', 1, 20000)]),
        'PITCHTRACK' => new CommandSpec([$src, argument('frame', 16, 'L'), argument('hop', 1, 'frame'), $minHz, $maxHz, argument('threshold', 0, 32767)]),
        'EXCERPT' => new CommandSpec([$src, $start, argument('count', 1, 1000)]),
        'PLOT' => new CommandSpec([$src, $start, argument('count', 1, 'L - start'), argument('columns', 8, 'min(120, count)'), argument('half', 2, 20), $attack, $release]),
        'METER' => new CommandSpec([$src, argument('block', 1, 20000)]), 'HISTOGRAM' => new CommandSpec([$src, argument('bins', 2, 64)]), 'TRACE' => new CommandSpec([$src]), 'SAVE' => new CommandSpec([$src]),
    ];
}
function resolveBound(int|string $bound, array $known, ?Signal $source): int {
    if (is_int($bound)) return $bound;
    return match ($bound) {
        'count - 1' => $known['count'] - 1, 'min(120, count)' => min(120, $known['count']), 'min_hz + 1' => $known['min_hz'] + 1, 'num + 1' => $known['num'] + 1,
        'L' => count($source->samples), 'L - 1' => count($source->samples) - 1, 'L - start' => count($source->samples) - $known['start'],
        'rate div 2' => intdiv($source->rate, 2), 'rate div 2 - 1' => intdiv($source->rate, 2) - 1, default => $known[$bound],
    };
}
function sameRate(array $sources): void { foreach ($sources as $source) if ($source->rate !== $sources[0]->rate) throw new CommandError('rate mismatch'); }
function milliseconds(int $index, int $rate): int { return intdiv($index * 1000, $rate); }
function twoDecimals(int $value): string { return intdiv($value, 100) . '.' . str_pad((string)($value % 100), 2, '0', STR_PAD_LEFT); }
function frequencyText(int $rate, int $lag): string { return twoDecimals(rdiv(100 * $rate, $lag)); }
function lagRange(int $rate, int $minHz, int $maxHz): array { return [intdiv($rate + $maxHz - 1, $maxHz), intdiv($rate, $minHz)]; }
function metricValue(array $samples, string $metric): int {
    return match ($metric) { 'samples' => count($samples), 'peak' => peak($samples), 'rms' => rms($samples), 'sum' => array_sum($samples), 'zero_crossings' => zeroCrossings($samples), 'clipped' => countClipped($samples) };
}
function waveformPlot(Signal $source, int $start, int $count, int $columns, int $half, int $attack, int $release): array {
    $window = array_slice($source->samples, $start, $count); $levels = array_slice(envelope($source->samples, $attack, $release), $start, $count); $rows = 2 * $half + 1; $scale = max(1, peak($window));
    $grid = array_fill(0, $rows, array_fill(0, $columns, ' ')); $rowOf = fn($value) => rdiv(($scale - $value) * ($rows - 1), 2 * $scale);
    for ($c = 0; $c < $columns; $c++) {
        $first = intdiv($c * $count, $columns); $last = intdiv(($c + 1) * $count, $columns); $part = array_slice($window, $first, $last - $first);
        $top = $rowOf(max($part)); $bottom = $rowOf(min($part)); $level = min($scale, max(array_slice($levels, $first, $last - $first))); $upper = $rowOf($level); $lower = $rowOf(-$level);
        for ($r = 0; $r < $rows; $r++) $grid[$r][$c] = $r === $upper || $r === $lower ? '*' : ($top <= $r && $r <= $bottom ? '#' : ($r === $half ? '-' : ' '));
    }
    $lines = ["PLOT $source->name rate=$source->rate start=$start count=$count columns=$columns rows=$rows scale=$scale attack=$attack release=$release"];
    for ($r = 0; $r < $rows; $r++) { $label = $r === 0 ? (string)$scale : ($r === $half ? '0' : ($r === $rows - 1 ? (string)-$scale : '')); $lines[] = str_pad($label, 6, ' ', STR_PAD_LEFT) . ' |' . implode('', $grid[$r]) . '|'; }
    $axis = ''; for ($c = 0; $c < $columns; $c++) $axis .= $c % 10 === 0 ? '+' : '-'; $lines[] = '       +' . $axis . '+';
    $time = '    ms'; for ($c = 0; $c < $columns; $c += 10) $time = str_pad($time, 8 + $c) . milliseconds($start + intdiv($c * $count, $columns), $source->rate); $lines[] = $time; return $lines;
}
function meterPlot(Signal $source, int $block): array {
    $length = count($source->samples); $blocks = intdiv($length + $block - 1, $block); $lines = ["METER $source->name rate=$source->rate samples=$length block=$block blocks=$blocks"];
    for ($b = 0; $b < $blocks; $b++) {
        $part = array_slice($source->samples, $b * $block, $block); $p = peak($part); $q = rms($part); $np = rdiv($p * 40, 32768); $nq = rdiv($q * 40, 32768); $bar = '';
        for ($j = 0; $j < 40; $j++) $bar .= $j < $nq ? '#' : ($j < $np ? '-' : ' ');
        $lines[] = str_pad((string)milliseconds($b * $block, $source->rate), 6, ' ', STR_PAD_LEFT) . " |$bar| peak=$p rms=$q clipped=" . countClipped($part);
    } return $lines;
}
function histogramPlot(Signal $source, int $bins): array {
    $counts = array_fill(0, $bins, 0); foreach ($source->samples as $x) $counts[intdiv(($x + 32768) * $bins, 65536)]++;
    $edges = []; for ($b = 0; $b <= $bins; $b++) $edges[] = intdiv($b * 65536 + $bins - 1, $bins) - 32768; $largest = max($counts); $length = count($source->samples);
    $lines = ["HISTOGRAM $source->name rate=$source->rate samples=$length bins=$bins max=$largest"];
    for ($b = 0; $b < $bins; $b++) $lines[] = str_pad((string)$edges[$b], 6, ' ', STR_PAD_LEFT) . ' ' . str_pad((string)($edges[$b + 1] - 1), 6, ' ', STR_PAD_LEFT) . ' ' . str_pad((string)$counts[$b], 5, ' ', STR_PAD_LEFT) . ' |' . str_repeat('#', rdiv($counts[$b] * 50, $largest)); return $lines;
}
function pitchRow(int $rate, int $start, int $level, ?int $lag, int $low, int $high): string {
    $prefix = str_pad((string)milliseconds($start, $rate), 6, ' ', STR_PAD_LEFT) . ' |';
    if ($lag === null) return $prefix . str_repeat(' ', 41) . "| unvoiced rms=$level";
    $position = $high > $low ? rdiv(($high - $lag) * 40, $high - $low) : 0;
    return $prefix . str_repeat(' ', $position) . 'o' . str_repeat(' ', 40 - $position) . "| lag=$lag hz=" . frequencyText($rate, $lag) . " rms=$level";
}
function traceLines(Signal $signal, int $depth, array &$lines): void { $lines[] = str_repeat('  ', $depth) . "$signal->name <- $signal->origin"; foreach ($signal->ingredients as $ingredient) traceLines($ingredient, $depth + 1, $lines); }

final class Pipeline {
    private array $signals = [], $variables = [], $commands, $log = [], $analysis = ['signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz'], $excerpts = [], $waveforms = [], $saved = [];
    private int $steps = 0, $errors = 0, $passed = 0, $failed = 0;
    public function __construct() {
        $this->commands = commands(); foreach (readSignals() as $signal) { $this->signals[$signal->name] = $signal; $this->log[] = "load $signal->name rate=$signal->rate samples=" . count($signal->samples) . ' peak=' . peak($signal->samples); }
    }
    private function integerValue(string $token): int {
        if (str_starts_with($token, '$')) { $name = substr($token, 1); if (!array_key_exists($name, $this->variables)) throw new CommandError("undefined variable $token"); return $this->variables[$name]; }
        if (!preg_match('/\A-?(0|[1-9][0-9]{0,9})\z/', $token) || $token === '-0') throw new CommandError("bad integer $token"); return (int)$token;
    }
    private function parse(string $name, CommandSpec $command, array $tokens): array {
        $values = []; $sources = []; $known = [];
        foreach ($tokens as $j => $token) {
            $argument = $command->argument($j); $kind = $argument->name;
            if ($kind === 'dst' || $kind === 'var') { if (!preg_match('/\A[a-z][a-z0-9_]{0,15}\z/', $token)) throw new CommandError("bad name $token"); $value = $token; }
            elseif ($kind === 'src') { if (!isset($this->signals[$token])) throw new CommandError("unknown signal $token"); $value = $this->signals[$token]; $sources[] = $value; }
            elseif ($kind === 'metric') { if (!in_array($token, ['samples', 'peak', 'rms', 'sum', 'zero_crossings', 'clipped'], true)) throw new CommandError("unknown metric $token"); $value = $token; }
            elseif ($kind === 'op') { if (!in_array($token, $name === 'SET' ? ['+', '-', '*', '/'] : ['eq', 'ne', 'lt', 'le', 'gt', 'ge'], true)) throw new CommandError("unknown operator $token"); $value = $token; }
            else {
                $value = $this->integerValue($token); $source = $sources[0] ?? null; $low = resolveBound($argument->low, $known, $source); $high = resolveBound($argument->high, $known, $source);
                if ($value < $low || $value > $high) throw new CommandError("$kind out of range"); $known[$kind] = $value;
            }
            $values[] = $value;
        } return [$values, $sources];
    }
    private function generate(int $number, string $command, array $v, array $sources): string {
        $extras = []; $rate = $sources ? $sources[0]->rate : $v[1]; $x = $sources ? $sources[0]->samples : [];
        switch ($command) {
            case 'IMPULSE': $samples = impulse($v[2], $v[3], $v[4]); break;
            case 'STEP': $samples = stepSignal($v[2], $v[3], $v[4]); break;
            case 'NOISE': $samples = noise($v[2], $v[3]); break;
            case 'GAIN': [$samples, $clips] = signalGain($x, $v[2], $v[3]); $extras = ["clipped=$clips"]; break;
            case 'MIX':
                sameRate($sources); $tracks = []; $weights = []; for ($j = 2; $j < count($v); $j += 2) { $tracks[] = $v[$j]->samples; $weights[] = $v[$j + 1]; }
                [$samples, $clips] = signalMix($tracks, $weights, $v[1]); $extras = ["clipped=$clips"]; break;
            case 'DELAY': if (count($x) + $v[2] > 20000) throw new CommandError('result too long'); $samples = signalDelay($x, $v[2]); break;
            case 'ECHO':
                if (abs($v[3]) >= $v[4]) throw new CommandError('unstable feedback'); if (count($x) + $v[5] > 20000) throw new CommandError('result too long');
                [$samples, $clips] = signalEcho($x, $v[2], $v[3], $v[4], $v[5]); $extras = ["clipped=$clips"]; break;
            case 'RESAMPLE': if (resampledLength(count($x), $rate, $v[2]) > 20000) throw new CommandError('result too long'); $samples = signalResample($x, $rate, $v[2]); $rate = $v[2]; break;
            case 'FADE': $samples = signalFade($x, $v[2], $v[3]); break;
            case 'TRIM': $samples = array_slice($x, $v[2], $v[3]); break;
            case 'CONCAT':
                sameRate($sources); $length = 0; foreach ($sources as $source) $length += count($source->samples); if ($length > 20000) throw new CommandError('result too long');
                $samples = []; foreach ($sources as $source) array_push($samples, ...$source->samples); break;
            case 'FIR': [$samples, $clips] = firFilter($x, $v[2], array_slice($v, 3)); $extras = ["clipped=$clips"]; break;
            case 'BIQUAD': $sections = array_chunk(array_slice($v, 2), 5); [$samples, $clips] = biquadFilter($x, $sections); $extras = ['sections=' . count($sections), "clipped=$clips"]; break;
            case 'MOVAVG': $samples = movingAverage($x, $v[2]); break;
            case 'DCBLOCK': [$samples, $clips] = dcBlock($x, $v[2], $v[3]); $extras = ["clipped=$clips"]; break;
            case 'NORMALIZE': [$samples, $sourcePeak] = normalizeSignal($x, $v[2]); $extras = ["source_peak=$sourcePeak"]; break;
            case 'GATE': [$samples, $muted] = gateSignal($x, $v[2], $v[3]); $extras = ["muted=$muted"]; break;
            case 'ENVELOPE': $samples = envelope($x, $v[2], $v[3]); break;
            case 'COMPRESS': [$samples, $minimum, $reduced] = compressSignal($x, $v[2], $v[3], $v[4], $v[5], $v[6]); $extras = ["min_gain=$minimum", "reduced=$reduced"]; break;
        }
        $dst = $v[0]; $this->signals[$dst] = new Signal($dst, $rate, $samples, "line $number $command", $sources);
        return "$dst rate=$rate samples=" . count($samples) . ' peak=' . peak($samples) . ' sum=' . array_sum($samples) . ($extras ? ' ' . implode(' ', $extras) : '');
    }
    private function execute(int $number, string $name, array $tokens): array {
        if (!isset($this->commands[$name])) throw new CommandError("unknown command $name"); $command = $this->commands[$name];
        if (!$command->accepts(count($tokens))) throw new CommandError('wrong number of arguments'); [$v, $sources] = $this->parse($name, $command, $tokens);
        if (in_array($name, ['IMPULSE', 'STEP', 'NOISE', 'GAIN', 'MIX', 'DELAY', 'ECHO', 'RESAMPLE', 'FADE', 'TRIM', 'CONCAT', 'FIR', 'BIQUAD', 'MOVAVG', 'DCBLOCK', 'NORMALIZE', 'GATE', 'ENVELOPE', 'COMPRESS'], true)) return [$this->generate($number, $name, $v, $sources)];
        if ($name === 'SET') {
            $result = $v[1]; if (count($v) === 4) { if ($v[2] === '/' && $v[3] === 0) throw new CommandError('division by zero'); $result = match ($v[2]) { '+' => $result + $v[3], '-' => $result - $v[3], '*' => $result * $v[3], '/' => floorDiv($result, $v[3]) }; if (abs($result) > 10000000) throw new CommandError('value out of range'); }
            $this->variables[$v[0]] = $result; return ["{$v[0]}=$result"];
        }
        $source = $v[0]; $x = $source->samples; $length = count($x); $rate = $source->rate;
        switch ($name) {
            case 'ANALYZE':
                [$low, $high] = lagRange($rate, $v[1], $v[2]); if ($low > $high) throw new CommandError('empty lag range'); if ($high >= $length) throw new CommandError('signal too short'); $lag = pitchLag($x, $low, $high);
                $this->analysis[] = implode(',', [$source->name, peak($x), rms($x), zeroCrossings($x), countClipped($x), crestFraction($x), $lag ?? 'none', $lag === null ? 'none' : frequencyText($rate, $lag)]); return ["$source->name lags=$low-$high"];
            case 'COMPARE':
                sameRate($sources); $b = $v[1]->samples; $differing = 0; $maximum = 0; $first = 'none'; $energy = 0;
                for ($i = 0; $i < max($length, count($b)); $i++) { $difference = ($x[$i] ?? 0) - ($b[$i] ?? 0); if ($difference !== 0) { $differing++; if ($first === 'none') $first = $i; } $maximum = max($maximum, abs($difference)); $energy += $difference * $difference; }
                return ["$source->name {$v[1]->name} differing=$differing max_diff=$maximum first=$first error_energy=$energy"];
            case 'EXPECT':
                $measured = metricValue($x, $v[1]); $pass = match ($v[2]) { 'eq' => $measured === $v[3], 'ne' => $measured !== $v[3], 'lt' => $measured < $v[3], 'le' => $measured <= $v[3], 'gt' => $measured > $v[3], 'ge' => $measured >= $v[3] };
                if ($pass) $this->passed++; else $this->failed++; return ["$source->name {$v[1]}=$measured {$v[2]} {$v[3]} " . ($pass ? 'pass' : 'fail')];
            case 'SEGMENTS':
                $found = []; foreach ($x as $i => $sample) if (abs($sample) >= $v[1]) { $last = count($found) - 1; if ($last >= 0 && $i - $found[$last][1] <= $v[2]) $found[$last][1] = $i; else $found[] = [$i, $i]; }
                $found = array_values(array_filter($found, fn($pair) => $pair[1] - $pair[0] + 1 >= $v[3])); $lines = ["$source->name segments=" . count($found)];
                foreach ($found as $j => [$start, $end]) { $part = array_slice($x, $start, $end - $start + 1); $lines[] = '  segment ' . ($j + 1) . " start=$start end=$end start_ms=" . milliseconds($start, $rate) . ' end_ms=' . milliseconds($end, $rate) . ' peak=' . peak($part) . ' rms=' . rms($part) . ' crossings=' . zeroCrossings($part); } return $lines;
            case 'ONSETS':
                $levels = envelope($x, $v[1], $v[2]); $onsets = []; foreach ($levels as $n => $level) if ($level >= $v[3] && ($n === 0 || $levels[$n - 1] < $v[3]) && (!$onsets || $n - $onsets[count($onsets) - 1] >= $v[4])) $onsets[] = $n;
                $intervals = []; for ($i = 1; $i < count($onsets); $i++) $intervals[] = $onsets[$i] - $onsets[$i - 1]; $tempo = 'none'; if ($intervals) { $ordered = $intervals; sort($ordered, SORT_NUMERIC); $tempo = twoDecimals(rdiv(6000 * $rate, $ordered[intdiv(count($onsets) - 2, 2)])); }
                $lines = ["$source->name onsets=" . count($onsets) . " tempo=$tempo"]; foreach ($onsets as $j => $n) $lines[] = '  onset ' . ($j + 1) . " sample=$n ms=" . milliseconds($n, $rate) . ' interval=' . ($j === 0 ? 'none' : $intervals[$j - 1]); return $lines;
            case 'PITCHTRACK':
                [$low, $high] = lagRange($rate, $v[3], $v[4]); if ($low > $high) throw new CommandError('empty lag range'); if ($high >= $v[1]) throw new CommandError('frame too short'); $count = intdiv($length - $v[1], $v[2]) + 1; $rows = []; $voiced = 0;
                for ($t = 0; $t < $count; $t++) { $part = array_slice($x, $t * $v[2], $v[1]); $level = rms($part); $lag = $level < $v[5] ? null : pitchLag($part, $low, $high); if ($lag !== null) $voiced++; $rows[] = pitchRow($rate, $t * $v[2], $level, $lag, $low, $high); }
                $this->waveforms[] = "PITCHTRACK $source->name rate=$rate frame={$v[1]} hop={$v[2]} lags=$low-$high threshold={$v[5]} frames=$count voiced=$voiced"; array_push($this->waveforms, ...$rows); return ["$source->name frames=$count voiced=$voiced"];
            case 'EXCERPT':
                $start = $v[1]; $count = min($v[2], $length - $start); $this->excerpts[] = "EXCERPT $source->name rate=$rate samples=$length start=$start count=$count";
                foreach (array_chunk(array_slice($x, $start, $count), 8) as $j => $part) { $line = str_pad((string)($start + 8 * $j), 5, ' ', STR_PAD_LEFT) . ':'; foreach ($part as $sample) $line .= ' ' . str_pad((string)$sample, 6, ' ', STR_PAD_LEFT); $this->excerpts[] = $line; } return ["$source->name start=$start count=$count"];
            case 'PLOT': array_push($this->waveforms, ...waveformPlot($source, ...array_slice($v, 1))); return ["$source->name start={$v[1]} count={$v[2]} columns={$v[3]} rows=" . (2 * $v[4] + 1)];
            case 'METER': array_push($this->waveforms, ...meterPlot($source, $v[1])); return ["$source->name block={$v[1]}"];
            case 'HISTOGRAM': array_push($this->waveforms, ...histogramPlot($source, $v[1])); return ["$source->name bins={$v[1]}"];
            case 'TRACE': $lines = [$source->name]; traceLines($source, 1, $lines); return $lines;
            case 'SAVE': array_push($this->saved, ...formatSignal($source)); return ["$source->name samples=$length"];
        }
    }
    public function run(): void {
        foreach (file('input/pipeline.txt', FILE_IGNORE_NEW_LINES) as $j => $line) {
            if ($line === '' || str_starts_with($line, '#')) continue; $parts = explode(' ', $line); $name = array_shift($parts); $number = $j + 1;
            try { $lines = $this->execute($number, $name, $parts); $this->log[] = "line $number: $name " . array_shift($lines); array_push($this->log, ...$lines); $this->steps++; }
            catch (CommandError $error) { $this->log[] = "line $number: error: " . $error->getMessage(); $this->errors++; }
        }
        ksort($this->signals, SORT_STRING); foreach ($this->signals as $signal) $this->log[] = "signal $signal->name rate=$signal->rate samples=" . count($signal->samples) . ' peak=' . peak($signal->samples) . ' rms=' . rms($signal->samples);
        $this->log[] = "summary steps=$this->steps errors=$this->errors signals=" . count($this->signals) . " passed=$this->passed failed=$this->failed";
        if (!is_dir('output')) mkdir('output'); foreach (['log.txt' => $this->log, 'analysis.csv' => $this->analysis, 'excerpts.txt' => $this->excerpts, 'waveforms.txt' => $this->waveforms, 'signals_out.txt' => $this->saved] as $name => $lines) file_put_contents('output/' . $name, $lines ? implode("\n", $lines) . "\n" : '');
    }
}
(new Pipeline())->run();
