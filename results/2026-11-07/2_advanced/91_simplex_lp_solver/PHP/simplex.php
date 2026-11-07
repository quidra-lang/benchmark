<?php

function runPhase(Tableau $t, array $costs, array $candidates, callable $objective): object
{
    $iterations = 0;
    $lines = [];
    sort($candidates, SORT_NUMERIC);
    while (true) {
        $reduced = $t->reduced($costs);
        $q = null;
        foreach ($candidates as $k)
            if ($reduced[$k]->n < 0) {
                $q = $k;
                break;
            }
        if ($q === null)
            return (object) ['iterations' => $iterations, 'lines' => $lines, 'unbounded' => null];
        $p = null;
        $ratio = null;
        foreach ($t->values as $i => $row)
            if ($row[$q]->n > 0) {
                $v = $t->rhs[$i]->div($row[$q]);
                if (
                    $p === null
                    || $v->cmp($ratio) < 0
                    || $v->cmp($ratio) === 0 && $t->basic[$i] < $t->basic[$p]
                ) {
                    $p = $i;
                    $ratio = $v;
                }
            }
        if ($p === null)
            return (object) ['iterations' => $iterations, 'lines' => $lines, 'unbounded' => $q];
        $leaving = $t->basic[$p];
        $before = $reduced[$q];
        $t->pivot($p, $q);
        ++$iterations;
        $value = $objective($t->phaseValue($costs));
        $lines[] = "PIVOT $iterations enter {$t->columnNames[$q]} reduced $before leave {$t->columnNames[$leaving]} row {$t->rowNames[$p]} ratio $ratio objective $value";
    }
}
