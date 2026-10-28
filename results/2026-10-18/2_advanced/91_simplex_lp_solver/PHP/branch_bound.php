<?php

final readonly class BranchNode
{
    public function __construct(
        public array $lower,
        public array $upper,
        public int $depth,
        public ?int $parent,
        public string $branch,
        public ?Rational $parentValue,
    ) {}
}

function branchSearch(object $model, int $limit, callable $solve): object
{
    $stack = [new BranchNode($model->lower, $model->upper, 0, null, 'root', null)];
    $solves = $lines = [];
    $incumbent = $objective = $status = null;
    $incumbents = $pruned = $infeasible = 0;
    while ($stack) {
        if (count($solves) === $limit) {
            $status = 'NODE_LIMIT';
            break;
        }
        $node = array_pop($stack);
        $number = count($solves) + 1;
        $r = $solve($node->lower, $node->upper, $number);
        $solves[] = $r;
        if ($r->status === 'INFEASIBLE') {
            $outcome = 'infeasible';
            ++$infeasible;
        } elseif ($r->status === 'UNBOUNDED') {
            $outcome = 'unbounded';
            $status = 'UNBOUNDED';
        } elseif (
            $objective !== null
            && (
                $model->direction === 'maximize'
                    ? $r->objective->cmp($objective) <= 0
                    : $r->objective->cmp($objective) >= 0
            )
        ) {
            $outcome = 'pruned';
            ++$pruned;
        } else {
            $fractional = null;
            foreach ($model->integer as $j => $integer)
                if ($integer && $r->solution[$j]->d !== 1) {
                    $fractional = $j;
                    break;
                }
            if ($fractional === null) {
                $incumbent = $r->solution;
                $objective = $r->objective;
                $outcome = 'incumbent';
                ++$incumbents;
            } else {
                $value = $r->solution[$fractional];
                $name = $model->variables[$fractional];
                $down = $value->floorValue();
                $up = $value->ceilValue();
                $lower = $node->lower;
                $upper = $node->upper;
                $lower[$fractional] = new Rational($up);
                $upper[$fractional] = new Rational($down);
                $stack[] = new BranchNode(
                    $lower,
                    $node->upper,
                    $node->depth + 1,
                    $number,
                    "$name>=$up",
                    $r->objective,
                );
                $stack[] = new BranchNode(
                    $node->lower,
                    $upper,
                    $node->depth + 1,
                    $number,
                    "$name<=$down",
                    $r->objective,
                );
                $outcome = "branch $name $value";
            }
        }
        $parent = $node->parent ?? '-';
        $lp = $r->status === 'OPTIMAL' ? (string) $r->objective : strtolower($r->status);
        $lines[] = "NODE $number depth {$node->depth} parent $parent branch {$node->branch} lp $lp pivots {$r->pivots} action $outcome";
        if ($status === 'UNBOUNDED')
            break;
    }
    $status ??= $incumbent === null ? 'INFEASIBLE' : 'OPTIMAL';
    $bound = $objective;
    if ($status === 'NODE_LIMIT') {
        foreach (array_reverse($stack) as $node)
            $lines[] = "OPEN parent {$node->parent} branch {$node->branch} bound {$node->parentValue}";
        foreach ($stack as $node)
            if (
                $bound === null
                || (
                    $model->direction === 'maximize'
                        ? $node->parentValue->cmp($bound) > 0
                        : $node->parentValue->cmp($bound) < 0
                )
            )
                $bound = $node->parentValue;
    }
    $shown = $objective === null ? '-' : (string) $objective;
    $shownBound = $bound === null ? '-' : (string) $bound;
    $nodes = count($solves);
    $open = count($stack);
    $lines[] = "RESULT $status objective $shown nodes $nodes incumbents $incumbents pruned $pruned infeasible $infeasible open $open bound $shownBound";
    return (object) [
        'status' => $status,
        'objective' => $objective,
        'solution' => $incumbent,
        'solves' => $solves,
        'root' => $solves[0],
        'lines' => $lines,
        'nodes' => $nodes,
    ];
}
