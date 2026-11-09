<?php

const BASES = ['A' => 1, 'C' => 2, 'G' => 4, 'T' => 8, 'R' => 5, 'Y' => 10, 'S' => 6, 'W' => 9,
    'K' => 12, 'M' => 3, 'B' => 14, 'D' => 13, 'H' => 11, 'V' => 7, 'N' => 15, '-' => 15];
const LETTERS = 'ACGT';

function readFasta(string $path): array
{
    $records = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES) as $i => $line) {
        if (str_starts_with($line, '>')) {
            $fields = explode(' ', substr($line, 1), 2);
            $records[] = (object) ['name' => $fields[0], 'line' => $i + 1, 'sequence' => ''];
        } else {
            $records[count($records) - 1]->sequence .= strtoupper($line);
        }
    }
    return $records;
}

function encode(array $taxa): array
{
    $result = [];
    foreach ($taxa as $taxon) {
        $sequence = [];
        for ($i = 0; $i < strlen($taxon->sequence); $i++) {
            $sequence[] = BASES[$taxon->sequence[$i]];
        }
        $result[] = $sequence;
    }
    return $result;
}

function patterns(array $taxa, int $length): object
{
    $columns = [];
    $distinct = [];
    for ($c = 0; $c < $length; $c++) {
        $pattern = '';
        foreach ($taxa as $taxon) {
            $pattern .= $taxon->sequence[$c];
        }
        $columns[] = $pattern;
        $distinct[$pattern][] = $c;
    }
    return (object) compact('columns', 'distinct');
}

function classifyColumns(array $taxa, int $length): array
{
    $columns = [];
    for ($c = 0; $c < $length; $c++) {
        $counts = [0, 0, 0, 0];
        $gapped = false;
        foreach ($taxa as $taxon) {
            $character = $taxon->sequence[$c];
            $base = strpos(LETTERS, $character);
            if ($base !== false) {
                $counts[$base]++;
            }
            if ($character === '-') {
                $gapped = true;
            }
        }
        $kinds = count(array_filter($counts, fn($count) => $count > 0));
        $informative = count(array_filter($counts, fn($count) => $count >= 2)) >= 2;
        $columns[] = (object) compact('counts', 'kinds', 'gapped', 'informative');
    }
    return $columns;
}
