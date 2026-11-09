<?php

function readSequences(): object
{
    $references = [];
    foreach (file('input/reference.fasta', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line[0] === '>') {
            $name = explode(' ', substr($line, 1))[0];
            $references[] = (object) ['name' => $name, 'sequence' => '', 'masked' => 0];
        } else {
            $reference = $references[count($references) - 1];
            $reference->masked += preg_match_all('/[acgt]/', $line);
            $reference->sequence .= strtoupper($line);
        }
    }
    $records = file('input/reads.fastq', FILE_IGNORE_NEW_LINES);
    $reads = [];
    for ($i = 0; $i < count($records); $i += 4) {
        $qualities = [];
        for ($j = 0; $j < strlen($records[$i + 3]); $j++) {
            $qualities[] = ord($records[$i + 3][$j]) - 33;
        }
        $reads[] = (object) ['name' => substr($records[$i], 1), 'sequence' => $records[$i + 1],
            'quality' => $records[$i + 3], 'qualities' => $qualities];
    }
    $params = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $parts = explode(' ', $line);
        $key = array_shift($parts);
        $values = array_map('intval', $parts);
        $params[$key] = $key === 'SCORES' || $key === 'VARIANTS' ? $values : $values[0];
    }
    return (object) ['references' => $references, 'reads' => $reads, 'params' => $params];
}

function reverseComplement(string $sequence): string
{
    return strtr(strrev($sequence), 'ACGTN', 'TGCAN');
}
