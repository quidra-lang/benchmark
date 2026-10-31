<?php

class Round
{
    private int $variables;
    private array $clauses;
    private array $values;
    private array $trail = [];
    private int $position = 0;
    private array $watches = [];
    private int $depth = 0;
    private object $statistics;
    private array $events = [];

    public function __construct(int $variables, array $clauses)
    {
        $this->variables = $variables;
        $this->clauses = $clauses;
        $this->values = array_fill(0, $variables + 1, 0);
        $this->statistics = (object) ['decisions' => 0, 'propagations' => 0, 'conflicts' => 0, 'maxDepth' => 0];
    }

    private function value(int $literal): int
    {
        return $this->values[abs($literal)] * ($literal > 0 ? 1 : -1);
    }

    private function assign(int $literal, string $kind): void
    {
        $this->values[abs($literal)] = $literal > 0 ? 1 : -1;
        $this->trail[] = (object) compact('literal', 'kind');
        $this->events[] = $kind . $literal;
        if ($kind !== 'P') $this->depth++;
    }

    private function conflict(): bool
    {
        $this->statistics->conflicts++;
        $this->events[] = 'C';
        return false;
    }

    private function initialize(): bool
    {
        foreach ($this->clauses as $index => $clause) {
            if (count($clause) < 2) continue;
            $this->watches[$clause[0]][] = $index;
            $this->watches[$clause[1]][] = $index;
        }
        foreach ($this->clauses as $clause) {
            if (!$clause || (count($clause) === 1 && $this->value($clause[0]) < 0)) return $this->conflict();
            if (count($clause) === 1 && $this->value($clause[0]) === 0) {
                $this->assign($clause[0], 'P');
                $this->statistics->propagations++;
            }
        }
        return true;
    }

    private function propagate(): bool
    {
        while ($this->position < count($this->trail)) {
            $falseLiteral = -$this->trail[$this->position++]->literal;
            if (!isset($this->watches[$falseLiteral])) $this->watches[$falseLiteral] = [];
            $list =& $this->watches[$falseLiteral];
            $index = 0;
            while ($index < count($list)) {
                $clauseNumber = $list[$index];
                $clause =& $this->clauses[$clauseNumber];
                if ($clause[0] === $falseLiteral) [$clause[0], $clause[1]] = [$clause[1], $clause[0]];
                if ($this->value($clause[0]) > 0) {
                    $index++;
                    continue;
                }
                $replacement = 2;
                while ($replacement < count($clause) && $this->value($clause[$replacement]) < 0) $replacement++;
                if ($replacement < count($clause)) {
                    [$clause[1], $clause[$replacement]] = [$clause[$replacement], $clause[1]];
                    array_splice($list, $index, 1);
                    $this->watches[$clause[1]][] = $clauseNumber;
                    continue;
                }
                if ($this->value($clause[0]) < 0) return $this->conflict();
                $this->assign($clause[0], 'P');
                $this->statistics->propagations++;
                $index++;
            }
            unset($clause, $list);
        }
        return true;
    }

    private function decide(): bool
    {
        $positive = $negative = array_fill(0, $this->variables + 1, 0);
        foreach ($this->clauses as $clause) {
            $satisfied = false;
            foreach ($clause as $literal) if ($this->value($literal) > 0) {
                $satisfied = true;
                break;
            }
            if ($satisfied) continue;
            foreach ($clause as $literal) {
                if ($this->value($literal) === 0) {
                    if ($literal > 0) $positive[abs($literal)]++;
                    else $negative[abs($literal)]++;
                }
            }
        }
        $chosen = $count = 0;
        for ($variable = 1; $variable <= $this->variables; $variable++) {
            if ($positive[$variable] > $count) {
                $count = $positive[$variable];
                $chosen = $variable;
            }
            if ($negative[$variable] > $count) {
                $count = $negative[$variable];
                $chosen = -$variable;
            }
        }
        if ($chosen === 0) return false;
        $this->assign($chosen, 'D');
        $this->statistics->decisions++;
        $this->statistics->maxDepth = max($this->statistics->maxDepth, $this->depth);
        return true;
    }

    private function removeLast(): object
    {
        $item = array_pop($this->trail);
        $this->values[abs($item->literal)] = 0;
        if ($item->kind !== 'P') $this->depth--;
        return $item;
    }

    private function backtrack(): bool
    {
        while ($this->trail && $this->trail[count($this->trail) - 1]->kind !== 'D') $this->removeLast();
        if (!$this->trail) return false;
        $decision = $this->removeLast();
        $this->position = count($this->trail);
        $this->assign(-$decision->literal, 'F');
        return true;
    }

    private function finish(bool $satisfiable): object
    {
        return (object) ['satisfiable' => $satisfiable, 'model' => $satisfiable ? array_map(fn($value) => $value > 0, $this->values) : null,
            'statistics' => $this->statistics, 'events' => $this->events];
    }

    public function run(): object
    {
        if (!$this->initialize()) return $this->finish(false);
        while (true) {
            if (!$this->propagate()) {
                if (!$this->backtrack()) return $this->finish(false);
            } elseif (!$this->decide()) return $this->finish(true);
        }
    }
}

function solveRound(int $variables, array $clauses): object
{
    return (new Round($variables, $clauses))->run();
}
