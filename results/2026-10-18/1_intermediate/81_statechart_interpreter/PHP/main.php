<?php
class EvaluationError extends Exception
{
}

class Expression
{
    private const PRECEDENCE = ['||' => 0, '&&' => 1, '==' => 2, '!=' => 2, '<' => 2, '<=' => 2, '>' => 2, '>=' => 2, '+' => 3, '-' => 3, '*' => 4, '/' => 4, '%' => 4];
    private array $tokens;
    private int $index = 0;
    private array $tree;
    public array $references = [];

    public function __construct(string $text)
    {
        preg_match_all('~\|\||&&|==|!=|<=|>=|[()+*/%!<>-]|[0-9]+|[A-Za-z_][A-Za-z0-9_]*~', $text, $matches);
        $this->tokens = $matches[0];
        $this->tree = $this->parse(0);
    }

    private function parse(int $level): array
    {
        if ($level === 5) {
            return $this->unary();
        }
        $left = $this->parse($level + 1);
        while ((self::PRECEDENCE[$this->tokens[$this->index] ?? ''] ?? -1) === $level) {
            $operator = $this->tokens[$this->index++];
            $left = [$operator, $left, $this->parse($level + 1)];
        }
        return $left;
    }

    private function unary(): array
    {
        $token = $this->tokens[$this->index++];
        if ($token === '!' || $token === '-') {
            return [$token === '!' ? 'not' : 'negative', $this->unary()];
        }
        if ($token === '(') {
            $result = $this->parse(0);
            $this->index++;
            return $result;
        }
        if ($token === 'in') {
            $this->index++;
            $state = $this->tokens[$this->index];
            $this->index += 2;
            $this->references[] = ['state', $state];
            return ['in', $state];
        }
        if (preg_match('/\A[0-9]+\z/D', $token)) {
            return ['number', (int)$token];
        }
        if ($token !== '_data') {
            $this->references[] = ['variable', $token];
        }
        return ['variable', $token];
    }

    public function evaluate(array $variables, int $data, array $configuration, ?array $node = null): int
    {
        $node ??= $this->tree;
        $operator = $node[0];
        $left = $node[1];
        if ($operator === 'number') {
            return $left;
        }
        if ($operator === 'variable') {
            return $left === '_data' ? $data : $variables[$left];
        }
        if ($operator === 'in') {
            return (int)isset($configuration[$left]);
        }
        if ($operator === 'not' || $operator === 'negative') {
            $value = $this->evaluate($variables, $data, $configuration, $left);
            return $operator === 'not' ? (int)($value === 0) : -$value;
        }
        $a = $this->evaluate($variables, $data, $configuration, $left);
        if ($operator === '&&' && $a === 0) {
            return 0;
        }
        if ($operator === '||' && $a !== 0) {
            return 1;
        }
        $b = $this->evaluate($variables, $data, $configuration, $node[2]);
        if (($operator === '/' || $operator === '%') && $b === 0) {
            throw new EvaluationError();
        }
        return match ($operator) {
            '+' => $a + $b, '-' => $a - $b, '*' => $a * $b,
            '/' => intdiv($a, $b), '%' => $a - intdiv($a, $b) * $b,
            '==' => (int)($a === $b), '!=' => (int)($a !== $b), '<' => (int)($a < $b),
            '<=' => (int)($a <= $b), '>' => (int)($a > $b), '>=' => (int)($a >= $b),
            '&&', '||' => (int)($b !== 0)
        };
    }
}

class State
{
    public array $children = [];
    public State|string|null $initial = null;
    public ?string $historyKind = null;
    public State|string|null $default = null;
    public array $entries = [];
    public array $exits = [];
    public array $transitions = [];
    public int $depth;
    public int $entered = 0;
    public int $taken = 0;
    public int $dwell = 0;
    public int $entryTime = 0;

    public function __construct(public string $name, public string $kind, public ?State $parent = null)
    {
        $this->depth = $parent === null ? 0 : $parent->depth + 1;
    }

    public function childStates(): array
    {
        return array_values(array_filter($this->children, fn($state) => $state->kind !== 'history'));
    }

    public function compound(): bool
    {
        return $this->kind === 'root' || ($this->kind === 'state' && $this->childStates() !== []);
    }

    public function parallel(): bool
    {
        return $this->kind === 'parallel' && $this->childStates() !== [];
    }

    public function atomic(): bool
    {
        return $this->kind !== 'history' && $this->childStates() === [];
    }

    public function initialChild(): State
    {
        return $this->initial ?? $this->childStates()[0];
    }
}

class Transition
{
    public function __construct(public State $source, public string $kind, public array $descriptors, public int $delay, public ?Expression $guard, public ?State $target, public string $mode, public array $actions)
    {
    }
}

class Chart
{
    private State $root;
    private array $states = [];
    private array $variables = [];
    private array $errors = [];
    private array $document = [];
    private array $configuration = [];
    private array $history = [];
    private array $queue = [];
    private array $reservations = [];
    private int $creation = 0;
    private int $time = 0;
    private int $data = 0;
    private int $macrosteps = 0;
    private int $microsteps = 0;
    private bool $trace = false;
    private bool $halted = false;

    public function __construct(private array $definitions)
    {
        $this->root = new State('', 'root');
    }

    private function descendant(State $state, State $ancestor): bool
    {
        for ($parent = $state->parent; $parent !== null; $parent = $parent->parent) {
            if ($parent === $ancestor) {
                return true;
            }
        }
        return false;
    }

    private function checkReferences(array $references): ?string
    {
        foreach ($references as [$kind, $name]) {
            if ($kind === 'variable' && !array_key_exists($name, $this->variables)) {
                return "unknown variable $name";
            }
            if ($kind === 'state' && !isset($this->states[$name])) {
                return "unknown state $name";
            }
        }
        return null;
    }

    private function expression(?string $text): ?Expression
    {
        return $text === null ? null : new Expression($text);
    }

    private function actions(?string $text): array
    {
        $references = $result = [];
        foreach ($text === null ? [] : explode('; ', $text) as $action) {
            $parts = explode(' ', $action, 2);
            $kind = $parts[0];
            $rest = $parts[1] ?? '';
            $record = ['kind' => $kind];
            if ($kind === 'raise') {
                $parts = explode(' ', $rest, 2);
                $record['event'] = $parts[0];
                $record['expression'] = $this->expression($parts[1] ?? null);
            } elseif ($kind === 'send') {
                $parts = explode(' ', $rest, 3);
                $record['event'] = $parts[0];
                $record['delay'] = (int)$parts[1];
                $record['expression'] = $this->expression($parts[2] ?? null);
            } elseif ($kind === 'cancel') {
                $record['event'] = $rest;
            } elseif ($kind === 'log') {
                if (str_starts_with($rest, '"')) {
                    $finish = strpos($rest, '"', 1);
                    $record['text'] = substr($rest, 1, $finish - 1);
                    if ($finish + 1 < strlen($rest)) {
                        $record['expression'] = $this->expression(substr($rest, $finish + 2));
                    }
                } else {
                    $record['expression'] = $this->expression($rest);
                }
            } else {
                [$name, $value] = explode(' = ', $action, 2);
                $record = ['kind' => 'assign', 'name' => $name, 'expression' => $this->expression($value)];
                $references[] = ['variable', $name];
            }
            if (isset($record['expression'])) {
                $references = array_merge($references, $record['expression']->references);
            }
            $result[] = $record;
        }
        return [$result, $references];
    }

    private function validate(): bool
    {
        foreach ($this->definitions as [$line, $number]) {
            $parts = explode(' ', $line);
            [$kind, $name] = array_slice($parts, 0, 2);
            if (in_array($kind, ['state', 'parallel', 'final', 'history'], true)) {
                $parentName = $kind === 'state' && ($parts[2] ?? '') === 'initial' ? null : ($parts[2] ?? null);
                if (isset($this->states[$name])) {
                    $this->errors[$number] = "duplicate state $name";
                } elseif ($parentName !== null && !isset($this->states[$parentName])) {
                    $this->errors[$number] = "unknown state $parentName";
                } elseif ($parentName !== null && in_array($this->states[$parentName]->kind, ['final', 'history'], true)) {
                    $this->errors[$number] = "$parentName cannot have children";
                } else {
                    $parent = $parentName === null ? $this->root : $this->states[$parentName];
                    $state = new State($name, $kind, $parent);
                    if ($kind === 'history') {
                        $state->historyKind = $parts[3];
                        $state->default = $parts[4] ?? null;
                    }
                    if ($kind === 'state' && ($at = array_search('initial', $parts, true)) !== false) {
                        $state->initial = $parts[$at + 1];
                    }
                    $this->states[$name] = $state;
                    $parent->children[] = $state;
                }
            } elseif ($kind === 'var') {
                if (array_key_exists($name, $this->variables)) {
                    $this->errors[$number] = "duplicate variable $name";
                } else {
                    $this->variables[$name] = (int)$parts[2];
                }
            }
        }
        $visit = function (State $state) use (&$visit): void {
            $this->document[] = $state;
            foreach ($state->children as $child) {
                $visit($child);
            }
        };
        foreach ($this->root->children as $state) {
            $visit($state);
        }
        foreach ($this->definitions as [$line, $number]) {
            if (isset($this->errors[$number])) {
                continue;
            }
            [$kind, $name] = array_slice(explode(' ', $line), 0, 2);
            $state = $this->states[$name] ?? null;
            $reason = null;
            if ($kind === 'state' && $state->initial !== null) {
                $child = $this->states[$state->initial] ?? null;
                if ($child === null) {
                    $reason = "unknown state {$state->initial}";
                } elseif ($child->parent !== $state || $child->kind === 'history') {
                    $reason = "{$child->name} is not a child of $name";
                }
            } elseif ($kind === 'final' || $kind === 'history') {
                $parent = $state->parent;
                if ($parent->kind !== 'state' || $parent->childStates() === []) {
                    $reason = "$name needs a compound parent";
                } elseif ($kind === 'history' && $state->default !== null) {
                    $target = $this->states[$state->default] ?? null;
                    if ($target === null) {
                        $reason = "unknown state {$state->default}";
                    } elseif (!$this->descendant($target, $parent) || $target->kind === 'history') {
                        $reason = "{$target->name} is not a descendant of {$parent->name}";
                    }
                }
            } elseif ($kind === 'entry' || $kind === 'exit') {
                if ($state === null) {
                    $reason = "unknown state $name";
                } elseif ($state->kind === 'history') {
                    $reason = "$name cannot have actions";
                } else {
                    [$list, $references] = $this->actions(explode(' / ', $line, 2)[1]);
                    $reason = $this->checkReferences($references);
                    if ($reason === null) {
                        if ($kind === 'entry') {
                            $state->entries[] = $list;
                        } else {
                            $state->exits[] = $list;
                        }
                    }
                }
            } elseif ($kind === 'on') {
                if ($state === null) {
                    $reason = "unknown state $name";
                } elseif (in_array($state->kind, ['final', 'history'], true)) {
                    $reason = "$name cannot have transitions";
                } else {
                    preg_match('~\Aon (\S+) (always|after [0-9]+|[^ ]+)(?: \[(.*?)\])?(?: (->|\~>) (\S+))?(?: / (.*))?\z~D', $line, $match, PREG_UNMATCHED_AS_NULL);
                    $trigger = $match[2];
                    $guard = $this->expression($match[3] ?? null);
                    $arrow = $match[4] ?? null;
                    $targetName = $match[5] ?? null;
                    [$list, $references] = $this->actions($match[6] ?? null);
                    $ordered = $guard?->references ?? [];
                    if ($targetName !== null) {
                        $ordered[] = ['state', $targetName];
                    }
                    $reason = $this->checkReferences(array_merge($ordered, $references));
                    if ($reason === null) {
                        $triggerKind = $trigger === 'always' ? 'always' : (str_starts_with($trigger, 'after ') ? 'timer' : 'event');
                        $delay = $triggerKind === 'timer' ? (int)explode(' ', $trigger)[1] : 0;
                        $state->transitions[] = new Transition($state, $triggerKind, $triggerKind === 'event' ? explode('|', $trigger) : [], $delay, $guard, $targetName === null ? null : $this->states[$targetName], $arrow === '~>' ? 'local' : ($arrow === null ? 'internal' : 'external'), $list);
                    }
                }
            }
            if ($reason !== null) {
                $this->errors[$number] = $reason;
            }
        }
        if ($this->errors !== []) {
            ksort($this->errors, SORT_NUMERIC);
            foreach ($this->errors as $number => $reason) {
                echo "error line $number: $reason\n";
            }
            return false;
        }
        foreach ($this->document as $state) {
            if ($state->initial !== null) {
                $state->initial = $this->states[$state->initial];
            }
            if ($state->default !== null) {
                $state->default = $this->states[$state->default];
            }
        }
        return true;
    }

    private function defaultTarget(State $history): State
    {
        return $history->default ?? $history->parent->initialChild();
    }

    private function warnUnreachable(): void
    {
        $initial = $this->root->initialChild();
        $reachable = [$initial->name => $initial];
        do {
            $before = count($reachable);
            foreach (array_values($reachable) as $state) {
                if ($state->parent !== $this->root) {
                    $reachable[$state->parent->name] = $state->parent;
                }
                if ($state->compound()) {
                    $child = $state->initialChild();
                    $reachable[$child->name] = $child;
                }
                if ($state->parallel()) {
                    foreach ($state->childStates() as $child) {
                        $reachable[$child->name] = $child;
                    }
                }
                foreach ($state->transitions as $transition) {
                    $target = $transition->target;
                    if ($target !== null) {
                        $target = $target->kind === 'history' ? $this->defaultTarget($target) : $target;
                        $reachable[$target->name] = $target;
                    }
                }
            }
        } while (count($reachable) !== $before);
        foreach ($this->document as $state) {
            if ($state->kind !== 'history' && !isset($reachable[$state->name])) {
                echo "warning: unreachable state {$state->name}\n";
            }
        }
    }

    private function evaluate(Expression $expression): int
    {
        return $expression->evaluate($this->variables, $this->data, $this->configuration);
    }

    private function reserve(array $record): void
    {
        $record['due'] = $this->time + $record['delay'];
        $record['number'] = ++$this->creation;
        $this->reservations[] = $record;
    }

    private function runActions(array $list): void
    {
        try {
            foreach ($list as $action) {
                $value = isset($action['expression']) ? $this->evaluate($action['expression']) : 0;
                switch ($action['kind']) {
                    case 'assign':
                        $this->variables[$action['name']] = $value;
                        break;
                    case 'raise':
                        $this->queue[] = [$action['event'], $value];
                        break;
                    case 'send':
                        $this->reserve(['kind' => 'send', 'event' => $action['event'], 'value' => $value, 'delay' => $action['delay']]);
                        break;
                    case 'cancel':
                        $this->reservations = array_values(array_filter($this->reservations, fn($r) => $r['kind'] !== 'send' || $r['event'] !== $action['event']));
                        break;
                    case 'log':
                        echo isset($action['expression']) ? ($action['text'] ?? '') . $value : $action['text'], "\n";
                        break;
                }
            }
        } catch (EvaluationError $error) {
            $this->queue[] = ['error.execution', 0];
        }
    }

    private function effectiveTargets(Transition $transition): array
    {
        $target = $transition->target;
        if ($target === null) {
            return [];
        }
        return $target->kind === 'history' ? ($this->history[$target->name] ?? [$this->defaultTarget($target)]) : [$target];
    }

    private function choice(Transition $transition): array
    {
        if ($transition->mode === 'internal') {
            return ['transition' => $transition, 'scope' => null, 'exits' => []];
        }
        $targets = $this->effectiveTargets($transition);
        $source = $transition->source;
        $allDescendants = function (State $ancestor) use ($targets): bool {
            foreach ($targets as $target) {
                if (!$this->descendant($target, $ancestor)) {
                    return false;
                }
            }
            return true;
        };
        if ($transition->mode === 'local' && $source->compound() && $allDescendants($source)) {
            $scope = $source;
        } else {
            $scope = $source->parent;
            while (!$scope->compound() || !$allDescendants($scope)) {
                $scope = $scope->parent;
            }
        }
        return ['transition' => $transition, 'scope' => $scope, 'exits' => array_filter($this->configuration, fn($state) => $this->descendant($state, $scope))];
    }

    private function matches(Transition $transition, array $trigger): bool
    {
        if ($trigger['kind'] === 'always') {
            return $transition->kind === 'always';
        }
        if ($trigger['kind'] === 'timer') {
            return $transition === $trigger['transition'];
        }
        if ($transition->kind !== 'event') {
            return false;
        }
        foreach ($transition->descriptors as $descriptor) {
            if ($descriptor === '*' || $descriptor === $trigger['event'] || str_starts_with($trigger['event'], $descriptor . '.')) {
                return true;
            }
        }
        return false;
    }

    private function selectTransitions(array $trigger): array
    {
        $selected = [];
        foreach ($this->document as $atomic) {
            if (!isset($this->configuration[$atomic->name]) || !$atomic->atomic()) {
                continue;
            }
            $state = $atomic;
            $found = null;
            while ($state !== $this->root && $found === null) {
                foreach ($state->transitions as $transition) {
                    if (!$this->matches($transition, $trigger)) {
                        continue;
                    }
                    try {
                        $accepted = $transition->guard === null || $this->evaluate($transition->guard) !== 0;
                    } catch (EvaluationError $error) {
                        $this->queue[] = ['error.execution', 0];
                        $accepted = false;
                    }
                    if ($accepted) {
                        $found = $transition;
                        break;
                    }
                }
                $state = $state->parent;
            }
            if ($found !== null && !in_array($found, $selected, true)) {
                $selected[] = $found;
            }
        }
        $occupied = $result = [];
        foreach ($selected as $transition) {
            $candidate = $this->choice($transition);
            if (array_intersect_key($candidate['exits'], $occupied) !== []) {
                continue;
            }
            $occupied += $candidate['exits'];
            $result[] = $candidate;
        }
        return $result;
    }

    private function expandEntry(array $set): array
    {
        do {
            $before = count($set);
            foreach (array_values($set) as $state) {
                if ($state->parallel()) {
                    foreach ($state->childStates() as $child) {
                        $set[$child->name] = $child;
                    }
                } elseif ($state->compound()) {
                    $hasChild = false;
                    foreach ($state->childStates() as $child) {
                        $hasChild = $hasChild || isset($set[$child->name]);
                    }
                    if (!$hasChild) {
                        $child = $state->initialChild();
                        $set[$child->name] = $child;
                    }
                }
            }
        } while (count($set) !== $before);
        return $set;
    }

    private function complete(State $state): bool
    {
        if ($state->compound()) {
            foreach ($state->childStates() as $child) {
                if ($child->kind === 'final' && isset($this->configuration[$child->name])) {
                    return true;
                }
            }
            return false;
        }
        if ($state->parallel()) {
            foreach ($state->childStates() as $child) {
                if (!$this->complete($child)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    private function enter(array $set): void
    {
        foreach ($this->document as $state) {
            if (!isset($set[$state->name])) {
                continue;
            }
            $this->configuration[$state->name] = $state;
            $state->entered++;
            $state->entryTime = $this->time;
            foreach ($state->transitions as $transition) {
                if ($transition->kind === 'timer') {
                    $this->reserve(['kind' => 'timer', 'transition' => $transition, 'delay' => $transition->delay]);
                }
            }
            foreach ($state->entries as $actions) {
                $this->runActions($actions);
            }
            if ($state->kind === 'final') {
                $parent = $state->parent;
                $this->queue[] = ["done.state.{$parent->name}", 0];
                $grandparent = $parent->parent;
                if ($grandparent->parallel()) {
                    $complete = true;
                    foreach ($grandparent->childStates() as $child) {
                        $complete = $complete && $this->complete($child);
                    }
                    if ($complete) {
                        $this->queue[] = ["done.state.{$grandparent->name}", 0];
                    }
                }
            }
        }
    }

    private function statesText(array $states): string
    {
        return $states === [] ? '-' : implode(',', array_map(fn($state) => $state->name, $states));
    }

    private function triggerName(array $trigger): string
    {
        if ($trigger['kind'] === 'always') {
            return 'always';
        }
        if ($trigger['kind'] === 'timer') {
            $transition = $trigger['transition'];
            return "after({$transition->delay})@{$transition->source->name}";
        }
        return $trigger['event'] . ($trigger['value'] === 0 ? '' : '=' . $trigger['value']);
    }

    private function microstep(array $selected, array $trigger): void
    {
        $exits = [];
        foreach ($selected as $candidate) {
            $exits += $candidate['exits'];
        }
        foreach ($this->document as $state) {
            if ($state->kind !== 'history' || !isset($exits[$state->parent->name])) {
                continue;
            }
            $this->history[$state->name] = array_values(array_filter($this->document, function ($active) use ($state) {
                return isset($this->configuration[$active->name]) && ($state->historyKind === 'deep' ? $active->atomic() && $this->descendant($active, $state->parent) : $active->parent === $state->parent);
            }));
        }
        $entries = [];
        foreach ($selected as $candidate) {
            $transition = $candidate['transition'];
            if ($transition->mode === 'internal') {
                continue;
            }
            foreach ($this->effectiveTargets($transition) as $state) {
                while ($this->descendant($state, $candidate['scope'])) {
                    $entries[$state->name] = $state;
                    $state = $state->parent;
                }
            }
        }
        $entries = $this->expandEntry($entries);
        if ($this->trace) {
            $sources = array_map(fn($candidate) => $candidate['transition']->source, $selected);
            $exitList = array_values(array_filter(array_reverse($this->document), fn($state) => isset($exits[$state->name])));
            $entryList = array_values(array_filter($this->document, fn($state) => isset($entries[$state->name])));
            echo "[t={$this->time}] ", $this->triggerName($trigger), ' (', $this->statesText($sources), '): exit ', $this->statesText($exitList), '; enter ', $this->statesText($entryList), "\n";
        }
        foreach (array_reverse($this->document) as $state) {
            if (!isset($exits[$state->name])) {
                continue;
            }
            foreach ($state->exits as $actions) {
                $this->runActions($actions);
            }
            unset($this->configuration[$state->name]);
            $state->dwell += $this->time - $state->entryTime;
            $this->reservations = array_values(array_filter($this->reservations, fn($r) => $r['kind'] !== 'timer' || $r['transition']->source !== $state));
        }
        foreach ($selected as $candidate) {
            $transition = $candidate['transition'];
            $this->runActions($transition->actions);
            $transition->source->taken++;
        }
        $this->enter($entries);
    }

    private function perform(int &$count, array $selected, array $trigger): void
    {
        if ($count === 1000) {
            echo "LIVELOCK t={$this->time}\n";
            $this->halted = true;
        } else {
            $count++;
            $this->microsteps++;
            $this->microstep($selected, $trigger);
        }
    }

    private function macrostep(array $trigger): void
    {
        $this->macrosteps++;
        $count = 0;
        $this->data = $trigger['kind'] === 'event' ? $trigger['value'] : 0;
        if ($trigger['kind'] === 'start') {
            $initial = $this->root->initialChild();
            $this->enter($this->expandEntry([$initial->name => $initial]));
        } else {
            $selected = $this->selectTransitions($trigger);
            if ($selected !== []) {
                $this->perform($count, $selected, $trigger);
            }
        }
        while (!$this->halted) {
            $this->data = 0;
            $current = ['kind' => 'always'];
            $selected = $this->selectTransitions($current);
            if ($selected !== []) {
                $this->perform($count, $selected, $current);
                continue;
            }
            if ($this->queue === []) {
                break;
            }
            [$event, $value] = array_shift($this->queue);
            $this->data = $value;
            $current = ['kind' => 'event', 'event' => $event, 'value' => $value];
            $selected = $this->selectTransitions($current);
            if ($selected !== []) {
                $this->perform($count, $selected, $current);
            }
        }
    }

    private function orderedReservations(): array
    {
        $result = $this->reservations;
        usort($result, fn($a, $b) => [$a['due'], $a['number']] <=> [$b['due'], $b['number']]);
        return $result;
    }

    private function dump(): void
    {
        echo "dump t={$this->time}\n";
        foreach ($this->document as $state) {
            if (isset($this->configuration[$state->name])) {
                echo str_repeat('  ', $state->depth), $state->name, "\n";
            }
        }
        $variables = $this->variables;
        ksort($variables, SORT_STRING);
        foreach ($variables as $name => $value) {
            echo "  var $name = $value\n";
        }
        foreach ($this->document as $state) {
            if (array_key_exists($state->name, $this->history)) {
                echo "  history {$state->name} = ", $this->statesText($this->history[$state->name]), "\n";
            }
        }
        foreach ($this->orderedReservations() as $reservation) {
            if ($reservation['kind'] === 'timer') {
                echo "  timer {$reservation['due']} ", $this->triggerName($reservation), "\n";
            } else {
                echo "  send {$reservation['due']} {$reservation['event']} {$reservation['value']}\n";
            }
        }
    }

    public function run(array $script): void
    {
        if (!$this->validate()) {
            return;
        }
        $this->warnUnreachable();
        $this->macrostep(['kind' => 'start']);
        foreach ($script as $line) {
            if ($this->halted) {
                break;
            }
            $parts = explode(' ', $line, 2);
            $command = $parts[0];
            $rest = $parts[1] ?? '';
            if ($command === 'event') {
                $args = explode(' ', $rest);
                $this->macrostep(['kind' => 'event', 'event' => $args[0], 'value' => (int)($args[1] ?? '0')]);
            } elseif ($command === 'tick') {
                $finish = $this->time + (int)$rest;
                while (!$this->halted) {
                    $reservations = $this->orderedReservations();
                    $next = $reservations[0] ?? null;
                    if ($next === null || $next['due'] > $finish) {
                        break;
                    }
                    $this->reservations = array_values(array_filter($this->reservations, fn($r) => $r['number'] !== $next['number']));
                    $this->time = $next['due'];
                    $trigger = $next['kind'] === 'timer' ? $next : ['kind' => 'event', 'event' => $next['event'], 'value' => $next['value']];
                    $this->macrostep($trigger);
                }
                if (!$this->halted) {
                    $this->time = $finish;
                }
            } elseif ($command === 'set') {
                [$name, $value] = explode(' ', $rest);
                if (array_key_exists($name, $this->variables)) {
                    $this->variables[$name] = (int)$value;
                } else {
                    echo "error: unknown variable $name\n";
                }
            } elseif ($command === 'trace') {
                $this->trace = $rest === 'on';
            } elseif ($command === 'eval') {
                $value = new Expression($rest);
                $reason = $this->checkReferences($value->references);
                if ($reason !== null) {
                    echo "error: $reason\n";
                } else {
                    $this->data = 0;
                    try {
                        $result = $this->evaluate($value);
                        echo "$rest -> $result\n";
                    } catch (EvaluationError $error) {
                        echo "error: division by zero\n";
                    }
                }
            } elseif ($command === 'dump') {
                $this->dump();
            }
        }
        echo "end t={$this->time} macrosteps={$this->macrosteps} microsteps={$this->microsteps}\n";
        foreach ($this->document as $state) {
            if ($state->kind === 'history') {
                continue;
            }
            $time = $state->dwell + (isset($this->configuration[$state->name]) ? $this->time - $state->entryTime : 0);
            echo "  {$state->name} entered={$state->entered} taken={$state->taken} time=$time\n";
        }
    }
}

$input = array_map(fn($line) => rtrim($line, "\r\n"), file('php://stdin'));
$charts = (int)$input[0];
$i = 1;
for ($chart = 0; $chart < $charts; $chart++) {
    $name = explode(' ', $input[$i++])[1];
    $definitions = [];
    while ($input[$i] !== 'RUN') {
        $definitions[] = [$input[$i], $i + 1];
        $i++;
    }
    $i++;
    $script = [];
    while ($input[$i] !== 'END') {
        $script[] = $input[$i++];
    }
    $i++;
    echo "chart $name\n";
    (new Chart($definitions))->run($script);
}
