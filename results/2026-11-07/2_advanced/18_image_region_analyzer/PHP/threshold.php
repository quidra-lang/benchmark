<?php
declare(strict_types=1);

namespace ImageRegions;

final class Histogram
{
    public int $pixels;
    public array $counts;
    public array $belowCounts = [];
    public array $belowSums = [];
    public int $total;
    public int $minimum;
    public int $maximum;
    public int $levels = 0;
    public int $median;
    public int $mode;
    public int $binWidth;
    public array $bins = [];

    public function __construct(public int $maxval, array $values)
    {
        $this->pixels = count($values) * count($values[0]);
        $this->counts = array_fill(0, $maxval + 1, 0);
        foreach ($values as $row) {
            foreach ($row as $value) {
                $this->counts[$value]++;
            }
        }
        $count = 0;
        $total = 0;
        $modeCount = -1;
        for ($value = 0; $value <= $maxval; $value++) {
            $frequency = $this->counts[$value];
            $count += $frequency;
            $total += $value * $frequency;
            $this->belowCounts[] = $count;
            $this->belowSums[] = $total;
            if ($frequency > 0) {
                if ($this->levels === 0) {
                    $this->minimum = $value;
                }
                $this->maximum = $value;
                $this->levels++;
            }
            if (!isset($this->median) && 2 * $count >= $this->pixels) {
                $this->median = $value;
            }
            if ($frequency > $modeCount) {
                $this->mode = $value;
                $modeCount = $frequency;
            }
        }
        $this->total = $total;
        $this->binWidth = intdiv($maxval + 8, 8);
        for ($start = 0; $start <= $maxval; $start += $this->binWidth) {
            $frequency = 0;
            for ($value = $start; $value <= min($start + $this->binWidth - 1, $maxval); $value++) {
                $frequency += $this->counts[$value];
            }
            $this->bins[] = $frequency;
        }
    }

    public function split(int $cutoff): array
    {
        $below = $this->belowCounts[$cutoff];
        $sum = $this->belowSums[$cutoff];
        return [$below, $sum, $this->pixels - $below, $this->total - $sum];
    }
}

final class Candidate
{
    public int $numerator;
    public int $denominator;

    public function __construct(
        public int $cutoff,
        public int $below,
        public int $sumBelow,
        public int $above,
        public int $sumAbove
    ) {
        $this->numerator = $sumBelow * $sumBelow * $above + $sumAbove * $sumAbove * $below;
        $this->denominator = $below * $above;
    }
}

final class OtsuResult
{
    public function __construct(public int $cutoff, public int $upper, public array $candidates) {}
}

function compareScores(Candidate $first, Candidate $second): int
{
    $firstQuotient = intdiv($first->numerator, $first->denominator);
    $secondQuotient = intdiv($second->numerator, $second->denominator);
    if ($firstQuotient !== $secondQuotient) {
        return $firstQuotient <=> $secondQuotient;
    }
    $left = ($first->numerator % $first->denominator) * $second->denominator;
    $right = ($second->numerator % $second->denominator) * $first->denominator;
    return $left <=> $right;
}

function otsu(Histogram $histogram): OtsuResult
{
    $candidates = [];
    for ($cutoff = 0; $cutoff < $histogram->maxval; $cutoff++) {
        [$below, $sumBelow, $above, $sumAbove] = $histogram->split($cutoff);
        if ($histogram->counts[$cutoff] > 0 && $above > 0) {
            $candidates[] = new Candidate($cutoff, $below, $sumBelow, $above, $sumAbove);
        }
    }
    usort($candidates, static function (Candidate $a, Candidate $b): int {
        $order = compareScores($b, $a);
        return $order !== 0 ? $order : $a->cutoff <=> $b->cutoff;
    });
    if ($candidates === []) {
        return new OtsuResult($histogram->minimum, $histogram->minimum, []);
    }
    $best = $candidates[0]->cutoff;
    for ($following = $best + 1; $histogram->counts[$following] === 0; $following++) {}
    return new OtsuResult($best, $following - 1, $candidates);
}

function isodata(Histogram $histogram): array
{
    $cutoff = intdiv($histogram->total, $histogram->pixels);
    $iterations = 0;
    while (true) {
        [$below, $sumBelow, $above, $sumAbove] = $histogram->split($cutoff);
        if ($below === 0 || $above === 0) {
            break;
        }
        $following = intdiv($sumBelow * $above + $sumAbove * $below, 2 * $below * $above);
        $iterations++;
        if ($following === $cutoff) {
            break;
        }
        $cutoff = $following;
        if ($iterations === 100) {
            break;
        }
    }
    return [$cutoff, $iterations];
}
