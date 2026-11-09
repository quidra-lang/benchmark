<?php

declare(strict_types=1);

const BASES = 'ACGT';

const IUPAC = [
    'A' => 'A', 'C' => 'C', 'G' => 'G', 'T' => 'T', 'R' => 'AG',
    'Y' => 'CT', 'W' => 'AT', 'S' => 'CG', 'K' => 'GT', 'M' => 'AC',
    'B' => 'CGT', 'D' => 'AGT', 'H' => 'ACT', 'V' => 'ACG', 'N' => 'ACGT',
];

const GENETIC_GROUPS = [
    'A' => 'GCT GCC GCA GCG', 'C' => 'TGT TGC', 'D' => 'GAT GAC',
    'E' => 'GAA GAG', 'F' => 'TTT TTC', 'G' => 'GGT GGC GGA GGG',
    'H' => 'CAT CAC', 'I' => 'ATT ATC ATA', 'K' => 'AAA AAG',
    'L' => 'TTA TTG CTT CTC CTA CTG', 'M' => 'ATG', 'N' => 'AAT AAC',
    'P' => 'CCT CCC CCA CCG', 'Q' => 'CAA CAG',
    'R' => 'CGT CGC CGA CGG AGA AGG', 'S' => 'TCT TCC TCA TCG AGT AGC',
    'T' => 'ACT ACC ACA ACG', 'V' => 'GTT GTC GTA GTG', 'W' => 'TGG',
    'Y' => 'TAT TAC', '*' => 'TAA TAG TGA',
];

const AMINO_MASS = [
    'A' => 71079, 'C' => 103139, 'D' => 115089, 'E' => 129116,
    'F' => 147177, 'G' => 57052, 'H' => 137141, 'I' => 113160,
    'K' => 128174, 'L' => 113160, 'M' => 131193, 'N' => 114104,
    'P' => 97117, 'Q' => 128131, 'R' => 156188, 'S' => 87078,
    'T' => 101105, 'V' => 99133, 'W' => 186213, 'Y' => 163176,
];

const BASE_MASS = ['A' => 331222, 'C' => 307197, 'G' => 347221, 'T' => 322208];

const ENZYMES = [
    'EcoRI' => ['GAATTC', 1], 'BamHI' => ['GGATCC', 1],
    'HindIII' => ['AAGCTT', 1], 'PstI' => ['CTGCAG', 5],
    'SmaI' => ['CCCGGG', 3], 'KpnI' => ['GGTACC', 5],
    'XbaI' => ['TCTAGA', 1], 'NotI' => ['GCGGCCGC', 2],
    'EcoRV' => ['GATATC', 3], 'HaeIII' => ['GGCC', 2],
    'AluI' => ['AGCT', 2], 'TaqI' => ['TCGA', 1],
    'Sau3AI' => ['GATC', 0], 'HincII' => ['GTYRAC', 3],
    'AvaI' => ['CYCGRG', 1],
];

const ARITY = [
    'SEQ' => [2, 2], 'SLICE' => [4, 4], 'JOIN' => [3, 9],
    'MUTATE' => [3, 3], 'DEL' => [1, 1], 'LIST' => [0, 0],
    'REVCOMP' => [1, 1], 'COMPLEMENT' => [1, 1], 'REVERSE' => [1, 1],
    'TRANSCRIBE' => [1, 1], 'TRANSLATE' => [2, 2], 'CODONS' => [2, 2],
    'PROTEIN' => [2, 2], 'ORFS' => [2, 2], 'GC' => [1, 1],
    'GCWINDOW' => [3, 3], 'SKEW' => [1, 1], 'KMERS' => [3, 3],
    'FIND' => [2, 2], 'RESTRICT' => [2, 7], 'PALINDROMES' => [3, 3],
    'REPEATS' => [4, 4], 'HAMMING' => [2, 2], 'ALIGN' => [6, 6],
    'CONSENSUS' => [2, 10], 'TM' => [1, 1], 'MASS' => [1, 1],
    'PRIMER' => [1, 1], 'FOLD' => [2, 2], 'ASSEMBLE' => [4, 10],
    'PACK' => [1, 1], 'UNPACK' => [3, 3],
];

final class CommandError extends RuntimeException {}

function revcomp(string $sequence): string
{
    return strrev(strtr($sequence, 'ACGTRYWSKMBVDHN', 'TGCAYRWSMKVBHDN'));
}

function gc(string $sequence): int
{
    return substr_count($sequence, 'G') + substr_count($sequence, 'C');
}

function fixed(int $value, int $places): string
{
    $scale = 10 ** $places;
    return intdiv($value, $scale) . '.' . str_pad((string) ($value % $scale), $places, '0', STR_PAD_LEFT);
}

function percentage(int $part, int $whole): string
{
    return fixed(intdiv(10000 * $part, $whole), 2);
}

function transition(string $a, string $b): bool
{
    return $a !== $b && in_array($a . $b, ['AG', 'GA', 'CT', 'TC'], true);
}

function frequencyOrder(array $counts): array
{
    $keys = array_keys($counts);
    usort($keys, static function (string $a, string $b) use ($counts): int {
        return ($counts[$b] <=> $counts[$a]) ?: strcmp($a, $b);
    });
    return $keys;
}

function codons(string $sequence, int $frame): array
{
    $strand = $frame > 0 ? $sequence : revcomp($sequence);
    $triplets = [];
    for ($offset = abs($frame) - 1, $n = strlen($strand); $offset + 2 < $n; $offset += 3) {
        $triplets[] = substr($strand, $offset, 3);
    }
    return $triplets;
}

function occurrences(string $sequence, string $motif): array
{
    $found = [];
    $n = strlen($sequence);
    $m = strlen($motif);
    for ($start = 0; $start + $m <= $n; ++$start) {
        $matches = true;
        for ($i = 0; $i < $m; ++$i) {
            if (strpos(IUPAC[$motif[$i]], $sequence[$start + $i]) === false) {
                $matches = false;
                break;
            }
        }
        if ($matches) {
            $found[] = $start + 1;
        }
    }
    return $found;
}

function repeatCount(string $sequence, int $position, int $width): int
{
    $unit = substr($sequence, $position, $width);
    $count = 0;
    while (substr($sequence, $position + $count * $width, $width) === $unit) {
        ++$count;
    }
    return $count;
}

function primitive(string $unit): bool
{
    $length = strlen($unit);
    for ($width = 1; $width < $length; ++$width) {
        if ($length % $width === 0 &&
            str_repeat(substr($unit, 0, $width), intdiv($length, $width)) === $unit) {
            return false;
        }
    }
    return true;
}

function longestPalindrome(string $sequence): int
{
    $longest = 0;
    $n = strlen($sequence);
    for ($center = 1; $center < $n; ++$center) {
        $left = $center - 1;
        $right = $center;
        while ($left >= 0 && $right < $n &&
            strtr($sequence[$left], 'ACGT', 'TGCA') === $sequence[$right]) {
            $longest = max($longest, $right - $left + 1);
            --$left;
            ++$right;
        }
    }
    return $longest;
}

function temperature(string $sequence): int
{
    $n = strlen($sequence);
    $amount = gc($sequence);
    return $n < 14
        ? 10 * (2 * ($n - $amount) + 4 * $amount)
        : intdiv(649 * $n + 410 * $amount - 6724, $n);
}

function strandMass(string $sequence): int
{
    $mass = 0;
    for ($i = 0, $n = strlen($sequence); $i < $n; ++$i) {
        $mass += BASE_MASS[$sequence[$i]];
    }
    return $mass - ($n - 1) * 18015;
}

final class Toolkit
{
    private array $registry = [];
    private array $output = [];
    private array $code;

    public function __construct()
    {
        $this->code = [];
        foreach (GENETIC_GROUPS as $amino => $codons) {
            foreach (explode(' ', $codons) as $codon) {
                $this->code[$codon] = (string) $amino;
            }
        }
    }

    private function emit(string|int ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function emitList(string $label, array $values): void
    {
        $this->emit($label, ...($values ?: ['none']));
    }

    private function number(string $text, int $min, int $max, bool $nonzero = false): int
    {
        if (!preg_match('/^-?[0-9]{1,6}$/D', $text)) {
            throw new CommandError('invalid number ' . $text);
        }
        $number = (int) $text;
        if ($number < $min || $number > $max || ($nonzero && $number === 0)) {
            throw new CommandError('invalid number ' . $text);
        }
        return $number;
    }

    private function kinds(string $command, int $count): array
    {
        return match ($command) {
            'SEQ' => ['new', 'sequence'],
            'SLICE' => ['name', 'position', 'position', 'new'],
            'JOIN' => array_merge(['new'], array_fill(0, $count - 1, 'name')),
            'MUTATE' => ['name', 'position', 'base'],
            'TRANSLATE', 'CODONS', 'PROTEIN' => ['name', 'frame'],
            'ORFS' => ['name', 'orf'],
            'GCWINDOW' => ['name', 'window', 'window'],
            'KMERS' => ['name', 'kmer', 'limit'],
            'FIND' => ['name', 'motif'],
            'RESTRICT' => array_merge(['name'], array_fill(0, $count - 1, 'enzyme')),
            'PALINDROMES' => ['name', 'palindrome', 'palindrome'],
            'REPEATS' => ['name', 'repeat', 'repeat', 'repeatCount'],
            'ALIGN' => ['name', 'name', 'mode', 'match', 'mismatch', 'gap'],
            'FOLD' => ['name', 'loop'],
            'ASSEMBLE' => array_merge(['new', 'overlap'], array_fill(0, $count - 2, 'name')),
            'UNPACK' => ['new', 'length', 'hex'],
            default => array_fill(0, $count, 'name'),
        };
    }

    private function validate(string $command, array $args): array
    {
        if (!isset(ARITY[$command])) {
            throw new CommandError('unknown command ' . $command);
        }
        [$minimum, $maximum] = ARITY[$command];
        if (count($args) < $minimum || count($args) > $maximum) {
            throw new CommandError('wrong argument count');
        }
        $values = $args;
        $seen = [];
        foreach ($this->kinds($command, count($args)) as $position => $kind) {
            $text = $args[$position];
            switch ($kind) {
                case 'position':
                case 'frame':
                case 'orf':
                case 'window':
                case 'kmer':
                case 'limit':
                case 'palindrome':
                case 'repeat':
                case 'repeatCount':
                case 'match':
                case 'mismatch':
                case 'gap':
                case 'loop':
                case 'overlap':
                case 'length':
                    [$min, $max] = match ($kind) {
                        'position' => [1, strlen($this->registry[$args[0]])],
                        'frame' => [-3, 3],
                        'orf' => [1, 200],
                        'window' => [1, 500],
                        'kmer' => [1, 12],
                        'limit' => [1, 100],
                        'palindrome' => [2, 20],
                        'repeat' => [1, 6],
                        'repeatCount' => [2, 50],
                        'match' => [1, 20],
                        'mismatch' => [-20, 0],
                        'gap' => [-20, -1],
                        'loop' => [0, 10],
                        'overlap' => [1, 100],
                        'length' => [1, 500],
                    };
                    $values[$position] = $this->number($text, $min, $max, $kind === 'frame');
                    break;
                case 'name':
                    if (!array_key_exists($text, $this->registry)) {
                        throw new CommandError('unknown sequence ' . $text);
                    }
                    break;
                case 'new':
                    if (!preg_match('/^[a-z][a-z0-9]{0,9}$/D', $text)) {
                        throw new CommandError('invalid name ' . $text);
                    }
                    break;
                case 'sequence':
                    for ($i = 0, $n = strlen($text); $i < $n; ++$i) {
                        if (strpos(BASES, $text[$i]) === false) {
                            throw new CommandError('invalid base ' . $text[$i] . ' at ' . ($i + 1));
                        }
                    }
                    break;
                case 'base':
                    if (strlen($text) !== 1 || strpos(BASES, $text) === false) {
                        throw new CommandError('invalid base ' . $text);
                    }
                    break;
                case 'motif':
                    if (strlen($text) < 1 || strlen($text) > 30 ||
                        strspn($text, implode('', array_keys(IUPAC))) !== strlen($text)) {
                        throw new CommandError('invalid motif ' . $text);
                    }
                    break;
                case 'enzyme':
                    if (!isset(ENZYMES[$text])) {
                        throw new CommandError('unknown enzyme ' . $text);
                    }
                    if (isset($seen[$text])) {
                        throw new CommandError('duplicate enzyme ' . $text);
                    }
                    $seen[$text] = true;
                    break;
                case 'mode':
                    if (!in_array($text, ['GLOBAL', 'LOCAL'], true)) {
                        throw new CommandError('invalid mode ' . $text);
                    }
                    break;
                case 'hex':
                    if (strlen($text) !== 2 * intdiv($values[1] + 3, 4) ||
                        !preg_match('/^[0-9A-F]+$/D', $text)) {
                        throw new CommandError('invalid hex');
                    }
                    break;
            }
        }
        return $values;
    }

    private function store(string $name, string $sequence): string
    {
        if (strlen($sequence) > 500) {
            throw new CommandError('too long');
        }
        $label = array_key_exists($name, $this->registry) ? 'replaced' : 'stored';
        $this->registry[$name] = $sequence;
        return $label . ' ' . $name . ' ' . strlen($sequence) . ' nt';
    }

    private function translation(string $command, string $name, int $frame): void
    {
        $triplets = codons($this->registry[$name], $frame);
        $protein = '';
        foreach ($triplets as $codon) {
            $protein .= $this->code[$codon];
        }

        if ($command === 'TRANSLATE') {
            $this->emit($protein !== '' ? $protein : 'none');
        } elseif ($command === 'CODONS') {
            $counts = array_count_values($triplets);
            if (!$counts) {
                $this->emit('none');
            }
            foreach (frequencyOrder($counts) as $codon) {
                $this->emit($codon, $this->code[$codon], $counts[$codon]);
            }
        } else {
            $protein = explode('*', $protein, 2)[0];
            if ($protein === '') {
                throw new CommandError('empty protein');
            }
            $counts = array_count_values(str_split($protein));
            $mass = 18015;
            $charge = 0;
            foreach (str_split($protein) as $amino) {
                $mass += AMINO_MASS[$amino];
                $charge += (int) ($amino === 'K' || $amino === 'R');
                $charge -= (int) ($amino === 'D' || $amino === 'E');
            }
            $this->emit($protein);
            $this->emit('length', strlen($protein), 'mass', fixed($mass, 3),
                        'charge', $charge > 0 ? '+' . $charge : $charge);
            $entries = [];
            foreach (frequencyOrder($counts) as $amino) {
                $entries[] = $amino . '=' . $counts[$amino];
            }
            $this->emit(...$entries);
        }
    }

    private function orfs(string $sequence, int $minimum): void
    {
        $rows = [];
        foreach ([1, 2, 3, -1, -2, -3] as $frame) {
            $triplets = codons($sequence, $frame);
            $start = null;
            foreach ($triplets as $position => $codon) {
                if ($start === null) {
                    if ($codon === 'ATG') {
                        $start = $position;
                    }
                } elseif ($this->code[$codon] === '*') {
                    if ($position - $start >= $minimum) {
                        $left = abs($frame) - 1 + 3 * $start;
                        $right = abs($frame) - 1 + 3 * ($position + 1);
                        if ($frame < 0) {
                            [$left, $right] = [strlen($sequence) - $right, strlen($sequence) - $left];
                        }
                        $protein = '';
                        for ($i = $start; $i < $position; ++$i) {
                            $protein .= $this->code[$triplets[$i]];
                        }
                        $rows[] = [$left + 1, $right, $frame, $protein];
                    }
                    $start = null;
                }
            }
        }
        usort($rows, static function (array $a, array $b): int {
            return ($a[0] <=> $b[0]) ?: (($a[1] <=> $b[1]) ?:
                   (($a[2] <=> $b[2]) ?: strcmp($a[3], $b[3])));
        });
        if (!$rows) {
            $this->emit('none');
        }
        foreach ($rows as [$left, $right, $frame, $protein]) {
            $this->emit(sprintf('%+d', $frame), $left, $right, strlen($protein), $protein);
        }
    }

    private function restriction(string $sequence, array $enzymes): void
    {
        $combined = [];
        foreach ($enzymes as $enzyme) {
            [$motif, $offset] = ENZYMES[$enzyme];
            $cuts = [];
            foreach (occurrences($sequence, $motif) as $start) {
                $cut = $start + $offset - 1;
                if (1 <= $cut && $cut < strlen($sequence)) {
                    $cuts[] = $cut;
                    $combined[$cut] = true;
                }
            }
            $this->emitList($enzyme, $cuts);
        }
        $endpoints = array_map('intval', array_keys($combined));
        sort($endpoints, SORT_NUMERIC);
        $endpoints = array_merge([0], $endpoints, [strlen($sequence)]);
        $fragments = [];
        $sizes = [];
        for ($i = 1, $n = count($endpoints); $i < $n; ++$i) {
            $left = $endpoints[$i - 1] + 1;
            $right = $endpoints[$i];
            $fragments[] = $left . '-' . $right;
            $sizes[] = $right - $left + 1;
        }
        rsort($sizes, SORT_NUMERIC);
        $this->emitList('fragments', $fragments);
        $this->emitList('sizes', $sizes);
    }

    private function repeats(string $sequence, int $minimum, int $maximum, int $count): void
    {
        if ($minimum > $maximum) {
            throw new CommandError('invalid range');
        }
        $rows = [];
        for ($width = $minimum; $width <= $maximum; ++$width) {
            $position = 0;
            while ($position + $width <= strlen($sequence)) {
                $unit = substr($sequence, $position, $width);
                $repeated = repeatCount($sequence, $position, $width);
                if (primitive($unit) && $repeated >= $count) {
                    $rows[] = [$position, $width, $repeated, $unit];
                    $position += $width * $repeated;
                } else {
                    ++$position;
                }
            }
        }
        usort($rows, static function (array $a, array $b): int {
            return ($a[0] <=> $b[0]) ?: (($a[1] <=> $b[1]) ?:
                   (($a[2] <=> $b[2]) ?: strcmp($a[3], $b[3])));
        });
        if (!$rows) {
            $this->emit('none');
        }
        foreach ($rows as [$position, $width, $repeated, $unit]) {
            $this->emit(($position + 1) . '-' . ($position + $width * $repeated),
                        $unit . 'x' . $repeated);
        }
    }

    private function alignment(string $a, string $b, string $mode,
                               int $match, int $mismatch, int $gap): void
    {
        $m = strlen($a);
        $n = strlen($b);
        $local = $mode === 'LOCAL';
        $matrix = array_fill(0, $m + 1, array_fill(0, $n + 1, 0));
        if (!$local) {
            for ($i = 0; $i <= $m; ++$i) {
                $matrix[$i][0] = $i * $gap;
            }
            for ($j = 0; $j <= $n; ++$j) {
                $matrix[0][$j] = $j * $gap;
            }
        }
        $best = 0;
        $endI = 0;
        $endJ = 0;
        for ($i = 1; $i <= $m; ++$i) {
            for ($j = 1; $j <= $n; ++$j) {
                $diagonal = $matrix[$i - 1][$j - 1] +
                            ($a[$i - 1] === $b[$j - 1] ? $match : $mismatch);
                $value = max($diagonal, $matrix[$i - 1][$j] + $gap,
                             $matrix[$i][$j - 1] + $gap);
                $matrix[$i][$j] = $local ? max(0, $value) : $value;
                if ($local && $matrix[$i][$j] > $best) {
                    $best = $matrix[$i][$j];
                    $endI = $i;
                    $endJ = $j;
                }
            }
        }
        if (!$local) {
            $endI = $m;
            $endJ = $n;
            $best = $matrix[$m][$n];
        }
        if ($local && $best === 0) {
            $this->emit('score', 0);
            return;
        }
        $i = $endI;
        $j = $endJ;
        $rowA = [];
        $rowB = [];
        while (($local && $matrix[$i][$j] !== 0) || (!$local && ($i !== 0 || $j !== 0))) {
            if ($i > 0 && $j > 0 &&
                $matrix[$i][$j] === $matrix[$i - 1][$j - 1] +
                ($a[$i - 1] === $b[$j - 1] ? $match : $mismatch)) {
                $rowA[] = $a[--$i];
                $rowB[] = $b[--$j];
            } elseif ($i > 0 && $matrix[$i][$j] === $matrix[$i - 1][$j] + $gap) {
                $rowA[] = $a[--$i];
                $rowB[] = '-';
            } else {
                $rowA[] = '-';
                $rowB[] = $b[--$j];
            }
        }
        $rowA = array_reverse($rowA);
        $rowB = array_reverse($rowB);
        $marks = '';
        $identical = 0;
        $gaps = 0;
        for ($position = 0; $position < count($rowA); ++$position) {
            $x = $rowA[$position];
            $y = $rowB[$position];
            if ($x === '-' || $y === '-') {
                $marks .= '-';
                ++$gaps;
            } elseif ($x === $y) {
                $marks .= '|';
                ++$identical;
            } else {
                $marks .= '*';
            }
        }
        $this->emit('score', $best, 'a', ($i + 1) . '-' . $endI,
                    'b', ($j + 1) . '-' . $endJ,
                    'identity', $identical . '/' . strlen($marks), 'gaps', $gaps);
        $this->emit(implode('', $rowA));
        $this->emit($marks);
        $this->emit(implode('', $rowB));
    }

    private function consensus(array $sequences): void
    {
        $n = strlen($sequences[0]);
        foreach ($sequences as $sequence) {
            if (strlen($sequence) !== $n) {
                throw new CommandError('length mismatch');
            }
        }
        $profile = ['A' => [], 'C' => [], 'G' => [], 'T' => []];
        $consensus = '';
        $ambiguous = '';
        $symbols = array_flip(IUPAC);
        for ($position = 0; $position < $n; ++$position) {
            $counts = array_fill_keys(str_split(BASES), 0);
            foreach ($sequences as $sequence) {
                ++$counts[$sequence[$position]];
            }
            $maxCount = max($counts);
            $tied = '';
            foreach ($counts as $base => $value) {
                $profile[$base][] = $value;
                if ($value === $maxCount) {
                    $tied .= $base;
                }
            }
            $consensus .= $tied[0];
            $ambiguous .= $symbols[$tied];
        }
        foreach ($profile as $base => $counts) {
            $this->emit($base, ...$counts);
        }
        $this->emit('consensus', $consensus);
        $this->emit('iupac', $ambiguous);
    }

    private function primer(string $sequence): void
    {
        $n = strlen($sequence);
        $amount = gc($sequence);
        $tm = temperature($sequence);
        $clamp = gc(substr($sequence, -5));
        $longestRun = 0;
        $run = 0;
        $last = '';
        for ($i = 0; $i < $n; ++$i) {
            $run = $sequence[$i] === $last ? $run + 1 : 1;
            $last = $sequence[$i];
            $longestRun = max($longestRun, $run);
        }
        $repeated = 0;
        for ($i = 0; $i + 1 < $n; ++$i) {
            if ($sequence[$i] !== $sequence[$i + 1]) {
                $repeated = max($repeated, repeatCount($sequence, $i, 2));
            }
        }
        $selfcomp = longestPalindrome($sequence);
        $results = [
            'length' => [$n, 18 <= $n && $n <= 25],
            'gc' => [percentage($amount, $n), 40 * $n <= 100 * $amount && 100 * $amount <= 60 * $n],
            'tm' => [fixed($tm, 1), 520 <= $tm && $tm <= 620],
            'clamp' => [$clamp, 1 <= $clamp && $clamp <= 3],
            'run' => [$longestRun, $longestRun <= 4],
            'repeat' => [$repeated, $repeated <= 4],
            'selfcomp' => [$selfcomp, $selfcomp <= 6],
        ];
        $failed = [];
        foreach ($results as $label => [$value, $passed]) {
            $this->emit($label, $value, $passed ? 'OK' : 'FAIL');
            if (!$passed) {
                $failed[] = $label;
            }
        }
        $this->emit($failed ? 'FAIL' : 'PASS', ...$failed);
    }

    private function folding(string $sequence, int $loop): void
    {
        $n = strlen($sequence);
        if ($n > 100) {
            throw new CommandError('too long');
        }
        $table = array_fill(0, $n, array_fill(0, $n, 0));
        $paired = static function (string $a, string $b): bool {
            return in_array($a . $b, ['AT', 'TA', 'CG', 'GC', 'GT', 'TG'], true);
        };
        $value = static function (int $i, int $j) use (&$table): int {
            return $i > $j ? 0 : $table[$i][$j];
        };
        for ($width = 2; $width <= $n; ++$width) {
            for ($i = 0; $i + $width <= $n; ++$i) {
                $j = $i + $width - 1;
                $best = $value($i, $j - 1);
                for ($k = $i; $k < $j - $loop; ++$k) {
                    if ($paired($sequence[$k], $sequence[$j])) {
                        $best = max($best, $value($i, $k - 1) + 1 + $value($k + 1, $j - 1));
                    }
                }
                $table[$i][$j] = $best;
            }
        }
        $structure = str_repeat('.', $n);
        $pending = [[0, $n - 1]];
        while ($pending) {
            [$i, $j] = array_pop($pending);
            if ($i > $j || $value($i, $j) === 0) {
                continue;
            }
            if ($value($i, $j) === $value($i, $j - 1)) {
                $pending[] = [$i, $j - 1];
                continue;
            }
            for ($k = $i; $k < $j - $loop; ++$k) {
                if ($paired($sequence[$k], $sequence[$j]) &&
                    $value($i, $k - 1) + 1 + $value($k + 1, $j - 1) === $value($i, $j)) {
                    $structure[$k] = '(';
                    $structure[$j] = ')';
                    $pending[] = [$i, $k - 1];
                    $pending[] = [$k + 1, $j - 1];
                    break;
                }
            }
        }
        $this->emit($structure);
        $this->emit('pairs', $table[0][$n - 1]);
    }

    private function assembly(string $name, int $minimum, array $sequences): void
    {
        $unique = array_values(array_unique($sequences));
        $fragments = [];
        foreach ($unique as $fragment) {
            $contained = false;
            foreach ($unique as $other) {
                if ($fragment !== $other && strpos($other, $fragment) !== false) {
                    $contained = true;
                    break;
                }
            }
            if (!$contained) {
                $fragments[] = $fragment;
            }
        }
        while (count($fragments) >= 2) {
            $best = 0;
            $chosen = null;
            foreach ($fragments as $i => $a) {
                foreach ($fragments as $j => $b) {
                    if ($i === $j) {
                        continue;
                    }
                    $overlap = 0;
                    $limit = min(strlen($a), strlen($b));
                    for ($width = $limit - 1; $width > 0; --$width) {
                        if (substr($a, -$width) === substr($b, 0, $width)) {
                            $overlap = $width;
                            break;
                        }
                    }
                    if ($chosen === null || $overlap > $best) {
                        $best = $overlap;
                        $chosen = [$i, $j];
                    }
                }
            }
            if ($best < $minimum) {
                break;
            }
            [$i, $j] = $chosen;
            $merged = $fragments[$i] . substr($fragments[$j], $best);
            $next = [];
            foreach ($fragments as $k => $fragment) {
                if ($k === $i) {
                    $next[] = $merged;
                } elseif ($k !== $j && strpos($merged, $fragment) === false) {
                    $next[] = $fragment;
                }
            }
            $fragments = $next;
        }
        $longest = $fragments[0];
        foreach ($fragments as $fragment) {
            if (strlen($fragment) > strlen($longest)) {
                $longest = $fragment;
            }
        }
        $registration = $this->store($name, $longest);
        $this->emit('contigs', count($fragments));
        foreach ($fragments as $fragment) {
            $this->emit(strlen($fragment), $fragment);
        }
        $this->emit($registration);
    }

    private function command(string $command, array $a): void
    {
        if ($command === 'SEQ') {
            $this->emit($this->store($a[0], $a[1]));
            return;
        }
        if ($command === 'UNPACK') {
            $codes = [];
            foreach (str_split(hex2bin($a[2])) as $byte) {
                $value = ord($byte);
                $codes[] = intdiv($value, 64);
                $codes[] = intdiv($value, 16) % 4;
                $codes[] = intdiv($value, 4) % 4;
                $codes[] = $value % 4;
            }
            foreach (array_slice($codes, $a[1]) as $code) {
                if ($code !== 0) {
                    throw new CommandError('invalid padding');
                }
            }
            $sequence = '';
            foreach (array_slice($codes, 0, $a[1]) as $code) {
                $sequence .= BASES[$code];
            }
            $this->emit($this->store($a[0], $sequence));
            return;
        }
        if ($command === 'JOIN') {
            $sequence = '';
            foreach (array_slice($a, 1) as $name) {
                $sequence .= $this->registry[$name];
            }
            $this->emit($this->store($a[0], $sequence));
            return;
        }
        if ($command === 'ASSEMBLE') {
            $sequences = [];
            foreach (array_slice($a, 2) as $name) {
                $sequences[] = $this->registry[$name];
            }
            $this->assembly($a[0], $a[1], $sequences);
            return;
        }
        if ($command === 'LIST') {
            $names = array_keys($this->registry);
            sort($names, SORT_STRING);
            if (!$names) {
                $this->emit('no sequences');
            }
            foreach ($names as $name) {
                $this->emit($name, strlen($this->registry[$name]), 'nt');
            }
            return;
        }

        $name = $a[0];
        $sequence = $this->registry[$name];
        $n = strlen($sequence);
        switch ($command) {
            case 'SLICE':
                $part = $a[1] <= $a[2]
                    ? substr($sequence, $a[1] - 1, $a[2] - $a[1] + 1)
                    : revcomp(substr($sequence, $a[2] - 1, $a[1] - $a[2] + 1));
                $this->emit($this->store($a[3], $part));
                break;
            case 'MUTATE':
                $old = $sequence[$a[1] - 1];
                if ($old === $a[2]) {
                    throw new CommandError('no change');
                }
                $this->registry[$name] = substr_replace($sequence, $a[2], $a[1] - 1, 1);
                $this->emit($name, $old . $a[1] . $a[2],
                            transition($old, $a[2]) ? 'transition' : 'transversion');
                break;
            case 'DEL':
                unset($this->registry[$name]);
                $this->emit('deleted', $name);
                break;
            case 'REVCOMP':
                $this->emit(revcomp($sequence));
                break;
            case 'COMPLEMENT':
                $this->emit(strtr($sequence, 'ACGTRYWSKMBVDHN', 'TGCAYRWSMKVBHDN'));
                break;
            case 'REVERSE':
                $this->emit(strrev($sequence));
                break;
            case 'TRANSCRIBE':
                $this->emit(str_replace('T', 'U', $sequence));
                break;
            case 'TRANSLATE':
            case 'CODONS':
            case 'PROTEIN':
                $this->translation($command, $name, $a[1]);
                break;
            case 'ORFS':
                $this->orfs($sequence, $a[1]);
                break;
            case 'GC':
                $parts = [];
                foreach (str_split(BASES) as $base) {
                    $parts[] = $base . '=' . substr_count($sequence, $base);
                }
                $parts[] = 'GC=' . percentage(gc($sequence), $n) . '%';
                $this->emit(...$parts);
                break;
            case 'GCWINDOW':
                if ($a[1] > $n) {
                    throw new CommandError('window too large');
                }
                for ($i = 0; $i + $a[1] <= $n; $i += $a[2]) {
                    $this->emit(($i + 1) . '-' . ($i + $a[1]),
                                percentage(gc(substr($sequence, $i, $a[1])), $a[1]) . '%');
                }
                break;
            case 'SKEW':
                $prefix = [0];
                $skew = 0;
                for ($i = 0; $i < $n; ++$i) {
                    $skew += (int) ($sequence[$i] === 'G') - (int) ($sequence[$i] === 'C');
                    $prefix[] = $skew;
                }
                foreach (['min' => min($prefix), 'max' => max($prefix)] as $label => $extreme) {
                    $positions = [];
                    foreach ($prefix as $position => $value) {
                        if ($value === $extreme) {
                            $positions[] = $position;
                        }
                    }
                    $this->emit($label, $extreme, 'at', ...$positions);
                }
                break;
            case 'KMERS':
                if ($a[1] > $n) {
                    throw new CommandError('k too large');
                }
                $counts = [];
                for ($i = 0; $i + $a[1] <= $n; ++$i) {
                    $word = substr($sequence, $i, $a[1]);
                    $counts[$word] = ($counts[$word] ?? 0) + 1;
                }
                $this->emit($n - $a[1] + 1, 'windows', count($counts), 'distinct');
                foreach (array_slice(frequencyOrder($counts), 0, $a[2]) as $word) {
                    $this->emit($word, $counts[$word]);
                }
                break;
            case 'FIND':
                $this->emitList('forward', occurrences($sequence, $a[1]));
                $this->emitList('reverse', occurrences($sequence, revcomp($a[1])));
                break;
            case 'RESTRICT':
                $this->restriction($sequence, array_slice($a, 1));
                break;
            case 'PALINDROMES':
                if ($a[1] > $a[2]) {
                    throw new CommandError('invalid range');
                }
                $found = false;
                for ($i = 0; $i < $n; ++$i) {
                    for ($width = $a[1]; $width <= $a[2] && $i + $width <= $n; ++$width) {
                        $part = substr($sequence, $i, $width);
                        if ($part === revcomp($part)) {
                            $this->emit($i + 1, $width, $part);
                            $found = true;
                        }
                    }
                }
                if (!$found) {
                    $this->emit('none');
                }
                break;
            case 'REPEATS':
                $this->repeats($sequence, $a[1], $a[2], $a[3]);
                break;
            case 'HAMMING':
                $other = $this->registry[$a[1]];
                if ($n !== strlen($other)) {
                    throw new CommandError('length mismatch');
                }
                $distance = 0;
                $transitions = 0;
                for ($i = 0; $i < $n; ++$i) {
                    if ($sequence[$i] !== $other[$i]) {
                        ++$distance;
                        $transitions += (int) transition($sequence[$i], $other[$i]);
                    }
                }
                $this->emit('distance', $distance, 'transitions', $transitions,
                            'transversions', $distance - $transitions);
                break;
            case 'ALIGN':
                $this->alignment($sequence, $this->registry[$a[1]], $a[2], $a[3], $a[4], $a[5]);
                break;
            case 'CONSENSUS':
                $sequences = [];
                foreach ($a as $source) {
                    $sequences[] = $this->registry[$source];
                }
                $this->consensus($sequences);
                break;
            case 'TM':
                $this->emit('Tm', fixed(temperature($sequence), 1), $n < 14 ? 'wallace' : 'gc');
                break;
            case 'MASS':
                $single = strandMass($sequence);
                $this->emit('ss', fixed($single, 3), 'ds', fixed($single + strandMass(revcomp($sequence)), 3));
                break;
            case 'PRIMER':
                $this->primer($sequence);
                break;
            case 'FOLD':
                $this->folding($sequence, $a[1]);
                break;
            case 'PACK':
                $codes = [];
                for ($i = 0; $i < $n; ++$i) {
                    $codes[] = strpos(BASES, $sequence[$i]);
                }
                while (count($codes) % 4 !== 0) {
                    $codes[] = 0;
                }
                $hex = '';
                for ($i = 0; $i < count($codes); $i += 4) {
                    $byte = 64 * $codes[$i] + 16 * $codes[$i + 1] +
                            4 * $codes[$i + 2] + $codes[$i + 3];
                    $hex .= sprintf('%02X', $byte);
                }
                $this->emit($n, $hex);
                break;
        }
    }

    public function execute(string $line): void
    {
        $tokens = explode(' ', $line);
        $command = array_shift($tokens);
        try {
            $arguments = $this->validate($command, $tokens);
            $this->command($command, $arguments);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
    }

    public function output(): string
    {
        return implode("\n", $this->output) . "\n";
    }
}

$count = (int) trim((string) fgets(STDIN));
$toolkit = new Toolkit();
for ($i = 0; $i < $count; ++$i) {
    $toolkit->execute(rtrim((string) fgets(STDIN), "\r\n"));
}
echo $toolkit->output();
