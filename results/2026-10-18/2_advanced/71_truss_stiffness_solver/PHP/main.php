<?php
declare(strict_types=1);

require_once __DIR__ . '/model_io.php';
require_once __DIR__ . '/assembly.php';
require_once __DIR__ . '/solver.php';
require_once __DIR__ . '/postprocess.php';
require_once __DIR__ . '/design.php';

function real(float $value, int $digits = 4): string
{
    $text = sprintf('%.' . $digits . 'f', $value);
    return (float)$text == 0.0 && $text[0] === '-' ? substr($text, 1) : $text;
}

function choose(array $items, callable $key, bool $minimum = false): mixed
{
    $best = $items[array_key_first($items)];
    $score = (float)real($key($best));
    foreach ($items as $item) {
        $value = (float)real($key($item));
        if ($minimum ? $value < $score : $value > $score) {
            $best = $item;
            $score = $value;
        }
    }
    return $best;
}

function extreme_index(array $values, bool $minimum = false): int
{
    return choose(array_keys($values), static fn(int $i): float => $values[$i], $minimum);
}

function renumber(array $nodes, array $members): array
{
    $neighbors = array_fill(0, count($nodes), []);
    foreach ($members as $member) {
        $neighbors[$member->start][] = $member->end;
        $neighbors[$member->end][] = $member->start;
    }
    $compare = static fn(int $a, int $b): int =>
        [count($neighbors[$a]), $nodes[$a]->identifier] <=> [count($neighbors[$b]), $nodes[$b]->identifier];
    $indices = array_keys($nodes);
    usort($indices, $compare);
    $queue = [$indices[0]];
    $visited = [$indices[0] => true];
    for ($i = 0; $i < count($queue); ++$i) {
        $following = array_values(array_filter($neighbors[$queue[$i]], static fn(int $node): bool => !isset($visited[$node])));
        usort($following, $compare);
        foreach ($following as $node) {
            $queue[] = $node;
            $visited[$node] = true;
        }
    }
    return [array_reverse($queue), $neighbors];
}

function numbering_metrics(array $numbers, array $neighbors, array $members): array
{
    $bandwidth = 0;
    foreach ($members as $member) {
        $bandwidth = max($bandwidth, abs($numbers[$member->start] - $numbers[$member->end]));
    }
    $profile = 0;
    foreach ($neighbors as $node => $adjacent) {
        $minimum = $numbers[$node];
        foreach ($adjacent as $other) {
            $minimum = min($minimum, $numbers[$other]);
        }
        $profile += $numbers[$node] - $minimum;
    }
    return [$bandwidth, $profile];
}

final class Canvas
{
    public int $width;
    public int $height;
    private int $x0;
    private int $y1;
    private array $grid;

    public function __construct(array $nodes, private int $horizontal, private int $vertical)
    {
        $xs = array_map(static fn(Node $node): int => $node->x, $nodes);
        $ys = array_map(static fn(Node $node): int => $node->y, $nodes);
        $this->x0 = min($xs);
        $this->y1 = max($ys);
        $this->width = (int)floor((max($xs) - $this->x0) / $horizontal + 0.5) + 5;
        $this->height = (int)floor(($this->y1 - min($ys)) / $vertical + 0.5) + 5;
        $this->grid = array_fill(0, $this->height, str_repeat(' ', $this->width));
    }

    public function position(float $x, float $y): array
    {
        return [(int)floor(($x - $this->x0) / $this->horizontal + 0.5) + 2,
            (int)floor(($this->y1 - $y) / $this->vertical + 0.5) + 2];
    }

    public function put(int $column, int $row, string $character): void
    {
        if ($column >= 0 && $column < $this->width && $row >= 0 && $row < $this->height) {
            $this->grid[$row][$column] = $character;
        }
    }

    public function line(array $first, array $last, string $character): void
    {
        [$column, $row] = $first;
        [$final_column, $final_row] = $last;
        $dc = abs($final_column - $column);
        $dr = -abs($final_row - $row);
        $sc = $column < $final_column ? 1 : -1;
        $sr = $row < $final_row ? 1 : -1;
        $error = $dc + $dr;
        while (true) {
            $this->put($column, $row, $character);
            if ($column === $final_column && $row === $final_row) {
                break;
            }
            $twice = 2 * $error;
            if ($twice >= $dr) {
                $error += $dr;
                $column += $sc;
            }
            if ($twice <= $dc) {
                $error += $dc;
                $row += $sr;
            }
        }
    }

    public function framed(): array
    {
        $border = '+' . str_repeat('-', $this->width) . '+';
        return [$border, ...array_map(static fn(string $row): string => '|' . $row . '|', $this->grid), $border];
    }
}

final readonly class AnalysisSystem
{
    public function __construct(public array $properties, public array $matrix, public array $free_matrix,
        public ?array $lower, public ?int $unstable, public ?int $removed) {}
}

final class Truss
{
    private array $nodes, $members, $settings, $order, $neighbors, $numbers, $node_dofs, $owners;
    private array $prescribed, $support_directions = [], $restrained, $free, $geometry, $groups = [];
    private array $combination_definitions = [], $result_order = [], $deck, $deck_x, $units = [];
    private array $choices, $properties, $results, $combinations, $limits, $utilizations;
    private array $governing_cases, $governing;
    private int $degrees;
    private float $weight;
    private AnalysisSystem $final_system;

    public function __construct(private Model $model)
    {
        $this->nodes = $model->nodes;
        $this->members = $model->members;
        $this->settings = $model->settings;
        [$this->order, $this->neighbors] = renumber($this->nodes, $this->members);
        $this->numbers = array_fill(0, count($this->nodes), 0);
        foreach ($this->order as $number => $node) {
            $this->numbers[$node] = $number;
        }
        $this->node_dofs = array_map(static fn(int $number): array => [2 * $number, 2 * $number + 1], $this->numbers);
        $this->degrees = 2 * count($this->nodes);
        $this->owners = array_fill(0, $this->degrees, null);
        foreach ($this->node_dofs as $node => $directions) {
            foreach ($directions as $axis => $degree) {
                $this->owners[$degree] = [$node, $axis];
            }
        }
        $this->prescribed = array_fill(0, $this->degrees, 0.0);
        foreach ($model->supports as $support) {
            for ($axis = 0; $axis < 2; ++$axis) {
                if ($support->fixed[$axis]) {
                    $degree = $this->node_dofs[$support->node][$axis];
                    $this->prescribed[$degree] = $support->prescribed[$axis];
                    $this->support_directions[] = [$support->node, $axis, $degree];
                }
            }
        }
        $this->restrained = array_column($this->support_directions, 2);
        sort($this->restrained, SORT_NUMERIC);
        $this->free = array_values(array_diff(range(0, $this->degrees - 1), $this->restrained));
        $this->geometry = member_geometry($this->nodes, $this->members, $this->node_dofs);
        foreach ($this->members as $number => $member) {
            $this->groups[$member->group][] = $number;
        }
        foreach ($model->cases as $case) {
            $this->result_order[] = ['case', $case->name];
        }
        foreach ($model->combinations as $combination) {
            $this->combination_definitions[$combination->name] = $combination;
            $this->result_order[] = ['combination', $combination->name];
        }
        $this->deck = $this->settings['deck'];
        $this->deck_x = array_map(fn(int $node): int => $this->nodes[$node]->x, $this->deck);
    }

    private function system(array $choices, ?int $removed = null): AnalysisSystem
    {
        $properties = member_properties($this->model, $choices, $this->geometry);
        $matrix = assemble($this->geometry, $properties, $this->degrees, $removed);
        $free_matrix = [];
        foreach ($this->free as $row) {
            $free_matrix[] = array_map(static fn(int $column): float => $matrix[$row][$column], $this->free);
        }
        [$lower, $unstable] = cholesky($free_matrix, $this->free);
        return new AnalysisSystem($properties, $matrix, $free_matrix, $lower, $unstable, $removed);
    }

    private function displacement(AnalysisSystem $system, array $force, bool $settlement = false): array
    {
        $displacement = array_fill(0, $this->degrees, 0.0);
        foreach ($this->restrained as $degree) {
            $displacement[$degree] = $settlement ? $this->prescribed[$degree] : 0.0;
        }
        $right = [];
        foreach ($this->free as $degree) {
            $value = $force[$degree];
            foreach ($this->restrained as $restrained) {
                $value -= $system->matrix[$degree][$restrained] * $displacement[$restrained];
            }
            $right[] = $value;
        }
        $solution = solve($system->lower, $right);
        foreach ($this->free as $i => $degree) {
            $displacement[$degree] = $solution[$i];
        }
        return $displacement;
    }

    private function case_result(AnalysisSystem $system, LoadCase $case): AnalysisResult
    {
        $loading = load_vectors($case, $this->geometry, $system->properties, $this->node_dofs,
            $this->degrees, $system->removed);
        $displacement = $this->displacement($system, $loading->total, $loading->settlement);
        $forces = axial_forces($this->geometry, $system->properties, $displacement,
            $loading->temperature, $system->removed);
        $reaction = reactions($system->matrix, $displacement, $loading->total, $this->restrained);
        return new AnalysisResult($case->name, $displacement, $forces, $reaction, $loading->external);
    }

    private function analyze(AnalysisSystem $system, ?Combination $combination = null): array
    {
        $combinations = $combination === null ? $this->model->combinations : [$combination];
        $needed = [];
        foreach ($combinations as $item) {
            foreach ($item->terms as [$name]) {
                $needed[$name] = true;
            }
        }
        $results = [];
        foreach ($this->model->cases as $case) {
            if ($combination === null || isset($needed[$case->name])) {
                $results[$case->name] = $this->case_result($system, $case);
            }
        }
        foreach ($combinations as $item) {
            $results[$item->name] = superpose($item, $results);
        }
        return $results;
    }

    private function unit_result(int $node): AnalysisResult
    {
        if (!isset($this->units[$node])) {
            $force = array_fill(0, $this->degrees, 0.0);
            $force[$this->node_dofs[$node][1]] = -1000.0;
            $displacement = $this->displacement($this->final_system, $force);
            $forces = axial_forces($this->geometry, $this->properties, $displacement,
                array_fill(0, count($this->members), 0.0));
            $reaction = reactions($this->final_system->matrix, $displacement, $force, $this->restrained);
            $this->units[$node] = new AnalysisResult('unit', $displacement, $forces, $reaction, $force);
        }
        return $this->units[$node];
    }

    private function design_sections(): array
    {
        $choices = array_map(static fn(Member $member): int => $member->section, $this->members);
        $history = [];
        for ($round = 1; $round <= 10; ++$round) {
            $system = $this->system($choices);
            $results = $this->analyze($system);
            $combinations = array_map(static fn(Combination $item): AnalysisResult => $results[$item->name], $this->model->combinations);
            $limits = $utilizations = $candidates = [];
            $weight = 0.0;
            foreach ($this->members as $number => $member) {
                $limits[] = slenderness_limit($number, $combinations, $this->settings['slenderness']);
                $row = [];
                foreach ($combinations as $case => $result) {
                    $value = utilization($result->forces[$number], $system->properties[$number], $this->geometry[$number]);
                    $row[] = $value;
                    $candidates[] = [$value, $number, $case];
                }
                $utilizations[] = $row;
                $weight += member_weight($system->properties[$number], $this->geometry[$number]);
            }
            [$value, $member, $case] = choose($candidates, static fn(array $item): float => $item[0]);
            $changes = [];
            foreach ($this->groups as $name => $members) {
                $chosen = select_section($members, $this->model->sections, $system->properties,
                    $this->geometry, $combinations, $limits);
                $current = $choices[$members[0]];
                if ($chosen !== $current) {
                    $values = [];
                    foreach ($members as $number) {
                        array_push($values, ...$utilizations[$number]);
                    }
                    $largest = choose($values, static fn(float $entry): float => $entry);
                    $changes[] = [$name, $current, $chosen, $largest];
                }
            }
            $history[] = "round $round weight " . real($weight / 1000) . ' max_utilization ' . real($value)
                . " at {$this->members[$member]->identifier} {$combinations[$case]->name} changes " . count($changes);
            foreach ($changes as [$name, $current, $chosen, $largest]) {
                $history[] = "change $name {$this->model->sections[$current]->name} {$this->model->sections[$chosen]->name} utilization " . real($largest);
            }
            $converged = !$changes;
            if ($converged || $round === 10) {
                break;
            }
            foreach ($changes as [$name, , $chosen]) {
                foreach ($this->groups[$name] as $number) {
                    $choices[$number] = $chosen;
                }
            }
        }
        $this->choices = $choices;
        $this->final_system = $system;
        $this->properties = $system->properties;
        $this->results = $results;
        $this->combinations = $combinations;
        $this->limits = $limits;
        $this->utilizations = $utilizations;
        $this->weight = $weight;
        $this->governing_cases = array_map('extreme_index', $utilizations);
        $this->governing = [];
        foreach ($utilizations as $number => $row) {
            $this->governing[] = $row[$this->governing_cases[$number]];
        }
        $history[] = 'result ' . ($converged ? 'converged' : 'not_converged') . " rounds $round";
        return $history;
    }

    private function design_report(array $history): array
    {
        $lines = $history;
        foreach ($this->groups as $name => $members) {
            $member = choose($members, fn(int $number): float => $this->governing[$number]);
            $section = $this->model->sections[$this->choices[$members[0]]]->name;
            $lines[] = "group $name section $section members " . count($members) . ' utilization '
                . real($this->governing[$member]) . " at {$this->members[$member]->identifier}";
        }
        foreach ($this->members as $number => $member) {
            $section = $this->model->sections[$this->choices[$number]]->name;
            $value = $this->governing[$number];
            $slender = slenderness($this->properties[$number], $this->geometry[$number]);
            $limit = $this->limits[$number];
            $verdict = $value <= 1 && $slender <= $limit ? 'ok' : 'over';
            $combination = $this->combinations[$this->governing_cases[$number]]->name;
            $lines[] = "member {$member->identifier} group {$member->group} section $section utilization " . real($value)
                . " governing $combination slenderness " . real($slender) . ' limit ' . real($limit) . " $verdict";
        }
        $ranking = array_keys($this->members);
        usort($ranking, fn(int $a, int $b): int => (float)real($this->governing[$b]) <=> (float)real($this->governing[$a]));
        foreach (array_slice($ranking, 0, 5) as $rank => $number) {
            $lines[] = 'rank ' . ($rank + 1) . " member {$this->members[$number]->identifier} utilization " . real($this->governing[$number]);
        }
        foreach ($this->members as $number => $member) {
            $values = array_map(static fn(AnalysisResult $result): float => $result->forces[$number] / 1000, $this->combinations);
            $largest = extreme_index($values);
            $smallest = extreme_index($values, true);
            $lines[] = "envelope {$member->identifier} max " . real($values[$largest]) . " {$this->combinations[$largest]->name} min "
                . real($values[$smallest]) . " {$this->combinations[$smallest]->name}";
        }
        foreach ($this->model->sections as $section => $description) {
            $members = array_keys($this->choices, $section, true);
            if ($members) {
                $length = 0.0;
                foreach ($members as $number) {
                    $length += $this->geometry[$number]->length;
                }
                $lines[] = "section {$description->name} members " . count($members) . ' length ' . real($length);
            }
        }
        $lines[] = 'weight ' . real($this->weight / 1000);
        return $lines;
    }

    private function magnitudes(AnalysisResult $result): array
    {
        $values = [];
        foreach ($this->node_dofs as [$x, $y]) {
            $horizontal = $result->displacement[$x];
            $vertical = $result->displacement[$y];
            $values[] = sqrt($horizontal * $horizontal + $vertical * $vertical);
        }
        return $values;
    }

    private function result_summary(string $kind, AnalysisResult $result): string
    {
        $magnitudes = $this->magnitudes($result);
        $node = extreme_index($magnitudes);
        $energy = 0.0;
        foreach ($result->forces as $number => $force) {
            $shape = $this->geometry[$number];
            $member = $this->properties[$number];
            $energy += $force * $force * $shape->length / (2 * $member->young * $member->area);
        }
        $reactions = $loads = [0.0, 0.0];
        foreach ($this->node_dofs as $directions) {
            for ($axis = 0; $axis < 2; ++$axis) {
                $reactions[$axis] += $result->reactions[$directions[$axis]];
                $loads[$axis] += $result->external[$directions[$axis]];
            }
        }
        $scale = max(1, max(array_map('abs', $result->external)), max(array_map('abs', $result->reactions)));
        $equilibrium = equilibrium_residual($result, $this->geometry) <= 0.000001 * $scale ? 'ok' : 'failed';
        return "$kind {$result->name} equilibrium $equilibrium max_displacement " . real($magnitudes[$node])
            . " at {$this->nodes[$node]->identifier} energy " . real($energy / 1000) . ' reactions '
            . real($reactions[0] / 1000) . ' ' . real($reactions[1] / 1000) . ' loads '
            . real($loads[0] / 1000) . ' ' . real($loads[1] / 1000);
    }

    private function analysis_report(): array
    {
        $indeterminacy = count($this->members) + count($this->restrained) - 2 * count($this->nodes);
        $before = numbering_metrics(array_keys($this->nodes), $this->neighbors, $this->members);
        $after = numbering_metrics($this->numbers, $this->neighbors, $this->members);
        $order = implode(' ', array_map(fn(int $node): int => $this->nodes[$node]->identifier, $this->order));
        $lines = ['model nodes ' . count($this->nodes) . ' members ' . count($this->members) . ' supports '
            . count($this->model->supports) . ' free_dofs ' . count($this->free) . ' restrained_dofs '
            . count($this->restrained) . " indeterminacy $indeterminacy", "renumbering $order",
            "bandwidth before {$before[0]} after {$after[0]}", "profile before {$before[1]} after {$after[1]}"];
        foreach ($this->members as $number => $member) {
            $shape = $this->geometry[$number];
            $lines[] = "member {$member->identifier} nodes {$this->nodes[$member->start]->identifier} {$this->nodes[$member->end]->identifier} length "
                . real($shape->length) . ' cos ' . real($shape->cosine, 6) . ' sin ' . real($shape->sine, 6);
        }
        foreach ($this->result_order as [$kind, $name]) {
            $lines[] = $this->result_summary($kind, $this->results[$name]);
        }
        foreach ($this->support_directions as [$node, $axis, $degree]) {
            $values = array_map(static fn(AnalysisResult $result): float => $result->reactions[$degree] / 1000, $this->combinations);
            $largest = extreme_index($values);
            $smallest = extreme_index($values, true);
            $line = "reaction_envelope {$this->nodes[$node]->identifier} " . 'xy'[$axis]
                . ' max ' . real($values[$largest]) . " {$this->combinations[$largest]->name} min "
                . real($values[$smallest]) . " {$this->combinations[$smallest]->name}";
            if ($axis === 1) {
                $line .= ' uplift ' . (min($values) < 0 ? 'yes' : 'no');
            }
            $lines[] = $line;
        }
        $displacements = array_map($this->magnitudes(...), $this->combinations);
        foreach ($this->nodes as $node => $description) {
            $values = array_column($displacements, $node);
            $largest = extreme_index($values);
            $lines[] = "displacement_envelope {$description->identifier} max " . real($values[$largest])
                . " {$this->combinations[$largest]->name}";
        }
        return array_merge($lines, $this->deflection_report(), $this->removal_report());
    }

    private function deflection_report(): array
    {
        [$name, $ratio] = $this->settings['deflection'];
        $result = $this->results[$name];
        $fixed = [];
        foreach ($this->support_directions as [$node, $axis]) {
            if ($axis === 1) {
                $fixed[$node] = true;
            }
        }
        $anchors = [];
        foreach ($this->deck as $position => $node) {
            if (isset($fixed[$node])) {
                $anchors[] = $position;
            }
        }
        $lines = [];
        for ($span = 0; $span + 1 < count($anchors); ++$span) {
            [$first, $last] = [$anchors[$span], $anchors[$span + 1]];
            [$left, $right] = [$this->deck[$first], $this->deck[$last]];
            [$xa, $xb] = [$this->deck_x[$first], $this->deck_x[$last]];
            $va = $result->displacement[$this->node_dofs[$left][1]];
            $vb = $result->displacement[$this->node_dofs[$right][1]];
            $deflections = [];
            for ($i = $first + 1; $i < $last; ++$i) {
                $deflections[$i] = abs($result->displacement[$this->node_dofs[$this->deck[$i]][1]]
                    - ($va + ($vb - $va) * ($this->deck_x[$i] - $xa) / ($xb - $xa)));
            }
            $chosen = extreme_index($deflections);
            $maximum = $deflections[$chosen];
            $node = $this->deck[$chosen];
            $limit = ($xb - $xa) / $ratio;
            $verdict = $maximum <= $limit ? 'ok' : 'exceeded';
            $lines[] = "deflection $name span {$this->nodes[$left]->identifier} {$this->nodes[$right]->identifier} max "
                . real($maximum) . " at {$this->nodes[$node]->identifier} limit " . real($limit) . " $verdict";
            $unit = $this->unit_result($node);
            $virtual = 0.0;
            foreach ($result->forces as $number => $force) {
                $member = $this->properties[$number];
                $virtual += $force * ($unit->forces[$number] / 1000) * $this->geometry[$number]->length
                    / ($member->young * $member->area);
            }
            $stiffness = -$result->displacement[$this->node_dofs[$node][1]];
            $verified = abs($virtual - $stiffness) <= 0.000001 * max(1, abs($stiffness)) ? 'ok' : 'failed';
            $lines[] = "virtual_work $name node {$this->nodes[$node]->identifier} stiffness " . real($stiffness)
                . ' virtual ' . real($virtual) . " $verified";
        }
        return $lines;
    }

    private function removal_report(): array
    {
        $combination = $this->combination_definitions[$this->settings['removal']];
        $lines = [];
        foreach ($this->members as $removed => $description) {
            $system = $this->system($this->choices, $removed);
            if ($system->unstable !== null) {
                [$node, $axis] = $this->owners[$system->unstable];
                $lines[] = "removal {$description->identifier} unstable at {$this->nodes[$node]->identifier} " . 'xy'[$axis];
                continue;
            }
            $result = $this->analyze($system, $combination)[$combination->name];
            $values = [];
            foreach ($this->members as $number => $member) {
                if ($number !== $removed) {
                    $values[$number] = utilization($result->forces[$number], $system->properties[$number], $this->geometry[$number]);
                }
            }
            $largest = extreme_index($values);
            $magnitudes = $this->magnitudes($result);
            $node = extreme_index($magnitudes);
            $lines[] = "removal {$description->identifier} stable max_utilization " . real($values[$largest])
                . " at {$this->members[$largest]->identifier} max_displacement " . real($magnitudes[$node]) . " at {$this->nodes[$node]->identifier}";
        }
        return $lines;
    }

    private function ordinate(array $ordinates, int $position): float
    {
        $last = count($this->deck_x) - 1;
        if ($position < $this->deck_x[0] || $position > $this->deck_x[$last]) {
            return 0.0;
        }
        if ($position === $this->deck_x[$last]) {
            return $ordinates[$last];
        }
        $index = 0;
        while ($this->deck_x[$index + 1] <= $position) {
            ++$index;
        }
        [$first, $last] = [$this->deck_x[$index], $this->deck_x[$index + 1]];
        return $ordinates[$index] + ($ordinates[$index + 1] - $ordinates[$index]) * ($position - $first) / ($last - $first);
    }

    private function vehicle_range(array $ordinates, array $positions, array $axles): array
    {
        $effects = [];
        foreach ($positions as $position) {
            $value = 0.0;
            foreach ($axles as [$offset, $load]) {
                $value += $load * $this->ordinate($ordinates, $position - $offset);
            }
            $effects[] = $value;
        }
        $largest = extreme_index($effects);
        $smallest = extreme_index($effects, true);
        return [$effects[$largest], $positions[$largest], $effects[$smallest], $positions[$smallest]];
    }

    private function influence_report(): array
    {
        $member_ordinates = array_fill(0, count($this->members), []);
        $reaction_ordinates = [];
        foreach ($this->support_directions as [, , $degree]) {
            $reaction_ordinates[$degree] = [];
        }
        foreach ($this->deck as $node) {
            $result = $this->unit_result($node);
            foreach ($result->forces as $number => $force) {
                $member_ordinates[$number][] = $force / 1000;
            }
            foreach ($reaction_ordinates as $degree => $values) {
                $reaction_ordinates[$degree][] = $result->reactions[$degree] / 1000;
            }
        }
        $lines = [];
        foreach ($this->settings['influence'] as $number) {
            $ordinates = $member_ordinates[$number];
            $lines[] = "influence {$this->members[$number]->identifier}";
            $positive = $negative = 0.0;
            foreach ($this->deck as $i => $node) {
                $value = $ordinates[$i];
                $lines[] = "node {$this->nodes[$node]->identifier} " . real($value);
                if ($value > 0) {
                    $positive += $value;
                } elseif ($value < 0) {
                    $negative += $value;
                }
            }
            $largest = extreme_index($ordinates);
            $smallest = extreme_index($ordinates, true);
            $lines[] = 'max ' . real($ordinates[$largest]) . " at {$this->nodes[$this->deck[$largest]]->identifier} min "
                . real($ordinates[$smallest]) . " at {$this->nodes[$this->deck[$smallest]]->identifier} positive "
                . real($positive) . ' negative ' . real($negative);
            $crossings = [];
            for ($i = 0; $i + 1 < count($ordinates); ++$i) {
                [$first, $last] = [$ordinates[$i], $ordinates[$i + 1]];
                if (($first > 0 && $last < 0) || ($first < 0 && $last > 0)) {
                    $crossings[] = $this->deck_x[$i] + ($this->deck_x[$i + 1] - $this->deck_x[$i]) * $first / ($first - $last);
                }
            }
            $lines[] = 'crossings ' . count($crossings) . ($crossings ? ' ' . implode(' ', array_map(static fn(float $v): string => real($v, 1), $crossings)) : '');
        }
        [$step, $axles] = $this->settings['vehicle'];
        $positions = [];
        $end = $this->deck_x[count($this->deck_x) - 1] + $axles[count($axles) - 1][0];
        for ($position = $this->deck_x[0]; $position <= $end; $position += $step) {
            $positions[] = $position;
        }
        $lines[] = 'vehicle axles ' . count($axles) . ' positions ' . count($positions);
        $member_ranges = [];
        foreach ($this->members as $number => $member) {
            [$largest, $high_position, $smallest, $low_position] = $this->vehicle_range($member_ordinates[$number], $positions, $axles);
            $member_ranges[] = [$largest, $smallest];
            $lines[] = "vehicle_member {$member->identifier} max " . real($largest) . " at $high_position min " . real($smallest) . " at $low_position";
        }
        foreach ($this->support_directions as [$node, $axis, $degree]) {
            [$largest, $high_position, $smallest, $low_position] = $this->vehicle_range($reaction_ordinates[$degree], $positions, $axles);
            $lines[] = "vehicle_reaction {$this->nodes[$node]->identifier} " . 'xy'[$axis]
                . ' max ' . real($largest) . " at $high_position min " . real($smallest) . " at $low_position";
        }
        [$name, $dead_factor, $vehicle_factor] = $this->settings['rating'];
        $dead = $this->results[$name];
        $ratings = [];
        foreach ($this->members as $number => $member) {
            $properties = $this->properties[$number];
            $shape = $this->geometry[$number];
            [$largest, $smallest] = $member_ranges[$number];
            $dead_force = $dead->forces[$number] / 1000;
            $tension_capacity = $properties->area * $properties->yield_stress / 1000;
            $compression_capacity = min($properties->area * $properties->yield_stress, buckling($properties, $shape)) / 1000;
            $tension = $compression = 'none';
            if ((float)real($largest) > 0) {
                $rating = ($tension_capacity - $dead_factor * $dead_force) / ($vehicle_factor * $largest);
                $tension = real($rating);
                $ratings[] = [$number, 'tension', $rating];
            }
            if ((float)real($smallest) < 0) {
                $rating = ($compression_capacity + $dead_factor * $dead_force) / ($vehicle_factor * (-$smallest));
                $compression = real($rating);
                $ratings[] = [$number, 'compression', $rating];
            }
            $lines[] = "rating {$member->identifier} tension $tension compression $compression";
        }
        [$number, $kind, $rating] = choose($ratings, static fn(array $item): float => $item[2], true);
        $lines[] = 'rating_min ' . real($rating) . " at {$this->members[$number]->identifier} $kind";
        return $lines;
    }

    private function vibration_report(): array
    {
        [$name, $mode_count, $iterations] = $this->settings['vibration'];
        $external = $this->results[$name]->external;
        $masses = array_map(static fn(array $dofs): float => -$external[$dofs[1]] / 9.81, $this->node_dofs);
        $free_masses = array_map(fn(int $degree): float => $masses[$this->owners[$degree][0]], $this->free);
        $size = count($this->free);
        $system = $this->final_system;
        $modes = [];
        $total_mass = 0.0;
        foreach ($masses as $mass) {
            $total_mass += $mass;
        }
        $lines = ["vibration $name mass " . real($total_mass) . " iterations $iterations"];
        for ($mode = 1; $mode <= $mode_count; ++$mode) {
            $vector = array_fill(0, $size, 1.0);
            for ($iteration = 0; $iteration < $iterations; ++$iteration) {
                foreach ($modes as $previous) {
                    $beta = 0.0;
                    for ($i = 0; $i < $size; ++$i) {
                        $beta += $previous[$i] * $free_masses[$i] * $vector[$i];
                    }
                    for ($i = 0; $i < $size; ++$i) {
                        $vector[$i] -= $beta * $previous[$i];
                    }
                }
                $right = [];
                for ($i = 0; $i < $size; ++$i) {
                    $right[] = $free_masses[$i] * $vector[$i];
                }
                $solution = solve($system->lower, $right);
                $norm_squared = 0.0;
                for ($i = 0; $i < $size; ++$i) {
                    $norm_squared += $free_masses[$i] * $solution[$i] * $solution[$i];
                }
                $norm = sqrt($norm_squared);
                $vector = array_map(static fn(float $value): float => $value / $norm, $solution);
            }
            $modes[] = $vector;
            $numerator = $denominator = 0.0;
            for ($row = 0; $row < $size; ++$row) {
                $product = 0.0;
                for ($column = 0; $column < $size; ++$column) {
                    $product += $system->free_matrix[$row][$column] * $vector[$column];
                }
                $numerator += $vector[$row] * $product;
                $denominator += $free_masses[$row] * $vector[$row] * $vector[$row];
            }
            $frequency = sqrt(1000 * ($numerator / $denominator)) / (2 * TRUSS_PI);
            $lines[] = "mode $mode frequency " . real($frequency) . ' period ' . real(1 / $frequency);
            $peak = 0;
            for ($i = 1; $i < $size; ++$i) {
                if (abs($vector[$i]) > abs($vector[$peak])) {
                    $peak = $i;
                }
            }
            $normalized = array_fill(0, $this->degrees, 0.0);
            foreach ($this->free as $i => $degree) {
                $normalized[$degree] = $vector[$i] / $vector[$peak];
            }
            foreach ($this->nodes as $i => $node) {
                [$x, $y] = $this->node_dofs[$i];
                $lines[] = "node {$node->identifier} " . real($normalized[$x]) . ' ' . real($normalized[$y]);
            }
        }
        return $lines;
    }

    private function drawing_report(): array
    {
        $lines = [];
        foreach ($this->settings['drawing'] as [$name, $magnification, $horizontal, $vertical]) {
            $result = $this->results[$name];
            $canvas = new Canvas($this->nodes, $horizontal, $vertical);
            $original = $deformed = [];
            foreach ($this->nodes as $i => $node) {
                [$x, $y] = $this->node_dofs[$i];
                $original[] = $canvas->position($node->x, $node->y);
                $deformed[] = $canvas->position($node->x + $magnification * $result->displacement[$x],
                    $node->y + $magnification * $result->displacement[$y]);
            }
            foreach ($this->members as $member) {
                $canvas->line($original[$member->start], $original[$member->end], '.');
            }
            foreach ($original as [$column, $row]) {
                $canvas->put($column, $row, '+');
            }
            foreach ($this->members as $member) {
                $canvas->line($deformed[$member->start], $deformed[$member->end], '*');
            }
            foreach ($deformed as [$column, $row]) {
                $canvas->put($column, $row, 'o');
            }
            $lines[] = "drawing $name magnification $magnification columns {$canvas->width} rows {$canvas->height}";
            array_push($lines, ...$canvas->framed());
        }
        [$horizontal, $vertical] = $this->settings['utilization_map'];
        $canvas = new Canvas($this->nodes, $horizontal, $vertical);
        $positions = array_map(static fn(Node $node): array => $canvas->position($node->x, $node->y), $this->nodes);
        foreach ($this->members as $number => $member) {
            $value = $this->governing[$number];
            $character = $value >= 1 ? '#' : (string)(int)floor(10 * $value);
            $canvas->line($positions[$member->start], $positions[$member->end], $character);
        }
        foreach ($positions as [$column, $row]) {
            $canvas->put($column, $row, 'o');
        }
        $lines[] = "utilization_map columns {$canvas->width} rows {$canvas->height}";
        return array_merge($lines, $canvas->framed());
    }

    private function csv_reports(): array
    {
        $displacements = ['case,node,dx,dy'];
        $forces = ['case,member,force,stress,utilization'];
        $reactions = ['case,node,rx,ry'];
        foreach ($this->result_order as [, $name]) {
            $result = $this->results[$name];
            foreach ($this->nodes as $i => $node) {
                [$x, $y] = $this->node_dofs[$i];
                $displacements[] = "$name,{$node->identifier}," . real($result->displacement[$x]) . ',' . real($result->displacement[$y]);
            }
            foreach ($this->members as $number => $member) {
                $force = $result->forces[$number];
                $properties = $this->properties[$number];
                $value = utilization($force, $properties, $this->geometry[$number]);
                $forces[] = "$name,{$member->identifier}," . real($force / 1000) . ',' . real($force / $properties->area) . ',' . real($value);
            }
            foreach ($this->model->supports as $support) {
                [$x, $y] = $this->node_dofs[$support->node];
                $reactions[] = "$name,{$this->nodes[$support->node]->identifier}," . real($result->reactions[$x] / 1000) . ',' . real($result->reactions[$y] / 1000);
            }
        }
        return [$displacements, $forces, $reactions];
    }

    public function run(): void
    {
        $history = $this->design_sections();
        [$displacements, $forces, $reactions] = $this->csv_reports();
        $outputs = ['analysis.txt' => $this->analysis_report(), 'displacements.csv' => $displacements,
            'member_forces.csv' => $forces, 'reactions.csv' => $reactions, 'design.txt' => $this->design_report($history),
            'influence.txt' => $this->influence_report(), 'drawing.txt' => $this->drawing_report(),
            'vibration.txt' => $this->vibration_report()];
        if (!is_dir('output')) {
            mkdir('output');
        }
        foreach ($outputs as $name => $lines) {
            file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
        }
    }
}

(new Truss(read_model()))->run();
