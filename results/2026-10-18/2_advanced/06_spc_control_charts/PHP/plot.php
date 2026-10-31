<?php
function place(array &$band, int $position, string $symbol): void { $band[min(60,max(0,$position))] = $symbol; }
function framed_band(int $center): array { $band = array_fill(0,61,'.'); place($band,0,':'); place($band,60,':'); place($band,$center,'|'); return $band; }
function limits_band(array $limits, float $value, bool $signalled): string {
    [$lcl,$cl,$ucl] = $limits; $span = $ucl - $lcl; $band = framed_band((int)floor(60 * (($cl - $lcl) / $span) + 0.5));
    place($band,(int)floor(60 * (($value - $lcl) / $span) + 0.5),$signalled ? '*' : 'o'); return implode('',$band);
}
function cusum_band(float $upper, float $lower, float $threshold, bool $upperSignal, bool $lowerSignal): string {
    $band = framed_band(30);
    if ($lower > 0) place($band,30 - min(30,(int)floor(30 * ($lower / $threshold) + 0.5)),$lowerSignal ? '*' : '-');
    if ($upper > 0) place($band,30 + min(30,(int)floor(30 * ($upper / $threshold) + 0.5)),$upperSignal ? '*' : '+');
    return implode('',$band);
}
function width_band(float $scale, float $width, float $value, float $center, bool $signalled): string {
    $band = array_fill(0,61,'.'); $edge = min(30,(int)floor(30 * ($width / $scale) + 0.5)); place($band,30,'|'); place($band,30 - $edge,':'); place($band,30 + $edge,':');
    place($band,30 + (int)floor(30 * (($value - $center) / $scale) + 0.5),$signalled ? '*' : 'o'); return implode('',$band);
}
function standard_band(float $z, bool $ok): string { $band = framed_band(30); place($band,30 + (int)floor(10 * $z + 0.5),$ok ? 'o' : '*'); return implode('',$band); }
