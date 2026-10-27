<?php

require_once __DIR__ . '/sequence_io.php';
require_once __DIR__ . '/suffix_array.php';
require_once __DIR__ . '/fm_index.php';
require_once __DIR__ . '/search.php';
require_once __DIR__ . '/sam_writer.php';

const BASES = 'ACGT';

function positionOrder(object $a, object $b): int
{
    return ($a->r <=> $b->r) ?: ($a->pos <=> $b->pos) ?: ($a->strand <=> $b->strand);
}

function gcCount(string $sequence): int
{
    return substr_count($sequence, 'G') + substr_count($sequence, 'C');
}

function textPosition(array $references, int $position): ?object
{
    foreach ($references as $r => $reference) {
        if ($position >= $reference->offset && $position < $reference->offset + strlen($reference->sequence)) {
            return (object) ['r' => $r, 'pos' => $position - $reference->offset];
        }
    }
    return null;
}

function indexStatistics(array $references, array $params, object $forwardBuild, object $reverseBuild,
    FMIndex $forward, FMIndex $reverse): array
{
    $n = strlen($forward->text);
    $checked = checkSuffixArray($forward->text, $forward->sa);
    $reverseChecked = checkSuffixArray($reverse->text, $reverse->sa);
    $kmers = [];
    $namePosition = function (int $position) use ($references): string {
        $location = textPosition($references, $position);
        return $location === null ? '*' : $references[$location->r]->name . ':' . ($location->pos + 1);
    };
    foreach ($forward->sa as $position) {
        if ($position + $params['SEED_LENGTH'] > $n) {
            continue;
        }
        $kmer = substr($forward->text, $position, $params['SEED_LENGTH']);
        if (strspn($kmer, BASES) === strlen($kmer)) {
            $kmers[$kmer] = ($kmers[$kmer] ?? 0) + 1;
        }
    }
    $occurrences = 0;
    $unique = 0;
    $maxOccurrence = 0;
    foreach ($kmers as $count) {
        $occurrences += $count;
        if ($count === 1) {
            $unique++;
        }
        $maxOccurrence = max($maxOccurrence, $count);
    }
    $correct = 0;
    $steps = 0;
    $maxSteps = 0;
    for ($row = 0; $row < $n; $row++) {
        $located = $forward->locate($row);
        if ($located->position === $forward->sa[$row]) {
            $correct++;
        }
        $steps += $located->steps;
        $maxSteps = max($maxSteps, $located->steps);
    }
    $bwtLine = function (FMIndex $index): string {
        $runs = 0;
        for ($i = 0; $i < strlen($index->bwt); $i++) {
            if ($i === 0 || $index->bwt[$i] !== $index->bwt[$i - 1]) {
                $runs++;
            }
        }
        return 'bwt runs ' . $runs . ' head ' . substr($index->bwt, 0, 60);
    };
    $symbolValues = function (array $values): string {
        $parts = [];
        for ($i = 0; $i < strlen(SYMBOLS); $i++) {
            $parts[] = SYMBOLS[$i] . ' ' . $values[$i];
        }
        return implode(' ', $parts);
    };
    $lines = ['text length ' . $n . ' sequences ' . count($references)];
    foreach ($references as $reference) {
        $length = strlen($reference->sequence);
        $lines[] = 'sequence ' . $reference->name . ' length ' . $length . ' offset ' . $reference->offset
            . ' gc ' . ratio(gcCount($reference->sequence), $length) . ' masked ' . $reference->masked;
    }
    $lines[] = 'symbols ' . $symbolValues($forward->counts);
    $lines[] = '';
    $lines[] = 'forward_index';
    $lines[] = 'suffix_array rounds ' . (count($forwardBuild->rounds) - 1);
    foreach ($forwardBuild->rounds as $round => $classes) {
        $lines[] = 'round ' . $round . ' prefix_length ' . (1 << $round) . ' classes ' . $classes;
    }
    $lines[] = 'sa_check pairs ' . ($n - 1) . ' ordered ' . $checked->ordered . ' lcp_sum ' . $checked->lcpSum
        . ' mean_lcp ' . ratio($checked->lcpSum, $n - 1) . ' max_lcp ' . $checked->maximum;
    $lines[] = 'longest_repeat ' . $checked->maximum . ' ' . $namePosition($forward->sa[$checked->row - 1])
        . ' ' . $namePosition($forward->sa[$checked->row]);
    $lines[] = 'kmers length ' . $params['SEED_LENGTH'] . ' occurrences ' . $occurrences . ' distinct ' . count($kmers)
        . ' unique ' . $unique . ' max_occurrence ' . $maxOccurrence . ' unique_fraction ' . ratio($unique, $occurrences);
    $lines[] = $bwtLine($forward);
    $lines[] = 'c_array ' . $symbolValues($forward->C);
    $lines[] = 'occ interval ' . $params['OCC_INTERVAL'] . ' checkpoints ' . count($forward->checkpoints);
    $lines[] = 'sa_sample interval ' . $params['SA_SAMPLE_INTERVAL'] . ' samples ' . count($forward->samples);
    $lines[] = 'locate rows ' . $n . ' correct ' . $correct . ' total_steps ' . $steps . ' max_steps ' . $maxSteps
        . ' mean_steps ' . ratio($steps, $n);
    $lines[] = 'inverse_bwt identical ' . ($forward->inverse() === $forward->text ? 'yes' : 'no');
    $lines[] = '';
    $lines[] = 'reverse_index';
    $lines[] = 'suffix_array rounds ' . (count($reverseBuild->rounds) - 1);
    $lines[] = 'sa_check pairs ' . ($n - 1) . ' ordered ' . $reverseChecked->ordered;
    $lines[] = $bwtLine($reverse);
    $lines[] = 'inverse_bwt identical ' . ($reverse->inverse() === $reverse->text ? 'yes' : 'no');
    $lines[] = '';
    $lines[] = 'direct_sort';
    $directCount = 0;
    foreach ($references as $reference) {
        if (strlen($reference->sequence) > $params['DIRECT_SORT_LIMIT']) {
            continue;
        }
        $text = $reference->sequence . '$';
        $built = buildSuffixArray($text);
        $direct = directSuffixArray($text);
        $lines[] = $reference->name . ' length ' . strlen($text) . ' rounds ' . (count($built->rounds) - 1)
            . ' identical ' . ($built->sa === $direct ? 'yes' : 'no');
        $directCount++;
    }
    if ($directCount === 0) {
        $lines[] = 'none';
    }
    $occBytes = 24 * count($forward->checkpoints);
    $sampleBytes = 4 * count($forward->samples);
    $bitmapBytes = intdiv($n + 7, 8);
    $size = $n + $occBytes + $sampleBytes + $bitmapBytes;
    $lines[] = '';
    $lines[] = 'index_size bwt_bytes ' . $n . ' occ_bytes ' . $occBytes . ' sample_bytes ' . $sampleBytes
        . ' bitmap_bytes ' . $bitmapBytes . ' total_bytes ' . $size . ' full_bytes ' . (5 * $n) . ' ratio ' . ratio($size, 5 * $n);
    return $lines;
}

function bandedAlignment(string $sequence, string $reference, int $center, array $params): ?object
{
    [$match, $mismatch, $open, $extend] = $params['SCORES'];
    $length = strlen($sequence);
    $width = $params['BAND_WIDTH'];
    $rows = [];
    $value = fn($cell, $state) => $cell === null ? null : $cell[$state];
    $minus = fn($score, $penalty) => $score === null ? null : $score - $penalty;
    $maximum = function (array $candidates): ?int {
        $best = null;
        foreach ($candidates as $candidate) {
            if ($candidate !== null && ($best === null || $candidate > $best)) {
                $best = $candidate;
            }
        }
        return $best;
    };
    for ($i = 0; $i <= $length; $i++) {
        $row = [];
        $first = max(0, $i + $center - $width);
        $last = min(strlen($reference), $i + $center + $width);
        for ($j = $first; $j <= $last; $j++) {
            if ($i === 0) {
                $row[$j] = ['H' => 0, 'E' => null, 'F' => null];
                continue;
            }
            $above = $rows[$i - 1][$j] ?? null;
            $left = $row[$j - 1] ?? null;
            $diagonal = $rows[$i - 1][$j - 1] ?? null;
            $F = $maximum([$minus($value($above, 'H'), $open + $extend), $minus($value($above, 'F'), $extend)]);
            $E = $j === 0 ? null : $maximum([$minus($value($left, 'H'), $open + $extend), $minus($value($left, 'E'), $extend)]);
            $previous = $value($diagonal, 'H');
            $paired = $j === 0 || $previous === null ? null : $previous + ($sequence[$i - 1] === $reference[$j - 1] ? $match : -$mismatch);
            $row[$j] = ['H' => $maximum([$paired, $E, $F]), 'E' => $E, 'F' => $F];
        }
        $rows[] = $row;
    }
    $end = null;
    $score = null;
    foreach ($rows[$length] as $j => $cell) {
        if ($cell['H'] !== null && ($score === null || $cell['H'] > $score)) {
            $end = $j;
            $score = $cell['H'];
        }
    }
    if ($end === null) {
        return null;
    }
    $i = $length;
    $j = $end;
    $state = 'H';
    $operations = [];
    while (true) {
        if ($state === 'H' && $i === 0) {
            break;
        }
        $cell = $rows[$i][$j];
        if ($state === 'H') {
            $diagonal = $j >= 1 ? $value($rows[$i - 1][$j - 1] ?? null, 'H') : null;
            if ($diagonal !== null && $cell['H'] === $diagonal + ($sequence[$i - 1] === $reference[$j - 1] ? $match : -$mismatch)) {
                $operations[] = 'M';
                $i--;
                $j--;
            } else {
                $state = $cell['F'] !== null && $cell['H'] === $cell['F'] ? 'I' : 'D';
            }
        } elseif ($state === 'I') {
            $operations[] = 'I';
            $previous = $value($rows[$i - 1][$j] ?? null, 'F');
            $state = $previous !== null && $cell['F'] === $previous - $extend ? 'I' : 'H';
            $i--;
        } else {
            $operations[] = 'D';
            $previous = $value($rows[$i][$j - 1] ?? null, 'E');
            $state = $previous !== null && $cell['E'] === $previous - $extend ? 'D' : 'H';
            $j--;
        }
    }
    return (object) ['pos' => $j, 'ops' => implode('', array_reverse($operations)), 'score' => $score];
}

function mapRead(object $read, array $references, array $params, FMIndex $forward, FMIndex $reverse,
    object $searchStats, object $seedStats): object
{
    $length = strlen($read->sequence);
    while ($length > 0 && $read->qualities[$length - 1] < $params['TRIM_QUALITY']) {
        $length--;
    }
    $read->length = $length;
    $read->trimmed = strlen($read->sequence) - $length;
    if ($length < $params['MIN_READ_LENGTH']) {
        return (object) ['reason' => 'SHORT'];
    }
    $core = substr($read->sequence, 0, $length);
    $oriented = [$core, reverseComplement($core)];
    $exactForward = $forward->backward($oriented[0]);
    $exactReverse = $forward->backward($oriented[1]);
    $maximum = $exactForward[0] < $exactForward[1] || $exactReverse[0] < $exactReverse[1] ? 1 : $params['MAX_MISMATCHES'];
    $hits = [];
    for ($strand = 0; $strand < 2; $strand++) {
        $searched = backtrack($oriented[$strand], $maximum, $forward, $reverse);
        $searchStats->calls++;
        $searchStats->nodes += $searched->nodes;
        $searchStats->leaves += count($searched->leaves);
        $searchStats->positions += $searched->hits;
        foreach ($searched->leaves as $leaf) {
            for ($row = $leaf->lo; $row < $leaf->hi; $row++) {
                $location = textPosition($references, $forward->locate($row)->position);
                $hits[] = (object) ['r' => $location->r, 'pos' => $location->pos, 'strand' => $strand,
                    'mm' => $leaf->mismatches, 'ops' => str_repeat('M', $length)];
            }
        }
    }
    if ($hits) {
        usort($hits, fn($a, $b) => ($a->mm <=> $b->mm) ?: positionOrder($a, $b));
        $best = $hits[0]->mm;
        $x0 = 0;
        $x1 = 0;
        $alignments = [];
        foreach ($hits as $hit) {
            if ($hit->mm === $best) {
                $x0++;
            } elseif ($hit->mm === $best + 1) {
                $x1++;
            }
            if ($hit->mm <= $best + 1) {
                $alignments[] = $hit;
            }
        }
        $mapq = $x0 >= 2 ? 0 : ($x1 === 0 ? 60 - 12 * $best : max(30 - 12 * $best - 3 * $x1, 1));
        return (object) ['alignments' => $alignments, 'x0' => $x0, 'x1' => $x1, 'mapq' => $mapq,
            'score' => ($length - $best) * $params['SCORES'][0] - $best * $params['SCORES'][1],
            'method' => $best === 0 ? 'EXACT' : 'MISMATCH'];
    }
    if ($length < $params['SEED_LENGTH']) {
        return (object) ['reason' => 'NOHIT'];
    }
    $seedStats->reads++;
    $candidates = [];
    for ($strand = 0; $strand < 2; $strand++) {
        $sequence = $oriented[$strand];
        for ($offset = 0; $offset + $params['SEED_LENGTH'] <= $length; $offset += $params['SEED_STEP']) {
            $seedStats->seeds++;
            $seed = substr($sequence, $offset, $params['SEED_LENGTH']);
            if (str_contains($seed, 'N')) {
                $seedStats->withN++;
                continue;
            }
            [$lo, $hi] = $forward->backward($seed);
            if ($hi - $lo > $params['MAX_SEED_HITS']) {
                $seedStats->repetitive++;
                continue;
            }
            if ($lo >= $hi) {
                $seedStats->withoutHit++;
                continue;
            }
            for ($row = $lo; $row < $hi; $row++) {
                $location = textPosition($references, $forward->locate($row)->position);
                $center = $location->pos - $offset;
                $key = $strand . '/' . $location->r . '/' . $center;
                $candidates[$key] = (object) ['strand' => $strand, 'r' => $location->r, 'c' => $center];
            }
        }
    }
    $ordered = array_values($candidates);
    usort($ordered, fn($a, $b) => ($a->strand <=> $b->strand) ?: ($a->r <=> $b->r) ?: ($a->c <=> $b->c));
    $seedStats->candidates += count($ordered);
    $accepted = [];
    foreach ($ordered as $candidate) {
        $alignment = bandedAlignment($oriented[$candidate->strand], $references[$candidate->r]->sequence, $candidate->c, $params);
        if ($alignment === null || 100 * $alignment->score < $params['MIN_SCORE_PERCENT'] * $params['SCORES'][0] * $length) {
            continue;
        }
        $alignment->r = $candidate->r;
        $alignment->strand = $candidate->strand;
        $key = $alignment->r . '/' . $alignment->pos . '/' . $alignment->strand;
        if (!isset($accepted[$key]) || $alignment->score > $accepted[$key]->score) {
            $accepted[$key] = $alignment;
        }
    }
    $seedStats->passing += count($accepted);
    if (!$accepted) {
        return (object) ['reason' => 'NOHIT'];
    }
    $alignments = array_values($accepted);
    usort($alignments, fn($a, $b) => ($b->score <=> $a->score) ?: positionOrder($a, $b));
    $score = $alignments[0]->score;
    $x0 = 0;
    foreach ($alignments as $alignment) {
        if ($alignment->score === $score) {
            $x0++;
        }
    }
    $x1 = count($alignments) - $x0;
    $second = $x1 === 0 ? 0 : $alignments[$x0]->score;
    $mapq = $x0 >= 2 ? 0 : intdiv(60 * ($score - $second), $score);
    return (object) ['alignments' => $alignments, 'score' => $score, 'x0' => $x0, 'x1' => $x1, 'mapq' => $mapq, 'method' => 'SEED'];
}

function describeAlignment(object $read, object $alignment, array $references): void
{
    $core = substr($read->sequence, 0, $read->length);
    $sequence = $alignment->strand === 0 ? $core : reverseComplement($core);
    $reference = $references[$alignment->r]->sequence;
    $runs = [];
    for ($p = 0; $p < strlen($alignment->ops); $p++) {
        $operation = $alignment->ops[$p];
        $last = count($runs) - 1;
        if ($last >= 0 && $runs[$last]->operation === $operation) {
            $runs[$last]->length++;
        } else {
            $runs[] = (object) ['operation' => $operation, 'length' => 1];
        }
    }
    $pairs = [];
    $md = '';
    $i = 0;
    $j = $alignment->pos;
    $matches = 0;
    $nm = 0;
    foreach ($runs as $run) {
        if ($run->operation === 'I') {
            $i += $run->length;
            $nm += $run->length;
            continue;
        }
        if ($run->operation === 'D') {
            $md .= $matches . '^' . substr($reference, $j, $run->length);
            $matches = 0;
            $j += $run->length;
            $nm += $run->length;
            continue;
        }
        for ($k = 0; $k < $run->length; $k++) {
            $cycle = $alignment->strand === 0 ? $i + 1 : $read->length - $i;
            $match = $sequence[$i] === $reference[$j];
            $pairs[] = (object) ['refPos' => $j, 'base' => $sequence[$i], 'reference' => $reference[$j],
                'cycle' => $cycle, 'quality' => $read->qualities[$cycle - 1], 'match' => $match];
            if ($match) {
                $matches++;
            } else {
                $md .= $matches . $reference[$j];
                $matches = 0;
                $nm++;
            }
            $i++;
            $j++;
        }
    }
    $md .= $matches;
    $cigar = '';
    foreach ($runs as $run) {
        $cigar .= $run->length . $run->operation;
    }
    if ($read->trimmed > 0) {
        $soft = $read->trimmed . 'S';
        $cigar = $alignment->strand === 0 ? $cigar . $soft : $soft . $cigar;
    }
    $alignment->runs = $runs;
    $alignment->pairs = $pairs;
    $alignment->cigar = $cigar;
    $alignment->md = $md;
    $alignment->nm = $nm;
}

function tallyCoverage(array $reads, array $results, array $references, array $params): array
{
    $coverage = [];
    foreach ($references as $reference) {
        $length = strlen($reference->sequence);
        $coverage[] = (object) ['depth' => array_fill(0, $length, 0), 'starts' => array_fill(0, $length, 0),
            'pileup' => array_fill(0, $length, array_fill(0, 8, 0))];
    }
    foreach ($reads as $index => $read) {
        $result = $results[$index];
        if (isset($result->reason)) {
            continue;
        }
        $primary = $result->alignments[0];
        $target = $coverage[$primary->r];
        if ($result->mapq === 0) {
            $target->starts[$primary->pos]++;
        }
        if ($result->mapq < $params['COVERAGE_MIN_MAPQ']) {
            continue;
        }
        foreach ($primary->pairs as $pair) {
            $target->depth[$pair->refPos]++;
            if ($pair->base !== 'N' && $pair->quality >= $params['VARIANTS'][1]) {
                $target->pileup[$pair->refPos][4 * $primary->strand + strpos(BASES, $pair->base)]++;
            }
        }
    }
    return $coverage;
}

function coverageReport(array $references, array $coverage, array $params): array
{
    $lines = ['window ' . $params['COVERAGE_WINDOW'] . ' min_mapq ' . $params['COVERAGE_MIN_MAPQ']];
    foreach ($references as $r => $reference) {
        $depth = $coverage[$r]->depth;
        $starts = $coverage[$r]->starts;
        $length = strlen($reference->sequence);
        $sum = 0;
        $maximum = 0;
        $covered = 0;
        foreach ($depth as $value) {
            $sum += $value;
            $maximum = max($maximum, $value);
            if ($value > 0) {
                $covered++;
            }
        }
        $histogram = array_fill(0, $maximum + 1, 0);
        foreach ($depth as $value) {
            $histogram[$value]++;
        }
        $histogramText = [];
        foreach ($histogram as $value => $count) {
            $histogramText[] = $value . ':' . $count;
        }
        $lines[] = 'reference ' . $reference->name . ' length ' . $length . ' covered ' . $covered
            . ' breadth ' . ratio($covered, $length) . ' mean_depth ' . ratio($sum, $length) . ' max_depth ' . $maximum;
        $lines[] = 'depth_histogram ' . implode(' ', $histogramText);
        for ($first = 0; $first < $length; $first += $params['COVERAGE_WINDOW']) {
            $end = min($first + $params['COVERAGE_WINDOW'], $length);
            $width = $end - $first;
            $windowSum = 0;
            $windowMaximum = 0;
            $zero = 0;
            $mapq0 = 0;
            for ($j = $first; $j < $end; $j++) {
                $windowSum += $depth[$j];
                $windowMaximum = max($windowMaximum, $depth[$j]);
                if ($depth[$j] === 0) {
                    $zero++;
                }
                $mapq0 += $starts[$j];
            }
            $lines[] = $reference->name . ' ' . ($first + 1) . ' ' . $end . ' gc '
                . ratio(gcCount(substr($reference->sequence, $first, $width)), $width) . ' sum ' . $windowSum
                . ' mean ' . ratio($windowSum, $width) . ' max ' . $windowMaximum . ' zero ' . $zero . ' mapq0 ' . $mapq0
                . ' |' . str_repeat('#', intdiv(10 * $windowSum, $width));
        }
    }
    return $lines;
}

function variantReport(array $references, array $coverage, array $params): array
{
    [$minDepth, $quality, $percent, $homPercent] = $params['VARIANTS'];
    $lines = ['min_depth ' . $minDepth . ' min_base_quality ' . $quality . ' min_alt_percent ' . $percent . ' hom_percent ' . $homPercent];
    $callable = 0;
    $heterozygous = 0;
    $homozygous = 0;
    foreach ($references as $r => $reference) {
        for ($j = 0; $j < strlen($reference->sequence); $j++) {
            $pileup = $coverage[$r]->pileup[$j];
            $counts = [];
            for ($base = 0; $base < 4; $base++) {
                $counts[] = $pileup[$base] + $pileup[$base + 4];
            }
            $depth = array_sum($counts);
            if ($depth < $minDepth) {
                continue;
            }
            $callable++;
            $alternative = -1;
            for ($base = 0; $base < 4; $base++) {
                if (BASES[$base] !== $reference->sequence[$j] && ($alternative < 0 || $counts[$base] > $counts[$alternative])) {
                    $alternative = $base;
                }
            }
            $count = $counts[$alternative];
            if ($count < 2 || 100 * $count < $percent * $depth) {
                continue;
            }
            $homo = 100 * $count >= $homPercent * $depth;
            if ($homo) {
                $homozygous++;
            } else {
                $heterozygous++;
            }
            $lines[] = $reference->name . ' ' . ($j + 1) . ' ' . $reference->sequence[$j] . '>' . BASES[$alternative]
                . ' depth ' . $depth . ' alt ' . $count . ' fraction ' . ratio($count, $depth) . ' genotype ' . ($homo ? '1/1' : '0/1')
                . ' strands ' . $pileup[$alternative] . ' ' . $pileup[$alternative + 4] . ' counts ' . implode(' ', $counts);
        }
    }
    $lines[] = 'callable ' . $callable . ' variants ' . ($heterozygous + $homozygous)
        . ' heterozygous ' . $heterozygous . ' homozygous ' . $homozygous;
    return $lines;
}

function summaryReport(array $reads, array $results, array $references, object $searchStats, object $seedStats): array
{
    $count = ['trimmed' => 0, 'trimmedBases' => 0, 'SHORT' => 0, 'NOHIT' => 0, 'mapped' => 0, 'unique' => 0, 'multi' => 0,
        'EXACT' => 0, 'MISMATCH' => 0, 'SEED' => 0, 'forward' => 0, 'reverse' => 0, 'nReads' => 0, 'nBases' => 0, 'nMapped' => 0];
    $refStats = array_fill(0, count($references), ['mapped' => 0, 'unique' => 0, 'forward' => 0, 'reverse' => 0]);
    $bins = [];
    $targets = [];
    $mapqHistogram = [];
    $nmHistogram = [];
    $substitutions = array_fill(0, 4, array_fill(0, 5, 0));
    $maxLength = 0;
    foreach ($reads as $read) {
        $maxLength = max($maxLength, strlen($read->sequence));
    }
    $cycles = array_fill(0, $maxLength, ['aligned' => 0, 'mismatches' => 0]);
    $qualityBins = array_fill(0, 5, ['aligned' => 0, 'mismatches' => 0]);
    $error = ['aligned' => 0, 'mismatches' => 0, 'matchedQuality' => 0, 'mismatchedQuality' => 0];
    $cigar = ['M' => 0, 'I' => 0, 'D' => 0, 'S' => 0];
    $indels = ['I' => ['events' => 0, 'bases' => 0], 'D' => ['events' => 0, 'bases' => 0]];
    foreach ($reads as $index => $read) {
        $result = $results[$index];
        $lo = 10 * intdiv($read->length, 10);
        if (!isset($bins[$lo])) {
            $bins[$lo] = ['reads' => 0, 'mapped' => 0, 'unique' => 0];
        }
        $bins[$lo]['reads']++;
        if ($read->trimmed > 0) {
            $count['trimmed']++;
        }
        $count['trimmedBases'] += $read->trimmed;
        $nBases = substr_count($read->sequence, 'N');
        if ($nBases > 0) {
            $count['nReads']++;
            $count['nBases'] += $nBases;
            if (!isset($result->reason)) {
                $count['nMapped']++;
            }
        }
        if (isset($result->reason)) {
            $count[$result->reason]++;
            continue;
        }
        $count['mapped']++;
        $count[$result->method]++;
        $bins[$lo]['mapped']++;
        $primary = $result->alignments[0];
        $strand = $primary->strand === 0 ? 'forward' : 'reverse';
        $unique = $result->x0 === 1;
        $count[$strand]++;
        $refStats[$primary->r][$strand]++;
        $refStats[$primary->r]['mapped']++;
        if ($unique) {
            $count['unique']++;
            $refStats[$primary->r]['unique']++;
            $bins[$lo]['unique']++;
        } else {
            $count['multi']++;
            $sequenceNumbers = [];
            foreach (array_slice($result->alignments, 0, $result->x0) as $alignment) {
                $sequenceNumbers[$alignment->r] = true;
            }
            ksort($sequenceNumbers, SORT_NUMERIC);
            $names = [];
            foreach (array_keys($sequenceNumbers) as $r) {
                $names[] = $references[$r]->name;
            }
            $key = '#' . implode('+', $names);
            $targets[$key] = ($targets[$key] ?? 0) + 1;
        }
        $mapqHistogram[$result->mapq] = ($mapqHistogram[$result->mapq] ?? 0) + 1;
        $nmHistogram[$primary->nm] = ($nmHistogram[$primary->nm] ?? 0) + 1;
        foreach ($primary->runs as $run) {
            $cigar[$run->operation] += $run->length;
            if ($unique && $run->operation !== 'M') {
                $indels[$run->operation]['events']++;
                $indels[$run->operation]['bases'] += $run->length;
            }
        }
        $cigar['S'] += $read->trimmed;
        if (!$unique) {
            continue;
        }
        foreach ($primary->pairs as $pair) {
            $cycle = $pair->cycle - 1;
            $qualityBin = min(4, intdiv($pair->quality, 10));
            $error['aligned']++;
            $cycles[$cycle]['aligned']++;
            $qualityBins[$qualityBin]['aligned']++;
            $substitutions[strpos(BASES, $pair->reference)][strpos('ACGTN', $pair->base)]++;
            if ($pair->match) {
                $error['matchedQuality'] += $pair->quality;
            } else {
                $error['mismatches']++;
                $cycles[$cycle]['mismatches']++;
                $qualityBins[$qualityBin]['mismatches']++;
                $error['mismatchedQuality'] += $pair->quality;
            }
        }
    }
    $unmapped = $count['SHORT'] + $count['NOHIT'];
    $lines = ['reads total ' . count($reads) . ' trimmed ' . $count['trimmed'] . ' trimmed_bases ' . $count['trimmedBases'] . ' short ' . $count['SHORT'],
        'mapped ' . $count['mapped'] . ' rate ' . ratio($count['mapped'], count($reads)) . ' unique ' . $count['unique']
            . ' multi ' . $count['multi'] . ' unmapped ' . $unmapped,
        'unmapped short ' . $count['SHORT'] . ' nohit ' . $count['NOHIT'],
        'method exact ' . $count['EXACT'] . ' mismatch ' . $count['MISMATCH'] . ' seed ' . $count['SEED'],
        'strand forward ' . $count['forward'] . ' reverse ' . $count['reverse']];
    foreach ($references as $r => $reference) {
        $stats = $refStats[$r];
        $lines[] = 'reference ' . $reference->name . ' mapped ' . $stats['mapped'] . ' unique ' . $stats['unique']
            . ' forward ' . $stats['forward'] . ' reverse ' . $stats['reverse'];
    }
    $lines[] = 'length_bins';
    $minBin = min(array_keys($bins));
    $maxBin = max(array_keys($bins));
    for ($lo = $minBin; $lo <= $maxBin; $lo += 10) {
        $bin = $bins[$lo] ?? ['reads' => 0, 'mapped' => 0, 'unique' => 0];
        $lines[] = $lo . '-' . ($lo + 9) . ' reads ' . $bin['reads'] . ' mapped ' . $bin['mapped'] . ' unique ' . $bin['unique'];
    }
    $lines[] = 'n_reads ' . $count['nReads'] . ' n_bases ' . $count['nBases'] . ' mapped ' . $count['nMapped'];
    $lines[] = 'multi_targets';
    if (!$targets) {
        $lines[] = 'none';
    } else {
        ksort($targets, SORT_STRING);
        foreach ($targets as $key => $value) {
            $lines[] = substr($key, 1) . ' ' . $value;
        }
    }
    $lines[] = 'mapq_histogram';
    krsort($mapqHistogram, SORT_NUMERIC);
    foreach ($mapqHistogram as $mapq => $value) {
        $lines[] = $mapq . ' ' . $value;
    }
    $lines[] = 'nm_histogram';
    ksort($nmHistogram, SORT_NUMERIC);
    foreach ($nmHistogram as $nm => $value) {
        $lines[] = $nm . ' ' . $value;
    }
    $lines[] = 'error_profile aligned_bases ' . $error['aligned'] . ' mismatches ' . $error['mismatches']
        . ' rate ' . ratio($error['mismatches'], $error['aligned']);
    $lines[] = 'substitutions';
    $lines[] = 'ref A C G T N';
    for ($base = 0; $base < 4; $base++) {
        $lines[] = BASES[$base] . ' ' . implode(' ', $substitutions[$base]);
    }
    $lines[] = 'mismatch_by_cycle';
    foreach ($cycles as $i => $cycle) {
        $lines[] = 'cycle ' . ($i + 1) . ' aligned ' . $cycle['aligned'] . ' mismatches ' . $cycle['mismatches']
            . ' rate ' . ratio($cycle['mismatches'], $cycle['aligned']);
    }
    $matched = $error['aligned'] - $error['mismatches'];
    $lines[] = 'quality matched ' . $matched . ' mean ' . ratio($error['matchedQuality'], $matched)
        . ' mismatched ' . $error['mismatches'] . ' mean ' . ratio($error['mismatchedQuality'], $error['mismatches']);
    $lines[] = 'quality_bins';
    $ranges = ['0-9', '10-19', '20-29', '30-39', '40-'];
    foreach ($qualityBins as $i => $bin) {
        $lines[] = $ranges[$i] . ' aligned ' . $bin['aligned'] . ' mismatches ' . $bin['mismatches']
            . ' rate ' . ratio($bin['mismatches'], $bin['aligned']);
    }
    $lines[] = 'cigar M ' . $cigar['M'] . ' I ' . $cigar['I'] . ' D ' . $cigar['D'] . ' S ' . $cigar['S'];
    $lines[] = 'indels insertions ' . $indels['I']['events'] . ' ' . $indels['I']['bases']
        . ' deletions ' . $indels['D']['events'] . ' ' . $indels['D']['bases'];
    $lines[] = 'search dfs_calls ' . $searchStats->calls . ' dfs_nodes ' . $searchStats->nodes . ' dfs_leaves '
        . $searchStats->leaves . ' dfs_positions ' . $searchStats->positions;
    $lines[] = 'seeds reads ' . $seedStats->reads . ' seeds ' . $seedStats->seeds . ' with_n ' . $seedStats->withN
        . ' repetitive ' . $seedStats->repetitive . ' without_hit ' . $seedStats->withoutHit . ' candidates '
        . $seedStats->candidates . ' passing ' . $seedStats->passing;
    return $lines;
}

function main(): void
{
    $input = readSequences();
    $references = $input->references;
    $reads = $input->reads;
    $params = $input->params;
    $offset = 0;
    $sequences = [];
    foreach ($references as $reference) {
        $reference->offset = $offset;
        $offset += strlen($reference->sequence) + 1;
        $sequences[] = $reference->sequence;
    }
    $text = implode('#', $sequences) . '$';
    $reverseText = strrev(substr($text, 0, -1)) . '$';
    $forwardBuild = buildSuffixArray($text);
    $reverseBuild = buildSuffixArray($reverseText);
    $forward = new FMIndex($text, $forwardBuild->sa, $params['OCC_INTERVAL'], $params['SA_SAMPLE_INTERVAL']);
    $reverse = new FMIndex($reverseText, $reverseBuild->sa, $params['OCC_INTERVAL']);
    $indexLines = indexStatistics($references, $params, $forwardBuild, $reverseBuild, $forward, $reverse);
    $searchStats = (object) ['calls' => 0, 'nodes' => 0, 'leaves' => 0, 'positions' => 0];
    $seedStats = (object) ['reads' => 0, 'seeds' => 0, 'withN' => 0, 'repetitive' => 0,
        'withoutHit' => 0, 'candidates' => 0, 'passing' => 0];
    $results = [];
    foreach ($reads as $read) {
        $results[] = mapRead($read, $references, $params, $forward, $reverse, $searchStats, $seedStats);
    }
    foreach ($results as $i => $result) {
        if (!isset($result->reason)) {
            foreach ($result->alignments as $alignment) {
                describeAlignment($reads[$i], $alignment, $references);
            }
        }
    }
    $coverage = tallyCoverage($reads, $results, $references, $params);
    $sam = samHeader($references);
    foreach ($reads as $i => $read) {
        $sam[] = samRecord($read, $results[$i], $references, $params['MAX_ALT_HITS']);
    }
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    writeLines('output/alignments.sam', $sam);
    writeLines('output/coverage.txt', coverageReport($references, $coverage, $params));
    writeLines('output/variants.txt', variantReport($references, $coverage, $params));
    writeLines('output/index_stats.txt', $indexLines);
    writeLines('output/summary.txt', summaryReport($reads, $results, $references, $searchStats, $seedStats));
}

main();
