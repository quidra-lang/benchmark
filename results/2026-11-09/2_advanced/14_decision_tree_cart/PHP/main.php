<?php

require_once __DIR__ . '/dataset.php';
require_once __DIR__ . '/impurity.php';
require_once __DIR__ . '/tree_builder.php';
require_once __DIR__ . '/evaluation.php';
require_once __DIR__ . '/pruning.php';

class Minstd
{
    public function __construct(public int $state)
    {
    }

    public function draw(): int
    {
        $this->state = 48271 * $this->state % 2147483647;
        return $this->state;
    }
}

class TreeCondition
{
    public ?int $lower = null;
    public ?int $upper = null;
    public ?int $equal = null;
    public array $excluded = [];

    public function __construct(public TreeAttribute $attribute)
    {
    }

    public function add(Split $split, bool $left): void
    {
        if ($this->attribute->integer) {
            if ($left) {
                $this->upper = $this->upper === null ? $split->point : min($this->upper, $split->point);
            } else {
                $this->lower = $this->lower === null ? $split->point : max($this->lower, $split->point);
            }
        } elseif ($left) {
            $this->equal = $split->point;
        } else {
            $this->excluded[$split->point] = true;
        }
    }

    public function text(): string
    {
        $name = $this->attribute->name;
        if ($this->attribute->integer) {
            if ($this->lower !== null && $this->upper !== null) {
                return half_text($this->lower) . " < $name <= " . half_text($this->upper);
            }
            return $this->lower !== null ? "$name > " . half_text($this->lower) : "$name <= " . half_text($this->upper);
        }
        if ($this->equal !== null) {
            return "$name = " . $this->attribute->values[$this->equal];
        }
        $names = [];
        foreach ($this->attribute->values as $index => $value) {
            if (isset($this->excluded[$index])) {
                $names[] = $value;
            }
        }
        return count($names) === 1 ? "$name != " . $names[0] : "$name not in {" . implode(',', $names) . '}';
    }

    public function holds(DataRow $row): bool
    {
        $value = $row->values[$this->attribute->index];
        if ($value === null) {
            return false;
        }
        if ($this->attribute->integer) {
            return ($this->lower === null || 2 * $value > $this->lower) && ($this->upper === null || 2 * $value <= $this->upper);
        }
        return $this->equal !== null ? $value === $this->equal : !isset($this->excluded[$value]);
    }
}

function conditions_text(array $conditions): string
{
    return $conditions ? implode(' and ', array_map(fn($condition) => $condition->text(), $conditions)) : 'true';
}

function coverage(array $conditions, array $rows, int $label): array
{
    $hits = 0;
    $covered = 0;
    foreach ($rows as $row) {
        foreach ($conditions as $condition) {
            if (!$condition->holds($row)) {
                continue 2;
            }
        }
        $covered++;
        if ($row->label === $label) {
            $hits++;
        }
    }
    return [$hits, $covered];
}

function generalize(array $conditions, array $rows, int $label, int $classCount): array
{
    $current = $conditions;
    $removed = [];
    while ($current) {
        [$hits, $covered] = coverage($current, $rows, $label);
        $estimate = [$hits + 1, $covered + $classCount];
        $best = null;
        $bestIndex = null;
        foreach ($current as $index => $condition) {
            $trial = $current;
            array_splice($trial, $index, 1);
            [$h, $c] = coverage($trial, $rows, $label);
            $value = [$h + 1, $c + $classCount];
            if ($best === null || compare_fractions($value, $best) > 0) {
                $best = $value;
                $bestIndex = $index;
            }
        }
        if (compare_fractions($estimate, $best) > 0) {
            break;
        }
        $removed[] = $current[$bestIndex]->attribute->name;
        array_splice($current, $bestIndex, 1);
    }
    return [$current, $removed];
}

function missing_count(DataRow $row): int
{
    return count(array_filter($row->values, fn($value) => $value === null));
}

function training_errors(TreeView $tree): int
{
    return array_sum(array_map(fn($leaf) => $leaf->errors, $tree->leaves()));
}

function tree_depth(TreeView $tree): int
{
    return max(array_map(fn($leaf) => $leaf->depth, $tree->leaves()));
}

function limited(TreeView $tree, int $depth): TreeView
{
    $cut = [];
    foreach ($tree->internalNodes() as $node) {
        if ($node->depth === $depth) {
            $cut[$node->number] = true;
        }
    }
    return new TreeView($tree->root, $cut);
}

function join_sections(array $sections): array
{
    $lines = [];
    foreach ($sections as $index => $section) {
        if ($index > 0) {
            $lines[] = '';
        }
        array_push($lines, ...$section);
    }
    return $lines;
}

class Study
{
    public array $attributes;
    public array $classes;
    public array $settings;
    public array $train;
    public array $validation;
    public array $test;
    public TreeBuilder $builder;
    public TreeView $grown;
    public TreeView $pruned;
    public array $decisions;
    public array $rules = [];
    public array $bounds = [];
    public array $foldTrees = [];
    public array $depthResults = [];
    public array $selectedDepth;
    public array $sequence;
    public int $selectedIndex = 0;
    public array $bags = [];
    public array $oobVotes = [];
    public array $testVotes = [];
    public array $predictions = [];

    public function __construct(public array $data)
    {
        $this->attributes = $data['attributes'];
        $this->classes = $data['classes'];
        $this->settings = $data['settings'];
        $this->train = $data['train'];
        $this->validation = $data['validation'];
        $this->test = $data['test'];
        $this->builder = new TreeBuilder($this->attributes, count($this->classes), $this->settings);
        $this->grown = new TreeView($this->builder->grow($this->train));
        [$this->pruned, $this->decisions] = reduced_error_pruning($this->grown->root, $this->validation);
        $this->buildRules();
        for ($fold = 0; $fold <= $this->settings['folds']; $fold++) {
            $this->bounds[] = intdiv($fold * count($this->train), $this->settings['folds']);
        }
        for ($fold = 0; $fold < $this->settings['folds']; $fold++) {
            $training = array_merge(array_slice($this->train, 0, $this->bounds[$fold]), array_slice($this->train, $this->bounds[$fold + 1]));
            $this->foldTrees[] = new TreeView($this->builder->grow($training));
        }
        for ($depth = 0; $depth <= $this->settings['max_depth']; $depth++) {
            $correct = 0;
            foreach ($this->foldTrees as $fold => $tree) {
                $correct += limited($tree, $depth)->correctCount($this->foldRows($fold));
            }
            $result = ['depth' => $depth, 'tree' => limited($this->grown, $depth), 'cv' => $correct];
            $this->depthResults[] = $result;
            if (!isset($this->selectedDepth) || $correct > $this->selectedDepth['cv']) {
                $this->selectedDepth = $result;
            }
        }
        $this->sequence = cost_complexity_sequence($this->grown->root);
        foreach ($this->sequence as $index => $step) {
            if ($this->validationErrors($step['tree']) <= $this->validationErrors($this->sequence[$this->selectedIndex]['tree'])) {
                $this->selectedIndex = $index;
            }
        }
        $this->bagging();
        $models = ['grown' => $this->grown, 'pruned' => $this->pruned, 'depth' => $this->selectedDepth['tree'],
            'cost_complexity' => $this->sequence[$this->selectedIndex]['tree']];
        foreach ($models as $name => $tree) {
            $this->predictions[$name] = array_map(fn($row) => $tree->predict($row), $this->test);
        }
        $this->predictions['bagging'] = array_map('majority', $this->testVotes);
    }

    public function accuracy(TreeView $tree, array $rows): string
    {
        return ratio_text($tree->correctCount($rows), count($rows));
    }

    public function foldRows(int $fold): array
    {
        return array_slice($this->train, $this->bounds[$fold], $this->bounds[$fold + 1] - $this->bounds[$fold]);
    }

    public function validationErrors(TreeView $tree): int
    {
        return count($this->validation) - $tree->correctCount($this->validation);
    }

    public function buildRules(): void
    {
        $collect = function ($node, $steps) use (&$collect) {
            if ($this->pruned->isLeaf($node)) {
                $conditions = [];
                foreach ($this->attributes as $attribute) {
                    $condition = null;
                    foreach ($steps as [$split, $left]) {
                        if ($split->attribute === $attribute) {
                            $condition ??= new TreeCondition($attribute);
                            $condition->add($split, $left);
                        }
                    }
                    if ($condition !== null) {
                        $conditions[] = $condition;
                    }
                }
                [$general, $removed] = generalize($conditions, $this->validation, $node->prediction, count($this->classes));
                $this->rules[] = ['number' => count($this->rules) + 1, 'leaf' => $node, 'label' => $node->prediction,
                    'conditions' => $conditions, 'general' => $general, 'removed' => $removed];
                return;
            }
            $collect($node->left, [...$steps, [$node->split, true]]);
            $collect($node->right, [...$steps, [$node->split, false]]);
        };
        $collect($this->pruned->root, []);
    }

    public function bagging(): void
    {
        $generator = new Minstd($this->settings['bag_seed']);
        $size = count($this->train);
        $this->oobVotes = array_fill(0, $size, array_fill(0, count($this->classes), 0));
        $this->testVotes = array_fill(0, count($this->test), array_fill(0, count($this->classes), 0));
        for ($bag = 0; $bag < $this->settings['bag_trees']; $bag++) {
            $sample = [];
            $sampled = [];
            for ($draw = 0; $draw < $size; $draw++) {
                $index = $generator->draw() % $size;
                $sample[] = $this->train[$index];
                $sampled[$index] = true;
            }
            $tree = new TreeView($this->builder->grow($sample));
            $outOfBag = 0;
            $correct = 0;
            foreach ($this->train as $index => $row) {
                if (!isset($sampled[$index])) {
                    $outOfBag++;
                    $prediction = $tree->predict($row);
                    $this->oobVotes[$index][$prediction]++;
                    if ($prediction === $row->label) {
                        $correct++;
                    }
                }
            }
            foreach ($this->test as $index => $row) {
                $this->testVotes[$index][$tree->predict($row)]++;
            }
            $this->bags[] = ['tree' => $tree, 'distinct' => count($sampled), 'out_of_bag' => $outOfBag, 'correct' => $correct];
        }
    }

    public function treeLines(TreeView $tree): array
    {
        $lines = [];
        $visit = function ($node, $condition) use (&$visit, &$lines, $tree) {
            $text = str_repeat('  ', $node->depth) . "$node->number $condition n $node->size counts " . implode(' ', $node->counts);
            if ($tree->isLeaf($node)) {
                $text .= ' leaf ' . $this->classes[$node->prediction];
            }
            $lines[] = $text;
            if (!$tree->isLeaf($node)) {
                $visit($node->left, $node->split->condition(true));
                $visit($node->right, $node->split->condition(false));
            }
        };
        $visit($tree->root, 'root');
        $nodes = $tree->preorder();
        $leaves = $tree->leaves();
        $depth = tree_depth($tree);
        $lines[] = '';
        $lines[] = sprintf('nodes %d leaves %d depth %d errors %s', count($nodes), count($leaves), $depth, ratio_text(training_errors($tree), count($this->train)));
        for ($level = 0; $level <= $depth; $level++) {
            $levelNodes = array_filter($nodes, fn($node) => $node->depth === $level);
            $levelLeaves = array_filter($leaves, fn($node) => $node->depth === $level);
            $rows = array_sum(array_map(fn($node) => $node->size, $levelLeaves));
            $errors = array_sum(array_map(fn($node) => $node->errors, $levelLeaves));
            $lines[] = sprintf('level %d nodes %d leaves %d rows %d errors %d', $level, count($levelNodes), count($levelLeaves), $rows, $errors);
        }
        return $lines;
    }

    public function treeFile(): array
    {
        $found = [];
        foreach ($this->attributes as $attribute) {
            $candidate = $this->builder->bestSplit($this->train, [$attribute]);
            if ($candidate !== null) {
                $found[] = $candidate;
            }
        }
        usort($found, fn($a, $b) => -compare_fractions($a['value'], $b['value']) ?: $a['split']->attribute->index <=> $b['split']->attribute->index);
        $root = $this->grown->root;
        $size = count($this->train);
        $candidates = ["root candidates n $size counts " . implode(' ', $root->counts)];
        foreach ($found as $index => $candidate) {
            $gain = $candidate['value'][0] / $candidate['value'][1] / $size - square_sum($root->counts) / ($size * $size);
            $candidates[] = sprintf('%d %s left %d right %d gain %s', $index + 1, $candidate['split']->condition(true), count($candidate['left']), count($candidate['right']), real_text($gain, 6));
        }
        $surrogates = ['surrogates'];
        foreach ($this->grown->internalNodes() as $node) {
            $listed = [];
            foreach ($node->surrogates as $surrogate) {
                $listed[] = sprintf('%s %s %d/%d', $surrogate['split']->condition(true), $surrogate['direction'], $surrogate['score'], $node->size);
            }
            $surrogates[] = sprintf('node %d split %s default %s surrogates %s', $node->number, $node->split->condition(true), $node->default, $listed ? implode(' ; ', $listed) : 'none');
        }
        return join_sections([$candidates, $this->treeLines($this->grown), $surrogates]);
    }

    public function prunedTreeFile(): array
    {
        $lines = ['reduced_error_pruning validation ' . count($this->validation)];
        $pruned = 0;
        foreach ($this->decisions as $decision) {
            if ($decision['pruned']) {
                $pruned++;
            }
            $lines[] = sprintf('node %d depth %d rows %d leaf %d subtree %d %s', $decision['node']->number, $decision['node']->depth,
                $decision['rows'], $decision['leaf_error'], $decision['subtree_error'], $decision['pruned'] ? 'pruned' : 'kept');
        }
        $lines[] = sprintf('examined %d pruned %d kept %d', count($this->decisions), $pruned, count($this->decisions) - $pruned);
        return join_sections([$lines, $this->treeLines($this->pruned)]);
    }

    public function predictionsFile(): array
    {
        $lines = ['id,predicted,actual,grown,leaf,path,missing'];
        foreach ($this->test as $index => $row) {
            $route = $this->pruned->route($row);
            $path = implode('-', array_map(fn($node) => $node->number, $route['path']));
            $missing = count(array_filter($route['steps'], fn($step) => $step['method'] !== 'primary'));
            $lines[] = implode(',', [$row->id, $this->classes[$route['leaf']->prediction], $this->classes[$row->label],
                $this->classes[$this->predictions['grown'][$index]], $route['leaf']->number, $path, $missing]);
        }
        return $lines;
    }

    public function rulesFile(): array
    {
        $original = ['rules ' . count($this->rules)];
        $generalized = ['generalized ' . count($this->rules)];
        $mistakes = [];
        $ruleNumbers = [];
        foreach ($this->rules as $rule) {
            $ruleNumbers[$rule['leaf']->number] = $rule['number'];
            $rows = 0;
            $hits = 0;
            foreach ($this->test as $row) {
                if ($this->pruned->route($row)['leaf'] === $rule['leaf']) {
                    $rows++;
                    if ($row->label === $rule['label']) {
                        $hits++;
                    }
                }
            }
            $original[] = sprintf('rule %d node %d if %s then %s train %s test %s', $rule['number'], $rule['leaf']->number,
                conditions_text($rule['conditions']), $this->classes[$rule['label']], ratio_text($rule['leaf']->counts[$rule['label']], $rule['leaf']->size), ratio_text($hits, $rows));
            [$vh, $vc] = coverage($rule['general'], $this->validation, $rule['label']);
            [$th, $tc] = coverage($rule['general'], $this->test, $rule['label']);
            $generalized[] = sprintf('general %d if %s then %s removed %s laplace %s validation %d/%d test %d/%d',
                $rule['number'], conditions_text($rule['general']), $this->classes[$rule['label']], $rule['removed'] ? implode(',', $rule['removed']) : 'none',
                fraction_text($vh + 1, $vc + count($this->classes)), $vh, $vc, $th, $tc);
        }
        foreach ($this->test as $row) {
            $route = $this->pruned->route($row);
            if ($route['leaf']->prediction !== $row->label) {
                $parts = [];
                foreach ($route['steps'] as $step) {
                    $parts[] = $step['node']->split->condition($step['left']) . ($step['method'] === 'primary' ? '' : ' [' . $step['method'] . ']');
                }
                $mistakes[] = sprintf('%s actual %s predicted %s rule %d path %s', $row->id, $this->classes[$row->label],
                    $this->classes[$route['leaf']->prediction], $ruleNumbers[$route['leaf']->number], $parts ? implode('; ', $parts) : 'root');
            }
        }
        return join_sections([$original, $generalized, ['misclassified ' . count($mistakes), ...$mistakes]]);
    }

    public function dataLines(): array
    {
        $lines = [sprintf('data train %d validation %d test %d attributes %d classes %d target %s', count($this->train), count($this->validation),
            count($this->test), count($this->attributes), count($this->classes), $this->data['target'])];
        $tr = class_counts($this->train, count($this->classes));
        $va = class_counts($this->validation, count($this->classes));
        $te = class_counts($this->test, count($this->classes));
        foreach ($this->classes as $label => $name) {
            $lines[] = "class $name train $tr[$label] validation $va[$label] test $te[$label]";
        }
        $vm = [];
        $tm = [];
        foreach ($this->attributes as $attribute) {
            $vm[] = count(array_filter($this->validation, fn($row) => $row->values[$attribute->index] === null));
            $tm[] = count(array_filter($this->test, fn($row) => $row->values[$attribute->index] === null));
        }
        $lines[] = 'missing validation ' . array_sum($vm) . ' test ' . array_sum($tm);
        foreach ($this->attributes as $index => $attribute) {
            $lines[] = "missing $attribute->name validation $vm[$index] test $tm[$index]";
        }
        return $lines;
    }

    public function summaryLine(string $name, TreeView $tree): string
    {
        return sprintf('%s nodes %d leaves %d depth %d train %s validation %s test %s', $name, count($tree->preorder()), count($tree->leaves()), tree_depth($tree),
            $this->accuracy($tree, $this->train), $this->accuracy($tree, $this->validation), $this->accuracy($tree, $this->test));
    }

    public function routingLines(): array
    {
        $tallies = [];
        $lines = ['routing pruned test'];
        foreach ($this->pruned->internalNodes() as $node) {
            $tallies[$node->number] = ['primary' => 0, 'surrogate' => 0, 'default' => 0];
        }
        $complete = [];
        $incomplete = [];
        foreach ($this->test as $row) {
            foreach ($this->pruned->route($row)['steps'] as $step) {
                $tallies[$step['node']->number][$step['method']]++;
            }
            if (missing_count($row) === 0) {
                $complete[] = $row;
            } else {
                $incomplete[] = $row;
            }
        }
        foreach ($this->pruned->internalNodes() as $node) {
            $tally = $tallies[$node->number];
            $lines[] = sprintf('node %d rows %d primary %d surrogate %d default %d', $node->number, array_sum($tally), $tally['primary'], $tally['surrogate'], $tally['default']);
        }
        $lines[] = 'complete rows ' . count($complete) . ' correct ' . $this->accuracy($this->pruned, $complete);
        $lines[] = 'incomplete rows ' . count($incomplete) . ' correct ' . $this->accuracy($this->pruned, $incomplete);
        return $lines;
    }

    public function crossValidationLines(): array
    {
        $lines = ['cross_validation folds ' . $this->settings['folds']];
        $total = 0;
        foreach ($this->foldTrees as $fold => $tree) {
            $rows = $this->foldRows($fold);
            $correct = $tree->correctCount($rows);
            $total += $correct;
            $lines[] = sprintf('fold %d rows %d-%d leaves %d correct %s', $fold + 1, $this->bounds[$fold] + 1, $this->bounds[$fold + 1], count($tree->leaves()), ratio_text($correct, count($rows)));
        }
        $lines[] = 'cv accuracy ' . ratio_text($total, count($this->train));
        return $lines;
    }

    public function depthLines(): array
    {
        $lines = ['depth_selection'];
        foreach ($this->depthResults as $result) {
            $tree = $result['tree'];
            $lines[] = sprintf('depth %d leaves %d cv %s train %s validation %s test %s', $result['depth'], count($tree->leaves()),
                ratio_text($result['cv'], count($this->train)), $this->accuracy($tree, $this->train), $this->accuracy($tree, $this->validation), $this->accuracy($tree, $this->test));
        }
        $selected = $this->selectedDepth;
        $lines[] = sprintf('selected depth %d leaves %d test %s', $selected['depth'], count($selected['tree']->leaves()), $this->accuracy($selected['tree'], $this->test));
        return $lines;
    }

    public function costComplexityLines(): array
    {
        $lines = ['cost_complexity'];
        foreach ($this->sequence as $index => $step) {
            $lines[] = sprintf('subtree %d alpha %s leaves %d train_errors %d validation_errors %d', $index,
                fraction_text($step['alpha'][0], $step['alpha'][1] * count($this->train), 6), count($step['tree']->leaves()), training_errors($step['tree']), $this->validationErrors($step['tree']));
        }
        $selected = $this->sequence[$this->selectedIndex]['tree'];
        $lines[] = sprintf('selected subtree %d leaves %d test %s', $this->selectedIndex, count($selected->leaves()), $this->accuracy($selected, $this->test));
        return $lines;
    }

    public function modelEvaluation(string $model): array
    {
        return classification_lines($model . ' test', $this->classes, $this->test, $this->predictions[$model]);
    }

    public function baggingLines(): array
    {
        $lines = [sprintf('bagging trees %d seed %d', $this->settings['bag_trees'], $this->settings['bag_seed'])];
        foreach ($this->bags as $index => $bag) {
            $lines[] = sprintf('bag %d distinct %d leaves %d oob %s', $index + 1, $bag['distinct'], count($bag['tree']->leaves()), ratio_text($bag['correct'], $bag['out_of_bag']));
        }
        $voted = 0;
        $hits = 0;
        foreach ($this->oobVotes as $index => $votes) {
            if (array_sum($votes) > 0) {
                $voted++;
                if (majority($votes) === $this->train[$index]->label) {
                    $hits++;
                }
            }
        }
        $lines[] = 'oob accuracy ' . ratio_text($hits, $voted) . ' unvoted ' . (count($this->train) - $voted);
        array_push($lines, ...$this->modelEvaluation('bagging'));
        return $lines;
    }

    public function mcnemarLines(): array
    {
        $lines = ['mcnemar pruned test'];
        foreach (['grown', 'depth', 'cost_complexity', 'bagging'] as $model) {
            $b = 0;
            $c = 0;
            foreach ($this->test as $index => $row) {
                $first = $this->predictions['pruned'][$index] === $row->label;
                $second = $this->predictions[$model][$index] === $row->label;
                if ($first && !$second) {
                    $b++;
                }
                if ($second && !$first) {
                    $c++;
                }
            }
            $difference = max(0, abs($b - $c) - 1);
            $squared = $difference * $difference;
            $statistic = $b + $c === 0 ? '0/1 0.0000' : fraction_text($squared, $b + $c);
            $lines[] = sprintf('versus %s b %d c %d statistic %s significant %s', $model, $b, $c, $statistic, 1000 * $squared > 3841 * ($b + $c) ? 'yes' : 'no');
        }
        return $lines;
    }

    public function aucLines(): array
    {
        $lines = [];
        foreach (['grown', 'pruned', 'bagging'] as $model) {
            $scores = [];
            foreach ($this->test as $index => $row) {
                if ($model === 'bagging') {
                    $scores[] = [$this->testVotes[$index], $this->settings['bag_trees']];
                } else {
                    $leaf = ($model === 'grown' ? $this->grown : $this->pruned)->route($row)['leaf'];
                    $scores[] = [$leaf->counts, $leaf->size];
                }
            }
            $parts = ['auc', $model];
            $total = 0.0;
            $available = 0;
            foreach ($this->classes as $label => $name) {
                $positives = [];
                $negatives = [];
                foreach ($this->test as $index => $row) {
                    if ($row->label === $label) {
                        $positives[] = $index;
                    } else {
                        $negatives[] = $index;
                    }
                }
                $wins = 0;
                foreach ($positives as $first) {
                    foreach ($negatives as $second) {
                        $comparison = compare_fractions([$scores[$first][0][$label], $scores[$first][1]], [$scores[$second][0][$label], $scores[$second][1]]);
                        if ($comparison > 0) {
                            $wins += 2;
                        } elseif ($comparison === 0) {
                            $wins++;
                        }
                    }
                }
                $denominator = 2 * count($positives) * count($negatives);
                $parts[] = $name;
                $parts[] = fraction_text($wins, $denominator);
                if ($denominator > 0) {
                    $total += $wins / $denominator;
                    $available++;
                }
            }
            $parts[] = 'macro';
            $parts[] = $available > 0 ? real_text($total / $available) : '-';
            $lines[] = implode(' ', $parts);
        }
        return $lines;
    }

    public function learningCurveLines(): array
    {
        $lines = ['learning_curve'];
        foreach ($this->settings['curve'] as $size) {
            $grown = new TreeView($this->builder->grow(array_slice($this->train, 0, $size)));
            [$pruned, $decisions] = reduced_error_pruning($grown->root, $this->validation);
            $lines[] = sprintf('size %d grown leaves %d test %s pruned leaves %d test %s', $size, count($grown->leaves()),
                $this->accuracy($grown, $this->test), count($pruned->leaves()), $this->accuracy($pruned, $this->test));
        }
        return $lines;
    }

    public function evaluationFile(): array
    {
        return join_sections([$this->dataLines(), [$this->summaryLine('grown', $this->grown), $this->summaryLine('pruned', $this->pruned)],
            $this->modelEvaluation('grown'), $this->modelEvaluation('pruned'), $this->routingLines(), $this->crossValidationLines(),
            $this->depthLines(), $this->costComplexityLines(), $this->baggingLines(), $this->mcnemarLines(), $this->aucLines(), $this->learningCurveLines()]);
    }

    public function impurityLines(string $title, TreeView $tree): array
    {
        $importance = array_fill(0, count($this->attributes), 0.0);
        $splits = array_fill(0, count($this->attributes), 0);
        foreach ($tree->internalNodes() as $node) {
            $index = $node->split->attribute->index;
            $importance[$index] += impurity_decrease($node);
            $splits[$index]++;
        }
        $total = 0.0;
        foreach ($importance as $value) {
            $total += $value;
        }
        $records = [];
        foreach ($this->attributes as $index => $attribute) {
            $share = real_text($total !== 0.0 ? $importance[$index] / $total : 0.0);
            $records[] = ['index' => $index, 'name' => $attribute->name, 'share' => $share, 'rounded' => (float) $share,
                'decrease' => real_text($importance[$index] / count($this->train)), 'splits' => $splits[$index]];
        }
        usort($records, fn($a, $b) => $b['rounded'] <=> $a['rounded'] ?: $a['index'] <=> $b['index']);
        $lines = ['impurity ' . $title];
        foreach ($records as $rank => $record) {
            $lines[] = sprintf('%d %s decrease %s share %s splits %d', $rank + 1, $record['name'], $record['decrease'], $record['share'], $record['splits']);
        }
        return $lines;
    }

    public function permutationLines(): array
    {
        $generator = new Minstd($this->settings['permutation_seed']);
        $repeats = $this->settings['permutation_repeats'];
        $size = count($this->test);
        $base = $this->pruned->correctCount($this->test);
        $results = [];
        foreach ($this->attributes as $attribute) {
            $counts = [];
            for ($repeat = 0; $repeat < $repeats; $repeat++) {
                $values = array_map(fn($row) => $row->values[$attribute->index], $this->test);
                for ($position = $size - 1; $position > 0; $position--) {
                    $other = $generator->draw() % ($position + 1);
                    [$values[$position], $values[$other]] = [$values[$other], $values[$position]];
                }
                $rows = [];
                foreach ($this->test as $index => $row) {
                    $changed = $row->values;
                    $changed[$attribute->index] = $values[$index];
                    $rows[] = new DataRow($row->id, $changed, $row->label);
                }
                $counts[] = $this->pruned->correctCount($rows);
            }
            $results[] = ['attribute' => $attribute, 'counts' => $counts, 'drop' => $repeats * $base - array_sum($counts)];
        }
        usort($results, fn($a, $b) => $b['drop'] <=> $a['drop'] ?: $a['attribute']->index <=> $b['attribute']->index);
        $lines = [sprintf('permutation pruned test repeats %d seed %d base %s', $repeats, $this->settings['permutation_seed'], ratio_text($base, $size))];
        foreach ($results as $rank => $result) {
            $lines[] = sprintf('%d %s correct %s drop %s', $rank + 1, $result['attribute']->name, implode(' ', $result['counts']), fraction_text($result['drop'], $repeats * $size));
        }
        return $lines;
    }

    public function importanceFile(): array
    {
        return join_sections([$this->impurityLines('grown', $this->grown), $this->impurityLines('pruned', $this->pruned), $this->permutationLines()]);
    }
}

function main(): void
{
    $study = new Study(load_dataset('input'));
    if (!is_dir('output')) {
        mkdir('output', 0777, true);
    }
    $files = ['tree.txt' => $study->treeFile(), 'pruned_tree.txt' => $study->prunedTreeFile(),
        'predictions.csv' => $study->predictionsFile(), 'rules.txt' => $study->rulesFile(),
        'evaluation.txt' => $study->evaluationFile(), 'importance.txt' => $study->importanceFile()];
    foreach ($files as $name => $lines) {
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
    }
}

main();
