<?php

foreach (['rational', 'lp_parser', 'tableau', 'simplex', 'branch_bound'] as $module)
    require_once __DIR__ . "/$module.php";
function coefficients(array $terms, array $variables): array
{
    $values = array_fill_keys($variables, new Rational());
    foreach ($terms as [$name, $v])
        $values[$name] = $values[$name]->add($v);
    return array_map(fn($name) => $values[$name], $variables);
}

function dot(array $a, array $b): Rational
{
    $v = new Rational();
    foreach ($a as $i => $x)
        $v = $v->add($x->mul($b[$i]));
    return $v;
}

function contentCheck(object $parsed): object
{
    if ($parsed->error !== null)
        return $parsed;
    $variables = [];
    foreach ([$parsed->objective, ...array_column($parsed->constraints, 'terms')] as $terms)
        foreach ($terms as [$name, $v])
            if (!in_array($name, $variables, true))
                $variables[] = $name;
    $model = (object) [
        'name' => $parsed->name,
        'error' => null,
        'direction' => $parsed->direction,
        'variables' => $variables,
        'constraints' => $parsed->constraints,
        'costs' => coefficients($parsed->objective, $variables),
        'matrix' => array_map(fn($row) => coefficients($row->terms, $variables), $parsed->constraints),
        'rhs' => array_column($parsed->constraints, 'rhs'),
        'comparisons' => array_column($parsed->constraints, 'comparison'),
        'lower' => array_fill(0, count($variables), new Rational()),
        'upper' => array_fill(0, count($variables), null),
        'integer' => array_fill(0, count($variables), false),
    ];
    $seen = [];
    foreach ($parsed->constraints as $row) {
        if (isset($seen[$row->name])) {
            $model->error = [$row->line, 'duplicate constraint ' . $row->name];
            return $model;
        }
        $seen[$row->name] = true;
    }
    $positions = array_flip($variables);
    foreach ($parsed->bounds as [$line, $name, $kind, $lo, $hi]) {
        if (!isset($positions[$name])) {
            $model->error = [$line, 'unknown variable ' . $name];
            return $model;
        }
        $j = $positions[$name];
        if ($kind === 'lower' || $kind === 'both')
            $model->lower[$j] = $lo;
        if ($kind === 'upper' || $kind === 'both')
            $model->upper[$j] = $hi;
        if (
            $model->lower[$j] !== null
            && $model->upper[$j] !== null
            && $model->lower[$j]->cmp($model->upper[$j]) > 0
        ) {
            $model->error = [$line, 'inconsistent bounds ' . $name];
            return $model;
        }
    }
    foreach ($parsed->integers as [$line, $names])
        foreach ($names as $name) {
            if (!isset($positions[$name])) {
                $model->error = [$line, 'unknown variable ' . $name];
                return $model;
            }
            $j = $positions[$name];
            $model->integer[$j] = true;
            if ($model->lower[$j] !== null)
                $model->lower[$j] = new Rational($model->lower[$j]->ceilValue());
            if ($model->upper[$j] !== null)
                $model->upper[$j] = new Rational($model->upper[$j]->floorValue());
            if (
                $model->lower[$j] !== null
                && $model->upper[$j] !== null
                && $model->lower[$j]->cmp($model->upper[$j]) > 0
            ) {
                $model->error = [$line, 'inconsistent bounds ' . $name];
                return $model;
            }
        }
    foreach ($parsed->binaries as [$line, $names])
        foreach ($names as $name) {
            if (!isset($positions[$name])) {
                $model->error = [$line, 'unknown variable ' . $name];
                return $model;
            }
            $j = $positions[$name];
            $model->integer[$j] = true;
            $model->lower[$j] = new Rational();
            $model->upper[$j] = new Rational(1);
        }
    return $model;
}

function standardForm(object $model, array $lower, array $upper): object
{
    $columnNames = $owners = $directions = $mappings = [];
    foreach ($model->variables as $j => $name) {
        $first = count($columnNames);
        if ($lower[$j] !== null) {
            $kind = 'shift';
            $offset = $lower[$j];
            $columns = [$first];
            $signs = [1];
            $names = [$name];
        } elseif ($upper[$j] !== null) {
            $kind = 'reflect';
            $offset = $upper[$j];
            $columns = [$first];
            $signs = [-1];
            $names = [$name . "'"];
        } else {
            $kind = 'split';
            $offset = new Rational();
            $columns = [$first, $first + 1];
            $signs = [1, -1];
            $names = [$name . '+', $name . '-'];
        }
        array_push($columnNames, ...$names);
        array_push($owners, ...array_fill(0, count($columns), $j));
        array_push($directions, ...$signs);
        $mappings[] = (object) [
            'kind' => $kind,
            'offset' => $offset,
            'columns' => $columns,
            'directions' => $signs,
            'upperRow' => null,
        ];
    }
    $offsets = array_column($mappings, 'offset');
    $rowNames = array_column($model->constraints, 'name');
    $matrix = $rhs = [];
    $comparisons = $model->comparisons;
    foreach ($model->matrix as $i => $row) {
        $values = [];
        foreach ($owners as $k => $j)
            $values[] = $row[$j]->scale($directions[$k]);
        $matrix[] = $values;
        $rhs[] = $model->rhs[$i]->sub(dot($row, $offsets));
    }
    foreach ($mappings as $j => $mapping)
        if ($mapping->kind === 'shift' && $upper[$j] !== null) {
            $mapping->upperRow = count($rowNames);
            $rowNames[] = $model->variables[$j] . '.ub';
            $row = array_fill(0, count($columnNames), new Rational());
            $row[$mapping->columns[0]] = new Rational(1);
            $matrix[] = $row;
            $rhs[] = $upper[$j]->sub($lower[$j]);
            $comparisons[] = '<=';
        }
    $signs = array_fill(0, count($rowNames), 1);
    foreach ($rhs as $i => $v)
        if ($v->n < 0) {
            $matrix[$i] = array_map(fn($x) => $x->neg(), $matrix[$i]);
            $rhs[$i] = $v->neg();
            $signs[$i] = -1;
            $comparisons[$i] = ['<=' => '>=', '>=' => '<=', '=' => '='][$comparisons[$i]];
        }
    $slack = $initial = array_fill(0, count($rowNames), null);
    $artificial = [];
    foreach ($comparisons as $i => $comparison)
        if ($comparison !== '=') {
            $slack[$i] = count($columnNames);
            $columnNames[] = 's:' . $rowNames[$i];
            foreach ($matrix as $t => $_)
                $matrix[$t][] = new Rational($t === $i ? ($comparison === '<=' ? 1 : -1) : 0);
            if ($comparison === '<=')
                $initial[$i] = $slack[$i];
        }
    foreach ($comparisons as $i => $comparison)
        if ($comparison !== '<=') {
            $column = count($columnNames);
            $artificial[$column] = true;
            $initial[$i] = $column;
            $columnNames[] = 'a:' . $rowNames[$i];
            foreach ($matrix as $t => $_)
                $matrix[$t][] = new Rational($t === $i ? 1 : 0);
        }
    $direction = $model->direction === 'minimize' ? 1 : -1;
    $phase1 = $phase2 = [];
    foreach ($columnNames as $k => $_) {
        $phase1[] = new Rational(isset($artificial[$k]) ? 1 : 0);
        $phase2[] = isset($owners[$k])
            ? $model->costs[$owners[$k]]->scale($direction * $directions[$k])
            : new Rational();
    }
    return (object) compact(
        'columnNames',
        'rowNames',
        'mappings',
        'matrix',
        'rhs',
        'signs',
        'slack',
        'artificial',
        'initial',
        'phase1',
        'phase2',
        'direction',
    );
}

function tableauSolution(object $form, Tableau $t): array
{
    $values = array_fill(0, count($form->columnNames), new Rational());
    foreach ($t->basic as $i => $basic)
        $values[$basic] = $t->rhs[$i];
    $solution = [];
    foreach ($form->mappings as $m) {
        $v = $m->offset;
        foreach ($m->columns as $i => $k)
            $v = $v->add($values[$k]->scale($m->directions[$i]));
        $solution[] = $v;
    }
    return $solution;
}

function solveLp(object $model, array $lower, array $upper, int $number, int $level): object
{
    $f = standardForm($model, $lower, $upper);
    $f->constant = dot($model->costs, array_column($f->mappings, 'offset'));
    $t = new Tableau($f->rowNames, $f->columnNames, $f->matrix, $f->rhs, $f->initial);
    $lines = [];
    $emit = function (int $required, string $text) use (&$lines, $level): void {
        if ($level >= $required)
            $lines[] = $text;
    };
    $display = function (string $heading, array $costs, callable $objective) use (&$lines, $t, $level): void {
        if ($level >= 2)
            array_push($lines, ...$t->display($heading, $costs, $objective));
    };
    $identity = fn($v) => $v;
    $phase2Value = fn($v) => $f->constant->add($v->scale($f->direction));
    $emit(
        0,
        "SOLVE node $number rows "
            . count($f->rowNames)
            . ' columns '
            . count($f->columnNames)
            . ' artificials '
            . count($f->artificial),
    );
    foreach ($f->mappings as $j => $m) {
        $name = $model->variables[$j];
        $line = "MAP $name {$m->kind}";
        if ($m->kind === 'reflect')
            $line .= ' ' . $upper[$j];
        elseif ($m->kind === 'shift') {
            $line .= ' ' . $lower[$j];
            if ($upper[$j] !== null)
                $line .= ' upper ' . $upper[$j];
        }
        $emit(1, $line);
    }
    foreach ($f->signs as $i => $sign)
        if ($sign === -1)
            $emit(1, 'FLIP ' . $f->rowNames[$i]);
    $phase1 = $phase2 = $drives = $redundant = 0;
    $infeasibility = new Rational();
    $status = 'OPTIMAL';
    $unbounded = null;
    if ($f->artificial) {
        $emit(1, 'PHASE 1');
        $display('phase 1 start', $f->phase1, $identity);
        $phase = runPhase($t, $f->phase1, array_keys($f->columnNames), $identity);
        $phase1 = $phase->iterations;
        foreach ($phase->lines as $line)
            $emit(1, $line);
        $infeasibility = $t->phaseValue($f->phase1);
        $emit(1, "PHASE 1 END objective $infeasibility iterations $phase1");
        if ($infeasibility->n > 0) {
            $status = 'INFEASIBLE';
            $display('final', $f->phase1, $identity);
        } else {
            foreach ($t->basic as $i => $b)
                if (isset($f->artificial[$b])) {
                    $q = null;
                    foreach ($t->values[$i] as $k => $v)
                        if (!isset($f->artificial[$k]) && $v->n !== 0) {
                            $q = $k;
                            break;
                        }
                    if ($q === null) {
                        ++$redundant;
                        $emit(1, 'REDUNDANT row ' . $f->rowNames[$i]);
                    } else {
                        $leaving = $f->columnNames[$b];
                        $t->pivot($i, $q);
                        ++$drives;
                        $emit(1, "DRIVE row {$f->rowNames[$i]} enter {$f->columnNames[$q]} leave $leaving");
                    }
                }
        }
    }
    if ($status !== 'INFEASIBLE') {
        $emit(1, 'PHASE 2');
        $display('phase 2 start', $f->phase2, $phase2Value);
        $candidates = array_values(array_filter(
            array_keys($f->columnNames),
            fn($k) => !isset($f->artificial[$k]),
        ));
        $phase = runPhase($t, $f->phase2, $candidates, $phase2Value);
        $phase2 = $phase->iterations;
        foreach ($phase->lines as $line)
            $emit(1, $line);
        $unbounded = $phase->unbounded;
        if ($unbounded !== null) {
            $status = 'UNBOUNDED';
            $emit(1, 'UNBOUNDED enter ' . $f->columnNames[$unbounded]);
        }
        $value = $phase2Value($t->phaseValue($f->phase2));
        $emit(1, "PHASE 2 END objective $value iterations $phase2");
        $display('final', $f->phase2, $phase2Value);
    }
    $objective = $status === 'OPTIMAL' ? $phase2Value($t->phaseValue($f->phase2)) : null;
    $shown = $objective === null ? '-' : (string) $objective;
    $emit(
        0,
        "RESULT $status objective $shown phase1 $phase1 phase2 $phase2 drives $drives redundant $redundant",
    );
    return (object) [
        'status' => $status,
        'objective' => $objective,
        'solution' => tableauSolution($f, $t),
        'form' => $f,
        'tableau' => $t,
        'unbounded' => $unbounded,
        'infeasibility' => $infeasibility,
        'phase1' => $phase1,
        'phase2' => $phase2,
        'drives' => $drives,
        'redundant' => $redundant,
        'pivots' => $phase1 + $phase2 + $drives,
        'lines' => $lines,
    ];
}

function farkasMultipliers(object $r): array
{
    $f = $r->form;
    $reduced = $r->tableau->reduced($f->phase1);
    $v = [];
    foreach ($f->initial as $i => $k)
        $v[] = $f->phase1[$k]->sub($reduced[$k])->scale($f->signs[$i]);
    return $v;
}

function unboundedRay(object $model, object $r): array
{
    $t = $r->tableau;
    $f = $r->form;
    $q = $r->unbounded;
    $delta = array_fill(0, count($f->columnNames), new Rational());
    $delta[$q] = new Rational(1);
    foreach ($t->basic as $i => $b)
        $delta[$b] = $t->values[$i][$q]->neg();
    $ray = [];
    foreach ($f->mappings as $m) {
        $v = new Rational();
        foreach ($m->columns as $i => $k)
            $v = $v->add($delta[$k]->scale($m->directions[$i]));
        $ray[] = $v;
    }
    return [$ray, dot($model->costs, $ray)];
}

function statisticsLine(object $m): string
{
    $matrix = [];
    foreach ($m->matrix as $row)
        array_push($matrix, ...array_filter($row, fn($v) => $v->n !== 0));
    $sets = [
        'matrix' => $matrix,
        'objective' => $m->costs,
        'rhs' => $m->rhs,
        'bounds' => [...$m->lower, ...$m->upper],
    ];
    $parts = ['STATS nonzeros ' . count($matrix)];
    foreach ($sets as $name => $values) {
        $lo = $hi = null;
        foreach ($values as $v)
            if ($v !== null && $v->n !== 0) {
                $v = $v->magnitude();
                if ($lo === null || $v->cmp($lo) < 0)
                    $lo = $v;
                if ($hi === null || $v->cmp($hi) > 0)
                    $hi = $v;
            }
        $parts[] = "$name " . ($lo === null ? '- -' : "$lo $hi");
    }
    return implode(' ', $parts);
}

function rangeEndpoints(Rational $origin, array $coefficients, array $numerators): array
{
    $lo = $hi = null;
    foreach ($coefficients as $i => $c) {
        if ($c->n === 0)
            continue;
        $v = $numerators[$i]->div($c);
        if ($c->n > 0) {
            if ($lo === null || $v->cmp($lo) > 0)
                $lo = $v;
        } elseif ($hi === null || $v->cmp($hi) < 0)
            $hi = $v;
    }
    return [$lo === null ? null : $origin->add($lo), $hi === null ? null : $origin->add($hi)];
}

function objectiveRange(object $model, object $r, int $j, array $reduced, array $nonbasic): array
{
    $f = $r->form;
    $t = $r->tableau;
    $h = array_fill(0, count($f->columnNames), new Rational());
    $m = $f->mappings[$j];
    foreach ($m->columns as $i => $k)
        $h[$k] = new Rational($f->direction * $m->directions[$i]);
    $eta = $numerators = [];
    foreach ($nonbasic as $k) {
        $v = $h[$k];
        foreach ($t->basic as $i => $b)
            $v = $v->sub($h[$b]->mul($t->values[$i][$k]));
        $eta[] = $v;
        $numerators[] = $reduced[$k]->neg();
    }
    return rangeEndpoints($model->costs[$j], $eta, $numerators);
}

function rhsRange(object $model, object $r, int $i): array
{
    $f = $r->form;
    $t = $r->tableau;
    $rho = [];
    foreach ($t->values as $row => $values) {
        $v = $values[$f->initial[$i]]->scale($f->signs[$i]);
        if ($v->n !== 0 && isset($f->artificial[$t->basic[$row]]))
            return [$model->rhs[$i], $model->rhs[$i]];
        $rho[] = $v;
    }
    return rangeEndpoints($model->rhs[$i], $rho, array_map(fn($v) => $v->neg(), $t->rhs));
}

function variableStatus(object $f, array $basic, int $j): string
{
    $m = $f->mappings[$j];
    if ($m->kind === 'split')
        return array_any($m->columns, fn($k) => isset($basic[$k])) ? 'basic' : 'zero';
    if ($m->kind === 'reflect')
        return isset($basic[$m->columns[0]]) ? 'basic' : 'upper';
    if (!isset($basic[$m->columns[0]]))
        return 'lower';
    if ($m->upperRow !== null && !isset($basic[$f->slack[$m->upperRow]]))
        return 'upper';
    return 'basic';
}

function sensitivityLines(object $model, object $r): array
{
    $f = $r->form;
    $t = $r->tableau;
    $reduced = $t->reduced($f->phase2);
    $basic = array_fill_keys($t->basic, true);
    $nonbasic = array_values(array_filter(
        array_keys($f->columnNames),
        fn($k) => !isset($basic[$k]) && !isset($f->artificial[$k]),
    ));
    $dual = [];
    foreach ($model->constraints as $i => $_)
        $dual[] = $reduced[$f->initial[$i]]->scale(-$f->direction * $f->signs[$i]);
    $variableReduced = [];
    foreach ($model->costs as $j => $cost)
        $variableReduced[] = $cost->sub(dot($dual, array_column($model->matrix, $j)));
    $primal = 0;
    foreach ($t->basic as $i => $b)
        if (!isset($f->artificial[$b]) && $t->rhs[$i]->n === 0)
            ++$primal;
    $dualDeg = count(array_filter($nonbasic, fn($k) => $reduced[$k]->n === 0));
    $dualObjective = dot($dual, $model->rhs)->add(dot($variableReduced, $r->solution));
    $kind = in_array(true, $model->integer, true) ? 'relaxation' : 'lp';
    $out = [
        "MODEL {$model->name} $kind objective {$r->objective}",
        'BASIS ' . implode(' ', array_map(fn($k) => $f->columnNames[$k], $t->basic)),
        "DEGENERACY primal $primal dual $dualDeg",
        "DUAL objective $dualObjective",
    ];
    foreach ($model->constraints as $i => $c) {
        [$lo, $hi] = rhsRange($model, $r, $i);
        $out[] =
            "CONSTRAINT {$c->name} price {$dual[$i]} rhs {$model->rhs[$i]} range "
            . endpoint($lo, true)
            . ' '
            . endpoint($hi, false);
    }
    foreach ($model->variables as $j => $name) {
        [$lo, $hi] = objectiveRange($model, $r, $j, $reduced, $nonbasic);
        $status = variableStatus($f, $basic, $j);
        $out[] =
            "VARIABLE $name $status value {$r->solution[$j]} reduced {$variableReduced[$j]} cost {$model->costs[$j]} range "
            . endpoint($lo, true)
            . ' '
            . endpoint($hi, false);
    }
    return $out;
}

function solutionLines(object $model, object $r, int $pivots): array
{
    $root = $r->root;
    $integers = count(array_filter($model->integer));
    $out = [
        "MODEL {$model->name} {$model->direction} variables "
            . count($model->variables)
            . ' constraints '
            . count($model->constraints)
            . " integers $integers",
        statisticsLine($model),
        'STATUS ' . $r->status,
    ];
    if ($r->solution !== null)
        $out[] = "OBJECTIVE {$r->objective} approx " . $r->objective->approximate();
    if ($integers && $root->status === 'OPTIMAL')
        $out[] = "RELAXATION {$root->objective} approx " . $root->objective->approximate();
    if ($root->status === 'INFEASIBLE') {
        $out[] = 'INFEASIBILITY ' . $root->infeasibility;
        foreach (farkasMultipliers($root) as $i => $v)
            $out[] = 'FARKAS ' . $root->form->rowNames[$i] . ' ' . $v;
    }
    $values = $r->status === 'UNBOUNDED' ? $root->solution : $r->solution;
    if ($values !== null)
        foreach ($model->variables as $j => $name)
            $out[] = "VALUE $name {$values[$j]}";
    if ($r->status === 'UNBOUNDED') {
        [$ray, $rate] = unboundedRay($model, $root);
        foreach ($model->variables as $j => $name)
            $out[] = "RAY $name {$ray[$j]}";
        $out[] = "RATE $rate";
    }
    if ($r->solution !== null)
        foreach ($model->constraints as $i => $c) {
            $value = dot($model->matrix[$i], $r->solution);
            $margin = $model->comparisons[$i] === '<='
                ? $model->rhs[$i]->sub($value)
                : $value->sub($model->rhs[$i]);
            $out[] = "ROW {$c->name} $value $margin";
        }
    if ($integers)
        $out[] = 'NODES ' . $r->nodes;
    $out[] = "PIVOTS $pivots";
    return $out;
}

function main(): void
{
    $settings = readSettings();
    $iterations = $solutions = $sensitivity = $tree = [];
    $summary = ['model,status,objective,approx,relaxation,nodes,pivots'];
    $statuses = array_fill_keys(['OPTIMAL', 'INFEASIBLE', 'UNBOUNDED', 'NODE_LIMIT', 'ERROR'], 0);
    $solves = $phase1 = $phase2 = $drives = $analyzed = $integerModels = $integerNodes = $limited = 0;
    foreach (readModels() as $parsed) {
        $model = contentCheck($parsed);
        $name = $model->name;
        if ($model->error !== null) {
            ++$statuses['ERROR'];
            [$line, $message] = $model->error;
            $iterations[] = "MODEL $name error";
            array_push($solutions, "MODEL $name", "STATUS ERROR line $line $message");
            $sensitivity[] = "MODEL $name skipped ERROR";
            $summary[] = "$name,ERROR,-,-,-,0,0";
            continue;
        }
        $level = $settings->logs[$name] ?? $settings->level;
        $limit = $settings->limits[$name] ?? $settings->limit;
        $solve = fn($lo, $hi, $n) => solveLp($model, $lo, $hi, $n, $level);
        $integerCount = count(array_filter($model->integer));
        if ($integerCount)
            $result = branchSearch($model, $limit, $solve);
        else {
            $root = $solve($model->lower, $model->upper, 1);
            $result = (object) [
                'status' => $root->status,
                'objective' => $root->objective,
                'solution' => $root->status === 'OPTIMAL' ? $root->solution : null,
                'solves' => [$root],
                'root' => $root,
                'nodes' => 1,
                'lines' => [],
            ];
        }
        ++$statuses[$result->status];
        $iterations[] = "MODEL $name level $level";
        $pivots = 0;
        foreach ($result->solves as $lp) {
            array_push($iterations, ...$lp->lines);
            ++$solves;
            $phase1 += $lp->phase1;
            $phase2 += $lp->phase2;
            $drives += $lp->drives;
            $pivots += $lp->pivots;
        }
        array_push($solutions, ...solutionLines($model, $result, $pivots));
        if ($result->root->status === 'OPTIMAL') {
            ++$analyzed;
            array_push($sensitivity, ...sensitivityLines($model, $result->root));
        } else
            $sensitivity[] = "MODEL $name skipped {$result->root->status}";
        if ($integerCount) {
            ++$integerModels;
            $integerNodes += $result->nodes;
            if ($result->status === 'NODE_LIMIT')
                ++$limited;
            $tree[] = "MODEL $name {$model->direction} integers $integerCount node_limit $limit";
            array_push($tree, ...$result->lines);
        }
        $objective = $result->objective === null ? '-' : (string) $result->objective;
        $approx = $result->objective === null ? '-' : $result->objective->approximate();
        $relaxation = $result->root->objective === null ? '-' : (string) $result->root->objective;
        $summary[] =
            "$name,{$result->status},$objective,$approx,$relaxation," . count($result->solves) . ",$pivots";
    }
    $models = array_sum($statuses);
    $pivots = $phase1 + $phase2 + $drives;
    $iterations[] = "TOTAL solves $solves phase1 $phase1 phase2 $phase2 drives $drives pivots $pivots";
    $solutions[] = "SUMMARY models $models optimal {$statuses['OPTIMAL']} infeasible {$statuses['INFEASIBLE']} unbounded {$statuses['UNBOUNDED']} node_limit {$statuses['NODE_LIMIT']} error {$statuses['ERROR']}";
    $sensitivity[] = "SUMMARY analyzed $analyzed skipped " . ($models - $analyzed);
    $tree[] = "SUMMARY models $integerModels nodes $integerNodes node_limit $limited";
    if (!is_dir('output'))
        mkdir('output');
    foreach ([
        'iterations.txt' => $iterations,
        'solutions.txt' => $solutions,
        'sensitivity.txt' => $sensitivity,
        'bnb_tree.txt' => $tree,
        'summary.csv' => $summary,
    ] as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

main();
