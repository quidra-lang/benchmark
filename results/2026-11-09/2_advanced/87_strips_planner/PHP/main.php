<?php

foreach (['pddl_parser', 'grounding', 'heuristics', 'search', 'graphplan'] as $module)
    require_once __DIR__ . "/$module.php";
function actionText(object $a): string
{
    return notation([$a->source->name, $a->arguments]);
}

function numberList(array $set): string
{
    $keys = sortedKeys($set);
    return $keys ? implode(',', $keys) : '-';
}

function headed(string $heading, array $items): string
{
    return $heading . ' ' . ($items ? implode(' ', $items) : '-');
}

function valueText(?int $v): string
{
    return $v === null ? 'inf' : (string) $v;
}

function heuristicText(array $values): string
{
    $parts = [];
    foreach (HEURISTICS as $name)
        $parts[] = $name . '=' . valueText($values[$name]);
    return implode(' ', $parts);
}

function inputLines(string $name): array
{
    return array_values(array_filter(
        file('input/' . $name, FILE_IGNORE_NEW_LINES),
        fn($line) => $line !== '' && $line[0] !== '#',
    ));
}

function readSettings(): array
{
    $settings = ['runs' => []];
    foreach (inputLines('params.txt') as $line) {
        $f = explode(' ', $line);
        if ($f[0] === 'run')
            $settings['runs'][] = array_slice($f, 1);
        elseif ($f[0] === 'repair')
            $settings['repair'] = array_slice($f, 1);
        else
            $settings[$f[0]] = (int) $f[1];
    }
    return $settings;
}

function readCandidates(): array
{
    $candidates = [];
    $current = null;
    foreach (inputLines('candidates.txt') as $line) {
        if (str_starts_with($line, 'plan ')) {
            [, $problem, $label] = explode(' ', $line);
            $current = (object) [
                'number' => count($candidates) + 1,
                'problem' => $problem,
                'label' => $label,
                'steps' => [],
            ];
        } elseif ($line === 'end')
            $candidates[] = $current;
        else {
            $f = explode(' ', substr($line, 1, -1));
            $current->steps[] = [$f[0], array_slice($f, 1)];
        }
    }
    return $candidates;
}

function argumentError(object $d, array $arguments, array $expected, array $table, string $noun): ?string
{
    if (count($arguments) !== count($expected))
        return 'expected ' . count($expected) . ' arguments, got ' . count($arguments);
    foreach ($arguments as $i => $argument) {
        if (!isset($table[$argument]))
            return "unknown $noun $argument";
        if (!subtype($d->parents, $table[$argument], $expected[$i]))
            return 'argument ' . ($i + 1) . " ($argument) is not of type {$expected[$i]}";
    }
    return null;
}

function validateDomain(object $d): void
{
    $kept = $diagnostics = [];
    foreach ($d->actions as $a) {
        $error = null;
        foreach ($a->parameters as [$name, $kind])
            if (!array_key_exists($kind, $d->parents)) {
                $error = 'unknown type ' . $kind;
                break;
            }
        if ($error === null) {
            $parameters = [];
            foreach ($a->parameters as [$name, $kind])
                $parameters[$name] = $kind;
            foreach ([...$a->condition, ...$a->effects] as [$sign, $atom]) {
                if ($atom[0] !== '=' && !isset($d->predicates[$atom[0]]))
                    $error = 'unknown predicate ' . $atom[0];
                else
                    $error = argumentError(
                        $d,
                        $atom[1],
                        $atom[0] === '=' ? ['object', 'object'] : $d->predicates[$atom[0]],
                        $parameters,
                        'variable',
                    );
                if ($error !== null) {
                    $error = notation($atom) . ': ' . $error;
                    break;
                }
            }
        }
        if ($error === null)
            $kept[] = $a;
        else
            $diagnostics[] = "error: action {$a->name}: $error";
    }
    $d->actions = $kept;
    $d->byName = $d->fluent = [];
    $used = [];
    foreach ($kept as $a) {
        $d->byName[$a->name] = $a;
        foreach ([...$a->condition, ...$a->effects] as [$sign, $atom])
            $used[$atom[0]] = true;
        foreach ($a->effects as [$sign, $atom])
            $d->fluent[$atom[0]] = true;
    }
    foreach ($d->predicates as $predicate => $unused)
        if (!isset($used[$predicate]))
            $diagnostics[] = "warning: predicate $predicate is not used by any action";
    $d->static = array_diff_key($d->predicates, $d->fluent);
    $d->diagnostics = $diagnostics;
}

function validateProblem(object $d, object $p): void
{
    $diagnostics = [];
    foreach (['init' => 'initial', 'goal' => 'goals'] as $side => $field) {
        $kept = $seen = [];
        foreach ($p->$field as $atom) {
            $error = !isset($d->predicates[$atom[0]])
                ? 'unknown predicate ' . $atom[0]
                : argumentError($d, $atom[1], $d->predicates[$atom[0]], $p->objects, 'object');
            $key = notation($atom);
            if ($error === null && isset($seen[$key]))
                $error = 'duplicate';
            if ($error === null) {
                $kept[] = $atom;
                $seen[$key] = true;
            } else
                $diagnostics[] = "warning: $side $key: $error";
        }
        $p->$field = $kept;
    }
    $p->diagnostics = $diagnostics;
}

function validationResult(string $status, array $messages, int $correct): object
{
    return (object) ['status' => $status, 'messages' => $messages, 'correct' => $correct];
}

function validateSteps(object $d, object $p, array $steps): object
{
    $world = [];
    foreach ($p->initial as $a)
        $world[notation($a)] = true;
    $cost = 0;
    foreach ($steps as $i => [$name, $arguments]) {
        $position = $i + 1;
        $heading = "step $position " . notation([$name, $arguments]) . ': ';
        if (!isset($d->byName[$name]))
            return validationResult('invalid', [$heading . 'unknown action ' . $name], $i);
        $schema = $d->byName[$name];
        $error = argumentError($d, $arguments, array_column($schema->parameters, 1), $p->objects, 'object');
        if ($error !== null)
            return validationResult('invalid', [$heading . $error], $i);
        $binding = array_combine(array_column($schema->parameters, 0), $arguments);
        foreach ($schema->condition as [$sign, $atom]) {
            $bound = substitute($atom, $binding);
            $text = notation($bound);
            $truth = $bound[0] === '=' ? $bound[1][0] === $bound[1][1] : isset($world[$text]);
            if ($truth !== $sign) {
                $literal = $sign ? $text : '(not ' . $text . ')';
                return validationResult('invalid', [$heading . 'precondition ' . $literal . ' is false'], $i);
            }
        }
        foreach ($schema->effects as [$sign, $atom])
            if (!$sign)
                unset($world[notation(substitute($atom, $binding))]);
        foreach ($schema->effects as [$sign, $atom])
            if ($sign)
                $world[notation(substitute($atom, $binding))] = true;
        $cost += $schema->cost;
    }
    $missing = [];
    foreach ($p->goals as $atom)
        if (!isset($world[notation($atom)]))
            $missing[] = 'unsatisfied goal ' . notation($atom);
    return (
        $missing
            ? validationResult('goal not reached', $missing, count($steps))
            : validationResult('valid', ['length=' . count($steps) . " cost=$cost"], count($steps))
    );
}

function verdict(object $v): string
{
    return $v->status . ($v->status === 'valid' ? ' ' : ': ') . $v->messages[0];
}

function planSteps(object $p, array $plan): array
{
    return array_map(fn($n) => [$p->actions[$n]->source->name, $p->actions[$n]->arguments], $plan);
}

function planCost(object $p, array $plan): int
{
    return array_sum(array_map(fn($n) => $p->actions[$n]->cost, $plan));
}

function interferes(object $a, object $b): bool
{
    return (bool) (
        array_intersect_key($a->delete, $b->pre + $b->add)
        || array_intersect_key($b->delete, $a->pre + $a->add)
        || array_intersect_key($a->add, $b->neg)
        || array_intersect_key($b->add, $a->neg)
    );
}

function parallelize(object $p, array $plan): array
{
    $assigned = $layers = [];
    foreach ($plan as $i => $number) {
        $a = $p->actions[$number];
        $layer = 1;
        for ($j = 0; $j < $i; ++$j) {
            $b = $p->actions[$plan[$j]];
            if (
                array_intersect_key($b->add, $a->pre)
                || array_intersect_key($b->delete, $a->neg)
                || interferes($b, $a)
            )
                $layer = max($layer, $assigned[$j] + 1);
        }
        $assigned[] = $layer;
        while (count($layers) < $layer)
            $layers[] = [];
        $layers[$layer - 1][] = $number;
    }
    return $layers;
}

function validateParallel(object $p, array $layers): string
{
    $state = $p->initial;
    foreach ($layers as $i => $layer) {
        $actions = array_map(fn($n) => $p->actions[$n], $layer);
        foreach ($actions as $j => $a) {
            if (!applicable($a, $state))
                return 'invalid at layer ' . ($i + 1);
            for ($k = $j + 1; $k < count($actions); ++$k)
                if (interferes($a, $actions[$k]))
                    return 'invalid at layer ' . ($i + 1);
        }
        $delete = $add = [];
        foreach ($actions as $a) {
            $delete += $a->delete;
            $add += $a->add;
        }
        $state = array_diff_key($state, $delete) + $add;
    }
    return subset($p->goal, $state) ? 'valid' : 'goal not reached';
}

function improve(object $p, array $plan): array
{
    $i = 0;
    while ($i < count($plan)) {
        $state = $p->initial;
        foreach (array_slice($plan, 0, $i) as $n)
            $state = applyAction($p->actions[$n], $state);
        $applied = [];
        foreach (array_slice($plan, $i + 1) as $n)
            if (applicable($p->actions[$n], $state)) {
                $state = applyAction($p->actions[$n], $state);
                $applied[] = $n;
            }
        if (subset($p->goal, $state))
            $plan = [...array_slice($plan, 0, $i), ...$applied];
        else
            ++$i;
    }
    return $plan;
}

function transformNegatives(object $p): array
{
    $negative = [];
    foreach ($p->actions as $a)
        $negative += $a->neg;
    $complements = [];
    foreach (sortedKeys($negative) as $i => $fact)
        $complements[$fact] = count($p->facts) + $i;
    $actions = [];
    foreach ($p->actions as $a) {
        $pre = $a->pre;
        $add = $a->add;
        $delete = $a->delete;
        foreach ($a->neg as $f => $unused)
            $pre[$complements[$f]] = true;
        foreach ($a->delete as $f => $unused)
            if (isset($complements[$f]))
                $add[$complements[$f]] = true;
        foreach ($a->add as $f => $unused)
            if (isset($complements[$f]))
                $delete[$complements[$f]] = true;
        $actions[] = (object) ['number' => $a->number, 'pre' => $pre, 'add' => $add, 'delete' => $delete];
    }
    $initial = $p->initial;
    foreach ($complements as $f => $c)
        if (!isset($initial[$f]))
            $initial[$c] = true;
    return [$actions, $initial, count($complements)];
}

final class Planner
{
    private object $domain;
    private array
        $sources,
        $settings,
        $candidates,
        $tags,
        $totals,
        $grounding = [],
        $plans = [],
        $graph = [],
        $validation = [],
        $comparison = ['problem,algorithm,heuristic,length,cost,expanded,generated'],
        $problems = [],
        $evaluators = [],
        $summaries = []
    ;
    private int $validatedPlans = 0, $validPlans = 0, $validCandidates = 0;

    public function __construct()
    {
        $this->domain = readDomain(file_get_contents('input/domain.txt'));
        $this->sources = readProblems(file_get_contents('input/problems.txt'));
        $this->settings = readSettings();
        $this->candidates = readCandidates();
        validateDomain($this->domain);
        $this->tags = array_map(fn($pair) => implode(' ', $pair), $this->settings['runs']);
        $this->tags[] = 'graphplan';
        $this->totals = array_fill(0, count($this->tags), [
            'solved' => 0,
            'best' => 0,
            'expanded' => 0,
            'generated' => 0,
        ]);
    }

    private function domainReport(): void
    {
        $d = $this->domain;
        $this->grounding = ["== domain {$d->name} ==", ...$d->diagnostics];
        foreach ($d->typeOrder as $kind) {
            $chain = [];
            $current = $kind;
            while ($current !== null) {
                $chain[] = $current;
                $current = $d->parents[$current];
            }
            $this->grounding[] = 'type ' . implode(' < ', $chain);
        }
        foreach ($d->predicates as $name => $types)
            $this->grounding[] =
                "predicate $name/" . count($types) . ' ' . (isset($d->fluent[$name]) ? 'fluent' : 'static');
        foreach ($d->actions as $a) {
            $adds = count(array_filter($a->effects, fn($l) => $l[0]));
            $deletes = count($a->effects) - $adds;
            $this->grounding[] =
                "action {$a->name}/"
                . count($a->parameters)
                . " cost={$a->cost} pre="
                . count($a->condition)
                . " add=$adds del=$deletes";
        }
    }

    private function groundingReport(object $p): void
    {
        array_push($this->grounding, '', "== problem {$p->name} ==", ...$p->source->diagnostics);
        $this->grounding[] = 'objects: ' . count($p->source->objects);
        foreach ($this->domain->typeOrder as $type)
            $this->grounding[] = headed("  $type:", $p->objectsByType[$type]);
        $this->grounding[] = 'static facts: ' . $p->staticCount;
        foreach ($this->domain->actions as $a) {
            [$assignments, $candidates, $reachable] = $p->statistics[$a->name];
            $this->grounding[] = "schema {$a->name}: assignments=$assignments candidates=$candidates reachable=$reachable";
        }
        $this->grounding[] = "candidates: {$p->candidateCount} reachable: " . count($p->actions);
        $this->grounding[] =
            'facts: ' . count($p->facts) . ' init: ' . count($p->initial) . ' goals: ' . count($p->goal);
        foreach ($p->unreachable as $atom)
            $this->grounding[] = 'unreachable goal: ' . notation($atom);
        $counts = [];
        foreach ($p->facts as $atom)
            $counts[$atom[0]] = ($counts[$atom[0]] ?? 0) + 1;
        $items = [];
        foreach ($this->domain->predicates as $name => $unused)
            if (isset($this->domain->fluent[$name]))
                $items[] = $name . '=' . ($counts[$name] ?? 0);
        $this->grounding[] = headed('facts by predicate:', $items);
        $this->grounding[] = 'facts:';
        foreach ($p->facts as $n => $atom)
            $this->grounding[] = "  $n " . notation($atom);
        $this->grounding[] = 'actions:';
        foreach ($p->actions as $a)
            $this->grounding[] =
                "  {$a->number} "
                . actionText($a)
                . " cost={$a->cost} pre="
                . numberList($a->pre)
                . ' neg='
                . numberList($a->neg)
                . ' add='
                . numberList($a->add)
                . ' del='
                . numberList($a->delete);
    }

    private function initialReport(object $p, Heuristics $e): array
    {
        $values = $e->values($p->initial);
        $landmarks = $e->landmarks($p->initial) ?? [];
        $relaxed = $e->relaxedPlan($p->initial) ?? [];
        $this->plans[] = 'initial h: ' . heuristicText($values);
        $this->plans[] = 'landmarks: ' . count($landmarks);
        foreach (sortedKeys($landmarks) as $n)
            $this->plans[] = '  ' . notation($p->facts[$n]);
        $this->plans[] = 'relaxed plan: length=' . count($relaxed) . ' cost=' . valueText($values['ff']);
        foreach ($relaxed as $n)
            $this->plans[] = '  ' . actionText($p->actions[$n]);
        $this->plans[] = headed('helpful:', array_map(fn($n) => actionText(
            $p->actions[$n],
        ), $e->helpful($p->initial)));
        return $landmarks;
    }

    private function planReport(object $p, string $tag, array $plan, array $landmarks, array &$earlier): void
    {
        $cost = planCost($p, $plan);
        $key = implode(',', $plan);
        $first = $earlier[$key] ??= $tag;
        $this->plans[] =
            'plan: length='
            . count($plan)
            . " cost=$cost"
            . ($first !== $tag ? ' (same as ' . $first . ')' : '');
        $counts = [];
        foreach ($plan as $i => $n) {
            $a = $p->actions[$n];
            $this->plans[] = '  ' . ($i + 1) . ' ' . actionText($a);
            $counts[$a->source->name] = ($counts[$a->source->name] ?? 0) + 1;
        }
        $items = [];
        foreach ($this->domain->actions as $a)
            if ($counts[$a->name] ?? 0)
                $items[] = $a->name . '=' . $counts[$a->name];
        $this->plans[] = headed('schemas:', $items);
        $layers = parallelize($p, $plan);
        $this->plans[] = 'parallel: layers=' . count($layers);
        foreach ($layers as $i => $layer)
            $this->plans[] = headed('  ' . ($i + 1) . ':', array_map(fn($n) => actionText(
                $p->actions[$n],
            ), $layer));
        $improved = improve($p, $plan);
        $removed = count($plan) - count($improved);
        $this->plans[] =
            'improved: length=' . count($improved) . ' cost=' . planCost($p, $improved) . " removed=$removed";
        if ($removed)
            foreach ($improved as $i => $n)
                $this->plans[] = '  ' . ($i + 1) . ' ' . actionText($p->actions[$n]);
        $state = $p->initial;
        $reached = [];
        foreach ($plan as $n) {
            $state = applyAction($p->actions[$n], $state);
            $reached += array_intersect_key($state, $landmarks);
        }
        $this->plans[] = 'landmarks reached: ' . count($reached) . '/' . count($landmarks);
        foreach (sortedKeys(array_diff_key($landmarks, $reached)) as $n)
            $this->plans[] = '  missed ' . notation($p->facts[$n]);
        $v = validateSteps($this->domain, $p->source, planSteps($p, $plan));
        $vi = validateSteps($this->domain, $p->source, planSteps($p, $improved));
        $this->validation[] = $tag . ': ' . verdict($v);
        $this->validation[] = '  parallel: ' . validateParallel($p, $layers);
        $this->validation[] = '  improved: ' . verdict($vi);
        ++$this->validatedPlans;
        $this->validPlans += (int) ($v->status === 'valid');
    }

    private function resultReport(
        object $p,
        string $tag,
        object $result,
        array $landmarks,
        array &$earlier,
    ): void {
        $this->plans[] = "-- $tag --";
        if ($p->unreachable) {
            $this->plans[] = 'result: FAIL (unreachable goal)';
            return;
        }
        $state = $result->status === 'solved' ? 'solved' : 'FAIL (' . $result->status . ')';
        $this->plans[] = "result: $state expanded={$result->expanded} generated={$result->generated}";
        if ($result->status === 'solved')
            $this->planReport($p, $tag, $result->plan, $landmarks, $earlier);
    }

    private function graphReport(object $p, object $result, int $complements): void
    {
        if ($p->unreachable) {
            $this->graph[] = 'result: FAIL (unreachable goal)';
            return;
        }
        $this->graph[] = 'complementary facts: ' . $complements;
        array_push($this->graph, ...$result->lines);
        $counts = " searched={$result->expanded} memo_hits={$result->memoHits} tried={$result->generated}";
        if ($result->status === 'solved') {
            $this->graph[] =
                'result: solved levels='
                . count($result->layers)
                . ' length='
                . count($result->plan)
                . ' cost='
                . planCost($p, $result->plan)
                . $counts;
            foreach ($result->layers as $i => $layer)
                $this->graph[] = headed('layer ' . ($i + 1) . ':', array_map(fn($n) => actionText(
                    $p->actions[$n],
                ), $layer));
        } else
            $this->graph[] = 'result: FAIL (' . $result->status . ')' . $counts;
    }

    private function profileReport(object $p, Heuristics $e, string $tag, array $plan): void
    {
        $state = $p->initial;
        $remaining = planCost($p, $plan);
        $overestimates = array_fill_keys(HEURISTICS, 0);
        $this->plans[] = "-- profile ($tag) --";
        for ($i = 0; $i <= count($plan); ++$i) {
            $values = $e->values($state);
            $this->plans[] = "  $i: h*=$remaining " . heuristicText($values);
            foreach ($values as $name => $value)
                if ($value === null || $value > $remaining)
                    ++$overestimates[$name];
            if ($i < count($plan)) {
                $a = $p->actions[$plan[$i]];
                $state = applyAction($a, $state);
                $remaining -= $a->cost;
            }
        }
        $parts = [];
        foreach (HEURISTICS as $name)
            $parts[] = $name . '=' . $overestimates[$name];
        $this->plans[] = 'overestimates: ' . implode(' ', $parts);
        $this->plans[] = "-- causal links ($tag) --";
        $suppliers = [];
        foreach ($plan as $i => $n) {
            $a = $p->actions[$n];
            $links = [];
            foreach (sortedKeys($a->pre) as $f)
                $links[] = notation($p->facts[$f]) . '<-' . ($suppliers[$f] ?? 0);
            $this->plans[] = headed('  ' . ($i + 1) . ' ' . actionText($a) . ':', $links);
            foreach ($a->add as $f => $unused)
                $suppliers[$f] = $i + 1;
        }
        $links = [];
        foreach (sortedKeys($p->goal) as $f)
            $links[] = notation($p->facts[$f]) . '<-' . ($suppliers[$f] ?? 0);
        $this->plans[] = headed('  goal:', $links);
    }

    private function summarize(object $p, array $results, ?int $proof): void
    {
        $solved = array_values(array_filter($results, fn($r) => $r->status === 'solved'));
        $best = $solved ? min(array_map(fn($r) => planCost($p, $r->plan), $solved)) : null;
        if ($proof !== null)
            $optimal = (string) planCost($p, $results[$proof]->plan);
        elseif (array_any($results, fn($r) => in_array(
            $r->status,
            ['unreachable goal', 'dead end', 'exhausted', 'unreachable'],
            true,
        )))
            $optimal = 'none';
        else
            $optimal = 'unknown';
        $this->summaries[$p->name] = ['solved' => count($solved), 'best' => $best, 'optimal' => $optimal];
        $pairs = [...$this->settings['runs'], ['graphplan', 'none']];
        foreach ($results as $i => $r) {
            $this->totals[$i]['expanded'] += $r->expanded;
            $this->totals[$i]['generated'] += $r->generated;
            $length = $cost = '-';
            if ($r->status === 'solved') {
                $length = count($r->plan);
                $cost = planCost($p, $r->plan);
                ++$this->totals[$i]['solved'];
                $this->totals[$i]['best'] += (int) ($cost === $best);
            }
            [$algorithm, $heuristic] = $pairs[$i];
            $this->comparison[] = implode(',', [
                $p->name,
                $algorithm,
                $heuristic,
                $length,
                $cost,
                $r->expanded,
                $r->generated,
            ]);
        }
    }

    private function solveProblem(object $source): void
    {
        validateProblem($this->domain, $source);
        $p = ground($this->domain, $source);
        $this->problems[$p->name] = $p;
        $this->groundingReport($p);
        $this->plans[] = $this->graph[] = $this->validation[] = "== problem {$p->name} ==";
        $results = $earlier = [];
        $proof = null;
        if ($p->unreachable) {
            $this->plans[] = 'initial h: unreachable goal';
            $e = null;
            $landmarks = [];
        } else {
            $e = new Heuristics($p);
            $this->evaluators[$p->name] = $e;
            $landmarks = $this->initialReport($p, $e);
        }
        foreach ($this->settings['runs'] as $i => [$algorithm, $heuristic]) {
            $r = $p->unreachable
                ? searchResult('unreachable goal')
                : runSearch(
                    $p,
                    $p->initial,
                    $algorithm,
                    $heuristic,
                    $this->settings['budget'],
                    $this->settings['weight'],
                    $e,
                );
            $results[] = $r;
            $this->resultReport($p, $this->tags[$i], $r, $landmarks, $earlier);
            if (
                $proof === null
                && (
                    $algorithm === 'ucs'
                    && $heuristic === 'none'
                    || $algorithm === 'astar'
                    && $heuristic === 'hmax'
                )
                && $r->status === 'solved'
            )
                $proof = $i;
        }
        $complements = 0;
        if ($p->unreachable)
            $graph = searchResult('unreachable goal');
        else {
            [$actions, $initial, $complements] = transformNegatives($p);
            $graph = new PlanningGraph($actions, $initial, $p->goal, $this->settings['graphplan'])->run();
        }
        $results[] = $graph;
        $this->resultReport($p, 'graphplan', $graph, $landmarks, $earlier);
        $this->graphReport($p, $graph, $complements);
        if ($proof !== null)
            $this->profileReport($p, $e, $this->tags[$proof], $results[$proof]->plan);
        $this->summarize($p, $results, $proof);
        $this->plans[] = $this->graph[] = $this->validation[] = '';
    }

    private function mappedSteps(object $p, array $steps): array
    {
        return array_map(fn($step) => $p->actionNumbers[notation($step)], $steps);
    }

    private function repair(object $p, object $candidate, object $checked): void
    {
        if ($p->unreachable) {
            $this->validation[] = '  repair: FAIL (unreachable goal)';
            return;
        }
        $prefix = $this->mappedSteps($p, array_slice($candidate->steps, 0, $checked->correct));
        $state = $p->initial;
        foreach ($prefix as $n)
            $state = applyAction($p->actions[$n], $state);
        [$algorithm, $heuristic] = $this->settings['repair'];
        $r = runSearch(
            $p,
            $state,
            $algorithm,
            $heuristic,
            $this->settings['budget'],
            $this->settings['weight'],
            $this->evaluators[$p->name],
        );
        if ($r->status !== 'solved') {
            $this->validation[] = '  repair: FAIL (' . $r->status . ')';
            return;
        }
        $repaired = [...$prefix, ...$r->plan];
        $v = validateSteps($this->domain, $p->source, planSteps($p, $repaired));
        $this->validation[] =
            '  repair: kept=' . count($prefix) . ' added=' . count($r->plan) . ' ' . verdict($v);
        foreach ($repaired as $i => $n)
            $this->validation[] = '    ' . ($i + 1) . ' ' . actionText($p->actions[$n]);
    }

    private function candidateReport(): void
    {
        $this->validation[] = '== candidates ==';
        foreach ($this->candidates as $candidate) {
            $p = $this->problems[$candidate->problem];
            $checked = validateSteps($this->domain, $p->source, $candidate->steps);
            $heading = "candidate {$candidate->number} {$candidate->problem} {$candidate->label}: ";
            if ($checked->status === 'valid') {
                ++$this->validCandidates;
                $this->validation[] = $heading . verdict($checked);
                $mapped = $this->mappedSteps($p, $candidate->steps);
                $improved = improve($p, $mapped);
                $best = $this->summaries[$p->name]['best'] ?? '-';
                $this->validation[] =
                    '  improved: length='
                    . count($improved)
                    . ' cost='
                    . planCost($p, $improved)
                    . ' removed='
                    . (count($mapped) - count($improved))
                    . " best known=$best";
            } else {
                $this->validation[] = $heading . $checked->status;
                foreach ($checked->messages as $message)
                    $this->validation[] = '  ' . $message;
                $this->repair($p, $candidate, $checked);
            }
        }
        array_push(
            $this->validation,
            '',
            '== summary ==',
            "plans: {$this->validatedPlans} valid: {$this->validPlans}",
            'candidates: ' . count($this->candidates) . " valid: {$this->validCandidates}",
        );
    }

    public function run(): void
    {
        $this->domainReport();
        foreach ($this->sources as $source)
            $this->solveProblem($source);
        $this->plans[] = '== summary ==';
        foreach ($this->summaries as $name => $s)
            $this->plans[] =
                "$name: solved={$s['solved']}/"
                . count($this->tags)
                . ' best='
                . ($s['best'] ?? '-')
                . " optimal={$s['optimal']}";
        foreach ($this->tags as $i => $tag) {
            $t = $this->totals[$i];
            $this->plans[] = "$tag: solved={$t['solved']} best={$t['best']} expanded={$t['expanded']} generated={$t['generated']}";
        }
        $this->candidateReport();
        if (!is_dir('output'))
            mkdir('output');
        foreach ([
            'grounding.txt' => $this->grounding,
            'plans.txt' => $this->plans,
            'graphplan.txt' => $this->graph,
            'validation.txt' => $this->validation,
            'comparison.csv' => $this->comparison,
        ] as $name => $lines)
            file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}

new Planner()->run();
