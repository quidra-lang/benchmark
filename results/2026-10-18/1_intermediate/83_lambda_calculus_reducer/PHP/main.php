<?php
class LambdaError extends Exception
{
}

class Untypable extends Exception
{
}

class Term
{
    public array $free;
    public int $size;
    public int $depth;

    public function __construct(
        public string $kind,
        public string|int|null $name = null,
        public ?Term $left = null,
        public ?Term $right = null
    ) {
        $this->free = match ($kind) {
            'var' => [$name => true],
            'abs' => $left->free,
            'app' => $left->free + $right->free,
            default => []
        };
        if ($kind === 'abs') {
            unset($this->free[$name]);
        }
        $this->size = 1 + ($left?->size ?? 0) + ($right?->size ?? 0);
        $this->depth = 1 + max($left?->depth ?? 0, $right?->depth ?? 0);
    }
}

function variable(string $name): Term
{
    return new Term('var', $name);
}

function abstraction(?string $name, Term $body): Term
{
    return new Term('abs', $name, $body);
}

function application(Term $left, Term $right): Term
{
    return new Term('app', null, $left, $right);
}

function printed(Term $term, bool $end = true, bool $db = false): string
{
    if (in_array($term->kind, ['var', 'macro', 'constant'], true)) {
        return $term->name;
    }
    if ($term->kind === 'number') {
        return '#' . $term->name;
    }
    if ($term->kind === 'index') {
        return (string)$term->name;
    }
    if ($term->kind === 'abs') {
        $names = [];
        $body = $term;
        while ($body->kind === 'abs') {
            $names[] = $body->name;
            $body = $body->left;
        }
        $text = $db
            ? str_repeat('\\', count($names)) . printed($body, true, true)
            : '\\' . implode(' ', $names) . '. ' . printed($body);
        return $end ? $text : '(' . $text . ')';
    }
    $left = $term->left->kind === 'abs' ? '(' . printed($term->left, true, $db) . ')' : printed($term->left, false, $db);
    $right = $term->right->kind === 'app' ? '(' . printed($term->right, true, $db) . ')' : printed($term->right, $end, $db);
    return $left . ' ' . $right;
}

class LambdaParser
{
    private array $tokens = [];
    private int $position = 0;

    public function __construct(string $argument, int $offset, int $endColumn)
    {
        $i = 0;
        $length = strlen($argument);
        while ($i < $length) {
            $c = $argument[$i];
            if ($c === ' ') {
                $i++;
                continue;
            }
            $start = $i;
            if (str_contains('\\.()=;', $c)) {
                $kind = $c;
                $i++;
            } elseif ($c >= 'a' && $c <= 'z') {
                $kind = 'var';
                $i++;
                while ($i < $length && preg_match('/[a-z0-9]/', $argument[$i])) {
                    $i++;
                }
            } elseif ($c >= 'A' && $c <= 'Z') {
                $kind = 'macro';
                $i++;
                while ($i < $length && preg_match('/[A-Z0-9_]/', $argument[$i])) {
                    $i++;
                }
            } elseif ($c === '#' && $i + 1 < $length && ctype_digit($argument[$i + 1])) {
                $kind = 'number';
                $i += 2;
                while ($i < $length && ctype_digit($argument[$i])) {
                    $i++;
                }
            } else {
                throw new LambdaError('column ' . ($offset + $i) . ": unexpected character '" . $c . "'");
            }
            $this->tokens[] = [$kind, substr($argument, $start, $i - $start), $offset + $start];
        }
        $this->tokens[] = ['end', '', $endColumn];
    }

    public function peek(): array
    {
        return $this->tokens[$this->position];
    }

    public function advance(): array
    {
        return $this->tokens[$this->position++];
    }

    public function expect(string $kind): string
    {
        $notation = ['var' => 'variable', 'macro' => 'macro name'][$kind] ?? "'" . $kind . "'";
        if ($this->peek()[0] !== $kind) {
            throw new LambdaError('column ' . $this->peek()[2] . ': expected ' . $notation);
        }
        return $this->advance()[1];
    }

    public function term(): Term
    {
        $elements = [];
        while (in_array($this->peek()[0], ['var', 'macro', 'number', '('], true)) {
            [$kind, $text] = $this->advance();
            if ($kind === '(') {
                $elements[] = $this->term();
                $this->expect(')');
            } else {
                $elements[] = new Term($kind, $kind === 'number' ? (int)substr($text, 1) : $text);
            }
        }
        if ($this->peek()[0] === '\\') {
            $this->advance();
            $names = [$this->expect('var')];
            while ($this->peek()[0] === 'var') {
                $names[] = $this->advance()[1];
            }
            $this->expect('.');
            $body = $this->term();
            foreach (array_reverse($names) as $name) {
                $body = abstraction($name, $body);
            }
            $elements[] = $body;
        }
        if ($elements === []) {
            throw new LambdaError('column ' . $this->peek()[2] . ': expected term');
        }
        $result = array_shift($elements);
        foreach ($elements as $element) {
            $result = application($result, $element);
        }
        return $result;
    }

    public function finish(): void
    {
        if ($this->peek()[0] !== 'end') {
            throw new LambdaError('column ' . $this->peek()[2] . ": unexpected '" . $this->peek()[1] . "'");
        }
    }
}

function references(Term $term): array
{
    return match ($term->kind) {
        'macro' => [$term->name],
        'abs' => references($term->left),
        'app' => array_merge(references($term->left), references($term->right)),
        default => []
    };
}

function nameAt(int $index): string
{
    return chr(97 + $index % 26) . ($index >= 26 ? intdiv($index, 26) : '');
}

function canonical(Term $term): Term
{
    $free = $term->free;
    $counter = 0;
    $visit = function (Term $node, array $bindings) use (&$visit, &$counter, $free): Term {
        if ($node->kind === 'var') {
            return variable($bindings[$node->name] ?? $node->name);
        }
        if ($node->kind === 'abs') {
            while (isset($free[nameAt($counter)])) {
                $counter++;
            }
            $name = nameAt($counter++);
            $bindings[$node->name] = $name;
            return abstraction($name, $visit($node->left, $bindings));
        }
        if ($node->kind === 'app') {
            $left = $visit($node->left, $bindings);
            $right = $visit($node->right, $bindings);
            return application($left, $right);
        }
        return $node;
    };
    return $visit($term, []);
}

function toDebruijn(Term $term, array $bindings = []): Term
{
    if ($term->kind === 'var') {
        $index = array_search($term->name, $bindings, true);
        return $index === false ? $term : new Term('index', $index);
    }
    if ($term->kind === 'abs') {
        return abstraction(null, toDebruijn($term->left, array_merge([$term->name], $bindings)));
    }
    return application(toDebruijn($term->left, $bindings), toDebruijn($term->right, $bindings));
}

function fromDebruijn(Term $term): Term
{
    $free = $term->free;
    $counter = 0;
    $visit = function (Term $node, array $bindings) use (&$visit, &$counter, $free): Term {
        if ($node->kind === 'index') {
            return variable($bindings[$node->name]);
        }
        if ($node->kind === 'var') {
            return $node;
        }
        if ($node->kind === 'abs') {
            while (isset($free[nameAt($counter)])) {
                $counter++;
            }
            $name = nameAt($counter++);
            return abstraction($name, $visit($node->left, array_merge([$name], $bindings)));
        }
        $left = $visit($node->left, $bindings);
        $right = $visit($node->right, $bindings);
        return application($left, $right);
    };
    return $visit($term, []);
}

function substitute(Term $term, string $name, Term $replacement): Term
{
    if ($term->kind === 'var') {
        return $term->name === $name ? $replacement : $term;
    }
    if ($term->kind === 'app') {
        return application(substitute($term->left, $name, $replacement), substitute($term->right, $name, $replacement));
    }
    $bound = $term->name;
    $body = $term->left;
    if ($bound === $name || !isset($body->free[$name])) {
        return $term;
    }
    if (isset($replacement->free[$bound])) {
        $stem = preg_replace('/[0-9]+\z/', '', $bound);
        $suffix = 1;
        while (isset($replacement->free[$stem . $suffix]) || isset($body->free[$stem . $suffix])) {
            $suffix++;
        }
        $fresh = $stem . $suffix;
        $body = substitute($body, $bound, variable($fresh));
        $bound = $fresh;
    }
    return abstraction($bound, substitute($body, $name, $replacement));
}

function etaTarget(Term $term): ?Term
{
    $body = $term->left;
    return $body->kind === 'app' && $body->right->kind === 'var' && $body->right->name === $term->name && !isset($body->left->free[$term->name]) ? $body->left : null;
}

function oneStep(Term $term, string $strategy, bool $eta): ?array
{
    if ($term->kind === 'app') {
        $left = $term->left;
        $right = $term->right;
        if (in_array($strategy, ['NORMAL', 'CBN'], true) && $left->kind === 'abs') {
            return [substitute($left->left, $left->name, $right), 'beta'];
        }
        $step = oneStep($left, $strategy, $eta);
        if ($step !== null) {
            return [application($step[0], $right), $step[1]];
        }
        if ($strategy !== 'CBN') {
            $step = oneStep($right, $strategy, $eta);
            if ($step !== null) {
                return [application($left, $step[0]), $step[1]];
            }
        }
        if (in_array($strategy, ['APPLICATIVE', 'CBV'], true) && $left->kind === 'abs' && ($strategy !== 'CBV' || in_array($right->kind, ['var', 'abs'], true))) {
            return [substitute($left->left, $left->name, $right), 'beta'];
        }
    } elseif ($term->kind === 'abs' && in_array($strategy, ['NORMAL', 'APPLICATIVE'], true)) {
        $target = $eta ? etaTarget($term) : null;
        if ($target !== null && $strategy === 'NORMAL') {
            return [$target, 'eta'];
        }
        $step = oneStep($term->left, $strategy, $eta);
        if ($step !== null) {
            return [abstraction($term->name, $step[0]), $step[1]];
        }
        if ($target !== null) {
            return [$target, 'eta'];
        }
    }
    return null;
}

function skiAbstract(string $name, Term $term): Term
{
    if (!isset($term->free[$name])) {
        return application(new Term('constant', 'K'), $term);
    }
    if ($term->kind === 'var' && $term->name === $name) {
        return new Term('constant', 'I');
    }
    if ($term->right->kind === 'var' && $term->right->name === $name && !isset($term->left->free[$name])) {
        return $term->left;
    }
    return application(application(new Term('constant', 'S'), skiAbstract($name, $term->left)), skiAbstract($name, $term->right));
}

function toSki(Term $term): Term
{
    return match ($term->kind) {
        'var' => $term,
        'abs' => skiAbstract($term->name, toSki($term->left)),
        'app' => application(toSki($term->left), toSki($term->right))
    };
}

function skiStep(Term $term): ?array
{
    $head = $term;
    $args = [];
    while ($head->kind === 'app') {
        array_unshift($args, $head->right);
        $head = $head->left;
    }
    $arity = $head->kind === 'constant' ? ['I' => 1, 'K' => 2, 'S' => 3][$head->name] : null;
    if ($arity !== null && count($args) >= $arity) {
        $result = $head->name === 'S' ? application(application($args[0], $args[2]), application($args[1], $args[2])) : $args[0];
        foreach (array_slice($args, $arity) as $arg) {
            $result = application($result, $arg);
        }
        return [$result, $head->name];
    }
    foreach ($args as $i => $arg) {
        $step = skiStep($arg);
        if ($step !== null) {
            $args[$i] = $step[0];
            $result = $head;
            foreach ($args as $argument) {
                $result = application($result, $argument);
            }
            return [$result, $step[1]];
        }
    }
    return null;
}

class TypeInference
{
    private int $next = 0;
    private array $links = [];
    private array $free = [];

    private function fresh(): array
    {
        return ['variable', $this->next++];
    }

    private function prune(array $type): array
    {
        $path = [];
        while ($type[0] === 'variable' && isset($this->links[$type[1]])) {
            $path[] = $type[1];
            $type = $this->links[$type[1]];
        }
        foreach ($path as $id) {
            $this->links[$id] = $type;
        }
        return $type;
    }

    private function occurs(int $id, array $type): bool
    {
        $type = $this->prune($type);
        return $type[0] === 'variable' ? $type[1] === $id : $this->occurs($id, $type[1]) || $this->occurs($id, $type[2]);
    }

    private function unify(array $left, array $right): void
    {
        $left = $this->prune($left);
        $right = $this->prune($right);
        if ($left === $right) {
            return;
        }
        if ($left[0] === 'variable') {
            if ($this->occurs($left[1], $right)) {
                throw new Untypable();
            }
            $this->links[$left[1]] = $right;
        } elseif ($right[0] === 'variable') {
            $this->unify($right, $left);
        } else {
            $this->unify($left[1], $right[1]);
            $this->unify($left[2], $right[2]);
        }
    }

    private function infer(Term $term, array $environment = []): array
    {
        if ($term->kind === 'var') {
            if (isset($environment[$term->name])) {
                return $environment[$term->name];
            }
            return $this->free[$term->name] ??= $this->fresh();
        }
        if ($term->kind === 'abs') {
            $parameter = $this->fresh();
            $environment[$term->name] = $parameter;
            return ['arrow', $parameter, $this->infer($term->left, $environment)];
        }
        $function = $this->infer($term->left, $environment);
        $argument = $this->infer($term->right, $environment);
        $result = $this->fresh();
        $this->unify($function, ['arrow', $argument, $result]);
        return $result;
    }

    public function show(Term $term): string
    {
        try {
            $type = $this->infer($term);
            $names = [];
            $visit = function (array $node) use (&$visit, &$names): string {
                $node = $this->prune($node);
                if ($node[0] === 'variable') {
                    return $names[$node[1]] ??= nameAt(count($names));
                }
                $left = $visit($node[1]);
                if ($this->prune($node[1])[0] === 'arrow') {
                    $left = '(' . $left . ')';
                }
                return $left . ' -> ' . $visit($node[2]);
            };
            return $visit($type);
        } catch (Untypable) {
            return 'not typable';
        }
    }
}

function churchValue(Term $term): string
{
    if ($term->kind === 'abs' && $term->left->kind === 'abs') {
        $f = $term->name;
        $x = $term->left->name;
        $body = $term->left->left;
        $count = 0;
        while ($body->kind === 'app' && $body->left->kind === 'var' && $body->left->name === $f) {
            $count++;
            $body = $body->right;
        }
        if ($body->kind === 'var' && $body->name === $x) {
            return (string)$count;
        }
        if ($term->left->left->kind === 'var' && $term->left->left->name === $f) {
            return 'true';
        }
    }
    if ($term->kind === 'abs') {
        $body = $term->left;
        if ($body->kind === 'app' && $body->left->kind === 'app' && $body->left->left->kind === 'var' && $body->left->left->name === $term->name) {
            $p = $body->left->right;
            $q = $body->right;
            if (!isset($p->free[$term->name]) && !isset($q->free[$term->name])) {
                return '(' . churchValue($p) . ', ' . churchValue($q) . ')';
            }
        }
    }
    return printed(canonical($term));
}

function materialize(Term $code, array $environment, int $level = 0): Term
{
    while ($code->kind === 'index' && $code->name >= $level) {
        [$code, $environment] = $environment[$code->name - $level];
        $level = 0;
    }
    if ($code->kind === 'app') {
        return application(materialize($code->left, $environment, $level), materialize($code->right, $environment, $level));
    }
    if ($code->kind === 'abs') {
        return abstraction(null, materialize($code->left, $environment, $level + 1));
    }
    return $code;
}

class Workbench
{
    private const RESERVED = ['S', 'K', 'I', 'NORMAL', 'APPLICATIVE', 'CBN', 'CBV'];
    private const COMMANDS = ['let', 'unlet', 'macros', 'steps', 'eta', 'limit', 'expand', 'subst',
        'reduce', 'equal', 'alpha', 'debruijn', 'fv', 'size', 'depth', 'type', 'church', 'ski', 'skireduce', 'kam'];
    private array $macros;
    private bool $steps = false;
    private bool $eta = false;
    private int $limit = 10000;

    public function __construct()
    {
        $this->macros = [
            'S' => abstraction('x', abstraction('y', abstraction('z', application(application(variable('x'), variable('z')), application(variable('y'), variable('z')))))),
            'K' => abstraction('x', abstraction('y', variable('x'))),
            'I' => abstraction('x', variable('x'))
        ];
    }

    private function depends(string $name, string $target, ?array &$visited = null): bool
    {
        if ($visited === null) {
            $visited = [];
        }
        if (isset($visited[$name])) {
            return false;
        }
        $visited[$name] = true;
        if (!isset($this->macros[$name]) || in_array($name, ['S', 'K', 'I'], true)) {
            return false;
        }
        foreach (references($this->macros[$name]) as $ref) {
            if ($ref === $target || $this->depends($ref, $target, $visited)) {
                return true;
            }
        }
        return false;
    }

    private function expand(Term $term): Term
    {
        if ($term->kind === 'macro') {
            if (!isset($this->macros[$term->name])) {
                throw new LambdaError('unbound macro ' . $term->name);
            }
            return $this->expand($this->macros[$term->name]);
        }
        if ($term->kind === 'number') {
            $body = variable('x');
            for ($i = 0; $i < $term->name; $i++) {
                $body = application(variable('f'), $body);
            }
            return abstraction('f', abstraction('x', $body));
        }
        if ($term->kind === 'abs') {
            return abstraction($term->name, $this->expand($term->left));
        }
        if ($term->kind === 'app') {
            $left = $this->expand($term->left);
            $right = $this->expand($term->right);
            return application($left, $right);
        }
        return $term;
    }

    private function reduce(Term $term, string $strategy, bool $eta, bool $display = false, bool $ski = false): ?array
    {
        $count = 0;
        while (true) {
            $step = $ski ? skiStep($term) : oneStep($term, $strategy, $eta);
            if ($step === null) {
                return [$term, $count];
            }
            if ($count === $this->limit) {
                return null;
            }
            $term = $step[0];
            $count++;
            if ($display && $this->steps) {
                echo 'step ', $count, ' (', $step[1], '): ', printed($term), "\n";
            }
        }
    }

    private function kam(Term $term): void
    {
        $code = toDebruijn($term);
        $environment = [];
        $stack = [];
        $count = 0;
        while (true) {
            $kind = match ($code->kind) {
                'app' => 'push', 'abs' => $stack === [] ? null : 'grab', 'index' => 'access', default => null
            };
            if ($kind === null) {
                break;
            }
            if ($count === $this->limit) {
                echo 'no result within ', $this->limit, " transitions\n";
                return;
            }
            if ($kind === 'push') {
                $stack[] = [$code->right, $environment];
                $code = $code->left;
            } elseif ($kind === 'grab') {
                array_unshift($environment, array_pop($stack));
                $code = $code->left;
            } else {
                [$code, $environment] = $environment[$code->name];
            }
            $count++;
            if ($this->steps) {
                echo 'step ', $count, ' (', $kind, '): ', printed($code, true, true), ' [env ', count($environment), ', stack ', count($stack), "]\n";
            }
        }
        $result = materialize($code, $environment);
        foreach (array_reverse($stack) as $closure) {
            $result = application($result, materialize($closure[0], $closure[1]));
        }
        echo 'result: ', printed(fromDebruijn($result)), ' (transitions: ', $count, ")\n";
    }

    private function simpleCommand(string $command, string $argument): void
    {
        $words = preg_split('/ +/', $argument, -1, PREG_SPLIT_NO_EMPTY);
        if ($command === 'steps' || $command === 'eta') {
            if (count($words) !== 1 || !in_array($words[0], ['on', 'off'], true)) {
                throw new LambdaError('bad argument');
            }
            if ($command === 'steps') {
                $this->steps = $words[0] === 'on';
            } else {
                $this->eta = $words[0] === 'on';
            }
        } elseif ($command === 'limit') {
            if (count($words) !== 1 || !preg_match('/\A[0-9]{1,5}\z/', $words[0]) || (int)$words[0] < 1 || (int)$words[0] > 10000) {
                throw new LambdaError('bad argument');
            }
            $this->limit = (int)$words[0];
        } elseif ($command === 'macros') {
            if ($words !== []) {
                throw new LambdaError('bad argument');
            }
            $names = array_values(array_diff(array_keys($this->macros), ['S', 'K', 'I']));
            sort($names, SORT_STRING);
            if ($names === []) {
                echo "(none)\n";
            }
            foreach ($names as $name) {
                echo $name, ' = ', printed($this->macros[$name]), "\n";
            }
        } else {
            if (count($words) !== 1 || !preg_match('/\A[A-Z][A-Z0-9_]*\z/', $words[0])) {
                throw new LambdaError('bad argument');
            }
            $name = $words[0];
            if (in_array($name, self::RESERVED, true)) {
                throw new LambdaError('reserved name ' . $name);
            }
            if (!isset($this->macros[$name])) {
                throw new LambdaError('unbound macro ' . $name);
            }
            $names = array_keys($this->macros);
            sort($names, SORT_STRING);
            foreach ($names as $key) {
                if (!in_array($key, ['S', 'K', 'I'], true) && in_array($name, references($this->macros[$key]), true)) {
                    throw new LambdaError($name . ' is used by ' . $key);
                }
            }
            unset($this->macros[$name]);
            echo 'removed ', $name, "\n";
        }
    }

    public function command(string $line): void
    {
        $parts = explode(' ', $line, 2);
        $command = $parts[0];
        $argument = $parts[1] ?? '';
        if (!in_array($command, self::COMMANDS, true)) {
            throw new LambdaError('unknown command ' . $command);
        }
        if (in_array($command, ['steps', 'eta', 'limit', 'macros', 'unlet'], true)) {
            $this->simpleCommand($command, $argument);
            return;
        }
        $parser = new LambdaParser($argument, strlen($command) + 2, strlen($line) + 1);
        $strategy = 'NORMAL';
        $name = null;
        $terms = [];
        if ($command === 'let' || $command === 'subst') {
            $name = $parser->expect($command === 'let' ? 'macro' : 'var');
            $parser->expect('=');
            $terms[] = $parser->term();
            if ($command === 'subst') {
                $parser->expect(';');
                $terms[] = $parser->term();
            }
        } elseif ($command === 'equal' || $command === 'alpha') {
            $terms[] = $parser->term();
            $parser->expect(';');
            $terms[] = $parser->term();
        } else {
            if ($command === 'reduce' && $parser->peek()[0] === 'macro' && in_array($parser->peek()[1], ['NORMAL', 'APPLICATIVE', 'CBN', 'CBV'], true)) {
                $strategy = $parser->advance()[1];
            }
            $terms[] = $parser->term();
        }
        $parser->finish();
        if ($command === 'let') {
            if (in_array($name, self::RESERVED, true)) {
                throw new LambdaError('reserved name ' . $name);
            }
            foreach (references($terms[0]) as $ref) {
                if ($ref === $name || $this->depends($ref, $name)) {
                    throw new LambdaError('recursive definition of ' . $name);
                }
                if (!isset($this->macros[$ref])) {
                    throw new LambdaError('unbound macro ' . $ref);
                }
            }
            if ($terms[0]->free !== []) {
                $free = array_keys($terms[0]->free);
                sort($free, SORT_STRING);
                throw new LambdaError('free variable ' . $free[0] . ' in definition of ' . $name);
            }
            echo isset($this->macros[$name]) ? 'redefined ' : 'defined ', $name, "\n";
            $this->macros[$name] = $terms[0];
            return;
        }
        foreach ($terms as $i => $term) {
            $terms[$i] = $this->expand($term);
        }
        $term = $terms[0];
        switch ($command) {
            case 'expand':
                echo printed($term), "\n";
                break;
            case 'subst':
                echo printed(substitute($terms[1], $name, $term)), "\n";
                break;
            case 'alpha':
                echo printed(toDebruijn($term), true, true) === printed(toDebruijn($terms[1]), true, true) ? "yes\n" : "no\n";
                break;
            case 'debruijn':
                echo printed(toDebruijn($term), true, true), "\n";
                break;
            case 'fv':
                $free = array_keys($term->free);
                sort($free, SORT_STRING);
                echo $free === [] ? '(none)' : implode(' ', $free), "\n";
                break;
            case 'size':
                echo $term->size, "\n";
                break;
            case 'depth':
                echo $term->depth, "\n";
                break;
            case 'type':
                echo (new TypeInference())->show($term), "\n";
                break;
            case 'ski':
                echo printed(toSki($term)), "\n";
                break;
            case 'kam':
                $this->kam($term);
                break;
            case 'equal':
                $left = $this->reduce($term, 'NORMAL', $this->eta);
                $right = $this->reduce($terms[1], 'NORMAL', $this->eta);
                if ($left === null || $right === null) {
                    echo "unknown\n";
                } else {
                    echo printed(canonical($left[0])) === printed(canonical($right[0])) ? "yes\n" : "no\n";
                }
                break;
            default:
                if ($command === 'church') {
                    $result = $this->reduce($term, 'NORMAL', false);
                } elseif ($command === 'skireduce') {
                    $result = $this->reduce(toSki($term), 'NORMAL', false, true, true);
                } else {
                    $result = $this->reduce($term, $strategy, $this->eta, true);
                }
                if ($result === null) {
                    echo 'no normal form within ', $this->limit, " steps\n";
                } elseif ($command === 'church') {
                    echo churchValue(canonical($result[0])), "\n";
                } else {
                    $text = $command === 'skireduce' ? printed($result[0]) : printed(canonical($result[0]));
                    echo 'result: ', $text, ' (steps: ', $result[1], ")\n";
                }
        }
    }

    public function run(): void
    {
        while (($input = fgets(STDIN)) !== false) {
            $line = str_ends_with($input, "\n") ? substr($input, 0, -1) : $input;
            if ($line === 'quit') {
                break;
            }
            if ($line === '' || str_starts_with($line, '--')) {
                continue;
            }
            try {
                $this->command($line);
            } catch (LambdaError $error) {
                echo 'error: ', $error->getMessage(), "\n";
            }
        }
    }
}

(new Workbench())->run();
