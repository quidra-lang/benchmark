<?php

const ORGANIC = ['B', 'C', 'N', 'O', 'P', 'S', 'F', 'Cl', 'Br', 'I'];

const AROMATIC = ['B', 'C', 'N', 'O', 'P', 'S'];

const BOND_TYPES = ['-' => 1, '/' => 1, '\\' => 1, '=' => 2, '#' => 3, ':' => 4];

const BASE_VALUES = [0, 1, 2, 3, 1];

final readonly class Element
{
    public function __construct(
        public string $symbol,
        public int $number,
        public int $weight,
        public array $valences,
    ) {}
}

final class AnalysisError extends RuntimeException
{
    public function __construct(
        public string $reason,
        public int $column,
    ) {
        parent::__construct($reason);
    }
}

final class Atom
{
    public function __construct(
        public Element $element,
        public bool $aromatic = false,
        public int $mass = 0,
        public int $charge = 0,
        public int $hydrogens = 0,
        public bool $bracket = false,
        public int $column = 0,
    ) {}
}

final class Bond
{
    public array $ends;
    public ?int $kind = null;
    public int $multiplicity = 0;
    public bool $ring = false;

    public function __construct(
        int $a,
        int $b,
        public string|int|null $symbol,
    ) {
        $this->ends = [min($a, $b), max($a, $b)];
    }

    public function key(): string
    {
        return $this->ends[0] . ':' . $this->ends[1];
    }
}

function bondKey(int $a, int $b): string
{
    return min($a, $b) . ':' . max($a, $b);
}

final class Molecule
{
    public array
        $atoms = [],
        $neighbors = [],
        $bonds = [],
        $rings = [],
        $ringAtoms = [],
        $properties = [],
        $systems = [],
        $aromaticRings = [],
        $bits = []
    ;
    public string $name = '', $canonical = '';
    public ?string $scaffold = null;
    public int $order = 0, $classes = 0, $paths = 0;

    public function __construct(
        public array $elements,
    ) {}

    public function addAtom(object $atom): int
    {
        $n = count($this->atoms);
        $this->atoms[] = $atom;
        $this->neighbors[] = [];
        return $n;
    }

    public function addBond(int $a, int $b, string|int|null $symbol): Bond
    {
        $bond = new Bond($a, $b, $symbol);
        $this->bonds[$bond->key()] = $bond;
        $this->neighbors[$a][$b] = $this->neighbors[$b][$a] = $bond;
        return $bond;
    }

    public function orderedBonds(): array
    {
        $bonds = array_values($this->bonds);
        usort($bonds, fn($a, $b) => $a->ends <=> $b->ends);
        return $bonds;
    }

    public function degree(int $i): int
    {
        return count($this->neighbors[$i]);
    }

    public function baseTotal(int $i): int
    {
        return array_sum(array_map(fn($b) => BASE_VALUES[$b->kind], $this->neighbors[$i]));
    }

    public function bondTotal(int $i): int
    {
        return array_sum(array_map(fn($b) => $b->multiplicity, $this->neighbors[$i]));
    }
}

function readElements(): array
{
    $elements = [];
    foreach (file('input/elements.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '' || $line[0] === '#')
            continue;
        [$symbol, $number, $weight, $valences] = explode(' ', $line);
        $elements[$symbol] = new Element(
            $symbol,
            (int) $number,
            (int) $weight,
            array_map(intval(...), explode(',', $valences)),
        );
    }
    return $elements;
}

function needsPi(Molecule $m, int $i, ?int $hydrogens = null): bool
{
    $a = $m->atoms[$i];
    $hydrogens ??= $a->hydrogens;
    return $a->aromatic && ($a->element->valences[0] + $a->charge) >= ($m->baseTotal($i) + $hydrogens + 1);
}

function organicHydrogens(Atom $atom, int $total): ?int
{
    foreach ($atom->element->valences as $v)
        if ($v >= $total)
            return $v - $total;
    return null;
}
