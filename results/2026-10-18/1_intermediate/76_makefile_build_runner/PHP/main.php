<?php
class MakeError extends Exception
{
    public function __construct(string $reason, public string $location)
    {
        parent::__construct($reason);
    }
}

class BuildAbort extends Exception
{
}

class Recipe
{
    public array $lines = [];
}

class Rule
{
    public ?Recipe $recipe = null;
    public string $stem = '';

    public function __construct(public string $target, public array $prerequisites = [])
    {
    }
}

class MakeWorkbench
{
    private const FUNCTIONS = [
        'subst' => [3, 3], 'patsubst' => [3, 3], 'strip' => [1, 1],
        'findstring' => [2, 2], 'filter' => [2, 2], 'filter-out' => [2, 2],
        'sort' => [1, 1], 'word' => [2, 2], 'wordlist' => [3, 3],
        'words' => [1, 1], 'firstword' => [1, 1], 'lastword' => [1, 1],
        'dir' => [1, 1], 'notdir' => [1, 1], 'suffix' => [1, 1],
        'basename' => [1, 1], 'addsuffix' => [2, 2], 'addprefix' => [2, 2],
        'wildcard' => [1, 1], 'foreach' => [3, 3], 'if' => [2, 3],
        'call' => [1, null], 'value' => [1, 1], 'info' => [1, 1],
        'warning' => [1, 1], 'error' => [1, 1]
    ];
    private int $clock;
    private bool $loaded = false;
    private array $variables = [];
    private array $rules = [];
    private array $patterns = [];
    private array $phony = [];
    private ?string $default = null;
    private string $location = 'make';
    private array $scopes = [];
    private array $activeVariables = [];
    private ?array $automatic = null;

    public function __construct(private array $files)
    {
        $this->clock = $files === [] ? 0 : max($files);
    }

    private function trim(string $text): string
    {
        return trim($text, ' ');
    }

    private function words(string $text): array
    {
        return array_values(array_filter(explode(' ', $text), fn($word) => $word !== ''));
    }

    private function error(string $reason): never
    {
        throw new MakeError($reason, $this->location);
    }

    private function report(MakeError $error): void
    {
        echo $error->location, ': *** ', $error->getMessage(), ".  Stop.\n";
    }

    private function clearMakefile(): void
    {
        $this->loaded = false;
        $this->variables = $this->rules = $this->patterns = $this->phony = [];
        $this->default = null;
    }

    private function closing(string $text, int $opening): int
    {
        $left = $text[$opening];
        $right = $left === '(' ? ')' : '}';
        $depth = 0;
        for ($i = $opening; $i < strlen($text); $i++) {
            if ($text[$i] === $left) {
                $depth++;
            }
            if ($text[$i] === $right) {
                $depth--;
            }
            if ($depth === 0) {
                return $i;
            }
        }
        $this->error('unterminated variable reference');
    }

    private function outside(string $text): array
    {
        $result = [];
        for ($i = 0; $i < strlen($text);) {
            if ($text[$i] === '$') {
                $next = $text[$i + 1] ?? '';
                $i = $next === '(' || $next === '{' ? $this->closing($text, $i + 1) + 1 : $i + 2;
            } else {
                if (!array_key_exists($text[$i], $result)) {
                    $result[$text[$i]] = $i;
                }
                $i++;
            }
        }
        return $result;
    }

    private function stem(string $pattern, string $text): ?string
    {
        $percent = strpos($pattern, '%');
        if ($percent === false) {
            return $pattern === $text ? '' : null;
        }
        $left = substr($pattern, 0, $percent);
        $right = substr($pattern, $percent + 1);
        if (strlen($text) < strlen($left) + strlen($right) || !str_starts_with($text, $left) || !str_ends_with($text, $right)) {
            return null;
        }
        return substr($text, strlen($left), strlen($text) - strlen($left) - strlen($right));
    }

    private function substitute(string $text, string $value): string
    {
        $position = strpos($text, '%');
        return $position === false ? $text : substr($text, 0, $position) . $value . substr($text, $position + 1);
    }

    private function replace(string $word, string $pattern, string $replacement): string
    {
        $value = $this->stem($pattern, $word);
        if ($value === null) {
            return $word;
        }
        return str_contains($pattern, '%') ? $this->substitute($replacement, $value) : $replacement;
    }

    private function wildcard(string $pattern): array
    {
        if (!str_contains($pattern, '*') && !str_contains($pattern, '?')) {
            return array_key_exists($pattern, $this->files) ? [$pattern] : [];
        }
        $regex = '~\A' . str_replace(['\\*', '\\?'], ['[^/]*', '[^/]'], preg_quote($pattern, '~')) . '\z~D';
        $result = [];
        foreach (array_keys($this->files) as $name) {
            if (preg_match($regex, (string)$name)) {
                $result[] = (string)$name;
            }
        }
        sort($result, SORT_STRING);
        return $result;
    }

    private function referenceValue(string $name): string
    {
        for ($i = count($this->scopes) - 1; $i >= 0; $i--) {
            $scope = $this->scopes[$i];
            if ($scope[0] === 'foreach') {
                if ($scope[1] === $name) {
                    return $scope[2];
                }
            } elseif (preg_match('/\A[0-9]+\z/D', $name)) {
                return $scope[1][(int)$name] ?? '';
            }
        }
        if ($this->automatic !== null && array_key_exists($name, $this->automatic)) {
            return $this->automatic[$name];
        }
        return $this->variableValue($name);
    }

    private function variableValue(string $name): string
    {
        $variable = $this->variables[$name] ?? null;
        if ($variable === null) {
            return '';
        }
        if ($variable[0] === ':=') {
            return $variable[1];
        }
        if (isset($this->activeVariables[$name])) {
            $this->error("Recursive variable '$name' references itself (eventually)");
        }
        $this->activeVariables[$name] = true;
        try {
            return $this->expand($variable[1]);
        } finally {
            unset($this->activeVariables[$name]);
        }
    }

    private function expand(string $text): string
    {
        $result = '';
        for ($i = 0; $i < strlen($text);) {
            $next = $text[$i + 1] ?? '';
            if ($text[$i] !== '$') {
                $result .= $text[$i++];
            } elseif ($next === '$') {
                $result .= '$';
                $i += 2;
            } elseif ($next === '(' || $next === '{') {
                $finish = $this->closing($text, $i + 1);
                $result .= $this->reference(substr($text, $i + 2, $finish - $i - 2), $next);
                $i = $finish + 1;
            } else {
                if ($next !== '') {
                    $result .= $this->referenceValue($next);
                }
                $i += 2;
            }
        }
        return $result;
    }

    private function reference(string $content, string $bracket): string
    {
        $space = strpos($content, ' ');
        if ($space !== false && isset(self::FUNCTIONS[substr($content, 0, $space)])) {
            return $this->applyFunction(substr($content, 0, $space), ltrim(substr($content, $space + 1), ' '), $bracket);
        }
        $name = $this->expand($content);
        $colon = strpos($name, ':');
        $equals = $colon === false ? false : strpos($name, '=', $colon + 1);
        if ($equals === false) {
            return $this->referenceValue($name);
        }
        $variable = substr($name, 0, $colon);
        $pattern = substr($name, $colon + 1, $equals - $colon - 1);
        $replacement = substr($name, $equals + 1);
        if (!str_contains($pattern, '%')) {
            $pattern = '%' . $pattern;
            $replacement = '%' . $replacement;
        }
        return implode(' ', array_map(fn($word) => $this->replace($word, $pattern, $replacement), $this->words($this->referenceValue($variable))));
    }

    private function applyFunction(string $name, string $text, string $bracket): string
    {
        [$minimum, $maximum] = self::FUNCTIONS[$name];
        $args = [];
        $depth = $start = 0;
        $close = $bracket === '(' ? ')' : '}';
        for ($i = 0; $i < strlen($text); $i++) {
            if ($text[$i] === $bracket) {
                $depth++;
            }
            if ($text[$i] === $close) {
                $depth--;
            }
            if ($text[$i] === ',' && $depth === 0 && ($maximum === null || count($args) < $maximum - 1)) {
                $args[] = substr($text, $start, $i - $start);
                $start = $i + 1;
            }
        }
        $args[] = substr($text, $start);
        if (count($args) < $minimum) {
            $this->error('insufficient number of arguments (' . count($args) . ") to function '$name'");
        }
        if ($name === 'foreach') {
            $variable = $this->trim($this->expand($args[0]));
            $list = $this->words($this->expand($args[1]));
            $result = [];
            foreach ($list as $word) {
                $this->scopes[] = ['foreach', $variable, $word];
                try {
                    $result[] = $this->expand($args[2]);
                } finally {
                    array_pop($this->scopes);
                }
            }
            return implode(' ', $result);
        }
        if ($name === 'if') {
            $condition = $this->trim($this->expand($args[0]));
            return $this->expand($condition === '' ? ($args[2] ?? '') : $args[1]);
        }
        if ($name === 'call') {
            $values = array_map(fn($arg) => $this->expand($arg), $args);
            $variable = $this->trim(array_shift($values));
            $entry = $this->variables[$variable] ?? null;
            if ($entry === null) {
                return '';
            }
            if ($entry[0] === ':=') {
                return $entry[1];
            }
            $this->scopes[] = ['call', array_merge([$variable], $values)];
            try {
                return $this->expand($entry[1]);
            } finally {
                array_pop($this->scopes);
            }
        }
        $values = array_map(fn($arg) => $this->expand($arg), $args);
        if ($name !== 'subst') {
            $values = array_map(fn($arg) => $this->trim($arg), $values);
        }
        $a = $values[0];
        $b = $values[1] ?? '';
        $c = $values[2] ?? '';
        switch ($name) {
            case 'subst':
                return $a === '' ? $c : str_replace($a, $b, $c);
            case 'patsubst':
                return implode(' ', array_map(fn($word) => $this->replace($word, $a, $b), $this->words($c)));
            case 'strip':
                return implode(' ', $this->words($a));
            case 'findstring':
                return str_contains($b, $a) ? $a : '';
            case 'filter':
            case 'filter-out':
                $patterns = $this->words($a);
                $result = [];
                foreach ($this->words($b) as $word) {
                    $matches = false;
                    foreach ($patterns as $pattern) {
                        if ($this->stem($pattern, $word) !== null) {
                            $matches = true;
                            break;
                        }
                    }
                    if ($matches === ($name === 'filter')) {
                        $result[] = $word;
                    }
                }
                return implode(' ', $result);
            case 'sort':
                $result = array_values(array_unique($this->words($a), SORT_STRING));
                sort($result, SORT_STRING);
                return implode(' ', $result);
            case 'word':
                if (!preg_match('/\A[0-9]+\z/D', $a)) {
                    $this->error("non-numeric first argument to 'word' function: '$a'");
                }
                if ((int)$a === 0) {
                    $this->error("first argument to 'word' function must be greater than 0");
                }
                return $this->words($b)[(int)$a - 1] ?? '';
            case 'wordlist':
                if (!preg_match('/\A[0-9]+\z/D', $a)) {
                    $this->error("non-numeric first argument to 'wordlist' function: '$a'");
                }
                if (!preg_match('/\A[0-9]+\z/D', $b)) {
                    $this->error("non-numeric second argument to 'wordlist' function: '$b'");
                }
                if ((int)$a === 0) {
                    $this->error("invalid first argument to 'wordlist' function: '$a'");
                }
                return (int)$b < (int)$a ? '' : implode(' ', array_slice($this->words($c), (int)$a - 1, (int)$b - (int)$a + 1));
            case 'words':
                return (string)count($this->words($a));
            case 'firstword':
                return $this->words($a)[0] ?? '';
            case 'lastword':
                $list = $this->words($a);
                return $list === [] ? '' : $list[count($list) - 1];
            case 'dir':
            case 'notdir':
            case 'suffix':
            case 'basename':
                $result = [];
                foreach ($this->words($a) as $word) {
                    $slash = strrpos($word, '/');
                    $dot = strrpos($word, '.');
                    $extension = $dot !== false && ($slash === false || $dot > $slash);
                    if ($name === 'dir') {
                        $result[] = $slash === false ? './' : substr($word, 0, $slash + 1);
                    } elseif ($name === 'notdir') {
                        $result[] = $slash === false ? $word : substr($word, $slash + 1);
                    } elseif ($name === 'basename') {
                        $result[] = $extension ? substr($word, 0, $dot) : $word;
                    } elseif ($extension) {
                        $result[] = substr($word, $dot);
                    }
                }
                return implode(' ', $result);
            case 'addsuffix':
                return implode(' ', array_map(fn($word) => $word . $a, $this->words($b)));
            case 'addprefix':
                return implode(' ', array_map(fn($word) => $a . $word, $this->words($b)));
            case 'wildcard':
                $result = [];
                foreach ($this->words($a) as $pattern) {
                    $result = array_merge($result, $this->wildcard($pattern));
                }
                return implode(' ', $result);
            case 'value':
                return $this->variables[$a][1] ?? '';
            case 'info':
                echo $a, "\n";
                return '';
            case 'warning':
                echo $this->location, ': ', $a, "\n";
                return '';
            case 'error':
                $this->error($a);
        }
        return '';
    }

    private function register(string $target, array $prerequisites): Rule
    {
        if (!isset($this->rules[$target])) {
            $this->rules[$target] = new Rule($target);
        }
        $rule = $this->rules[$target];
        $rule->prerequisites = array_values(array_unique(array_merge($rule->prerequisites, $prerequisites), SORT_STRING));
        if ($this->default === null && !str_starts_with($target, '.')) {
            $this->default = $target;
        }
        return $rule;
    }

    private function addRecipe(?array &$current, int $number, string $text): void
    {
        if ($current === null) {
            $this->error('recipe commences before first target');
        }
        if ($current['entries'] === []) {
            return;
        }
        if ($current['recipe'] === null) {
            $recipe = new Recipe();
            foreach ($current['entries'] as $rule) {
                if ($current['explicit'] && $rule->recipe !== null) {
                    echo "Makefile:$number: warning: overriding recipe for target '{$rule->target}'\n";
                    echo 'Makefile:', $rule->recipe->lines[0][0], ": warning: ignoring old recipe for target '{$rule->target}'\n";
                }
                $rule->recipe = $recipe;
            }
            $current['recipe'] = $recipe;
        }
        $current['recipe']->lines[] = [$number, $text];
    }

    private function parseRule(string $text, int $colon, int $number): array
    {
        $targets = array_values(array_unique($this->words($this->expand(substr($text, 0, $colon))), SORT_STRING));
        $rest = substr($text, $colon + 1);
        $semicolon = $this->outside($rest)[';'] ?? null;
        $inline = $semicolon === null ? null : ltrim(substr($rest, $semicolon + 1), ' ');
        if ($semicolon !== null) {
            $rest = substr($rest, 0, $semicolon);
        }
        $second = $this->outside($rest)[':'] ?? null;
        $pattern = $second === null ? null : $this->trim($this->expand(substr($rest, 0, $second)));
        if ($second !== null) {
            $rest = substr($rest, $second + 1);
        }
        $prerequisites = $this->words($this->expand($rest));
        $entries = [];
        $explicit = true;
        if ($targets === ['.PHONY']) {
            foreach ($prerequisites as $target) {
                $this->phony[$target] = true;
            }
        } elseif ($pattern !== null) {
            if (!str_contains($pattern, '%')) {
                $this->error("target pattern contains no '%'");
            }
            foreach ($targets as $target) {
                $value = $this->stem($pattern, $target);
                if ($value !== null && $value !== '') {
                    $entry = $this->register($target, array_map(fn($p) => $this->substitute($p, $value), $prerequisites));
                    $entry->stem = $value;
                    $entries[] = $entry;
                } else {
                    echo "Makefile:$number: target '$target' doesn't match the target pattern\n";
                }
            }
        } else {
            $patternTargets = array_filter($targets, fn($target) => str_contains($target, '%'));
            if ($patternTargets !== []) {
                if (count($patternTargets) !== count($targets)) {
                    $this->error('mixed implicit and normal rules');
                }
                $explicit = false;
                foreach ($targets as $target) {
                    $entry = new Rule($target, $prerequisites);
                    $this->patterns[] = $entry;
                    $entries[] = $entry;
                }
            } else {
                foreach ($targets as $target) {
                    $entries[] = $this->register($target, $prerequisites);
                }
            }
        }
        $current = ['entries' => $entries, 'explicit' => $explicit, 'recipe' => null];
        if ($inline !== null) {
            $this->addRecipe($current, $number, $inline);
        }
        return $current;
    }

    private function loadMakefile(array $body): void
    {
        $this->clearMakefile();
        $current = null;
        $conditions = [];
        try {
            for ($i = 0; $i < count($body);) {
                $number = $i + 1;
                $this->location = "Makefile:$number";
                $top = $conditions === [] ? null : $conditions[count($conditions) - 1];
                $active = $top === null || ($top['outer'] && $top['value']);
                $text = $body[$i++];
                if (str_starts_with($text, '>')) {
                    if ($active) {
                        $this->addRecipe($current, $number, ltrim(substr($text, 1), ' '));
                    }
                    continue;
                }
                while (str_ends_with($text, '\\') && $i < count($body)) {
                    $text = rtrim(substr($text, 0, -1), ' ') . ' ' . ltrim($body[$i++], ' ');
                }
                $text = $this->trim(explode('#', $text, 2)[0]);
                $parts = explode(' ', $text, 2);
                $first = $parts[0];
                $rest = $this->trim($parts[1] ?? '');
                if (in_array($first, ['ifdef', 'ifndef', 'ifeq', 'ifneq'], true)) {
                    $value = false;
                    if ($active) {
                        if ($first === 'ifdef' || $first === 'ifndef') {
                            $variable = $this->variables[$this->trim($this->expand($rest))] ?? null;
                            $value = $variable !== null && $variable[1] !== '';
                            if ($first === 'ifndef') {
                                $value = !$value;
                            }
                        } else {
                            if (strlen($rest) < 2 || !str_starts_with($rest, '(') || !str_ends_with($rest, ')')) {
                                $this->error('invalid syntax in conditional');
                            }
                            $inner = substr($rest, 1, -1);
                            $depth = 0;
                            $comma = null;
                            for ($p = 0; $p < strlen($inner); $p++) {
                                if ($inner[$p] === '(') {
                                    $depth++;
                                }
                                if ($inner[$p] === ')') {
                                    $depth--;
                                }
                                if ($inner[$p] === ',' && $depth === 0) {
                                    $comma = $p;
                                    break;
                                }
                            }
                            if ($comma === null) {
                                $this->error('invalid syntax in conditional');
                            }
                            $left = $this->trim($this->expand(substr($inner, 0, $comma)));
                            $right = $this->trim($this->expand(substr($inner, $comma + 1)));
                            $value = $left === $right;
                            if ($first === 'ifneq') {
                                $value = !$value;
                            }
                        }
                    }
                    $conditions[] = ['outer' => $active, 'value' => $value, 'else' => false, 'number' => $number];
                } elseif ($first === 'else') {
                    if ($conditions === []) {
                        $this->error("extraneous 'else'");
                    }
                    $p = count($conditions) - 1;
                    if ($conditions[$p]['else']) {
                        $this->error("only one 'else' per conditional");
                    }
                    $conditions[$p]['value'] = !$conditions[$p]['value'];
                    $conditions[$p]['else'] = true;
                } elseif ($first === 'endif') {
                    if ($conditions === []) {
                        $this->error("extraneous 'endif'");
                    }
                    array_pop($conditions);
                } elseif ($active && $text !== '') {
                    $positions = $this->outside($text);
                    $equals = $positions['='] ?? null;
                    $colon = $positions[':'] ?? null;
                    if ($equals !== null && ($colon === null || $colon >= $equals - 1)) {
                        $operatorStart = $equals > 0 && in_array($text[$equals - 1], [':', '+', '?'], true) ? $equals - 1 : $equals;
                        $operator = substr($text, $operatorStart, $equals - $operatorStart + 1);
                        $variable = $this->trim(substr($text, 0, $operatorStart));
                        if ($variable === '') {
                            $this->error('empty variable name');
                        }
                        $rhs = $this->trim(substr($text, $equals + 1));
                        $old = $this->variables[$variable] ?? null;
                        if ($operator === ':=') {
                            $this->variables[$variable] = [':=', $this->expand($rhs)];
                        } elseif ($operator === '+=' && $old !== null) {
                            $addition = $old[0] === ':=' ? $this->expand($rhs) : $rhs;
                            $this->variables[$variable] = [$old[0], $old[1] === '' ? $addition : $old[1] . ' ' . $addition];
                        } elseif ($operator !== '?=' || $old === null) {
                            $this->variables[$variable] = ['=', $rhs];
                        }
                        $current = null;
                    } elseif ($colon !== null) {
                        $current = $this->parseRule($text, $colon, $number);
                    } elseif ($this->trim($this->expand($text)) !== '') {
                        $this->error('missing separator');
                    }
                }
            }
            if ($conditions !== []) {
                $this->location = 'Makefile:' . $conditions[count($conditions) - 1]['number'];
                $this->error("missing 'endif'");
            }
            $this->loaded = true;
            $patterns = count(array_filter($this->patterns, fn($rule) => $rule->recipe !== null));
            echo 'Makefile loaded: lines=', count($body), ' variables=', count($this->variables), ' targets=', count($this->rules), " patterns=$patterns goal=", $this->default ?? '(none)', "\n";
        } catch (MakeError $error) {
            $this->report($error);
            $this->clearMakefile();
        } finally {
            $this->location = 'make';
        }
    }

    private function newTime(string $name): void
    {
        $this->files[$name] = ++$this->clock;
    }

    private function removeFile(string $name, bool $forced = false): int
    {
        if (array_key_exists($name, $this->files)) {
            unset($this->files[$name]);
            return 0;
        }
        if ($forced) {
            return 0;
        }
        echo "rm: cannot remove '$name': No such file or directory\n";
        return 1;
    }

    private function determine(string $target): array
    {
        $explicit = $this->rules[$target] ?? null;
        if ($explicit !== null && $explicit->recipe !== null) {
            return [$explicit->prerequisites, $explicit->recipe, $explicit->stem, 'rule'];
        }
        if (!isset($this->phony[$target])) {
            $candidates = [];
            foreach ($this->patterns as $i => $rule) {
                $value = $rule->recipe === null ? null : $this->stem($rule->target, $target);
                if ($value !== null && $value !== '') {
                    $candidates[] = [strlen($value), $i, $rule, $value];
                }
            }
            usort($candidates, fn($a, $b) => [$a[0], $a[1]] <=> [$b[0], $b[1]]);
            foreach ($candidates as [, , $rule, $value]) {
                $prerequisites = array_map(fn($p) => $this->substitute($p, $value), $rule->prerequisites);
                $usable = true;
                foreach ($prerequisites as $p) {
                    if (!array_key_exists($p, $this->files) && !isset($this->rules[$p])) {
                        $usable = false;
                        break;
                    }
                }
                if ($usable) {
                    return [array_values(array_unique(array_merge($prerequisites, $explicit?->prerequisites ?? []), SORT_STRING)), $rule->recipe, $value, 'rule'];
                }
            }
        }
        if ($explicit !== null || isset($this->phony[$target])) {
            return [$explicit?->prerequisites ?? [], null, $explicit?->stem ?? '', 'rule'];
        }
        return [[], null, '', array_key_exists($target, $this->files) ? 'source' : 'missing'];
    }

    private function targetTime(string $target): ?int
    {
        return isset($this->phony[$target]) ? null : ($this->files[$target] ?? null);
    }

    private function simulate(string $command): int
    {
        $parts = $this->words($command);
        $first = array_shift($parts);
        if ($first === 'echo') {
            echo implode(' ', $parts), "\n";
        } elseif ($first === 'touch') {
            foreach ($parts as $name) {
                $this->newTime($name);
            }
        } elseif ($first === 'rm') {
            $forced = ($parts[0] ?? '') === '-f';
            if ($forced) {
                array_shift($parts);
            }
            $result = 0;
            foreach ($parts as $pattern) {
                $matches = $this->wildcard($pattern);
                if ($matches === []) {
                    $matches = [$pattern];
                }
                foreach ($matches as $name) {
                    $result = max($result, $this->removeFile($name, $forced));
                }
            }
            return $result;
        } elseif ($first === 'false') {
            return 1;
        } elseif ($first === 'exit') {
            return (int)($parts[0] ?? '0');
        }
        return 0;
    }

    private function runRecipe(string $target, array $prerequisites, Recipe $recipe, string $value, array $newer, array $options): string
    {
        $this->automatic = ['@' => $target, '<' => $prerequisites[0] ?? '', '^' => implode(' ', $prerequisites), '?' => implode(' ', $newer), '*' => $value];
        try {
            $expanded = [];
            foreach ($recipe->lines as [$number, $text]) {
                $this->location = "Makefile:$number";
                $expanded[] = [$number, $this->expand($text)];
            }
            foreach ($expanded as [$number, $text]) {
                $prefixLength = strspn($text, ' @-');
                $prefix = substr($text, 0, $prefixLength);
                $command = rtrim(substr($text, $prefixLength), ' ');
                if ($command === '') {
                    continue;
                }
                if (isset($options['n']) || (!str_contains($prefix, '@') && !isset($options['s']))) {
                    echo $command, "\n";
                }
                if (isset($options['n'])) {
                    continue;
                }
                $code = $this->simulate($command);
                if ($code === 0) {
                    continue;
                }
                if (str_contains($prefix, '-') || isset($options['i'])) {
                    echo "make: [Makefile:$number: $target] Error $code (ignored)\n";
                } else {
                    echo "make: *** [Makefile:$number: $target] Error $code\n";
                    if (!isset($options['k'])) {
                        throw new BuildAbort();
                    }
                    return 'failure';
                }
            }
            return 'success';
        } finally {
            $this->automatic = null;
            $this->location = 'make';
        }
    }

    private function make(string $args): void
    {
        $options = $goals = [];
        foreach ($this->words($args) as $word) {
            if (str_starts_with($word, '-')) {
                for ($i = 1; $i < strlen($word); $i++) {
                    $char = $word[$i];
                    if (!str_contains('nBkis', $char)) {
                        echo "make: invalid option -- '$char'\n";
                        return;
                    }
                    $options[$char] = true;
                }
            } else {
                $goals[] = $word;
            }
        }
        if ($goals === []) {
            if (!$this->loaded) {
                echo "make: *** No targets specified and no makefile found.  Stop.\n";
                return;
            }
            if ($this->default === null) {
                echo "make: *** No targets.  Stop.\n";
                return;
            }
            $goals = [$this->default];
        }
        $savedFiles = $this->files;
        $savedClock = $this->clock;
        $results = $used = $building = [];
        $count = 0;
        $build = function (string $target, ?string $parent) use (&$build, &$results, &$used, &$building, &$count, $options): string {
            if (isset($results[$target])) {
                return $results[$target];
            }
            [$prerequisites, $recipe, $value, $kind] = $this->determine($target);
            $used[$target] = [$recipe, $kind];
            if ($kind === 'missing') {
                $results[$target] = 'failure';
                echo "make: *** No rule to make target '$target'", $parent === null ? '' : ", needed by '$parent'", '.', isset($options['k']) ? '' : '  Stop.', "\n";
                if (!isset($options['k'])) {
                    throw new BuildAbort();
                }
                return 'failure';
            }
            if ($kind === 'source') {
                return $results[$target] = 'success';
            }
            $building[$target] = true;
            $failed = false;
            $kept = [];
            foreach ($prerequisites as $p) {
                if (isset($building[$p])) {
                    echo "make: Circular $target <- $p dependency dropped.\n";
                } else {
                    $kept[] = $p;
                    if ($build($p, $target) !== 'success') {
                        $failed = true;
                    }
                }
            }
            unset($building[$target]);
            if ($failed) {
                $result = 'dependency_failure';
            } else {
                $time = $this->targetTime($target);
                $newer = [];
                foreach ($kept as $p) {
                    $other = $this->targetTime($p);
                    if (isset($options['B']) || $time === null || $other === null || $other > $time) {
                        $newer[] = $p;
                    }
                }
                if ($recipe === null || (!isset($options['B']) && $time !== null && $newer === [])) {
                    $result = 'success';
                } else {
                    $count++;
                    $result = $this->runRecipe($target, $kept, $recipe, $value, $newer, $options);
                    if ($result === 'success' && !isset($this->phony[$target])) {
                        $this->newTime($target);
                    }
                }
            }
            return $results[$target] = $result;
        };
        try {
            foreach ($goals as $goal) {
                $before = $count;
                $result = $build($goal, null);
                if ($result === 'success' && $count === $before) {
                    echo isset($this->phony[$goal]) || $used[$goal][0] === null ? "make: Nothing to be done for '$goal'.\n" : "make: '$goal' is up to date.\n";
                } elseif ($result === 'dependency_failure') {
                    echo "make: Target '$goal' not remade because of errors.\n";
                }
            }
        } catch (BuildAbort $error) {
        } catch (MakeError $error) {
            $this->report($error);
        } finally {
            if (isset($options['n'])) {
                $this->files = $savedFiles;
                $this->clock = $savedClock;
            }
            $this->location = 'make';
            $this->automatic = null;
        }
    }

    public function execute(string $line, ?array $body = null): void
    {
        echo '$ ', $line, "\n";
        $parts = explode(' ', $line, 2);
        $command = $parts[0];
        $args = $parts[1] ?? '';
        try {
            switch ($command) {
                case 'MAKEFILE':
                    $this->loadMakefile($body);
                    break;
                case 'MAKE':
                    $this->make($args);
                    break;
                case 'TOUCH':
                    foreach ($this->words($args) as $name) {
                        $this->newTime($name);
                    }
                    break;
                case 'RM':
                    foreach ($this->words($args) as $name) {
                        $this->removeFile($name);
                    }
                    break;
                case 'FILES':
                    echo "clock {$this->clock}\n";
                    $names = array_keys($this->files);
                    sort($names, SORT_STRING);
                    foreach ($names as $name) {
                        echo $name, ' ', $this->files[$name], "\n";
                    }
                    break;
                case 'VARS':
                    if ($this->loaded) {
                        $names = array_keys($this->variables);
                        sort($names, SORT_STRING);
                        foreach ($names as $name) {
                            $value = $this->trim($this->variableValue((string)$name));
                            echo $name, ' ', $this->variables[$name][0], $value === '' ? '' : ' ' . $value, "\n";
                        }
                    }
                    break;
                case 'RULES':
                    if ($this->loaded) {
                        $names = array_keys($this->rules);
                        sort($names, SORT_STRING);
                        $rules = array_map(fn($name) => $this->rules[$name], $names);
                        $rules = array_merge($rules, array_filter($this->patterns, fn($rule) => $rule->recipe !== null));
                        foreach ($rules as $rule) {
                            echo $rule->target, ':', $rule->prerequisites === [] ? '' : ' ' . implode(' ', $rule->prerequisites), "\n";
                            foreach ($rule->recipe?->lines ?? [] as [, $text]) {
                                echo '>', $text, "\n";
                            }
                        }
                        if ($this->phony !== []) {
                            $names = array_keys($this->phony);
                            sort($names, SORT_STRING);
                            echo '.PHONY: ', implode(' ', $names), "\n";
                        }
                    }
                    break;
                case 'EXPAND':
                    $result = $this->expand($args);
                    echo '[', $result, "]\n";
                    break;
            }
        } catch (MakeError $error) {
            $this->report($error);
        }
    }
}

$lines = array_map(fn($line) => rtrim($line, "\r\n"), file('php://stdin'));
$i = 1;
$files = [];
while ($lines[$i] !== 'END FILES') {
    [$name, $time] = explode(' ', $lines[$i++]);
    $files[$name] = (int)$time;
}
$i++;
$workbench = new MakeWorkbench($files);
while ($lines[$i] !== 'QUIT') {
    $line = $lines[$i++];
    $body = null;
    if ($line === 'MAKEFILE') {
        $body = [];
        while ($lines[$i] !== 'END MAKEFILE') {
            $body[] = $lines[$i++];
        }
        $i++;
    }
    $workbench->execute($line, $body);
}
