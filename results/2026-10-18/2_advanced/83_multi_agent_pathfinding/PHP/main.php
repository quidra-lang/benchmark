<?php

foreach (['grid_map', 'low_level', 'cbs', 'prioritized', 'report'] as $module)
    require_once __DIR__ . "/$module.php";
const CLASSES = ['cardinal', 'semi_cardinal', 'non_cardinal'];

final class Planner
{
    private Grid $grid;
    private array
        $agents,
        $distances = [],
        $settings = ['orders' => [], 'runs' => [], 'delays' => []],
        $independent = [],
        $overview = []
    ;

    public function __construct()
    {
        $this->grid = new Grid();
        $this->agents = readAgents($this->grid);
        foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            $type = array_shift($f);
            switch ($type) {
                case 'HORIZON':
                    $this->settings['horizon'] = (int) $f[0];
                    break;
                case 'HL_BUDGET':
                    $this->settings['hl_budget'] = (int) $f[0];
                    break;
                case 'LL_BUDGET':
                    $this->settings['ll_budget'] = (int) $f[0];
                    break;
                case 'WINDOW':
                    [$this->settings['window'], $this->settings['step']] = array_map(intval(...), $f);
                    break;
                case 'ORDER':
                    $this->settings['orders'][] = array_map(intval(...), $f);
                    break;
                case 'RUN':
                    $this->settings['runs'][] = [
                        'name' => $f[0] . '-' . $f[1],
                        'solver' => $f[0],
                        'function' => $f[1],
                    ];
                    break;
                case 'ANIMATE':
                    $this->settings['animate'] = $f[0];
                    $this->settings['frames'] = (int) $f[1];
                    break;
                case 'DELAY':
                    $this->settings['delays'][] = array_map(intval(...), $f);
                    break;
            }
        }
        array_unshift($this->settings['orders'], range(0, count($this->agents) - 1));
        foreach ($this->agents as $a)
            $this->distances[] = $this->grid->distances($a['goal']);
    }

    private function mdd(int $i, int $length, Prohibitions $p): array
    {
        $layers = [[$this->agents[$i]['start'] => true]];
        $distance = $this->distances[$i];
        for ($t = 1; $t <= $length; ++$t) {
            $next = [];
            foreach ($layers[$t - 1] as $cell => $unused)
                foreach ($this->grid->adjacent[$cell] as $v)
                    if (
                        ($t + ($distance[$v] ?? ($length + 1))) <= $length
                        && $p->actionAllowed($cell, $v, $t)
                    )
                        $next[$v] = true;
            $layers[] = $next;
        }
        $valid = array_fill(0, $length + 1, []);
        $valid[$length] = [$this->agents[$i]['goal'] => true];
        for ($t = $length - 1; $t >= 0; --$t)
            foreach ($layers[$t] as $u => $unused)
                foreach ($this->grid->adjacent[$u] as $v)
                    if (isset($valid[$t + 1][$v]) && $p->actionAllowed($u, $v, $t + 1)) {
                        $valid[$t][$u] = true;
                        break;
                    }
        return $valid;
    }

    private function conflictClass(array $c, array $paths, array $restrictions, array &$cache): string
    {
        $fixed = 0;
        foreach ([$c['a'], $c['b']] as $i) {
            $length = count($paths[$i]) - 1;
            $layers = $cache[$i] ??= $this->mdd($i, $length, $restrictions[$i]);
            $t = $c['time'];
            $forced =
                $t > $length
                || (
                    $c['kind'] === 'vertex'
                        ? count($layers[$t]) === 1
                        : count($layers[$t - 1]) === 1
                        && count($layers[$t]) === 1
                );
            $fixed += (int) $forced;
        }
        return CLASSES[2 - $fixed];
    }

    private function overview(): void
    {
        $budget = new Budget();
        $p = new Prohibitions();
        $empty = [];
        $info = [];
        foreach ($this->agents as $i => $a) {
            [$path] = lowSearch(
                $this->grid,
                $a,
                $this->distances[$i],
                $a['start'],
                0,
                $p,
                $this->settings['horizon'],
                $budget,
            );
            $this->independent[] = $path;
            $shortest = $this->distances[$i][$a['start']];
            $layers = $this->mdd($i, $shortest, $p);
            $sizes = array_map(count(...), $layers);
            $info[] = ['shortest' => $shortest, 'states' => array_sum($sizes), 'width' => max($sizes)];
            $empty[] = new Prohibitions();
        }
        $conflicts = conflicts($this->independent);
        $cache = [];
        $classes = array_fill_keys(CLASSES, 0);
        $kinds = ['vertex' => 0, 'edge' => 0];
        $adjacent = array_fill(0, count($this->agents), []);
        foreach ($conflicts as &$c) {
            $c['class'] = $this->conflictClass($c, $this->independent, $empty, $cache);
            ++$classes[$c['class']];
            ++$kinds[$c['kind']];
            $adjacent[$c['a']][$c['b']] = true;
            $adjacent[$c['b']][$c['a']] = true;
        }
        unset($c);
        $seen = $groups = [];
        foreach ($this->agents as $start => $unused)
            if (!isset($seen[$start]) && $adjacent[$start]) {
                $queue = [$start];
                $seen[$start] = true;
                for ($j = 0; $j < count($queue); ++$j)
                    foreach ($adjacent[$queue[$j]] as $other => $unused)
                        if (!isset($seen[$other])) {
                            $seen[$other] = true;
                            $queue[] = $other;
                        }
                sort($queue, SORT_NUMERIC);
                $groups[] = implode('', array_map(agentName(...), $queue));
            }
        $this->overview = [
            'degrees' => $this->grid->statistics(),
            'agents' => $info,
            'soc' => array_sum(array_column($info, 'shortest')),
            'makespan' => max(array_column($info, 'shortest')),
            'conflicts' => $conflicts,
            'classes' => $classes,
            'kinds' => $kinds,
            'groups' => $groups,
        ];
    }

    private function solvePP(array &$run): void
    {
        $budget = $run['budget'];
        foreach ($this->settings['orders'] as $index => $order) {
            $number = $index + 1;
            ++$run['high'];
            $before = $budget->expansions;
            [$paths, $attempts, $failure] = tryOrder(
                $this->grid,
                $this->agents,
                $this->distances,
                $this->settings['horizon'],
                $order,
                $budget,
            );
            foreach ($attempts as $a) {
                $text = "order $number agent " . agentName($a['agent']);
                $text .= $a['path'] === null ? ' failed' : ' cost ' . (count($a['path']) - 1);
                $run['trace'][] = $text . ' expansions ' . $a['expansions'];
            }
            if ($failure === 'll_budget') {
                $run['reason'] = 'll_budget';
                break;
            }
            $names = implode('', array_map(agentName(...), $order));
            $planned = count($attempts) - ($failure === null ? 0 : 1);
            $expanded = $budget->expansions - $before;
            $text = "order $number $names planned $planned expansions $expanded";
            if ($failure === null) {
                $run['specific'][] = $text . ' ok';
                $run['paths'] = $paths;
                $run['status'] = 'OK';
                $run['end'] = "end OK order $number";
                return;
            }
            $run['specific'][] = $text . ' failed ' . agentName($failure);
        }
        $run['reason'] ??= 'orders';
        $run['end'] = 'end FAIL ' . $run['reason'];
    }

    private function solveCBS(array &$run): void
    {
        $budget = $run['budget'];
        $empty = $paths = [];
        try {
            foreach ($this->agents as $i => $a) {
                $empty[] = new Prohibitions();
                [$path] = lowSearch(
                    $this->grid,
                    $a,
                    $this->distances[$i],
                    $a['start'],
                    0,
                    $empty[$i],
                    $this->settings['horizon'],
                    $budget,
                );
                $paths[] = $path;
            }
        } catch (BudgetExceeded) {
            $run['reason'] = 'll_budget';
            $run['generated'] = 0;
            $run['specific'][] = 'search expanded 0 generated 0 pruned 0 open 0';
            if ($run['solver'] === 'ICBS')
                $run['specific'][] = 'classes cardinal 0 semi_cardinal 0 non_cardinal 0';
            $run['end'] = 'end FAIL ll_budget';
            return;
        }
        $root = newNode($paths, $empty, 0, 0, null, $run['function']);
        $open = new SplPriorityQueue();
        $open->setExtractFlags(SplPriorityQueue::EXTR_DATA);
        $open->insert($root, nodePriority($root));
        $generated = 1;
        $expanded = $pruned = 0;
        $classes = array_fill_keys(CLASSES, 0);
        $reason = 'exhausted';
        $answer = null;
        while (!$open->isEmpty()) {
            $node = $open->extract();
            if (!$node['conflicts']) {
                $answer = $node;
                break;
            }
            if ($expanded === $this->settings['hl_budget']) {
                $reason = 'hl_budget';
                break;
            }
            ++$expanded;
            $conflict = $node['conflicts'][0];
            $category = null;
            if ($run['solver'] === 'ICBS') {
                $cache = [];
                $best = 3;
                foreach ($node['conflicts'] as $c) {
                    $class = $this->conflictClass($c, $node['paths'], $node['constraints'], $cache);
                    $rank = array_search($class, CLASSES, true);
                    if ($rank < $best) {
                        $conflict = $c;
                        $category = $class;
                        $best = $rank;
                    }
                }
                ++$classes[$category];
            }
            $children = [];
            $aborted = false;
            foreach (splitConstraints($conflict) as [$agent, $kind, $value, $t]) {
                $restrictions = $node['constraints'];
                $changed = clone $restrictions[$agent];
                if ($kind === 'vertex')
                    $changed->states[$t][$value] = true;
                else {
                    [$u, $v] = $value;
                    $changed->moves[$t][$u . ':' . $v] = [$u, $v];
                }
                $restrictions[$agent] = $changed;
                try {
                    [$path] = lowSearch(
                        $this->grid,
                        $this->agents[$agent],
                        $this->distances[$agent],
                        $this->agents[$agent]['start'],
                        0,
                        $changed,
                        $this->settings['horizon'],
                        $budget,
                    );
                } catch (BudgetExceeded) {
                    $aborted = true;
                    break;
                }
                if ($path === null) {
                    ++$pruned;
                    $children[] = '-';
                    continue;
                }
                $newPaths = $node['paths'];
                $newPaths[$agent] = $path;
                $child = newNode(
                    $newPaths,
                    $restrictions,
                    $generated,
                    $node['depth'] + 1,
                    $node['number'],
                    $run['function'],
                );
                $open->insert($child, nodePriority($child));
                $children[] = $generated++;
            }
            if ($aborted) {
                $reason = 'll_budget';
                break;
            }
            $parent = $node['parent'] ?? '-';
            $text =
                "expand $expanded node {$node['number']} parent $parent depth {$node['depth']} cost {$node['cost']} conflicts "
                . count($node['conflicts'])
                . ' split '
                . conflictText($conflict, $this->grid);
            if ($category !== null)
                $text .= ' class ' . $category;
            $run['trace'][] = $text . " children {$children[0]} {$children[1]}";
        }
        $run['high'] = $expanded;
        $run['generated'] = $generated;
        $run['specific'][] =
            "search expanded $expanded generated $generated pruned $pruned open " . $open->count();
        if ($run['solver'] === 'ICBS')
            $run['specific'][] = "classes cardinal {$classes['cardinal']} semi_cardinal {$classes['semi_cardinal']} non_cardinal {$classes['non_cardinal']}";
        if ($answer === null) {
            $run['reason'] = $reason;
            $run['end'] = 'end FAIL ' . $reason;
            return;
        }
        $run['status'] = 'OK';
        $run['paths'] = $answer['paths'];
        $run['specific'][] = "solution node {$answer['number']} depth {$answer['depth']}";
        foreach (orderedConstraints($answer, $this->grid) as [$agent, $t, $rank, $u, $v, $kind])
            $run['specific'][] =
                'constraint '
                . agentName($agent)
                . ' '
                . $kind
                . ' '
                . cellText($u, $this->grid)
                . ($kind === 'edge' ? ' ' . cellText($v, $this->grid) : '')
                . " t $t";
        $run['end'] = "end OK node {$answer['number']} cost {$answer['cost']}";
    }

    private function solveWHCA(array &$run): void
    {
        $horizon = $this->settings['horizon'];
        $window = $this->settings['window'];
        $step = $this->settings['step'];
        $current = array_column($this->agents, 'start');
        $executed = array_map(fn($c) => [$c], $current);
        $time = $rounds = 0;
        $reason = null;
        while ($current !== array_column($this->agents, 'goal')) {
            if ($time >= $horizon) {
                $reason = 'timeout';
                break;
            }
            ++$rounds;
            $p = new Prohibitions();
            $moving = $done = [];
            foreach ($this->agents as $i => $a) {
                if ($current[$i] === $a['goal'])
                    $done[] = $i;
                else
                    $moving[] = $i;
            }
            $plans = [];
            foreach ([...$moving, ...$done] as $i) {
                try {
                    [$path, $expansions] = lowSearch(
                        $this->grid,
                        $this->agents[$i],
                        $this->distances[$i],
                        $current[$i],
                        $time,
                        $p,
                        $time + $window,
                        $run['budget'],
                        true,
                    );
                } catch (BudgetExceeded) {
                    $reason = 'll_budget';
                    break;
                }
                $prefix = "round $rounds time $time agent " . agentName($i);
                if ($path === null) {
                    $run['trace'][] = "$prefix blocked expansions $expansions";
                    $reason = 'blocked';
                    break;
                }
                while (count($path) < ($window + 1))
                    $path[] = $path[count($path) - 1];
                $plans[$i] = $path;
                $run['trace'][] =
                    "$prefix moves " . actionString($path, $this->grid) . " expansions $expansions";
                $p->reserve($path, $time);
            }
            if ($reason !== null)
                break;
            foreach ($this->agents as $i => $a) {
                array_push($executed[$i], ...array_slice($plans[$i], 1, $step));
                $current[$i] = $plans[$i][$step];
            }
            $time += $step;
        }
        $run['high'] = $rounds;
        $run['specific'][] = "window $window step $step rounds $rounds";
        if ($reason !== null) {
            $run['reason'] = $reason;
            $run['end'] = 'end FAIL ' . $reason;
            return;
        }
        foreach ($executed as $i => &$path)
            while (
                count($path) > 1
                && $path[count($path) - 1] === $this->agents[$i]['goal']
                && $path[count($path) - 2] === $this->agents[$i]['goal']
            )
                array_pop($path);
        unset($path);
        $run['status'] = 'OK';
        $run['paths'] = $executed;
        $run['end'] = "end OK rounds $rounds";
    }

    private function validate(array $paths): array
    {
        $start = $goal = $moves = $follows = 0;
        foreach ($paths as $i => $p) {
            $start += (int) ($p[0] !== $this->agents[$i]['start']);
            $goal += (int) ($p[count($p) - 1] !== $this->agents[$i]['goal']);
            for ($t = 1; $t < count($p); ++$t)
                if (!in_array($p[$t], $this->grid->adjacent[$p[$t - 1]], true))
                    ++$moves;
        }
        $collisions = conflicts($paths);
        $vertex = count(array_filter($collisions, fn($c) => $c['kind'] === 'vertex'));
        $edge = count($collisions) - $vertex;
        $horizon = max(array_map(fn($p) => count($p) - 1, $paths));
        for ($t = 1; $t <= $horizon; ++$t)
            foreach ($paths as $a => $pa) {
                $old = position($pa, $t - 1);
                $next = position($pa, $t);
                if ($next === $old)
                    continue;
                foreach ($paths as $b => $pb)
                    if ($a !== $b && $next === position($pb, $t - 1) && position($pb, $t) !== $old)
                        ++$follows;
            }
        return [
            'verdict' => ($start + $goal + $moves + $vertex + $edge) === 0 ? 'VALID' : 'INVALID',
            'start' => $start,
            'goal' => $goal,
            'moves' => $moves,
            'vertex' => $vertex,
            'edge' => $edge,
            'follows' => $follows,
            'conflicts' => $collisions,
        ];
    }

    private function metrics(array $paths, string $function): array
    {
        $records = $traffic = $cellWaits = [];
        $lengths = array_map(fn($p) => count($p) - 1, $paths);
        $soc = array_sum($lengths);
        $makespan = max($lengths);
        $cost = $function === 'SOC' ? $soc : $makespan;
        foreach ($paths as $i => $p) {
            $actions = actionString($p, $this->grid);
            $moves = str_replace('.', '', $actions);
            $turns = $leave = 0;
            for ($j = 1; $j < strlen($moves); ++$j)
                if ($moves[$j] !== $moves[$j - 1])
                    ++$turns;
            for ($j = 1; $j < count($p); ++$j) {
                if ($p[$j - 1] === $this->agents[$i]['goal'] && $p[$j] !== $this->agents[$i]['goal'])
                    ++$leave;
                if ($p[$j] === $p[$j - 1])
                    $cellWaits[$p[$j]] = ($cellWaits[$p[$j]] ?? 0) + 1;
            }
            foreach (array_unique($p) as $c)
                $traffic[$c] = ($traffic[$c] ?? 0) + 1;
            $records[] = [
                'cost' => $lengths[$i],
                'extra' => $lengths[$i] - $this->overview['agents'][$i]['shortest'],
                'waits' => substr_count($actions, '.'),
                'turns' => $turns,
                'arrive' => array_search($this->agents[$i]['goal'], $p, true),
                'leave' => $leave,
                'actions' => $actions,
            ];
        }
        $arrivals = [];
        for ($t = 0; $t <= $makespan; ++$t)
            $arrivals[] = count(array_filter($lengths, fn($l) => $l <= $t));
        $hotspots = array_keys($traffic);
        usort($hotspots, fn($a, $b) => $traffic[$b] <=> $traffic[$a] ?: $a <=> $b);
        $hotspots = array_slice($hotspots, 0, 5);
        return [
            'soc' => $soc,
            'makespan' => $makespan,
            'cost' => $cost,
            'ratio' => fraction($cost, $this->overview[$function === 'SOC' ? 'soc' : 'makespan']),
            'agents' => $records,
            'sum_extra' => array_sum(array_column($records, 'extra')),
            'max_extra' => max(array_column($records, 'extra')),
            'waits' => array_sum(array_column($records, 'waits')),
            'turns' => array_sum(array_column($records, 'turns')),
            'arrivals' => $arrivals,
            'traffic' => $traffic,
            'cell_waits' => $cellWaits,
            'hotspots' => $hotspots,
        ];
    }

    private function delayedExecution(array $paths): array
    {
        $steps = [];
        foreach ($paths as $p) {
            $entries = [[0, $p[0]]];
            for ($t = 1; $t < count($p); ++$t)
                if ($p[$t] !== $p[$t - 1])
                    $entries[] = [$t, $p[$t]];
            $steps[] = $entries;
        }
        $prerequisites = [];
        foreach ($steps as $i => $entries)
            for ($k = 1; $k < count($entries); ++$k) {
                [$scheduled, $cell] = $entries[$k];
                $prerequisites[$i][$k] = [];
                foreach ($steps as $j => $other)
                    if ($i !== $j)
                        foreach ($other as $l => [$t, $c])
                            if ($c === $cell && $t < $scheduled)
                                $prerequisites[$i][$k][] = [$j, $l];
            }
        $progress = array_fill(0, count($paths), 0);
        $finish = $progress;
        $holds = $time = 0;
        while (array_any(array_keys($paths), fn($i) => $progress[$i] < (count($steps[$i]) - 1))) {
            $advance = [];
            $stopped = 0;
            foreach ($paths as $i => $p) {
                if ($progress[$i] === (count($steps[$i]) - 1))
                    continue;
                if (array_any(
                    $this->settings['delays'],
                    fn($d) => $d[0] === $i && $d[1] <= $time && $time < ($d[1] + $d[2]),
                )) {
                    ++$stopped;
                    continue;
                }
                if (array_all($prerequisites[$i][$progress[$i] + 1], fn($r) => $progress[$r[0]] > $r[1]))
                    $advance[] = $i;
                else
                    ++$holds;
            }
            if (!$advance && !$stopped)
                return ['deadlock' => $time, 'blocked' => $holds];
            foreach ($advance as $i) {
                ++$progress[$i];
                if ($progress[$i] === (count($steps[$i]) - 1))
                    $finish[$i] = $time + 1;
            }
            ++$time;
        }
        return [
            'deadlock' => null,
            'blocked' => $holds,
            'finish' => $finish,
            'soc' => array_sum($finish),
            'makespan' => max($finish),
        ];
    }

    private function overviewLines(): array
    {
        $o = $this->overview;
        [$isolated, $dead, $corridors, $junctions, $components] = $o['degrees'];
        $lines = [
            "instance width {$this->grid->width} height {$this->grid->height} free "
                . count($this->grid->free)
                . ' agents '
                . count($this->agents),
            "map isolated $isolated dead_ends $dead corridors $corridors junctions $junctions components $components",
        ];
        foreach ($this->agents as $i => $a) {
            $r = $o['agents'][$i];
            $lines[] =
                "agent {$a['name']} start "
                . cellText($a['start'], $this->grid)
                . ' goal '
                . cellText($a['goal'], $this->grid)
                . " distance {$r['shortest']} mdd {$r['states']} width {$r['width']}";
        }
        $lines[] = "lower_bound soc {$o['soc']} makespan {$o['makespan']}";
        $c = $o['classes'];
        $k = $o['kinds'];
        $lines[] =
            'independent conflicts '
            . count($o['conflicts'])
            . " vertex {$k['vertex']} edge {$k['edge']} cardinal {$c['cardinal']} semi_cardinal {$c['semi_cardinal']} non_cardinal {$c['non_cardinal']}";
        $lines[] = 'groups ' . ($o['groups'] ? implode(' ', $o['groups']) : '-');
        return $lines;
    }

    private function validationLines(string $name, ?array $v, bool $baseline = false): array
    {
        if ($v === null)
            return ["plan $name verdict NONE"];
        $lines = [
            "plan $name verdict {$v['verdict']} start {$v['start']} goal {$v['goal']} moves {$v['moves']} vertex {$v['vertex']} edge {$v['edge']} follows {$v['follows']}",
        ];
        foreach ($v['conflicts'] as $c)
            $lines[] = '  ' . conflictText($c, $this->grid) . ($baseline ? ' ' . $c['class'] : '');
        return $lines;
    }

    private function animation(array $runs): array
    {
        $selected = null;
        foreach ($runs as $r)
            if ($r['name'] === $this->settings['animate'])
                $selected = $r;
        if ($selected['status'] !== 'OK')
            return ['run ' . $selected['name'] . ' FAIL'];
        $paths = $selected['paths'];
        $frames = $this->settings['frames'];
        $lines = ["run {$selected['name']} frames $frames"];
        for ($t = 0; $t < $frames; ++$t) {
            $done = $moving = $waiting = 0;
            $glyphs = [];
            foreach ($this->agents as $a)
                $glyphs[$a['goal']] = strtolower($a['name']);
            foreach ($paths as $i => $p) {
                if ($t >= (count($p) - 1))
                    ++$done;
                elseif ($t >= 1 && position($p, $t) !== position($p, $t - 1))
                    ++$moving;
                else
                    ++$waiting;
                $glyphs[position($p, $t)] = $this->agents[$i]['name'];
            }
            array_push(
                $lines,
                '',
                "frame $t done $done moving $moving waiting $waiting",
                ...picture($this->grid, $glyphs),
            );
        }
        foreach (['traffic' => 'traffic', 'waits' => 'cell_waits'] as $name => $key) {
            $glyphs = [];
            foreach ($selected['metrics'][$key] as $cell => $n)
                if ($n > 0)
                    $glyphs[$cell] = $n <= 9 ? (string) $n : '+';
            array_push($lines, '', $name, ...picture($this->grid, $glyphs));
        }
        return $lines;
    }

    private function write(array $runs): void
    {
        $solutions = $this->overviewLines();
        $stats = [
            'run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions',
        ];
        $v = $this->validate($this->independent);
        $v['conflicts'] = $this->overview['conflicts'];
        $validation = $this->validationLines('INDEPENDENT', $v, true);
        $trace = [];
        $successful = [];
        foreach ($runs as $index => $r) {
            $solutions[] = '';
            $prefix = "run {$r['name']} solver {$r['solver']} cost_function {$r['function']} result {$r['status']}";
            $fields = [$r['name'], $r['solver'], $r['function'], $r['status'], $r['reason'] ?? '-'];
            if ($r['status'] === 'OK') {
                $successful[] = $index;
                $m = $r['metrics'];
                $e = $r['execution'];
                $solutions[] =
                    $prefix
                    . " cost {$m['cost']} soc {$m['soc']} makespan {$m['makespan']} ratio {$m['ratio']}";
                array_push($solutions, ...$r['specific']);
                foreach ($this->agents as $i => $a) {
                    $record = $m['agents'][$i];
                    $solutions[] = "agent {$a['name']} cost {$record['cost']} extra {$record['extra']} waits {$record['waits']} turns {$record['turns']} arrive {$record['arrive']} leave {$record['leave']} moves {$record['actions']}";
                }
                $solutions[] = 'arrivals ' . implode(' ', $m['arrivals']);
                $spots = [];
                foreach ($m['hotspots'] as $cell)
                    $spots[] = cellText($cell, $this->grid) . ':' . $m['traffic'][$cell];
                $solutions[] = 'hotspots ' . implode(' ', $spots);
                $solutions[] = $e['deadlock'] !== null
                    ? 'execution deadlock time ' . $e['deadlock']
                    : "execution soc {$e['soc']} makespan {$e['makespan']} blocked {$e['blocked']} finish "
                    . implode(' ', $e['finish']);
                foreach (['cost', 'soc', 'makespan', 'sum_extra', 'max_extra', 'waits', 'turns'] as $key)
                    $fields[] = $m[$key];
                array_push(
                    $fields,
                    $e['deadlock'] === null ? $e['soc'] : '-',
                    $e['deadlock'] === null ? $e['makespan'] : '-',
                );
            } else {
                $solutions[] = $prefix . ' reason ' . $r['reason'];
                array_push($solutions, ...$r['specific']);
                array_push($fields, ...array_fill(0, 9, '-'));
            }
            array_push(
                $fields,
                $r['high'],
                $r['generated'] ?? '-',
                $r['budget']->searches,
                $r['budget']->expansions,
            );
            $stats[] = implode(',', $fields);
            array_push($validation, ...$this->validationLines($r['name'], $r['validation'] ?? null));
            if ($index)
                $trace[] = '';
            array_push($trace, 'run ' . $r['name'], ...$r['trace'], $r['end']);
        }
        $solutions[] = '';
        $solutions[] = 'summary ok ' . count($successful) . ' failed ' . (count($runs) - count($successful));
        if ($successful) {
            foreach (['soc' => 'best_soc', 'makespan' => 'best_makespan'] as $key => $label) {
                $best = min(array_map(fn($i) => $runs[$i]['metrics'][$key], $successful));
                $names = array_map(
                    fn($i) => $runs[$i]['name'],
                    array_filter($successful, fn($i) => $runs[$i]['metrics'][$key] === $best),
                );
                $solutions[] = "$label $best " . implode(' ', $names);
            }
            usort(
                $successful,
                fn($a, $b) => (
                    [$runs[$a]['metrics']['soc'], $runs[$a]['metrics']['makespan'], $a] <=> [
                        $runs[$b]['metrics']['soc'],
                        $runs[$b]['metrics']['makespan'],
                        $b,
                    ]
                ),
            );
            $solutions[] = 'ranking ' . implode(' ', array_map(fn($i) => $runs[$i]['name'], $successful));
        }
        foreach ([
            'solutions.txt' => $solutions,
            'stats.csv' => $stats,
            'validation.txt' => $validation,
            'trace.txt' => $trace,
            'frames.txt' => $this->animation($runs),
        ] as $name => $lines)
            saveFile($name, $lines);
    }

    public function run(): void
    {
        $this->overview();
        $results = [];
        foreach ($this->settings['runs'] as $definition) {
            $r = $definition
            + [
                'status' => 'FAIL',
                'reason' => null,
                'paths' => null,
                'high' => 0,
                'generated' => null,
                'budget' => new Budget($this->settings['ll_budget']),
                'specific' => [],
                'trace' => [],
                'end' => '',
            ];
            if ($r['solver'] === 'PP')
                $this->solvePP($r);
            elseif ($r['solver'] === 'WHCA')
                $this->solveWHCA($r);
            else
                $this->solveCBS($r);
            if ($r['status'] === 'OK') {
                $r['metrics'] = $this->metrics($r['paths'], $r['function']);
                $r['validation'] = $this->validate($r['paths']);
                $r['execution'] = $this->delayedExecution($r['paths']);
            }
            $results[] = $r;
        }
        $this->write($results);
    }
}

new Planner()->run();
