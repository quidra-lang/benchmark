<?php

function ratio(int $numerator, int $denominator): string
{
    if ($denominator === 0) {
        return '-';
    }
    $whole = intdiv($numerator, $denominator);
    $remainder = $numerator % $denominator;
    $fraction = intdiv(20000 * $remainder + $denominator, 2 * $denominator);
    if ($fraction === 10000) {
        $whole++;
        $fraction = 0;
    }
    return $whole . '.' . str_pad((string) $fraction, 4, '0', STR_PAD_LEFT);
}

function samHeader(array $references): array
{
    $lines = ["@HD\tVN:1.6\tSO:unsorted"];
    foreach ($references as $reference) {
        $lines[] = "@SQ\tSN:" . $reference->name . "\tLN:" . strlen($reference->sequence);
    }
    $lines[] = "@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0";
    return $lines;
}

function samRecord(object $read, object $result, array $references, int $maximumAlternatives): string
{
    if (isset($result->reason)) {
        return implode("\t", [$read->name, 4, '*', 0, 0, '*', '*', 0, 0, $read->sequence, $read->quality, 'YM:Z:' . $result->reason]);
    }
    $primary = $result->alignments[0];
    $reverse = $primary->strand === 1;
    $fields = [$read->name, $reverse ? 16 : 0, $references[$primary->r]->name, $primary->pos + 1, $result->mapq,
        $primary->cigar, '*', 0, 0, $reverse ? reverseComplement($read->sequence) : $read->sequence,
        $reverse ? strrev($read->quality) : $read->quality, 'NM:i:' . $primary->nm, 'MD:Z:' . $primary->md,
        'AS:i:' . $result->score, 'X0:i:' . $result->x0, 'X1:i:' . $result->x1, 'YM:Z:' . $result->method];
    $alternatives = array_slice($result->alignments, 1);
    if ($alternatives && count($alternatives) <= $maximumAlternatives) {
        $tag = '';
        foreach ($alternatives as $alignment) {
            $tag .= $references[$alignment->r]->name . ',' . ($alignment->strand === 0 ? '+' : '-') . ($alignment->pos + 1)
                . ',' . $alignment->cigar . ',' . $alignment->nm . ';';
        }
        $fields[] = 'XA:Z:' . $tag;
    }
    return implode("\t", $fields);
}

function writeLines(string $path, array $lines): void
{
    file_put_contents($path, implode("\n", $lines) . "\n");
}
