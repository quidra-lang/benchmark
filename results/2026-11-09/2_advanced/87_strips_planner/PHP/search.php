<?php

function applicable(object $a, array $state): bool
{
    return subset($a->pre, $state) && !array_intersect_key($a->neg, $state);
}

function applyAction(object $a, array $state): array
{
    return array_diff_key($state, $a->delete) + $a->add;
}

function searchResult(string $status, int $expanded = 0, int $generated = 0, array $plan = []): object
{
    return (object) [
        'status' => $status,
        'expanded' => $expanded,
        'generated' => $generated,
        'plan' => $plan,
    ];
}

function stateKey(array $state): string
{
    return implode(',', sortedKeys($state));
}

function runSearch(
    object $problem,
    array $start,
    string $algorithm,
    string $heuristic,
    int $budget,
    int $weight,
    Heuristics $evaluator,
): object {
    $initialH = $evaluator->value($heuristic, $start);
    if ($initialH === null)
        return searchResult('dead end');
    $expanded = $generated = 0;
    if ($algorithm === 'ehc') {
        $current = $start;
        $plan = [];
        $hc = $initialH;
        while (!subset($problem->goal, $current)) {
            $queue = [[$current, []]];
            $visited = [stateKey($current) => true];
            $improved = false;
            for ($head = 0; $head < count($queue) && !$improved; ++$head) {
                [$state, $prefix] = $queue[$head];
                if ($expanded === $budget)
                    return searchResult('budget', $expanded, $generated);
                ++$expanded;
                foreach ($evaluator->helpful($state) as $number) {
                    $next = applyAction($problem->actions[$number], $state);
                    ++$generated;
                    $key = stateKey($next);
                    if (isset($visited[$key]))
                        continue;
                    $visited[$key] = true;
                    $h = $evaluator->value($heuristic, $next);
                    if ($h === null)
                        continue;
                    $path = [...$prefix, $number];
                    if ($h < $hc) {
                        array_push($plan, ...$path);
                        $current = $next;
                        $hc = $h;
                        $improved = true;
                        break;
                    }
                    $queue[] = [$next, $path];
                }
            }
            if (!$improved)
                return searchResult('stuck', $expanded, $generated);
        }
        return searchResult('solved', $expanded, $generated, $plan);
    }
    $priority = fn($g, $d, $h) => match ($algorithm) {
        'bfs' => $d,
        'ucs' => $g,
        'gbfs' => $h,
        'wastar' => $g + ($weight * $h),
        default => $g + $h,
    };
    $first = (object) ['state' => $start, 'g' => 0, 'depth' => 0, 'parent' => null, 'action' => null];
    $queue = new SplPriorityQueue();
    $queue->setExtractFlags(SplPriorityQueue::EXTR_DATA);
    $queue->insert($first, [-$priority(0, 0, $initialH), -$initialH, 0]);
    $best = [stateKey($start) => 0];
    $serial = 1;
    $reopen = in_array($algorithm, ['ucs', 'astar', 'wastar'], true);
    while (!$queue->isEmpty()) {
        $node = $queue->extract();
        if ($reopen && $node->g > $best[stateKey($node->state)])
            continue;
        if (subset($problem->goal, $node->state)) {
            $plan = [];
            while ($node->parent !== null) {
                $plan[] = $node->action;
                $node = $node->parent;
            }
            return searchResult('solved', $expanded, $generated, array_reverse($plan));
        }
        if ($expanded === $budget)
            return searchResult('budget', $expanded, $generated);
        ++$expanded;
        foreach ($problem->actions as $a)
            if (applicable($a, $node->state)) {
                $state = applyAction($a, $node->state);
                ++$generated;
                $g = $node->g + $a->cost;
                $key = stateKey($state);
                if (isset($best[$key]) && (!$reopen || $best[$key] <= $g))
                    continue;
                $best[$key] = $g;
                $h = $evaluator->value($heuristic, $state);
                if ($h === null)
                    continue;
                $child = (object) [
                    'state' => $state,
                    'g' => $g,
                    'depth' => $node->depth + 1,
                    'parent' => $node,
                    'action' => $a->number,
                ];
                $queue->insert($child, [-$priority($g, $child->depth, $h), -$h, -$serial++]);
            }
    }
    return searchResult('exhausted', $expanded, $generated);
}
