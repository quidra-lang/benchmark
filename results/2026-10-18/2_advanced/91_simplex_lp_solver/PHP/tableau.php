<?php

final class Tableau
{
    public function __construct(
        public array $rowNames,
        public array $columnNames,
        public array $values,
        public array $rhs,
        public array $basic,
    ) {}

    public function pivot(int $p, int $q): void
    {
        $divisor = $this->values[$p][$q];
        $this->values[$p] = array_map(fn($v) => $v->div($divisor), $this->values[$p]);
        $this->rhs[$p] = $this->rhs[$p]->div($divisor);
        foreach ($this->values as $i => $row) {
            if ($i === $p)
                continue;
            $f = $row[$q];
            foreach ($row as $k => $v)
                $this->values[$i][$k] = $v->sub($f->mul($this->values[$p][$k]));
            $this->rhs[$i] = $this->rhs[$i]->sub($f->mul($this->rhs[$p]));
        }
        $this->basic[$p] = $q;
    }

    public function reduced(array $costs): array
    {
        $r = $costs;
        foreach ($r as $k => $v)
            foreach ($this->basic as $i => $b)
                $r[$k] = $r[$k]->sub($costs[$b]->mul($this->values[$i][$k]));
        return $r;
    }

    public function phaseValue(array $costs): Rational
    {
        $v = new Rational();
        foreach ($this->basic as $i => $b)
            $v = $v->add($costs[$b]->mul($this->rhs[$i]));
        return $v;
    }

    public function display(string $heading, array $costs, callable $objective): array
    {
        $out = ['TABLEAU ' . $heading, 'COLUMNS ' . implode(' ', $this->columnNames)];
        foreach ($this->values as $i => $row)
            $out[] =
                'ROW '
                . $this->rowNames[$i]
                . ' '
                . $this->columnNames[$this->basic[$i]]
                . ' '
                . implode(' ', $row)
                . ' | '
                . $this->rhs[$i];
        $out[] =
            'COST ' . implode(' ', $this->reduced($costs)) . ' | ' . $objective($this->phaseValue($costs));
        return $out;
    }
}
