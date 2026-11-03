<?php
declare(strict_types=1);

const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
const WORKFLOWS = [
    'BUG' => ['OPEN', 'TRIAGED', 'IN_PROGRESS', 'REVIEW', 'RESOLVED', 'CLOSED', 'REOPENED'],
    'TASK' => ['OPEN', 'IN_PROGRESS', 'DONE'],
    'STORY' => ['BACKLOG', 'READY', 'IN_PROGRESS', 'REVIEW', 'DONE'],
];
const TRANSITIONS = [
    'BUG' => ['OPEN:TRIAGED', 'TRIAGED:IN_PROGRESS', 'IN_PROGRESS:REVIEW', 'REVIEW:IN_PROGRESS',
        'REVIEW:RESOLVED', 'RESOLVED:CLOSED', 'RESOLVED:REOPENED', 'CLOSED:REOPENED', 'REOPENED:IN_PROGRESS'],
    'TASK' => ['OPEN:IN_PROGRESS', 'IN_PROGRESS:OPEN', 'IN_PROGRESS:DONE'],
    'STORY' => ['BACKLOG:READY', 'READY:BACKLOG', 'READY:IN_PROGRESS', 'IN_PROGRESS:REVIEW', 'REVIEW:IN_PROGRESS', 'REVIEW:DONE'],
];
const DONE_STATES = ['RESOLVED', 'CLOSED', 'DONE'];
const ESTIMATES = [0, 1, 2, 3, 5, 8, 13, 21];
const EQUALITY = ['=', '!='];
const ORDERED = ['=', '!=', '<', '<=', '>', '>='];
const FIELD_OPERATORS = [
    'id' => ORDERED, 'type' => EQUALITY, 'status' => EQUALITY, 'priority' => ORDERED,
    'assignee' => EQUALITY, 'reviewer' => EQUALITY, 'estimate' => ORDERED, 'sprint' => EQUALITY,
    'comments' => ORDERED, 'blocked' => EQUALITY, 'done' => EQUALITY, 'title' => ['~'],
];

class CommandError extends RuntimeException {}

function display(mixed $value): string
{
    return $value === null ? '-' : (string)$value;
}

function yesNo(bool $value): string
{
    return $value ? 'yes' : 'no';
}

function numberList(array $set): string
{
    $numbers = array_keys($set);
    sort($numbers, SORT_NUMERIC);
    return $numbers === [] ? '-' : implode(',', $numbers);
}

class Issue
{
    public string $state;
    public ?string $assignee = null;
    public ?string $reviewer = null;
    public ?int $estimate = null;
    public ?string $sprint = null;
    public int $comments = 0;
    public array $blocks = [];
    public array $blockers = [];
    public ?int $duplicate = null;
    public array $duplicates = [];
    public array $history = [];

    public function __construct(public int $number, public string $kind, public string $priority, public string $title)
    {
        $this->state = WORKFLOWS[$kind][0];
    }

    public function done(): bool
    {
        return in_array($this->state, DONE_STATES, true);
    }

    public function points(): int
    {
        return $this->estimate ?? 0;
    }

    public function level(): int
    {
        return array_search($this->priority, PRIORITIES, true);
    }
}

class Sprint
{
    public string $phase = 'PLANNED';
    public ?int $start = null;
    public ?int $end = null;
    public int $velocity = 0;
    public array $records = [];

    public function __construct(public string $name) {}
}

class Tracker
{
    private int $day = 1;
    private array $users = [];
    private array $issues = [];
    private array $sprints = [];
    private array $output = [];

    public function execute(string $line): array
    {
        $this->output = [];
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            $this->process($command, $args);
        } catch (CommandError $error) {
            $this->emit('ERROR', $error->getMessage());
        }
        $active = $this->activeSprint();
        if ($active !== null) {
            $active->records[$this->day] = $this->remaining($active);
        }
        return $this->output;
    }

    private function emit(mixed ...$parts): void
    {
        $this->output[] = implode(' ', $parts);
    }

    private function issue(string $text): Issue
    {
        return $this->issues[(int)$text] ?? throw new CommandError('unknown issue');
    }

    private function user(string $spec): ?string
    {
        if ($spec === '-') {
            return null;
        }
        if (!isset($this->users[$spec])) {
            throw new CommandError('unknown user');
        }
        return $spec;
    }

    private function sprint(string $name): Sprint
    {
        return $this->sprints[$name] ?? throw new CommandError('unknown sprint');
    }

    private function notDone(Issue $issue): void
    {
        if ($issue->done()) {
            throw new CommandError('issue done');
        }
    }

    private function orderedIssues(): array
    {
        $issues = $this->issues;
        ksort($issues, SORT_NUMERIC);
        return array_values($issues);
    }

    private function unfinished(Issue $issue): array
    {
        $numbers = array_values(array_filter(array_keys($issue->blockers), fn($number) => !$this->issues[$number]->done()));
        sort($numbers, SORT_NUMERIC);
        return $numbers;
    }

    private function blocked(Issue $issue): bool
    {
        return !$issue->done() && $this->unfinished($issue) !== [];
    }

    private function wip(?string $user): int
    {
        return count(array_filter($this->issues, fn($issue) => $issue->assignee === $user && $issue->state === 'IN_PROGRESS'));
    }

    private function activeSprint(): ?Sprint
    {
        foreach ($this->sprints as $sprint) {
            if ($sprint->phase === 'ACTIVE') {
                return $sprint;
            }
        }
        return null;
    }

    private function members(Sprint $sprint): array
    {
        return array_values(array_filter($this->orderedIssues(), fn($issue) => $issue->sprint === $sprint->name));
    }

    private function remaining(Sprint $sprint): int
    {
        return array_sum(array_map(fn($issue) => $issue->done() ? 0 : $issue->points(), $this->members($sprint)));
    }

    private function summary(Sprint $sprint): string
    {
        $members = $this->members($sprint);
        $total = array_sum(array_map(fn($issue) => $issue->points(), $members));
        return 'issues ' . count($members) . " points $total";
    }

    private function record(Issue $issue, string $text): void
    {
        $issue->history[] = "day {$this->day} $text";
    }

    private function blockedStates(array $numbers): array
    {
        $before = [];
        foreach ($numbers as $number) {
            $before[$number] = $this->blocked($this->issues[$number]);
        }
        return $before;
    }

    private function notify(array $before): void
    {
        ksort($before, SORT_NUMERIC);
        foreach ($before as $number => $old) {
            $after = $this->blocked($this->issues[$number]);
            if ($old !== $after) {
                $this->emit($after ? 'BLOCKED' : 'UNBLOCKED', $number);
            }
        }
    }

    private function changeState(Issue $issue, string $target): void
    {
        $before = $this->blockedStates(array_keys($issue->blocks));
        $this->emit('MOVE', $issue->number, $issue->state, $target);
        $this->record($issue, "MOVE {$issue->state} $target");
        $issue->state = $target;
        $this->notify($before);
    }

    private function reaches(Issue $start, Issue $goal): bool
    {
        $pending = [$start->number];
        $visited = [];
        while ($pending !== []) {
            $number = array_pop($pending);
            if ($number === $goal->number) {
                return true;
            }
            if (isset($visited[$number])) {
                continue;
            }
            $visited[$number] = true;
            array_push($pending, ...array_keys($this->issues[$number]->blocks));
        }
        return false;
    }

    private function process(string $command, array $args): void
    {
        switch ($command) {
            case 'DAY':
                $day = (int)$args[0];
                if ($day < $this->day) {
                    throw new CommandError('day backwards');
                }
                $this->day = $day;
                $this->emit('DAY', $day);
                break;
            case 'USER':
                if (isset($this->users[$args[0]])) {
                    throw new CommandError('user exists');
                }
                $this->users[$args[0]] = true;
                $this->emit('USER', $args[0]);
                break;
            case 'CREATE':
                [$text, $kind, $priority] = $args;
                $number = (int)$text;
                if (isset($this->issues[$number])) {
                    throw new CommandError('issue exists');
                }
                if (!array_key_exists($kind, WORKFLOWS)) {
                    throw new CommandError('bad type');
                }
                if (!in_array($priority, PRIORITIES, true)) {
                    throw new CommandError('bad priority');
                }
                $issue = new Issue($number, $kind, $priority, implode(' ', array_slice($args, 3)));
                $this->issues[$number] = $issue;
                $this->record($issue, "CREATE $kind $priority");
                $this->emit('CREATE', $number, $kind, $priority, $issue->state);
                break;
            case 'PRIORITY':
                $issue = $this->issue($args[0]);
                $priority = $args[1];
                if (!in_array($priority, PRIORITIES, true)) {
                    throw new CommandError('bad priority');
                }
                $this->notDone($issue);
                if ($issue->priority === $priority) {
                    throw new CommandError('no change');
                }
                $old = $issue->priority;
                $issue->priority = $priority;
                $this->record($issue, "PRIORITY $old $priority");
                $this->emit('PRIORITY', $issue->number, $old, $priority);
                break;
            case 'ASSIGN': case 'REVIEWER':
                $this->setPerson($command, $args);
                break;
            case 'ESTIMATE':
                $issue = $this->issue($args[0]);
                $points = (int)$args[1];
                if (!in_array($points, ESTIMATES, true)) {
                    throw new CommandError('bad estimate');
                }
                $this->notDone($issue);
                if ($issue->estimate === $points) {
                    throw new CommandError('no change');
                }
                $old = display($issue->estimate);
                $issue->estimate = $points;
                $this->record($issue, "ESTIMATE $old $points");
                $this->emit('ESTIMATE', $issue->number, $old, $points);
                break;
            case 'COMMENT':
                $issue = $this->issue($args[0]);
                $user = $this->user($args[1]);
                ++$issue->comments;
                $this->record($issue, "COMMENT $user " . implode(' ', array_slice($args, 2)));
                $this->emit('COMMENT', $issue->number, $issue->comments);
                break;
            case 'MOVE': $this->move($args); break;
            case 'LINK': case 'UNLINK': $this->link($command, $args); break;
            case 'SPRINT': $this->sprintCommand($args); break;
            case 'QUERY': $this->query(implode(' ', $args)); break;
            case 'SHOW': $this->show($this->issue($args[0])); break;
            case 'HISTORY':
                $issue = $this->issue($args[0]);
                $this->emit('HISTORY', $issue->number, count($issue->history));
                array_push($this->output, ...$issue->history);
                break;
            case 'BOARD': $this->board(); break;
            case 'WORKLOAD': $this->workload(); break;
            case 'SPRINTS': $this->listSprints(); break;
            case 'BURNDOWN': $this->burndown($this->sprint($args[0])); break;
        }
    }

    private function setPerson(string $command, array $args): void
    {
        $issue = $this->issue($args[0]);
        $chosen = $this->user($args[1]);
        $this->notDone($issue);
        if ($command === 'ASSIGN') {
            if ($issue->assignee === $chosen) {
                throw new CommandError('no change');
            }
            if ($chosen === null && in_array($issue->state, ['IN_PROGRESS', 'REVIEW'], true)) {
                throw new CommandError('assignee required');
            }
            if ($issue->state === 'IN_PROGRESS' && $this->wip($chosen) >= 3) {
                throw new CommandError("wip limit {$args[1]}");
            }
            if ($issue->state === 'REVIEW' && $chosen === $issue->reviewer) {
                throw new CommandError('reviewer is assignee');
            }
            $issue->assignee = $chosen;
        } else {
            if ($issue->reviewer === $chosen) {
                throw new CommandError('no change');
            }
            if ($chosen === null && $issue->state === 'REVIEW') {
                throw new CommandError('reviewer required');
            }
            if ($issue->state === 'REVIEW' && $chosen === $issue->assignee) {
                throw new CommandError('reviewer is assignee');
            }
            $issue->reviewer = $chosen;
        }
        $this->record($issue, "$command {$args[1]}");
        $this->emit($command, $issue->number, $args[1]);
    }

    private function move(array $args): void
    {
        $issue = $this->issue($args[0]);
        $target = $args[1];
        if ($issue->duplicate !== null) {
            throw new CommandError("duplicate of {$issue->duplicate}");
        }
        if (!in_array($target, WORKFLOWS[$issue->kind], true)) {
            throw new CommandError('bad state');
        }
        if (!in_array("{$issue->state}:$target", TRANSITIONS[$issue->kind], true)) {
            throw new CommandError("cannot move {$issue->state} to $target");
        }
        if ($target === 'IN_PROGRESS') {
            $active = $this->activeSprint();
            if ($issue->kind === 'STORY' && ($active === null || $issue->sprint !== $active->name)) {
                throw new CommandError('not in active sprint');
            }
            if ($issue->assignee === null) {
                throw new CommandError('no assignee');
            }
            if ($this->wip($issue->assignee) >= 3) {
                throw new CommandError("wip limit {$issue->assignee}");
            }
        } elseif ($target === 'REVIEW') {
            if ($issue->reviewer === null) {
                throw new CommandError('no reviewer');
            }
            if ($issue->reviewer === $issue->assignee) {
                throw new CommandError('reviewer is assignee');
            }
        }
        $blockers = $this->unfinished($issue);
        if (in_array($target, ['DONE', 'RESOLVED'], true) && $blockers !== []) {
            throw new CommandError("blocked by {$blockers[0]}");
        }
        if ($target === 'READY' && $issue->estimate === null) {
            throw new CommandError('no estimate');
        }
        $this->changeState($issue, $target);
    }

    private function link(string $command, array $args): void
    {
        $relation = $args[1];
        $allowed = $command === 'LINK' ? ['BLOCKS', 'DUPLICATES'] : ['BLOCKS'];
        if (!in_array($relation, $allowed, true)) {
            throw new CommandError('bad link');
        }
        $source = $this->issue($args[0]);
        $target = $this->issue($args[2]);
        if ($command === 'UNLINK') {
            if (!isset($source->blocks[$target->number])) {
                throw new CommandError('no link');
            }
            $before = $this->blockedStates([$target->number]);
            unset($source->blocks[$target->number], $target->blockers[$source->number]);
            $this->record($source, "UNLINK BLOCKS {$target->number}");
            $this->record($target, "UNLINK BLOCKED_BY {$source->number}");
            $this->emit('UNLINK', $source->number, 'BLOCKS', $target->number);
            $this->notify($before);
            return;
        }
        if ($source === $target) {
            throw new CommandError('self link');
        }
        if ($relation === 'BLOCKS') {
            if (isset($source->blocks[$target->number])) {
                throw new CommandError('link exists');
            }
            if ($this->reaches($target, $source)) {
                throw new CommandError('cycle');
            }
            $this->notDone($target);
            $before = $this->blockedStates([$target->number]);
            $source->blocks[$target->number] = true;
            $target->blockers[$source->number] = true;
            $this->record($source, "LINK BLOCKS {$target->number}");
            $this->record($target, "LINK BLOCKED_BY {$source->number}");
            $this->emit('LINK', $source->number, $relation, $target->number);
            $this->notify($before);
        } else {
            if ($source->kind !== $target->kind) {
                throw new CommandError('type mismatch');
            }
            $this->notDone($source);
            if ($target->duplicate !== null) {
                throw new CommandError('target is duplicate');
            }
            $source->duplicate = $target->number;
            $target->duplicates[$source->number] = true;
            $this->record($source, "LINK DUPLICATES {$target->number}");
            $this->record($target, "LINK DUPLICATED_BY {$source->number}");
            $this->emit('LINK', $source->number, $relation, $target->number);
            $this->changeState($source, $source->kind === 'BUG' ? 'CLOSED' : 'DONE');
            if ($source->sprint !== null && $this->sprints[$source->sprint]->phase !== 'ENDED') {
                $this->record($source, "SPRINT REMOVE {$source->sprint}");
                $source->sprint = null;
            }
        }
    }

    private function sprintCommand(array $args): void
    {
        [$action, $name] = $args;
        if ($action === 'NEW') {
            if (isset($this->sprints[$name])) {
                throw new CommandError('sprint exists');
            }
            $this->sprints[$name] = new Sprint($name);
            $this->emit('SPRINT', 'NEW', $name);
            return;
        }
        $sprint = $this->sprint($name);
        if ($action === 'ADD' || $action === 'REMOVE') {
            $issue = $this->issue($args[2]);
            if ($sprint->phase === 'ENDED') {
                throw new CommandError('sprint ended');
            }
            if ($action === 'ADD') {
                $this->notDone($issue);
                if ($issue->sprint !== null && $this->sprints[$issue->sprint]->phase !== 'ENDED') {
                    throw new CommandError("in sprint {$issue->sprint}");
                }
                if ($issue->state === 'BACKLOG') {
                    throw new CommandError('not ready');
                }
                $issue->sprint = $name;
            } else {
                if ($issue->sprint !== $name) {
                    throw new CommandError('not in sprint');
                }
                $this->notDone($issue);
                $issue->sprint = null;
            }
            $this->record($issue, "SPRINT $action $name");
            $this->emit('SPRINT', $action, $name, $issue->number, $this->summary($sprint));
        } elseif ($action === 'START') {
            if ($sprint->phase !== 'PLANNED') {
                throw new CommandError('sprint not planned');
            }
            $active = $this->activeSprint();
            if ($active !== null) {
                throw new CommandError("sprint active {$active->name}");
            }
            if ($this->members($sprint) === []) {
                throw new CommandError('sprint empty');
            }
            $sprint->phase = 'ACTIVE';
            $sprint->start = $this->day;
            $sprint->records[$this->day] = $this->remaining($sprint);
            $this->emit('SPRINT', 'START', $name, 'day', $this->day, $this->summary($sprint), 'remaining', $this->remaining($sprint));
        } else {
            if ($sprint->phase !== 'ACTIVE') {
                throw new CommandError('sprint not active');
            }
            $sprint->records[$this->day] = $this->remaining($sprint);
            $members = $this->members($sprint);
            $finished = array_values(array_filter($members, fn($issue) => $issue->done()));
            $returned = array_values(array_filter($members, fn($issue) => !$issue->done()));
            $sprint->velocity = array_sum(array_map(fn($issue) => $issue->points(), $finished));
            $sprint->phase = 'ENDED';
            $sprint->end = $this->day;
            $this->emit('SPRINT', 'END', $name, 'day', $this->day, 'velocity', $sprint->velocity,
                'done', count($finished), 'returned', count($returned));
            foreach ($returned as $issue) {
                $issue->sprint = null;
                $this->record($issue, "SPRINT RETURN $name");
                $this->emit('RETURNED', $issue->number);
            }
        }
    }

    private function condition(string $token): array
    {
        if (!preg_match('/\A([a-z]*)(>=|<=|!=|=|<|>|~)(.*)\z/', $token, $parts) || $parts[1] === '' || $parts[3] === '') {
            throw new CommandError("syntax near $token");
        }
        [, $field, $operator, $text] = $parts;
        if (!array_key_exists($field, FIELD_OPERATORS)) {
            throw new CommandError("unknown field $field");
        }
        if (!in_array($operator, FIELD_OPERATORS[$field], true)) {
            throw new CommandError("bad operator $token");
        }
        if ($text === '-' && in_array($field, ['assignee', 'reviewer', 'estimate', 'sprint'], true) && in_array($operator, EQUALITY, true)) {
            $value = null;
        } elseif (in_array($field, ['id', 'estimate', 'comments'], true) && preg_match('/\A[0-9]{1,6}\z/', $text)) {
            $value = (int)$text;
        } elseif ($field === 'priority' && in_array($text, PRIORITIES, true)) {
            $value = array_search($text, PRIORITIES, true);
        } elseif ($field === 'type' && array_key_exists($text, WORKFLOWS)) {
            $value = $text;
        } elseif ($field === 'status' && array_any(WORKFLOWS, fn($states) => in_array($text, $states, true))) {
            $value = $text;
        } elseif (in_array($field, ['assignee', 'reviewer'], true) && isset($this->users[$text])) {
            $value = $text;
        } elseif ($field === 'sprint' && isset($this->sprints[$text])) {
            $value = $text;
        } elseif (in_array($field, ['blocked', 'done'], true) && in_array($text, ['yes', 'no'], true)) {
            $value = $text;
        } elseif ($field === 'title') {
            $value = strtolower($text);
        } else {
            throw new CommandError("bad value $token");
        }
        return [$field, $operator, $value];
    }

    private function compileQuery(string $text): array
    {
        preg_match_all('/[()]|[^ ()]+/', $text, $matches);
        $tokens = $matches[0];
        $conditions = [];
        $operand = true;
        $depth = 0;
        foreach ($tokens as $index => $token) {
            if ($operand) {
                if ($token === '(') {
                    ++$depth;
                } elseif (in_array($token, ['AND', 'OR', ')'], true)) {
                    throw new CommandError("syntax near $token");
                } elseif ($token !== 'NOT') {
                    $conditions[$index] = $this->condition($token);
                    $operand = false;
                }
            } elseif ($token === 'AND' || $token === 'OR') {
                $operand = true;
            } elseif ($token === ')' && $depth > 0) {
                --$depth;
            } else {
                throw new CommandError("syntax near $token");
            }
        }
        if ($operand || $depth !== 0) {
            throw new CommandError('syntax at end');
        }
        $output = [];
        $operators = [];
        $precedence = ['OR' => 1, 'AND' => 2, 'NOT' => 3];
        foreach ($tokens as $index => $token) {
            if (isset($conditions[$index])) {
                $output[] = $conditions[$index];
            } elseif ($token === '(' || $token === 'NOT') {
                $operators[] = $token;
            } elseif ($token === ')') {
                while (end($operators) !== '(') {
                    $output[] = array_pop($operators);
                }
                array_pop($operators);
            } else {
                while ($operators !== [] && end($operators) !== '(' && $precedence[end($operators)] >= $precedence[$token]) {
                    $output[] = array_pop($operators);
                }
                $operators[] = $token;
            }
        }
        return array_merge($output, array_reverse($operators));
    }

    private function fieldValue(Issue $issue, string $field): mixed
    {
        return match ($field) {
            'id' => $issue->number, 'type' => $issue->kind, 'status' => $issue->state,
            'priority' => $issue->level(), 'blocked' => yesNo($this->blocked($issue)),
            'done' => yesNo($issue->done()), 'title' => strtolower($issue->title),
            default => $issue->$field,
        };
    }

    private function matches(Issue $issue, array $program): bool
    {
        $stack = [];
        foreach ($program as $node) {
            if ($node === 'NOT') {
                $stack[] = !array_pop($stack);
            } elseif ($node === 'AND' || $node === 'OR') {
                $right = array_pop($stack);
                $left = array_pop($stack);
                $stack[] = $node === 'AND' ? $left && $right : $left || $right;
            } else {
                [$field, $operator, $expected] = $node;
                $actual = $this->fieldValue($issue, $field);
                $stack[] = match ($operator) {
                    '=' => $actual === $expected, '!=' => $actual !== $expected,
                    '~' => str_contains($actual, $expected),
                    '<' => $actual !== null && $actual < $expected,
                    '<=' => $actual !== null && $actual <= $expected,
                    '>' => $actual !== null && $actual > $expected,
                    '>=' => $actual !== null && $actual >= $expected,
                };
            }
        }
        return $stack[0];
    }

    private function query(string $text): void
    {
        $program = $this->compileQuery($text);
        $matches = array_values(array_filter($this->issues, fn($issue) => $this->matches($issue, $program)));
        usort($matches, fn($a, $b) => ($b->level() <=> $a->level()) ?: ($a->number <=> $b->number));
        $this->emit('QUERY', count($matches));
        foreach ($matches as $issue) {
            $this->emit($issue->number, $issue->kind, $issue->priority, $issue->state,
                display($issue->assignee), display($issue->estimate), $issue->title);
        }
    }

    private function show(Issue $issue): void
    {
        $this->emit('ISSUE', $issue->number, $issue->kind, $issue->priority, $issue->state, 'blocked', yesNo($this->blocked($issue)));
        $this->emit('TITLE', $issue->title);
        $this->emit('PEOPLE', 'assignee', display($issue->assignee), 'reviewer', display($issue->reviewer));
        $this->emit('PLAN', 'estimate', display($issue->estimate), 'sprint', display($issue->sprint), 'comments', $issue->comments);
        $this->emit('LINKS', 'blocks', numberList($issue->blocks), 'blocked_by', numberList($issue->blockers),
            'duplicate_of', display($issue->duplicate), 'duplicated_by', numberList($issue->duplicates));
    }

    private function board(): void
    {
        $this->emit('BOARD');
        foreach (WORKFLOWS as $kind => $states) {
            $parts = [$kind];
            foreach ($states as $state) {
                $parts[] = $state;
                $parts[] = count(array_filter($this->issues, fn($issue) => $issue->kind === $kind && $issue->state === $state));
            }
            $this->emit(...$parts);
        }
        $finished = count(array_filter($this->issues, fn($issue) => $issue->done()));
        $this->emit('TOTAL', count($this->issues), 'open', count($this->issues) - $finished, 'done', $finished);
    }

    private function workload(): void
    {
        $users = array_keys($this->users);
        sort($users, SORT_STRING);
        $this->emit('WORKLOAD', count($users));
        foreach ($users as $user) {
            $assigned = array_filter($this->issues, fn($issue) => $issue->assignee === $user && !$issue->done());
            $progress = count(array_filter($assigned, fn($issue) => $issue->state === 'IN_PROGRESS'));
            $review = count(array_filter($assigned, fn($issue) => $issue->state === 'REVIEW'));
            $reviewing = count(array_filter($this->issues, fn($issue) => $issue->reviewer === $user && $issue->state === 'REVIEW'));
            $points = array_sum(array_map(fn($issue) => $issue->points(), $assigned));
            $this->emit($user, 'assigned', count($assigned), 'in_progress', $progress,
                'review', $review, 'reviewing', $reviewing, 'points', $points);
        }
    }

    private function listSprints(): void
    {
        $this->emit('SPRINTS', count($this->sprints));
        foreach ($this->sprints as $sprint) {
            if ($sprint->phase === 'PLANNED') {
                $this->emit($sprint->name, $sprint->phase, $this->summary($sprint));
            } elseif ($sprint->phase === 'ACTIVE') {
                $this->emit($sprint->name, $sprint->phase, 'start', $sprint->start,
                    $this->summary($sprint), 'remaining', $this->remaining($sprint));
            } else {
                $this->emit($sprint->name, $sprint->phase, 'start', $sprint->start,
                    'end', $sprint->end, 'velocity', $sprint->velocity);
            }
        }
    }

    private function burndown(Sprint $sprint): void
    {
        if ($sprint->phase === 'PLANNED') {
            throw new CommandError('sprint not started');
        }
        $last = $sprint->phase === 'ACTIVE' ? $this->day : $sprint->end;
        $this->emit('BURNDOWN', $sprint->name, $sprint->phase, 'days', $last - $sprint->start + 1);
        $value = 0;
        for ($day = $sprint->start; $day <= $last; ++$day) {
            $value = $sprint->records[$day] ?? $value;
            $this->emit('day', $day, $value);
        }
    }
}

$tracker = new Tracker();
$count = (int)fgets(STDIN);
for ($index = 0; $index < $count; ++$index) {
    echo implode("\n", $tracker->execute(rtrim(fgets(STDIN), "\r\n"))), "\n";
}
