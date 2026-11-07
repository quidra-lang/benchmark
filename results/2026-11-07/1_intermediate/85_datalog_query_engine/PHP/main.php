<?php
class DatalogError extends Exception
{
}

const RESERVED = ['not', 'mod', 'count', 'sum', 'min', 'max', 'retract', 'dump', 'why', 'forget', 'listing', 'strata', 'stats', 'check', 'predicates', 'undo', 'halt'];

class Atom
{
    public function __construct(public string $name, public array $terms)
    {
    }
}

function valueText(int|string $value): string
{
    if (is_int($value)) {
        return (string)$value;
    }
    return preg_match('/\A[a-z][A-Za-z0-9_]*\z/', $value) && !in_array($value, RESERVED, true) ? $value : '"' . $value . '"';
}

function valueCompare(int|string $a, int|string $b): int
{
    if (is_int($a) !== is_int($b)) {
        return is_int($a) ? -1 : 1;
    }
    return is_int($a) ? $a <=> $b : strcmp($a, $b);
}

function tupleCompare(array $a, array $b): int
{
    foreach ($a as $i => $value) {
        $comparison = valueCompare($value, $b[$i]);
        if ($comparison !== 0) {
            return $comparison;
        }
    }
    return 0;
}

function tupleKey(array $tuple): string
{
    return json_encode($tuple);
}

function termText(array $term, ?array $environment = null): string
{
    return match ($term[0]) {
        'constant' => valueText($term[1]),
        'variable' => $environment === null ? $term[1] : valueText($environment[$term[1]]),
        'anonymous' => '_'
    };
}

function atomText(Atom $atom, ?array $environment = null): string
{
    return $atom->name . ($atom->terms === [] ? '' : '(' . implode(', ', array_map(fn($term) => termText($term, $environment), $atom->terms)) . ')');
}

function tupleText(string $name, array $tuple): string
{
    return atomText(new Atom($name, array_map(fn($value) => ['constant', $value], $tuple)));
}

function expressionText(array $expression, ?array $environment = null): string
{
    return match ($expression[0]) {
        'term' => termText($expression[1], $environment),
        'group' => '(' . expressionText($expression[1], $environment) . ')',
        'binary' => expressionText($expression[2], $environment) . ' ' . $expression[1] . ' ' . expressionText($expression[3], $environment)
    };
}

function literalText(array $literal, ?array $environment = null): string
{
    return match ($literal[0]) {
        'positive' => atomText($literal[1], $environment),
        'negative' => 'not ' . atomText($literal[1], $environment),
        'comparison' => expressionText($literal[2], $environment) . ' ' . $literal[1] . ' ' . expressionText($literal[3], $environment)
    };
}

function expressionTerms(array $expression): array
{
    return match ($expression[0]) {
        'term' => [$expression[1]],
        'group' => expressionTerms($expression[1]),
        'binary' => array_merge(expressionTerms($expression[2]), expressionTerms($expression[3]))
    };
}

function literalTerms(array $literal): array
{
    return $literal[0] === 'comparison' ? array_merge(expressionTerms($literal[2]), expressionTerms($literal[3])) : $literal[1]->terms;
}

function variableOccurrences(?Atom $head, array $body): array
{
    $terms = $head?->terms ?? [];
    foreach ($body as $literal) {
        $terms = array_merge($terms, literalTerms($literal));
    }
    return array_values(array_map(fn($term) => $term[1], array_filter($terms, fn($term) => $term[0] === 'variable')));
}

class Parser
{
    private const COMPARISONS = ['=', '!=', '<', '<=', '>', '>='];
    private const OPERATORS = ['+', '-', '*', '/', 'mod'];
    private array $tokens = [];
    private int $position = 0;

    public function __construct(string $line)
    {
        $i = 0;
        $length = strlen($line);
        while ($i < $length) {
            $c = $line[$i];
            if ($c === ' ') {
                $i++;
            } elseif ($c === '%') {
                break;
            } elseif ($c === '"') {
                $finish = strpos($line, '"', $i + 1);
                if ($finish === false) {
                    throw new DatalogError('unterminated string');
                }
                $this->tokens[] = ['string', substr($line, $i, $finish - $i + 1), substr($line, $i + 1, $finish - $i - 1)];
                $i = $finish + 1;
            } elseif (in_array(substr($line, $i, 2), [':-', '?-', '!=', '<=', '>='], true)) {
                $text = substr($line, $i, 2);
                $this->tokens[] = [$text, $text];
                $i += 2;
            } elseif (str_contains('(),.:=<>+-*/', $c)) {
                $this->tokens[] = [$c, $c];
                $i++;
            } elseif (preg_match('/[A-Za-z0-9_]/', $c)) {
                $start = $i++;
                while ($i < $length && preg_match('/[A-Za-z0-9_]/', $line[$i])) {
                    $i++;
                }
                $text = substr($line, $start, $i - $start);
                if (preg_match('/[a-z]/', $text[0])) {
                    $this->tokens[] = [in_array($text, RESERVED, true) ? $text : 'name', $text, $text];
                } elseif (preg_match('/[A-Z]/', $text[0])) {
                    $this->tokens[] = ['variable', $text, $text];
                } elseif ($text === '_') {
                    $this->tokens[] = ['anonymous', $text];
                } elseif (ctype_digit($text)) {
                    if ((int)$text > 1000000000) {
                        throw new DatalogError("integer out of range '" . $text . "'");
                    }
                    $this->tokens[] = ['integer', $text, (int)$text];
                } else {
                    throw new DatalogError("bad token '" . $text . "'");
                }
            } else {
                throw new DatalogError("bad character '" . $c . "'");
            }
        }
        $this->tokens[] = ['end', ''];
    }

    private function peek(): array
    {
        return $this->tokens[$this->position];
    }

    private function advance(): array
    {
        return $this->tokens[$this->position++];
    }

    private function syntaxError(): never
    {
        throw new DatalogError($this->peek()[0] === 'end' ? 'syntax error at end of line' : "syntax error at '" . $this->peek()[1] . "'");
    }

    private function expect(string $kind): array
    {
        if ($this->peek()[0] !== $kind) {
            $this->syntaxError();
        }
        return $this->advance();
    }

    private function term(): array
    {
        $kind = $this->peek()[0];
        if (in_array($kind, ['name', 'string', 'integer'], true)) {
            return ['constant', $this->advance()[2]];
        }
        if ($kind === 'variable') {
            return ['variable', $this->advance()[1]];
        }
        if ($kind === 'anonymous') {
            $this->advance();
            return ['anonymous'];
        }
        if ($kind === '-') {
            $this->advance();
            return ['constant', -$this->expect('integer')[2]];
        }
        $this->syntaxError();
    }

    private function atom(): Atom
    {
        $name = $this->expect('name')[1];
        $terms = [];
        if ($this->peek()[0] === '(') {
            $this->advance();
            $terms[] = $this->term();
            while ($this->peek()[0] === ',') {
                $this->advance();
                $terms[] = $this->term();
            }
            $this->expect(')');
        }
        return new Atom($name, $terms);
    }

    private function factor(): array
    {
        if ($this->peek()[0] === '(') {
            $this->advance();
            $result = ['group', $this->expression()];
            $this->expect(')');
            return $result;
        }
        return ['term', $this->term()];
    }

    private function product(): array
    {
        $result = $this->factor();
        while (in_array($this->peek()[0], ['*', '/', 'mod'], true)) {
            $operation = $this->advance()[0];
            $result = ['binary', $operation, $result, $this->factor()];
        }
        return $result;
    }

    private function expression(): array
    {
        $result = $this->product();
        while (in_array($this->peek()[0], ['+', '-'], true)) {
            $operation = $this->advance()[0];
            $result = ['binary', $operation, $result, $this->product()];
        }
        return $result;
    }

    private function literal(): array
    {
        if ($this->peek()[0] === 'not') {
            $this->advance();
            return ['negative', $this->atom()];
        }
        if ($this->peek()[0] === 'name' && !in_array($this->tokens[$this->position + 1][0], array_merge(self::COMPARISONS, self::OPERATORS), true)) {
            return ['positive', $this->atom()];
        }
        $left = $this->expression();
        if (!in_array($this->peek()[0], self::COMPARISONS, true)) {
            $this->syntaxError();
        }
        $operation = $this->advance()[0];
        return ['comparison', $operation, $left, $this->expression()];
    }

    private function body(): array
    {
        $literals = [$this->literal()];
        while ($this->peek()[0] === ',') {
            $this->advance();
            $literals[] = $this->literal();
        }
        return $literals;
    }

    public function statement(): ?array
    {
        $kind = $this->peek()[0];
        if ($kind === 'end') {
            return null;
        }
        if ($kind === 'name') {
            $head = $this->atom();
            if ($this->peek()[0] === ':-') {
                $this->advance();
                $result = ['kind' => 'rule', 'head' => $head, 'body' => $this->body()];
            } else {
                $result = ['kind' => 'fact', 'head' => $head, 'body' => []];
            }
        } elseif ($kind === ':-') {
            $this->advance();
            $result = ['kind' => 'constraint', 'head' => null, 'body' => $this->body()];
        } elseif ($kind === '?-') {
            $this->advance();
            $aggregate = null;
            $variable = null;
            if (in_array($this->peek()[0], ['count', 'sum', 'min', 'max'], true)) {
                $aggregate = $this->advance()[0];
                if ($aggregate !== 'count') {
                    $variable = $this->expect('variable')[1];
                    $this->expect(':');
                }
            }
            $result = ['kind' => 'query', 'head' => null, 'body' => $this->body(), 'aggregate' => $aggregate, 'variable' => $variable];
        } elseif (in_array($kind, ['retract', 'why'], true)) {
            $this->advance();
            $result = ['kind' => $kind, 'atom' => $this->atom()];
        } elseif ($kind === 'dump') {
            $this->advance();
            $result = ['kind' => 'dump', 'name' => $this->expect('name')[1]];
        } elseif ($kind === 'forget') {
            $this->advance();
            $result = ['kind' => 'forget', 'number' => $this->expect('integer')[2]];
        } elseif ($kind === 'listing') {
            $this->advance();
            $result = ['kind' => 'listing', 'name' => $this->peek()[0] === 'name' ? $this->advance()[1] : null];
        } elseif (in_array($kind, ['strata', 'stats', 'check', 'predicates', 'undo', 'halt'], true)) {
            $this->advance();
            $result = ['kind' => $kind];
        } else {
            $this->syntaxError();
        }
        $this->expect('.');
        $this->expect('end');
        return $result;
    }
}

class Engine
{
    private array $arities = [];
    private array $facts = [];
    private array $rules = [];
    private array $history = [];
    private int $nextRule = 1;
    private ?array $cache = null;

    private function atoms(array $statement): array
    {
        $atoms = isset($statement['head']) ? [$statement['head']] : [];
        foreach ($statement['body'] ?? [] as $literal) {
            if ($literal[0] !== 'comparison') {
                $atoms[] = $literal[1];
            }
        }
        return $atoms;
    }

    private function predicateCheck(array $atoms, bool $clause = false): array
    {
        $prospective = $this->arities;
        foreach ($atoms as $atom) {
            if (array_key_exists($atom->name, $prospective)) {
                $expected = $prospective[$atom->name];
                if ($expected !== count($atom->terms)) {
                    throw new DatalogError('arity mismatch for ' . $atom->name . ': expected ' . $expected . ', got ' . count($atom->terms));
                }
            } elseif ($clause) {
                $prospective[$atom->name] = count($atom->terms);
            } else {
                throw new DatalogError('unknown predicate ' . $atom->name);
            }
        }
        return $prospective;
    }

    private function safety(array $statement): void
    {
        $head = $statement['head'];
        $body = $statement['body'];
        foreach ($head?->terms ?? [] as $term) {
            if ($term[0] === 'anonymous') {
                throw new DatalogError('anonymous variable in head');
            }
        }
        foreach ($body as $literal) {
            if ($literal[0] === 'comparison') {
                foreach (literalTerms($literal) as $term) {
                    if ($term[0] === 'anonymous') {
                        throw new DatalogError('anonymous variable in comparison');
                    }
                }
            }
        }
        $bound = [];
        foreach ($body as $literal) {
            if ($literal[0] === 'positive') {
                foreach ($literal[1]->terms as $term) {
                    if ($term[0] === 'variable') {
                        $bound[$term[1]] = true;
                    }
                }
            }
        }
        $required = $head?->terms ?? (isset($statement['variable']) ? [['variable', $statement['variable']]] : []);
        foreach ($body as $literal) {
            if ($literal[0] !== 'positive') {
                $required = array_merge($required, literalTerms($literal));
            }
        }
        foreach ($required as $term) {
            if ($term[0] === 'variable' && !isset($bound[$term[1]])) {
                throw new DatalogError('unsafe variable ' . $term[1]);
            }
        }
    }

    private function ruleText(array $rule): string
    {
        return ($rule['head'] === null ? ':- ' : atomText($rule['head']) . ' :- ') . implode(', ', array_map(fn($literal) => literalText($literal), $rule['body'])) . '.';
    }

    private function strata(?array $arities = null, ?array $rules = null): ?array
    {
        $arities ??= $this->arities;
        $rules ??= $this->rules;
        $levels = array_fill_keys(array_keys($arities), 0);
        for ($i = 0; $i < count($arities); $i++) {
            $changed = false;
            foreach ($rules as $rule) {
                if ($rule['head'] === null) {
                    continue;
                }
                foreach ($rule['body'] as $literal) {
                    if ($literal[0] === 'comparison') {
                        continue;
                    }
                    $level = $levels[$literal[1]->name] + ($literal[0] === 'negative' ? 1 : 0);
                    $name = $rule['head']->name;
                    if ($level > $levels[$name]) {
                        $levels[$name] = $level;
                        $changed = true;
                    }
                }
            }
            if (!$changed) {
                return $levels;
            }
        }
        return $arities === [] ? $levels : null;
    }

    private function snapshot(int $line): void
    {
        $this->history[] = [$this->arities, $this->facts, $this->rules, $line];
        $this->cache = null;
    }

    private function matchAtom(Atom $atom, array $tuple, array $environment): ?array
    {
        foreach ($atom->terms as $i => $term) {
            if ($term[0] === 'constant') {
                if ($term[1] !== $tuple[$i]) {
                    return null;
                }
            } elseif ($term[0] === 'variable') {
                if (array_key_exists($term[1], $environment) && $environment[$term[1]] !== $tuple[$i]) {
                    return null;
                }
                $environment[$term[1]] = $tuple[$i];
            }
        }
        return $environment;
    }

    private function evaluate(array $expression, array $environment): int|string|null
    {
        if ($expression[0] === 'term') {
            $term = $expression[1];
            return $term[0] === 'constant' ? $term[1] : $environment[$term[1]];
        }
        if ($expression[0] === 'group') {
            return $this->evaluate($expression[1], $environment);
        }
        $a = $this->evaluate($expression[2], $environment);
        $b = $this->evaluate($expression[3], $environment);
        if (!is_int($a) || !is_int($b)) {
            return null;
        }
        if (($expression[1] === '/' || $expression[1] === 'mod') && $b === 0) {
            return null;
        }
        if ($expression[1] === '/' || $expression[1] === 'mod') {
            $q = intdiv($a, $b);
            $r = $a % $b;
            if ($r !== 0 && (($a < 0) !== ($b < 0))) {
                $q--;
                $r += $b;
            }
            return $expression[1] === '/' ? $q : $r;
        }
        return match ($expression[1]) {
            '+' => $a + $b, '-' => $a - $b, '*' => $a * $b
        };
    }

    private function comparison(array $literal, array $environment): bool
    {
        $a = $this->evaluate($literal[2], $environment);
        $b = $this->evaluate($literal[3], $environment);
        if ($a === null || $b === null) {
            return false;
        }
        if ($literal[1] === '=') {
            return $a === $b;
        }
        if ($literal[1] === '!=') {
            return $a !== $b;
        }
        if (!is_int($a) || !is_int($b)) {
            return false;
        }
        return match ($literal[1]) {
            '<' => $a < $b, '<=' => $a <= $b, '>' => $a > $b, '>=' => $a >= $b
        };
    }

    private function solutions(array $body, array $data, ?array $metadata = null, ?int $before = null): array
    {
        $positives = array_values(array_filter($body, fn($literal) => $literal[0] === 'positive'));
        $boundAt = [];
        foreach ($positives as $i => $literal) {
            foreach ($literal[1]->terms as $term) {
                if ($term[0] === 'variable' && !isset($boundAt[$term[1]])) {
                    $boundAt[$term[1]] = $i + 1;
                }
            }
        }
        $filters = array_fill(0, count($positives) + 1, []);
        foreach ($body as $literal) {
            if ($literal[0] === 'positive') {
                continue;
            }
            $stage = 0;
            foreach (literalTerms($literal) as $term) {
                if ($term[0] === 'variable') {
                    $stage = max($stage, $boundAt[$term[1]]);
                }
            }
            $filters[$stage][] = $literal;
        }
        $sources = [];
        foreach ($positives as $literal) {
            $atom = $literal[1];
            $tuples = [];
            foreach ($data[$atom->name] as $key => $tuple) {
                if ($before === null || $metadata[$atom->name][$key][0] < $before) {
                    $tuples[] = $tuple;
                }
            }
            $sources[] = $tuples;
        }
        $variables = array_values(array_unique(variableOccurrences(null, $body)));
        $results = [];
        $visit = function (int $stage, array $environment) use (&$visit, $positives, $sources, $filters, $variables, $data, &$results): void {
            foreach ($filters[$stage] as $literal) {
                if ($literal[0] === 'negative') {
                    foreach ($data[$literal[1]->name] as $tuple) {
                        if ($this->matchAtom($literal[1], $tuple, $environment) !== null) {
                            return;
                        }
                    }
                } elseif ($literal[0] === 'comparison' && !$this->comparison($literal, $environment)) {
                    return;
                }
            }
            if ($stage === count($positives)) {
                $key = tupleKey(array_map(fn($name) => $environment[$name], $variables));
                $results[$key] = $environment;
                return;
            }
            $atom = $positives[$stage][1];
            $seen = [];
            foreach ($sources[$stage] as $tuple) {
                $matched = $this->matchAtom($atom, $tuple, $environment);
                if ($matched === null) {
                    continue;
                }
                ksort($matched, SORT_STRING);
                $key = json_encode($matched);
                if (isset($seen[$key])) {
                    continue;
                }
                $seen[$key] = true;
                $visit($stage + 1, $matched);
            }
        };
        $visit(0, []);
        $environments = array_values($results);
        usort($environments, fn($a, $b) => tupleCompare(array_map(fn($name) => $a[$name], $variables), array_map(fn($name) => $b[$name], $variables)));
        return $environments;
    }

    private function headTuple(Atom $atom, array $environment): array
    {
        return array_map(fn($term) => $term[0] === 'constant' ? $term[1] : $environment[$term[1]], $atom->terms);
    }

    private function model(): array
    {
        if ($this->cache !== null) {
            return $this->cache;
        }
        $levels = $this->strata();
        $data = [];
        $metadata = [];
        foreach ($this->arities as $name => $arity) {
            $data[$name] = $this->facts[$name] ?? [];
            $metadata[$name] = [];
            foreach ($data[$name] as $key => $tuple) {
                $metadata[$name][$key] = [0, null];
            }
        }
        $rounds = [];
        $added = [];
        $serial = 0;
        $max = $levels === [] ? -1 : max($levels);
        for ($level = 0; $level <= $max; $level++) {
            $rounds[$level] = 0;
            $added[$level] = 0;
            while (true) {
                $fresh = [];
                foreach ($this->rules as $rule) {
                    if ($rule['head'] === null || $levels[$rule['head']->name] !== $level) {
                        continue;
                    }
                    $name = $rule['head']->name;
                    foreach ($this->solutions($rule['body'], $data) as $environment) {
                        $tuple = $this->headTuple($rule['head'], $environment);
                        $key = tupleKey($tuple);
                        if (!isset($data[$name][$key]) && !isset($fresh[$name][$key])) {
                            $fresh[$name][$key] = [$tuple, $rule['number']];
                        }
                    }
                }
                if ($fresh === []) {
                    break;
                }
                $serial++;
                $rounds[$level]++;
                foreach ($fresh as $name => $entries) {
                    $added[$level] += count($entries);
                    foreach ($entries as $key => [$tuple, $rule]) {
                        $data[$name][$key] = $tuple;
                        $metadata[$name][$key] = [$serial, $rule];
                    }
                }
            }
        }
        return $this->cache = [$data, $metadata, $levels, $rounds, $added];
    }

    private function answers(array $body, array $data): array
    {
        $variables = array_values(array_unique(variableOccurrences(null, $body)));
        $tuples = [];
        foreach ($this->solutions($body, $data) as $environment) {
            $tuple = array_map(fn($name) => $environment[$name], $variables);
            $tuples[tupleKey($tuple)] = $tuple;
        }
        $tuples = array_values($tuples);
        usort($tuples, 'tupleCompare');
        return [$variables, $tuples];
    }

    private function answerText(array $variables, array $tuple): string
    {
        $parts = [];
        foreach ($variables as $i => $name) {
            $parts[] = $name . ' = ' . valueText($tuple[$i]);
        }
        return implode(', ', $parts);
    }

    private function proof(string $name, array $tuple, array $data, array $metadata, int $depth = 0): array
    {
        $indent = str_repeat('  ', $depth);
        $serial = $metadata[$name][tupleKey($tuple)][0];
        if ($serial === 0) {
            return [$indent . tupleText($name, $tuple) . ' [fact]'];
        }
        $chosenRule = null;
        $chosen = null;
        foreach ($this->rules as $rule) {
            if ($rule['head'] === null || $rule['head']->name !== $name) {
                continue;
            }
            $variables = array_values(array_unique(variableOccurrences($rule['head'], $rule['body'])));
            $candidates = array_values(array_filter($this->solutions($rule['body'], $data, $metadata, $serial), fn($environment) => $this->headTuple($rule['head'], $environment) === $tuple));
            if ($candidates === []) {
                continue;
            }
            usort($candidates, fn($a, $b) => tupleCompare(array_map(fn($variable) => $a[$variable], $variables), array_map(fn($variable) => $b[$variable], $variables)));
            $chosenRule = $rule;
            $chosen = $candidates[0];
            break;
        }
        $lines = [$indent . tupleText($name, $tuple) . ' [rule ' . $chosenRule['number'] . ']'];
        foreach ($chosenRule['body'] as $literal) {
            if ($literal[0] === 'positive') {
                $atom = $literal[1];
                $matched = [];
                foreach ($data[$atom->name] as $key => $item) {
                    if ($metadata[$atom->name][$key][0] < $serial && $this->matchAtom($atom, $item, $chosen) !== null) {
                        $matched[] = $item;
                    }
                }
                usort($matched, 'tupleCompare');
                $lines = array_merge($lines, $this->proof($atom->name, $matched[0], $data, $metadata, $depth + 1));
            } else {
                $lines[] = $indent . '  ' . literalText($literal, $chosen);
            }
        }
        return $lines;
    }

    public function execute(array $statement, int $line): array|string
    {
        $kind = $statement['kind'];
        if ($kind === 'halt') {
            return 'halt';
        }
        if (in_array($kind, ['fact', 'rule', 'constraint'], true)) {
            $prospective = $this->predicateCheck($this->atoms($statement), true);
            $this->safety($statement);
            if ($kind === 'fact') {
                $atom = $statement['head'];
                $tuple = $this->headTuple($atom, []);
                $key = tupleKey($tuple);
                if (isset($this->facts[$atom->name][$key])) {
                    return [];
                }
                $this->snapshot($line);
                $this->arities = $prospective;
                $this->facts[$atom->name][$key] = $tuple;
                return [];
            }
            $notation = $this->ruleText($statement);
            foreach ($this->rules as $rule) {
                if ($rule['notation'] === $notation) {
                    throw new DatalogError('duplicate of rule ' . $rule['number']);
                }
            }
            if ($kind === 'rule' && $this->strata($prospective, array_merge($this->rules, [$statement])) === null) {
                throw new DatalogError('negative cycle through ' . $statement['head']->name);
            }
            $this->snapshot($line);
            $statement['number'] = $this->nextRule++;
            $statement['notation'] = $notation;
            $this->rules[] = $statement;
            $this->arities = $prospective;
            $occurrences = variableOccurrences($statement['head'], $statement['body']);
            $counts = array_count_values($occurrences);
            $lines = [];
            foreach (array_unique($occurrences) as $name) {
                if ($counts[$name] === 1) {
                    $lines[] = 'WARNING line ' . $line . ': singleton variable ' . $name;
                }
            }
            return $lines;
        }
        switch ($kind) {
            case 'query':
                $this->predicateCheck($this->atoms($statement));
                $this->safety($statement);
                [$variables, $tuples] = $this->answers($statement['body'], $this->model()[0]);
                $aggregate = $statement['aggregate'];
                if ($aggregate === 'count') {
                    return [(string)count($tuples)];
                }
                if (in_array($aggregate, ['sum', 'min', 'max'], true)) {
                    $position = array_search($statement['variable'], $variables, true);
                    $values = array_map(fn($tuple) => $tuple[$position], $tuples);
                    if ($aggregate === 'sum') {
                        foreach ($values as $value) {
                            if (!is_int($value)) {
                                throw new DatalogError('non-integer value in sum');
                            }
                        }
                        return [(string)array_sum($values)];
                    }
                    if ($values === []) {
                        return ['no answers'];
                    }
                    usort($values, 'valueCompare');
                    return [valueText($aggregate === 'min' ? $values[0] : $values[array_key_last($values)])];
                }
                if ($variables === []) {
                    return [$tuples === [] ? 'false.' : 'true.'];
                }
                $lines = array_map(fn($tuple) => $this->answerText($variables, $tuple), $tuples);
                $lines[] = count($tuples) . (count($tuples) === 1 ? ' answer' : ' answers');
                return $lines;
            case 'retract':
            case 'why':
                $atom = $statement['atom'];
                $this->predicateCheck([$atom]);
                if ($kind === 'retract') {
                    $removed = [];
                    foreach ($this->facts[$atom->name] ?? [] as $key => $tuple) {
                        if ($this->matchAtom($atom, $tuple, []) !== null) {
                            $removed[] = $key;
                        }
                    }
                    if ($removed === []) {
                        throw new DatalogError('no matching facts');
                    }
                    $this->snapshot($line);
                    foreach ($removed as $key) {
                        unset($this->facts[$atom->name][$key]);
                    }
                    return [count($removed) . (count($removed) === 1 ? ' fact retracted' : ' facts retracted')];
                }
                foreach ($atom->terms as $term) {
                    if ($term[0] !== 'constant') {
                        throw new DatalogError('why needs a ground atom');
                    }
                }
                $tuple = $this->headTuple($atom, []);
                [$data, $metadata] = $this->model();
                return isset($data[$atom->name][tupleKey($tuple)]) ? $this->proof($atom->name, $tuple, $data, $metadata) : ['false.'];
            case 'dump':
                $name = $statement['name'];
                if (!array_key_exists($name, $this->arities)) {
                    throw new DatalogError('unknown predicate ' . $name);
                }
                $tuples = array_values($this->model()[0][$name]);
                usort($tuples, 'tupleCompare');
                $lines = array_map(fn($tuple) => tupleText($name, $tuple) . '.', $tuples);
                $lines[] = count($tuples) . (count($tuples) === 1 ? ' tuple' : ' tuples');
                return $lines;
            case 'forget':
                $index = null;
                foreach ($this->rules as $i => $rule) {
                    if ($rule['number'] === $statement['number']) {
                        $index = $i;
                        break;
                    }
                }
                if ($index === null) {
                    throw new DatalogError('no rule ' . $statement['number']);
                }
                $this->snapshot($line);
                array_splice($this->rules, $index, 1);
                return [];
            case 'undo':
                if ($this->history === []) {
                    throw new DatalogError('nothing to undo');
                }
                [$this->arities, $this->facts, $this->rules, $original] = array_pop($this->history);
                $this->cache = null;
                return ['undid line ' . $original];
            case 'listing':
                $name = $statement['name'];
                if ($name !== null && !array_key_exists($name, $this->arities)) {
                    throw new DatalogError('unknown predicate ' . $name);
                }
                $rules = array_filter($this->rules, fn($rule) => $name === null || $rule['head']?->name === $name);
                return $rules === [] ? ['no rules'] : array_values(array_map(fn($rule) => $rule['number'] . ': ' . $rule['notation'], $rules));
            case 'strata':
                if ($this->arities === []) {
                    return ['no predicates'];
                }
                $levels = $this->strata();
                $dependencies = array_fill_keys(array_keys($this->arities), []);
                foreach ($this->rules as $rule) {
                    if ($rule['head'] !== null) {
                        foreach (array_slice($this->atoms($rule), 1) as $atom) {
                            $dependencies[$rule['head']->name][] = $atom->name;
                        }
                    }
                }
                $recursive = [];
                foreach ($dependencies as $name => $edges) {
                    $seen = [];
                    $search = function (string $current) use (&$search, &$seen, $dependencies, $name): bool {
                        foreach ($dependencies[$current] as $next) {
                            if ($next === $name) {
                                return true;
                            }
                            if (!isset($seen[$next])) {
                                $seen[$next] = true;
                                if ($search($next)) {
                                    return true;
                                }
                            }
                        }
                        return false;
                    };
                    $recursive[$name] = $search($name);
                }
                $lines = [];
                for ($level = 0; $level <= max($levels); $level++) {
                    $names = array_keys(array_filter($levels, fn($value) => $value === $level));
                    sort($names, SORT_STRING);
                    $lines[] = 'stratum ' . $level . ': ' . implode(', ', array_map(fn($name) => $name . ($recursive[$name] ? '*' : ''), $names));
                }
                return $lines;
            case 'stats':
                [$data, $metadata, $levels, $rounds, $added] = $this->model();
                $rules = array_values(array_filter($this->rules, fn($rule) => $rule['head'] !== null));
                $lines = ['facts ' . array_sum(array_map('count', $this->facts)) . ', rules ' . count($rules) . ', constraints ' . (count($this->rules) - count($rules)) . ', tuples ' . array_sum(array_map('count', $data))];
                for ($level = 0, $max = $levels === [] ? -1 : max($levels); $level <= $max; $level++) {
                    $lines[] = 'stratum ' . $level . ': rounds ' . $rounds[$level] . ', new ' . $added[$level];
                }
                foreach ($rules as $rule) {
                    $count = 0;
                    foreach ($metadata as $entries) {
                        foreach ($entries as [$serial, $number]) {
                            $count += (int)($number === $rule['number']);
                        }
                    }
                    $lines[] = 'rule ' . $rule['number'] . ': new ' . $count;
                }
                return $lines;
            case 'predicates':
                if ($this->arities === []) {
                    return ['no predicates'];
                }
                $data = $this->model()[0];
                $names = array_keys($this->arities);
                sort($names, SORT_STRING);
                $lines = [];
                foreach ($names as $name) {
                    $count = count(array_filter($this->rules, fn($rule) => $rule['head']?->name === $name));
                    $lines[] = $name . '/' . $this->arities[$name] . ': facts ' . count($this->facts[$name] ?? []) . ', rules ' . $count . ', tuples ' . count($data[$name]);
                }
                return $lines;
            case 'check':
                $constraints = array_values(array_filter($this->rules, fn($rule) => $rule['head'] === null));
                if ($constraints === []) {
                    return ['no constraints'];
                }
                $data = $this->model()[0];
                $lines = [];
                foreach ($constraints as $rule) {
                    [$variables, $tuples] = $this->answers($rule['body'], $data);
                    if ($tuples === []) {
                        $lines[] = 'constraint ' . $rule['number'] . ': ok';
                    } else {
                        $lines[] = 'constraint ' . $rule['number'] . ': ' . count($tuples) . (count($tuples) === 1 ? ' violation' : ' violations');
                        if ($variables !== []) {
                            foreach ($tuples as $tuple) {
                                $lines[] = '  ' . $this->answerText($variables, $tuple);
                            }
                        }
                    }
                }
                return $lines;
        }
        return [];
    }

    public function run(): void
    {
        $number = 0;
        while (($input = fgets(STDIN)) !== false) {
            $number++;
            $line = str_ends_with($input, "\n") ? substr($input, 0, -1) : $input;
            try {
                $statement = (new Parser($line))->statement();
                if ($statement === null) {
                    continue;
                }
                $output = $this->execute($statement, $number);
                if ($output === 'halt') {
                    break;
                }
                foreach ($output as $text) {
                    echo $text, "\n";
                }
            } catch (DatalogError $error) {
                echo 'ERROR line ', $number, ': ', $error->getMessage(), "\n";
            }
        }
    }
}

(new Engine())->run();
