<?php

foreach (['terms', 'reader', 'unify', 'database', 'predicates'] as $module)
    require_once __DIR__ . "/$module.php";
const CONTROLS = [[',', 2], ['!', 0], [';', 2], ['->', 2], ['\\+', 1], ['catch', 3]];

const EXTRA_BUILTINS = [['findall', 3], ['throw', 1], ['between', 3], ['length', 2]];

function isControl(array $key): bool
{
    return in_array($key, CONTROLS, true) || $key[0] === 'call' && $key[1] >= 1 && $key[1] <= 8;
}

function isBuiltin(array $key): bool
{
    return in_array($key, DETERMINISTIC, true) || in_array($key, EXTRA_BUILTINS, true);
}

function goalConversion(mixed $term): mixed
{
    $term = dereference($term);
    if ($term instanceof PrologVariable)
        return new Compound('call', $term);
    if (is_int($term))
        return null;
    if (
        $term instanceof Compound
        && in_array($term->name, [',', ';', '->'], true)
        && count($term->args) === 2
    ) {
        $left = goalConversion($term->args[0]);
        if ($left === null)
            return null;
        $right = goalConversion($term->args[1]);
        return $right === null ? null : new Compound($term->name, $left, $right);
    }
    return $term;
}

function atomName(string $name, bool $quoted): string
{
    $plain =
        in_array($name, ['[]', '!', ';'], true)
        || preg_match('/^[a-z][A-Za-z0-9_]*$/D', $name) === 1
        || $name !== '' && $name !== '.' && strspn($name, SYMBOLS) === strlen($name);
    return !$quoted || $plain
        ? $name
        : "'" . strtr($name, ['\\' => '\\\\', "'" => "\\'", "\n" => '\\n', "\t" => '\\t']) . "'";
}

final class Writer
{
    private int $nextName = 1;

    public function __construct(
        private array $names = [],
        private bool $quoted = true,
    ) {}

    public function write(mixed $term, int $limit = 1200, bool $operand = false): string
    {
        $term = dereference($term);
        if ($term instanceof PrologVariable)
            return $this->names[spl_object_id($term)] ??= '_G' . $this->nextName++;
        if (is_int($term))
            return (string) $term;
        if (is_string($term)) {
            $text = atomName($term, $this->quoted);
            return $operand && (isset(INFIX[$term]) || isset(PREFIX[$term])) ? '(' . $text . ')' : $text;
        }
        $name = $term->name;
        $args = $term->args;
        if ($name === '.' && count($args) === 2) {
            [$elements, $tail] = listParts($term);
            $parts = [];
            foreach ($elements as $e)
                $parts[] = $this->write($e, 999);
            return '[' . implode(',', $parts) . ($tail === '[]' ? '' : '|' . $this->write($tail, 999)) . ']';
        }
        if (count($args) === 2 && isset(INFIX[$name])) {
            [$p, $leftLimit, $rightLimit] = INFIX[$name];
            $left = $this->write($args[0], $leftLimit, true);
            $right = $this->write($args[1], $rightLimit, true);
            if ($name === ',')
                $text = $left . ',' . $right;
            elseif (ctype_alpha($name[0]))
                $text = $left . ' ' . $name . ' ' . $right;
            else
                $text =
                    $left
                    . ($left !== '' && str_contains(SYMBOLS, substr($left, -1)) ? ' ' : '')
                    . $name
                    . ($right !== '' && str_contains(SYMBOLS, $right[0]) ? ' ' : '')
                    . $right;
            return $p > $limit ? '(' . $text . ')' : $text;
        }
        if (count($args) === 1 && isset(PREFIX[$name])) {
            $p = PREFIX[$name];
            $arg = $this->write($args[0], $p, true);
            $space =
                $arg !== '' && (str_contains(SYMBOLS, $arg[0]) || ctype_digit($arg[0]) || $arg[0] === '(')
                    ? ' '
                    : '';
            $text = $name . $space . $arg;
            return $p > $limit ? '(' . $text . ')' : $text;
        }
        $parts = [];
        foreach ($args as $arg)
            $parts[] = $this->write($arg, 999);
        return atomName($name, $this->quoted) . '(' . implode(',', $parts) . ')';
    }
}

function predicateName(array $key): string
{
    return new Writer()->write(indicatorTerm($key));
}

final class Consultant
{
    public Database $database;
    public array $lines = [];
    private array
        $counts = ['prelude.pl' => [0, 0, 0], 'program.pl' => [0, 0, 0]],
        $last = ['prelude.pl' => null, 'program.pl' => null],
        $discontiguous = []
    ;

    public function __construct()
    {
        $this->database = new Database();
    }

    private function warning(string $file, int $line, string $message): void
    {
        $this->lines[] = "$file:$line: warning: $message";
        ++$this->counts[$file][2];
    }

    private function add(mixed $term, string $file, int $line, Reader $reader): void
    {
        $head = $term;
        $body = null;
        if ($term instanceof Compound && indicator($term) === [':-', 2])
            [$head, $body] = $term->args;
        $error = null;
        if ($head instanceof PrologVariable)
            $error = 'instantiation_error';
        elseif (is_int($head))
            $error = typeError('callable', $head);
        elseif (isControl(indicator($head)) || isBuiltin(indicator($head)))
            $error = new Compound(
                'permission_error',
                'modify',
                'static_procedure',
                indicatorTerm(indicator($head)),
            );
        elseif ($body !== null) {
            $converted = goalConversion($body);
            if ($converted === null)
                $error = typeError('callable', $body);
            else
                $body = $converted;
        }
        if ($error !== null) {
            $this->lines[] = "$file:$line: error: " . new Writer()->write($error);
            ++$this->counts[$file][1];
            return;
        }
        $indicator = indicator($head);
        $key = serialize($indicator);
        $previous = $this->database->predicates[$key] ?? [];
        if ($file === 'program.pl' && array_any($previous, fn($c) => $c->file === 'prelude.pl')) {
            $this->warning($file, $line, 'redefining prelude procedure ' . predicateName($indicator));
            $this->database->predicates[$key] = [];
            $previous = [];
        }
        $discontiguous = $file . '|' . $key;
        if (
            array_any($previous, fn($c) => $c->file === $file)
            && $this->last[$file] !== $key
            && !isset($this->discontiguous[$discontiguous])
        ) {
            $this->warning($file, $line, 'clauses of ' . predicateName($indicator) . ' are not together');
            $this->discontiguous[$discontiguous] = true;
        }
        $this->database->add(new Clause($head, $body, $file, $line));
        $this->last[$file] = $key;
        ++$this->counts[$file][0];
        $singletons = $repeated = [];
        foreach ($reader->counts as $name => $count) {
            if (!str_starts_with($name, '_') && $count === 1)
                $singletons[] = $name;
            if (strlen($name) > 1 && $name[0] === '_' && $count > 1)
                $repeated[] = $name;
        }
        if ($singletons)
            $this->warning($file, $line, 'singleton variables: ' . implode(', ', $singletons));
        if ($repeated)
            $this->warning(
                $file,
                $line,
                'variables starting with _ occur more than once: ' . implode(', ', $repeated),
            );
    }

    public function consult(string $file, string $text): void
    {
        $reader = new Reader($text);
        $sourceLines = explode("\n", $text);
        while ($reader->peek()->kind !== 'eof') {
            $line = $reader->peek()->line;
            try {
                $term = $reader->clause();
            } catch (ReaderSyntaxError $e) {
                $t = $e->token;
                ++$this->counts[$file][1];
                $this->lines[] = "$file:{$t->line}:{$t->column}: syntax error: " . $e->getMessage();
                if ($t->kind !== 'eof') {
                    $this->lines[] = '    ' . $sourceLines[$t->line - 1];
                    $this->lines[] = str_repeat(' ', $t->column + 3) . '^';
                }
                $reader->position = $t->index;
                while (!in_array($reader->peek()->kind, ['end', 'eof'], true))
                    $reader->take();
                if ($reader->peek()->kind === 'end')
                    $reader->take();
                continue;
            }
            $this->add($term, $file, $line, $reader);
        }
    }

    public function finish(): void
    {
        $reported = [];
        foreach ($this->database->predicates as $source => $clauses)
            foreach ($clauses as $clause) {
                $pending = $clause->body === null ? [] : [$clause->body];
                while ($pending) {
                    $term = dereference(array_pop($pending));
                    if ($term instanceof PrologVariable || is_int($term))
                        continue;
                    $key = indicator($term);
                    $encoded = serialize($key);
                    if (in_array($key, [[',', 2], [';', 2], ['->', 2]], true))
                        array_push($pending, ...array_reverse($term->args));
                    elseif (in_array($key, [['\\+', 1], ['call', 1]], true))
                        $pending[] = $term->args[0];
                    elseif ($key === ['findall', 3])
                        $pending[] = $term->args[1];
                    elseif ($key === ['catch', 3])
                        array_push($pending, $term->args[2], $term->args[0]);
                    elseif (
                        !isControl($key)
                        && !isBuiltin($key)
                        && !isset($this->database->predicates[$encoded])
                        && !isset($reported[$encoded])
                    ) {
                        $reported[$encoded] = true;
                        $this->warning(
                            $clause->file,
                            $clause->line,
                            'undefined procedure ' . predicateName($key) . ' called from '
                                . predicateName($this->database->indicators[$source]),
                        );
                    }
                }
            }
        foreach ($this->counts as $file => [$clauses, $errors, $warnings])
            $this->lines[] = "$file: clauses=$clauses errors=$errors warnings=$warnings";
        $this->lines[] =
            'database: predicates='
            . count($this->database->predicates)
            . ' clauses='
            . array_sum(array_map(count(...), $this->database->predicates));
    }
}

function listing(Database $db): array
{
    $out = [];
    foreach ($db->predicates as $clauses) {
        if ($out)
            $out[] = '';
        foreach ($clauses as $clause) {
            $occurrences = variablesIn($clause->head, $clause->body);
            $counts = [];
            foreach ($occurrences as $v) {
                $id = spl_object_id($v);
                $counts[$id] = ($counts[$id] ?? 0) + 1;
            }
            $names = [];
            $number = 0;
            foreach ($occurrences as $v) {
                $id = spl_object_id($v);
                if (isset($names[$id]))
                    continue;
                if ($counts[$id] === 1)
                    $names[$id] = '_';
                else {
                    $names[$id] =
                        chr(65 + ($number % 26)) . ($number >= 26 ? (string) intdiv($number, 26) : '');
                    ++$number;
                }
            }
            $writer = new Writer($names);
            $head = $writer->write($clause->head);
            if ($clause->body === null) {
                $out[] = $head . '.';
                continue;
            }
            $out[] = $head . ' :-';
            $goals = [];
            $body = $clause->body;
            while ($body instanceof Compound && indicator($body) === [',', 2]) {
                $goals[] = $body->args[0];
                $body = $body->args[1];
            }
            $goals[] = $body;
            foreach ($goals as $i => $goal)
                $out[] = '    ' . $writer->write($goal, 999) . ($i === (count($goals) - 1) ? '.' : ',');
        }
    }
    return $out;
}

function answer(array $queryVariables): string
{
    $names = [];
    foreach ($queryVariables as [$name, $v]) {
        $value = dereference($v);
        if ($value instanceof PrologVariable)
            $names[spl_object_id($value)] ??= $name;
    }
    $writer = new Writer($names);
    $previous = $items = [];
    foreach ($queryVariables as [$name, $v]) {
        $value = dereference($v);
        if ($value instanceof PrologVariable) {
            $id = spl_object_id($value);
            if (isset($previous[$id]))
                $items[] = $previous[$id] . ' = ' . $name;
            $previous[$id] = $name;
        } else
            $items[] = $name . ' = ' . $writer->write($value, 699, true);
    }
    return $items ? implode(', ', $items) : 'true';
}

final readonly class Marker
{
    public function __construct(
        public string $kind,
        public mixed $payload,
    ) {}
}

final readonly class GoalEntry
{
    public function __construct(
        public mixed $goal,
        public int $barrier,
        public ?object $context,
    ) {}
}

final readonly class GoalList
{
    public function __construct(
        public GoalEntry $entry,
        public ?self $next,
    ) {}
}

final class InferenceLimit extends RuntimeException {}

function prepend(?GoalList $continuation, GoalEntry ...$entries): ?GoalList
{
    foreach (array_reverse($entries) as $entry)
        $continuation = new GoalList($entry, $continuation);
    return $continuation;
}

final class Engine
{
    private Trail $trail;
    private ?GoalList $goals;
    private array $choices = [], $calls, $tries;
    private ?object $context = null;
    private ?array $currentKey = null;
    public int $solutions = 0, $inferences = 0, $choicepoints = 0, $backtracks = 0;
    public array $answers = [], $output = [];

    public function __construct(
        private Database $database,
        mixed $query,
        private array $queryVariables,
        private ?int $limit,
        array &$calls,
        array &$tries,
    ) {
        $this->calls = &$calls;
        $this->tries = &$tries;
        $this->trail = new Trail();
        $this->goals = prepend(null, new GoalEntry(new Compound('call', $query), 0, null));
    }

    private function createChoice(string $kind, ?GoalList $resume, array $fields = []): object
    {
        $choice = (object) (['kind' => $kind, 'mark' => $this->trail->mark(), 'resume' => $resume] + $fields);
        $this->choices[] = $choice;
        ++$this->choicepoints;
        return $choice;
    }

    private function infer(array $key): void
    {
        if ($this->inferences === 20000)
            throw new InferenceLimit();
        ++$this->inferences;
        $id = serialize($key);
        $this->calls[$id] = ($this->calls[$id] ?? 0) + 1;
    }

    private function cut(int $height): void
    {
        array_splice($this->choices, $height);
    }

    private function writeOutput(mixed $term, bool $quoted): void
    {
        $this->output[] = $term === null ? "\n" : new Writer(quoted: $quoted)->write($term);
    }

    private function tryClause(
        Clause $clause,
        mixed $goal,
        int $barrier,
        ?object $context,
        ?GoalList $continuation,
    ): bool {
        $id = serialize(indicator($goal));
        $this->tries[$id] = ($this->tries[$id] ?? 0) + 1;
        [$head, $body] = $clause->copy();
        if (!$this->trail->unify($head, $goal))
            return false;
        $this->goals = $body === null
            ? $continuation
            : prepend($continuation, new GoalEntry($body, $barrier, $context));
        return true;
    }

    private function userCall(mixed $goal, ?object $context): bool
    {
        $key = indicator($goal);
        if (!isset($this->database->predicates[serialize($key)]))
            throw new PrologFault(new Compound('existence_error', 'procedure', indicatorTerm($key)));
        $candidates = $this->database->candidates($goal);
        if (!$candidates)
            return false;
        $height = count($this->choices);
        if (count($candidates) > 1)
            $this->createChoice('CLAUSES', $this->goals, [
                'goal' => $goal,
                'candidates' => $candidates,
                'next' => 1,
                'barrier' => $height,
                'context' => $context,
            ]);
        return $this->tryClause($candidates[0], $goal, $height, $context, $this->goals);
    }

    private function control(mixed $goal, int $barrier, ?object $context): bool
    {
        $key = indicator($goal);
        $args = $goal instanceof Compound ? $goal->args : [];
        $continuation = $this->goals;
        $height = count($this->choices);
        if ($key === [',', 2])
            $this->goals = prepend(
                $continuation,
                new GoalEntry($args[0], $barrier, $context),
                new GoalEntry($args[1], $barrier, $context),
            );
        elseif ($key === ['!', 0])
            $this->cut($barrier);
        elseif ($key === [';', 2]) {
            $this->createChoice('ALT', prepend($continuation, new GoalEntry($args[1], $barrier, $context)));
            $left = dereference($args[0]);
            if ($left instanceof Compound && indicator($left) === ['->', 2]) {
                [$condition, $then] = $left->args;
                $this->goals = prepend(
                    $continuation,
                    new GoalEntry($condition, $height + 1, $context),
                    new GoalEntry(new Marker('ITE', $height), $barrier, $context),
                    new GoalEntry($then, $barrier, $context),
                );
            } else
                $this->goals = prepend($continuation, new GoalEntry($left, $barrier, $context));
        } elseif ($key === ['->', 2])
            $this->goals = prepend(
                $continuation,
                new GoalEntry($args[0], $height, $context),
                new GoalEntry(new Marker('ITE', $height), $barrier, $context),
                new GoalEntry($args[1], $barrier, $context),
            );
        elseif ($key === ['\\+', 1]) {
            $this->createChoice('ALT', $continuation);
            $this->goals = prepend(
                $continuation,
                new GoalEntry(new Compound('call', $args[0]), $barrier, $context),
                new GoalEntry(new Marker('NAF', $height), $barrier, $context),
            );
        } elseif ($key[0] === 'call') {
            $target = dereference($args[0]);
            if ($target instanceof PrologVariable)
                throw new PrologFault('instantiation_error');
            if (is_int($target))
                throw new PrologFault(typeError('callable', $target));
            if (count($args) > 1)
                $target = is_string($target)
                    ? new Compound($target, ...array_slice($args, 1))
                    : new Compound($target->name, ...$target->args, ...array_slice($args, 1));
            $converted = goalConversion($target);
            if ($converted === null)
                throw new PrologFault(typeError('callable', $target));
            $this->goals = prepend($continuation, new GoalEntry($converted, $height, $context));
        } elseif ($key === ['catch', 3]) {
            $frame = $this->createChoice('CATCH', $continuation, [
                'catcher' => $args[1],
                'recovery' => $args[2],
                'parent' => $context,
            ]);
            $this->goals = prepend(
                $continuation,
                new GoalEntry(new Compound('call', $args[0]), $barrier, $frame),
                new GoalEntry(new Marker('EXIT', $frame), $barrier, $context),
            );
        }
        return true;
    }

    private function marker(Marker $marker): bool
    {
        $kind = $marker->kind;
        $payload = $marker->payload;
        if ($kind === 'ITE' || $kind === 'NAF') {
            $this->cut($payload);
            return $kind === 'ITE';
        }
        if ($kind === 'EXIT') {
            if ($this->choices && $this->choices[count($this->choices) - 1] === $payload)
                array_pop($this->choices);
            return true;
        }
        $payload->results[] = copyTerm($payload->template);
        return false;
    }

    private function between(array $args): bool
    {
        $lower = requireInteger($args[0]);
        $upper = requireInteger($args[1]);
        $value = dereference($args[2]);
        if (!$value instanceof PrologVariable && !is_int($value))
            throw new PrologFault(typeError('integer', $value));
        if (is_int($value))
            return $lower <= $value && $value <= $upper;
        if ($lower > $upper)
            return false;
        if ($lower < $upper)
            $this->createChoice('BETWEEN', $this->goals, [
                'upper' => $upper,
                'target' => $value,
                'next' => $lower + 1,
            ]);
        return $this->trail->unify($value, $lower);
    }

    private function length(array $args): bool
    {
        $sequence = $args[0];
        $number = dereference($args[1]);
        if (!$number instanceof PrologVariable && !is_int($number))
            throw new PrologFault(typeError('integer', $number));
        if (is_int($number) && $number < 0)
            throw new PrologFault(domainError('not_less_than_zero', $number));
        [$elements, $tail] = listParts($sequence);
        $count = count($elements);
        if ($tail === '[]')
            return $this->trail->unify($number, $count);
        if (!$tail instanceof PrologVariable)
            throw new PrologFault(typeError('list', $sequence));
        if (is_int($number))
            return $number >= $count
            && $this->trail->unify($tail, makeList(freshVariables($number - $count)));
        $this->createChoice('LENGTH', $this->goals, [
            'tail' => $tail,
            'number' => $number,
            'count' => $count,
            'next' => $count + 1,
        ]);
        return $this->trail->unify($tail, '[]') && $this->trail->unify($number, $count);
    }

    private function step(): bool
    {
        $entry = $this->goals->entry;
        $this->goals = $this->goals->next;
        $goal = $entry->goal;
        $barrier = $entry->barrier;
        $context = $this->context = $entry->context;
        if ($goal instanceof Marker)
            return $this->marker($goal);
        $goal = dereference($goal);
        $key = $this->currentKey = indicator($goal);
        if (isControl($key))
            return $this->control($goal, $barrier, $context);
        $this->infer($key);
        if ($key === ['findall', 3]) {
            [$template, $body, $result] = $goal->args;
            $frame = $this->createChoice(
                'FINDALL',
                $this->goals,
                compact('template', 'result') + ['results' => []],
            );
            $this->goals = prepend(
                null,
                new GoalEntry(new Compound('call', $body), $barrier, $context),
                new GoalEntry(new Marker('COLLECT', $frame), $barrier, $context),
            );
            return true;
        }
        if ($key === ['throw', 1]) {
            $ball = dereference($goal->args[0]);
            if ($ball instanceof PrologVariable)
                throw new PrologFault('instantiation_error');
            throw new PrologBall($ball);
        }
        if ($key === ['between', 3])
            return $this->between($goal->args);
        if ($key === ['length', 2])
            return $this->length($goal->args);
        if (in_array($key, DETERMINISTIC, true))
            return executePredicate($goal, $this->trail, $this->writeOutput(...));
        return $this->userCall($goal, $context);
    }

    private function backtrack(): bool
    {
        while (true) {
            ++$this->backtracks;
            while ($this->choices) {
                $choice = $this->choices[count($this->choices) - 1];
                $this->trail->undo($choice->mark);
                if ($choice->kind === 'CATCH') {
                    array_pop($this->choices);
                    continue;
                }
                break;
            }
            if (!$this->choices)
                return false;
            if ($choice->kind === 'ALT') {
                array_pop($this->choices);
                $this->goals = $choice->resume;
                return true;
            }
            if ($choice->kind === 'CLAUSES') {
                $clause = $choice->candidates[$choice->next];
                if (($choice->next + 1) === count($choice->candidates))
                    array_pop($this->choices);
                else
                    ++$choice->next;
                if ($this->tryClause(
                    $clause,
                    $choice->goal,
                    $choice->barrier,
                    $choice->context,
                    $choice->resume,
                ))
                    return true;
            } elseif ($choice->kind === 'BETWEEN') {
                $this->infer(['between', 3]);
                $value = $choice->next;
                if ($value === $choice->upper)
                    array_pop($this->choices);
                else
                    ++$choice->next;
                if ($this->trail->unify($choice->target, $value)) {
                    $this->goals = $choice->resume;
                    return true;
                }
            } elseif ($choice->kind === 'LENGTH') {
                $this->infer(['length', 2]);
                $count = $choice->next++;
                $value = makeList(freshVariables($count - $choice->count));
                if (
                    $this->trail->unify($choice->tail, $value) && $this->trail->unify($choice->number, $count)
                ) {
                    $this->goals = $choice->resume;
                    return true;
                }
            } elseif ($choice->kind === 'FINDALL') {
                array_pop($this->choices);
                if ($this->trail->unify(makeList($choice->results), $choice->result)) {
                    $this->goals = $choice->resume;
                    return true;
                }
            }
        }
    }

    private function handleException(mixed $ball): bool
    {
        $ball = copyTerm($ball);
        $frame = $this->context;
        while ($frame !== null) {
            $index = array_search($frame, $this->choices, true);
            array_splice($this->choices, $index);
            $this->trail->undo($frame->mark);
            $mark = $this->trail->mark();
            if ($this->trail->unify(copyTerm($ball), $frame->catcher)) {
                $this->goals = prepend(
                    $frame->resume,
                    new GoalEntry(
                        new Compound('call', $frame->recovery),
                        count($this->choices),
                        $frame->parent,
                    ),
                );
                return true;
            }
            $this->trail->undo($mark);
            $frame = $frame->parent;
        }
        $this->answers[] = 'uncaught exception: ' . new Writer()->write($ball);
        return false;
    }

    public function run(): array
    {
        while (true) {
            try {
                if ($this->goals === null) {
                    ++$this->solutions;
                    $text = answer($this->queryVariables);
                    if ($this->solutions === $this->limit || !$this->choices) {
                        $this->answers[] = $text . '.';
                        break;
                    }
                    $this->answers[] = $text . ' ;';
                    $success = $this->backtrack();
                } else {
                    $success = $this->step();
                    if (!$success)
                        $success = $this->backtrack();
                }
                if (!$success) {
                    $this->answers[] = 'false.';
                    break;
                }
            } catch (PrologFault $e) {
                if (!$this->handleException(
                    new Compound('error', $e->term, indicatorTerm($this->currentKey)),
                ))
                    break;
            } catch (PrologBall $e) {
                if (!$this->handleException($e->term))
                    break;
            } catch (InferenceLimit) {
                $this->answers[] = 'inference limit exceeded';
                break;
            }
        }
        return [$this->solutions, $this->inferences, $this->choicepoints, $this->backtracks];
    }
}

function statistics(string $prefix, array $counts): string
{
    [$solutions, $inferences, $choices, $backtracks] = $counts;
    return "$prefix solutions=$solutions inferences=$inferences choicepoints=$choices backtracks=$backtracks";
}

function main(): void
{
    $consultant = new Consultant();
    foreach (['prelude.pl', 'program.pl'] as $file)
        $consultant->consult($file, file_get_contents('input/' . $file));
    $consultant->finish();
    $answers = $writes = $stats = $calls = $tries = [];
    $totals = [0, 0, 0, 0];
    foreach (file('input/queries.txt', FILE_IGNORE_NEW_LINES) as $i => $source) {
        $number = $i + 1;
        $answers[] = $source;
        $writes[] = "== query $number ==\n";
        $marker = strpos($source, '?- ');
        $limit = $marker === 0 ? null : (int) trim(substr($source, 0, $marker));
        $start = $marker + 3;
        $reader = new Reader(substr($source, $start), $start + 1);
        try {
            $query = $reader->clause(true);
        } catch (ReaderSyntaxError $e) {
            $answers[] = 'syntax error at column ' . $e->token->column . ': ' . $e->getMessage();
            $stats[] = "query $number: syntax error";
            continue;
        }
        $variables = [];
        foreach ($reader->names as $name => $variable)
            if (!str_starts_with($name, '_'))
                $variables[] = [$name, $variable];
        $engine = new Engine($consultant->database, $query, $variables, $limit, $calls, $tries);
        $counts = $engine->run();
        foreach ($counts as $j => $count)
            $totals[$j] += $count;
        array_push($answers, ...$engine->answers);
        $text = implode('', $engine->output);
        $writes[] = $text . ($text !== '' && !str_ends_with($text, "\n") ? "\n" : '');
        $stats[] = statistics("query $number:", $counts);
    }
    array_push($stats, statistics('total:', $totals), '== profile ==');
    $keys = array_keys($calls);
    usort(
        $keys,
        fn($a, $b) => (
            $calls[$b] <=> $calls[$a] ?: strcmp(
                predicateName(unserialize($a)),
                predicateName(unserialize($b)),
            )
        ),
    );
    foreach ($keys as $key) {
        $line = predicateName(unserialize($key)) . ' calls=' . $calls[$key];
        if (isset($consultant->database->predicates[$key]))
            $line .= ' tries=' . ($tries[$key] ?? 0);
        $stats[] = $line;
    }
    if (!is_dir('output'))
        mkdir('output');
    foreach ([
        'consult.txt' => $consultant->lines,
        'listing.txt' => listing($consultant->database),
        'answers.txt' => $answers,
        'stats.txt' => $stats,
    ] as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . ($lines ? "\n" : ''));
    file_put_contents('output/write_output.txt', implode('', $writes));
}

main();
