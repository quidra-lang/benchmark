<?php
class Version
{
    public const NUMBER = '~\A(?:0|[1-9][0-9]{0,3})\z~';
    public function __construct(public array $core, public ?array $pre = null) {}

    public static function parse(string $text): ?Version
    {
        if (!preg_match('~\A(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})(?:-([a-z0-9]+(?:\.[a-z0-9]+)*))?\z~', $text, $m)) {
            return null;
        }
        $pre = isset($m[4]) ? explode('.', $m[4]) : null;
        foreach ($pre ?? [] as $part) {
            if (ctype_digit($part) && !preg_match(self::NUMBER, $part)) {
                return null;
            }
        }
        return new Version([(int)$m[1], (int)$m[2], (int)$m[3]], $pre);
    }

    public function compare(Version $other): int
    {
        for ($i = 0; $i < 3; $i++) {
            if ($this->core[$i] !== $other->core[$i]) {
                return $this->core[$i] <=> $other->core[$i];
            }
        }
        if ($this->pre === null || $other->pre === null) {
            return $this->pre === $other->pre ? 0 : ($this->pre === null ? 1 : -1);
        }
        for ($i = 0; $i < min(count($this->pre), count($other->pre)); $i++) {
            $a = $this->pre[$i];
            $b = $other->pre[$i];
            if ($a === $b) {
                continue;
            }
            $an = ctype_digit($a);
            $bn = ctype_digit($b);
            return $an && $bn ? (int)$a <=> (int)$b : ($an === $bn ? strcmp($a, $b) : ($an ? -1 : 1));
        }
        return count($this->pre) <=> count($other->pre);
    }

    public function __toString(): string
    {
        return implode('.', $this->core) . ($this->pre === null ? '' : '-' . implode('.', $this->pre));
    }
}

class Constraint
{
    public function __construct(public array $alternatives) {}

    public static function parse(string $text): ?Constraint
    {
        $alternatives = [];
        foreach (explode(' || ', $text) as $alternative) {
            if ($alternative === '') {
                return null;
            }
            $comparators = [];
            $gates = [];
            foreach (explode(' ', $alternative) as $term) {
                $operator = '';
                foreach (['>=', '<=', '>', '<', '=', '^', '~'] as $op) {
                    if (str_starts_with($term, $op)) {
                        $operator = $op;
                        break;
                    }
                }
                $pattern = substr($term, strlen($operator));
                $version = Version::parse($pattern);
                if ($version !== null && $version->pre !== null) {
                    $core = $version->core;
                    $k = 3;
                    $gates[] = $core;
                } else {
                    $parts = explode('.', $pattern);
                    if (count($parts) < 1 || count($parts) > 3) {
                        return null;
                    }
                    $numbers = [];
                    $wildcard = false;
                    foreach ($parts as $part) {
                        if ($part === 'x' || $part === '*') {
                            $wildcard = true;
                        } elseif (!$wildcard && preg_match(Version::NUMBER, $part)) {
                            $numbers[] = (int)$part;
                        } else {
                            return null;
                        }
                    }
                    $k = count($numbers);
                    $core = array_pad($numbers, 3, 0);
                    $version = new Version($core);
                }
                $upper = function (int $i) use ($core): Version {
                    $values = $core;
                    $values[$i - 1]++;
                    for ($j = $i; $j < 3; $j++) {
                        $values[$j] = 0;
                    }
                    return new Version($values);
                };
                if ($k === 0) {
                    if ($operator === '>' || $operator === '<') {
                        $comparators[] = ['<', new Version([0, 0, 0], ['0'])];
                    }
                    continue;
                }
                switch ($operator) {
                    case '':
                    case '=':
                        if ($k === 3) {
                            $comparators[] = ['=', $version];
                        } else {
                            $comparators[] = ['>=', $version];
                            $comparators[] = ['<', $upper($k)];
                        }
                        break;
                    case '>':
                        $comparators[] = [$k === 3 ? '>' : '>=', $k === 3 ? $version : $upper($k)];
                        break;
                    case '<=':
                        $comparators[] = [$k === 3 ? '<=' : '<', $k === 3 ? $version : $upper($k)];
                        break;
                    case '>=':
                    case '<':
                        $comparators[] = [$operator, $version];
                        break;
                    case '~':
                        $comparators[] = ['>=', $version];
                        $comparators[] = ['<', $upper($k === 1 ? 1 : 2)];
                        break;
                    case '^':
                        $i = $core[0] !== 0 || $k === 1 ? 1 : ($core[1] !== 0 || $k === 2 ? 2 : 3);
                        $comparators[] = ['>=', $version];
                        $comparators[] = ['<', $upper($i)];
                        break;
                }
            }
            $alternatives[] = [$comparators, $gates];
        }
        return new Constraint($alternatives);
    }

    public function matches(Version $version): bool
    {
        foreach ($this->alternatives as [$comparators, $gates]) {
            if ($version->pre !== null && !in_array($version->core, $gates, true)) {
                continue;
            }
            foreach ($comparators as [$operator, $bound]) {
                $c = $version->compare($bound);
                $ok = match ($operator) {
                    '=' => $c === 0, '>' => $c > 0, '>=' => $c >= 0, '<' => $c < 0, '<=' => $c <= 0
                };
                if (!$ok) {
                    continue 2;
                }
            }
            return true;
        }
        return false;
    }

    public function __toString(): string
    {
        return implode(' || ', array_map(fn($a) => $a[0] ?
            implode(' ', array_map(fn($c) => $c[0] . $c[1], $a[0])) : '*', $this->alternatives));
    }
}

class PackageEntry
{
    public bool $yanked = false;
    public function __construct(public Version $version, public array $deps, public array $conflicts) {}
}

class PackageError extends Exception {}

class PackageManager
{
    private array $registry = [];
    private array $constraints = [];
    private array $requests = [];
    private array $installed = [];
    private array $held = [];
    private array $advisories = [];
    private array $history = [];

    private function keys(array $map): array
    {
        $names = array_keys($map);
        sort($names, SORT_STRING);
        return $names;
    }

    private function version(string $text): Version
    {
        $value = Version::parse($text);
        if ($value === null) {
            throw new PackageError("invalid version '$text'");
        }
        return $value;
    }

    private function constraint(string $text): Constraint
    {
        $value = $this->constraints[$text] ??= Constraint::parse($text);
        if ($value === null) {
            throw new PackageError("invalid constraint '$text'");
        }
        return $value;
    }

    private function matches(string $text, string $value): bool
    {
        return $this->constraint($text)->matches(Version::parse($value));
    }

    private function record(string $name, string $value): ?PackageEntry
    {
        return $this->registry[$name][$value] ?? null;
    }

    private function versions(string $name): array
    {
        $values = array_keys($this->registry[$name] ?? []);
        usort($values, fn($a, $b) => Version::parse($b)->compare(Version::parse($a)));
        return $values;
    }

    private function applicable(string $name, string $value): array
    {
        return array_values(array_filter($this->keys($this->advisories), fn($id) =>
            $this->advisories[$id][0] === $name && $this->matches($this->advisories[$id][1], $value)));
    }

    private function display(string $name, string $value): string
    {
        $flags = [];
        if ($this->record($name, $value)->yanked) {
            $flags[] = 'yanked';
        }
        if (($this->installed[$name] ?? null) === $value) {
            $flags[] = 'installed';
        }
        return "$name@$value" . ($flags ? ' (' . implode(', ', $flags) . ')' : '');
    }

    private function dependencies(string $name, ?array $installed = null): array
    {
        $installed ??= $this->installed;
        return $this->record($name, $installed[$name])->deps;
    }

    private function resolve(array $requests, array $preferred, bool $audit = false): array
    {
        $selected = [];
        $reasons = [];
        $failure = null;
        $failureDepth = -1;
        $usable = fn($n, $v) => (!$this->record($n, $v)->yanked || ($this->installed[$n] ?? null) === $v) &&
            (!$audit || !$this->applicable($n, $v));
        $save = function (array $chain, string $reason, ?array $other = null) use (&$selected, &$failure, &$failureDepth): void {
            if (count($selected) > $failureDepth) {
                $failureDepth = count($selected);
                $failure = ['UNSATISFIABLE', ...array_map(fn($s) => "  $s", $chain), "  $reason"];
                if ($other !== null) {
                    $failure = [...$failure, ...array_map(fn($s) => "    $s", $other)];
                }
            }
        };
        $search = function (array $requirements) use (&$search, &$selected, &$reasons, $preferred, $usable, $save): bool {
            if (!$requirements) {
                return true;
            }
            [$name, $text, $chain] = $requirements[0];
            $rest = array_slice($requirements, 1);
            if (isset($selected[$name])) {
                if ($this->matches($text, $selected[$name])) {
                    return $search($rest);
                }
                $save($chain, "$name@{$selected[$name]} was selected by:", $reasons[$name]);
                return false;
            }
            if (isset($this->held[$name])) {
                $value = $this->installed[$name];
                if (!$this->matches($text, $value) || !$usable($name, $value)) {
                    $save($chain, "$name@$value is held");
                    return false;
                }
                $candidates = [$value];
            } else {
                $candidates = array_values(array_filter($this->versions($name), fn($v) => $this->matches($text, $v) && $usable($name, $v)));
                $current = $this->installed[$name] ?? null;
                if (in_array($name, $preferred, true) && in_array($current, $candidates, true)) {
                    $candidates = array_values(array_diff($candidates, [$current]));
                    array_unshift($candidates, $current);
                }
                if (!$candidates) {
                    $save($chain, "no version of $name matches $text");
                    return false;
                }
            }
            foreach ($candidates as $value) {
                $conflicting = null;
                foreach ($this->keys($selected) as $q) {
                    foreach ($this->record($name, $value)->conflicts as [$d, $c]) {
                        if ($d === $q && $this->matches($c, $selected[$q])) {
                            $conflicting = $q;
                            break;
                        }
                    }
                    foreach ($this->record($q, $selected[$q])->conflicts as [$d, $c]) {
                        if ($d === $name && $this->matches($c, $value)) {
                            $conflicting = $q;
                            break;
                        }
                    }
                    if ($conflicting !== null) {
                        break;
                    }
                }
                if ($conflicting !== null) {
                    $save($chain, "$name@$value conflicts with $conflicting@{$selected[$conflicting]}, which was selected by:", $reasons[$conflicting]);
                    continue;
                }
                $selected[$name] = $value;
                $reasons[$name] = $chain;
                $extra = [];
                foreach ($this->record($name, $value)->deps as [$d, $c]) {
                    $extra[] = [$d, $c, [...$chain, "$name@$value requires $d $c"]];
                }
                if ($search([...$extra, ...$rest])) {
                    return true;
                }
                unset($selected[$name], $reasons[$name]);
            }
            return false;
        };
        $requirements = array_map(fn($r) => [$r[0], $r[1], ["requested {$r[0]} {$r[1]}"]], $requests);
        return $search($requirements) ? [$selected, null] : [null, $failure];
    }

    private function plan(array $new): void
    {
        $old = $this->installed;
        $arranged = [];
        $counts = ['install' => 0, 'upgrade' => 0, 'downgrade' => 0, 'remove' => 0];
        while (count($arranged) < count($new)) {
            foreach ($this->keys($new) as $name) {
                if (isset($arranged[$name])) {
                    continue;
                }
                foreach ($this->dependencies($name, $new) as [$d, $_]) {
                    if (!isset($arranged[$d])) {
                        continue 2;
                    }
                }
                break;
            }
            $arranged[$name] = true;
            $value = $new[$name];
            if (!isset($old[$name])) {
                echo "install $name@$value\n";
                $counts['install']++;
            } elseif ($old[$name] !== $value) {
                $kind = Version::parse($value)->compare(Version::parse($old[$name])) > 0 ? 'upgrade' : 'downgrade';
                echo "$kind $name {$old[$name]} -> $value\n";
                $counts[$kind]++;
            }
        }
        $remaining = array_diff_key($old, $new);
        while ($remaining) {
            foreach ($this->keys($remaining) as $name) {
                foreach ($remaining as $q => $_) {
                    foreach ($this->dependencies($q, $old) as [$d, $_]) {
                        if ($d === $name) {
                            continue 3;
                        }
                    }
                }
                break;
            }
            echo "remove $name@{$old[$name]}\n";
            $counts['remove']++;
            unset($remaining[$name]);
        }
        if (array_sum($counts) === 0) {
            echo "no changes\n";
        } else {
            echo "{$counts['install']} installed, {$counts['upgrade']} upgraded, {$counts['downgrade']} downgraded, {$counts['remove']} removed\n";
        }
    }

    private function update(array $requests, array $installed): void
    {
        $this->history[] = [$this->requests, $this->installed];
        $this->requests = $requests;
        $this->installed = $installed;
        $this->held = array_intersect_key($this->held, $installed);
    }

    private function resolveAndPlan(array $requests, array $preferred, bool $audit = false, bool $simulate = false): void
    {
        [$installed, $failure] = $this->resolve($requests, $preferred, $audit);
        if ($failure !== null) {
            echo implode("\n", $failure), "\n";
        } else {
            $this->plan($installed);
            if (!$simulate) {
                $this->update($requests, $installed);
            }
        }
    }

    private function requireInstalled(string $name): void
    {
        if (!isset($this->installed[$name])) {
            throw new PackageError("$name is not installed");
        }
    }

    private function requiredBy(string $name): string
    {
        foreach ($this->keys($this->installed) as $n) {
            foreach ($this->dependencies($n) as [$d, $_]) {
                if ($d === $name) {
                    return $n;
                }
            }
        }
    }

    private function tree(?string $name): void
    {
        if ($name !== null) {
            $this->requireInstalled($name);
        }
        $roots = $name !== null ? [$name] : array_column($this->requests, 0);
        if ($name === null) {
            sort($roots, SORT_STRING);
        }
        if (!$roots) {
            echo "(empty)\n";
            return;
        }
        $seen = [];
        $visit = function (string $n, ?string $text, string $prefix, string $indent) use (&$visit, &$seen): void {
            $body = "$prefix$n@{$this->installed[$n]}" . ($text === null ? '' : " [$text]");
            if (isset($seen[$n])) {
                echo "$body (*)\n";
                return;
            }
            echo "$body\n";
            $seen[$n] = true;
            $deps = $this->dependencies($n);
            foreach ($deps as $i => [$d, $c]) {
                $last = $i === count($deps) - 1;
                $visit($d, $c, $indent . ($last ? '`-- ' : '|-- '), $indent . ($last ? '    ' : '|   '));
            }
        };
        foreach ($roots as $root) {
            $text = null;
            foreach ($this->requests as [$n, $c]) {
                if ($n === $root) {
                    $text = $c;
                    break;
                }
            }
            $visit($root, $text, '', '');
        }
    }

    public function execute(string $line): void
    {
        [$command, $rest] = array_pad(explode(' ', $line, 2), 2, '');
        $args = $rest === '' ? [] : explode(' ', $rest);
        $name = $args[0] ?? null;
        try {
            switch ($command) {
                case 'PKG':
                    $clauses = explode('; ', $rest);
                    [$name, $value] = explode(' ', array_shift($clauses));
                    $parsed = $this->version($value);
                    if ($this->record($name, $value) !== null) {
                        throw new PackageError("$name@$value is already registered");
                    }
                    $deps = [];
                    $conflicts = [];
                    foreach ($clauses as $clause) {
                        [$kind, $other, $text] = explode(' ', $clause, 3);
                        $this->constraint($text);
                        if ($kind === 'DEP') {
                            $deps[] = [$other, $text];
                        } else {
                            $conflicts[] = [$other, $text];
                        }
                    }
                    $this->registry[$name][$value] = new PackageEntry($parsed, $deps, $conflicts);
                    echo "registered $name@$value\n";
                    break;
                case 'YANK':
                case 'INFO':
                    $value = $args[1];
                    $entry = $this->record($name, $value);
                    if ($entry === null) {
                        throw new PackageError("$name@$value is not registered");
                    }
                    if ($command === 'YANK') {
                        if ($entry->yanked) {
                            throw new PackageError("$name@$value is already yanked");
                        }
                        $entry->yanked = true;
                        echo "yanked $name@$value\n";
                    } else {
                        echo $this->display($name, $value), "\n";
                        foreach ($entry->deps as [$d, $c]) {
                            echo "  requires $d $c\n";
                        }
                        foreach ($entry->conflicts as [$d, $c]) {
                            echo "  conflicts with $d $c\n";
                        }
                        foreach ($this->applicable($name, $value) as $id) {
                            echo "  advisory $id\n";
                        }
                    }
                    break;
                case 'COMPARE':
                    $a = $this->version($name);
                    $b = $this->version($args[1]);
                    $comparison = $a->compare($b);
                    echo "$name ", $comparison < 0 ? '<' : ($comparison === 0 ? '=' : '>'), " {$args[1]}\n";
                    break;
                case 'MATCH':
                    [$value, $text] = explode(' ', $rest, 2);
                    $parsed = $this->version($value);
                    echo $this->constraint($text)->matches($parsed) ? "yes\n" : "no\n";
                    break;
                case 'RANGE':
                    echo $this->constraint($rest), "\n";
                    break;
                case 'VERSIONS':
                    [$name, $text] = array_pad(explode(' ', $rest, 2), 2, null);
                    if ($text !== null) {
                        $this->constraint($text);
                    }
                    if (!isset($this->registry[$name])) {
                        throw new PackageError("unknown package $name");
                    }
                    $selected = array_filter($this->versions($name), fn($v) => $text === null || $this->matches($text, $v));
                    if (!$selected) {
                        echo "no matching versions\n";
                    }
                    foreach ($selected as $value) {
                        echo $this->display($name, $value), "\n";
                    }
                    break;
                case 'DEPENDENTS':
                    $value = $args[1] ?? null;
                    if ($value !== null) {
                        $this->version($value);
                    }
                    $lines = [];
                    foreach ($this->keys($this->registry) as $n) {
                        foreach ($this->versions($n) as $v) {
                            foreach ($this->record($n, $v)->deps as [$d, $c]) {
                                if ($d === $name && ($value === null || $this->matches($c, $value))) {
                                    $lines[] = "$n@$v requires $name $c";
                                }
                            }
                        }
                    }
                    echo implode("\n", $lines ?: ['no dependents']), "\n";
                    break;
                case 'INSTALL':
                case 'SIMULATE':
                    [$name, $text] = array_pad(explode(' ', $rest, 2), 2, '*');
                    $this->constraint($text);
                    if (!isset($this->registry[$name])) {
                        throw new PackageError("unknown package $name");
                    }
                    $requests = $this->requests;
                    $index = array_search($name, array_column($requests, 0), true);
                    if ($index === false) {
                        $requests[] = [$name, $text];
                    } else {
                        $requests[$index] = [$name, $text];
                    }
                    $this->resolveAndPlan($requests, array_keys($this->installed), false, $command === 'SIMULATE');
                    break;
                case 'REMOVE':
                    if (!in_array($name, array_column($this->requests, 0), true)) {
                        throw new PackageError(isset($this->installed[$name]) ? "$name is required by " . $this->requiredBy($name) : "$name is not installed");
                    }
                    $requests = array_values(array_filter($this->requests, fn($r) => $r[0] !== $name));
                    $keep = array_column($requests, 0);
                    for ($i = 0; $i < count($keep); $i++) {
                        foreach ($this->dependencies($keep[$i]) as [$d, $_]) {
                            if (!in_array($d, $keep, true)) {
                                $keep[] = $d;
                            }
                        }
                    }
                    if (in_array($name, $keep, true)) {
                        echo "$name@{$this->installed[$name]} is still required by ", $this->requiredBy($name), "\n";
                        $this->update($requests, $this->installed);
                    } else {
                        $installed = array_intersect_key($this->installed, array_fill_keys($keep, true));
                        $this->plan($installed);
                        $this->update($requests, $installed);
                    }
                    break;
                case 'UPGRADE':
                    if ($name !== null) {
                        $this->requireInstalled($name);
                    }
                    $this->resolveAndPlan($this->requests, $name === null ? [] : array_values(array_diff(array_keys($this->installed), [$name])));
                    break;
                case 'ROLLBACK':
                    if (!$this->history) {
                        throw new PackageError('nothing to roll back');
                    }
                    [$requests, $installed] = array_pop($this->history);
                    $this->plan($installed);
                    $this->requests = $requests;
                    $this->installed = $installed;
                    $this->held = array_intersect_key($this->held, $installed);
                    break;
                case 'HOLD':
                    $this->requireInstalled($name);
                    if (isset($this->held[$name])) {
                        throw new PackageError("$name is already held");
                    }
                    $this->held[$name] = true;
                    echo "held $name@{$this->installed[$name]}\n";
                    break;
                case 'UNHOLD':
                    if (!isset($this->held[$name])) {
                        throw new PackageError("$name is not held");
                    }
                    unset($this->held[$name]);
                    echo "released $name\n";
                    break;
                case 'WHY':
                    $this->requireInstalled($name);
                    $queue = array_column($this->requests, 0);
                    if (in_array($name, $queue, true)) {
                        echo "$name@{$this->installed[$name]} is explicitly installed\n";
                        break;
                    }
                    sort($queue, SORT_STRING);
                    $parent = array_fill_keys($queue, null);
                    for ($i = 0; $i < count($queue); $i++) {
                        $n = $queue[$i];
                        $deps = array_column($this->dependencies($n), 0);
                        sort($deps, SORT_STRING);
                        foreach ($deps as $d) {
                            if (!array_key_exists($d, $parent)) {
                                $parent[$d] = $n;
                                $queue[] = $d;
                            }
                        }
                    }
                    $path = [$name];
                    while ($parent[$path[0]] !== null) {
                        array_unshift($path, $parent[$path[0]]);
                    }
                    echo implode(' -> ', array_map(fn($n) => "$n@{$this->installed[$n]}", $path)), "\n";
                    break;
                case 'TREE':
                    $this->tree($name);
                    break;
                case 'OUTDATED':
                    $lines = [];
                    foreach ($this->keys($this->installed) as $n) {
                        $current = $this->installed[$n];
                        $constraints = [];
                        foreach ($this->requests as [$d, $c]) {
                            if ($d === $n) {
                                $constraints[] = $c;
                            }
                        }
                        foreach ($this->installed as $q => $_) {
                            foreach ($this->dependencies($q) as [$d, $c]) {
                                if ($d === $n) {
                                    $constraints[] = $c;
                                }
                            }
                        }
                        $wanted = null;
                        $latest = null;
                        foreach ($this->versions($n) as $v) {
                            $entry = $this->record($n, $v);
                            if ($latest === null && !$entry->yanked && $entry->version->pre === null) {
                                $latest = $v;
                            }
                            if ($wanted !== null || ($entry->yanked && $v !== $current)) {
                                continue;
                            }
                            foreach ($constraints as $c) {
                                if (!$this->matches($c, $v)) {
                                    continue 2;
                                }
                            }
                            $wanted = $v;
                        }
                        if ($wanted !== $current || ($latest !== null && Version::parse($latest)->compare(Version::parse($current)) > 0)) {
                            $lines[] = "$n $current $wanted " . ($latest ?? '-');
                        }
                    }
                    echo implode("\n", $lines ?: ['all packages are up to date']), "\n";
                    break;
                case 'LOCK':
                    if (!$this->installed) {
                        echo "(empty)\n";
                    }
                    foreach ($this->keys($this->installed) as $n) {
                        echo "$n@{$this->installed[$n]}\n";
                    }
                    break;
                case 'STATUS':
                    if (!$this->requests) {
                        echo "no requests\n";
                    }
                    foreach ($this->requests as [$n, $c]) {
                        echo "$n $c -> {$this->installed[$n]}\n";
                    }
                    echo count($this->installed), ' installed, ', count($this->held), ' held, ', count($this->history), " snapshots\n";
                    break;
                case 'ADVISORY':
                    [$id, $n, $text] = explode(' ', $rest, 3);
                    if (isset($this->advisories[$id])) {
                        throw new PackageError("advisory $id already exists");
                    }
                    $this->constraint($text);
                    $this->advisories[$id] = [$n, $text];
                    echo "advisory $id recorded\n";
                    break;
                case 'AUDIT':
                    if ($name === 'FIX') {
                        $this->resolveAndPlan($this->requests, array_keys($this->installed), true);
                        break;
                    }
                    $lines = [];
                    foreach ($this->keys($this->installed) as $n) {
                        $current = $this->installed[$n];
                        $ids = $this->applicable($n, $current);
                        if (!$ids) {
                            continue;
                        }
                        $fix = null;
                        foreach (array_reverse($this->versions($n)) as $v) {
                            $entry = $this->record($n, $v);
                            if ($entry->version->compare(Version::parse($current)) > 0 && $entry->version->pre === null &&
                                !$entry->yanked && !$this->applicable($n, $v)) {
                                $fix = $v;
                                break;
                            }
                        }
                        $lines[] = "$n@$current: " . implode(', ', $ids) . ' (' . ($fix === null ? 'no fix' : "fix: $fix") . ')';
                    }
                    echo implode("\n", $lines ?: ['no known vulnerabilities']), "\n";
                    break;
            }
        } catch (PackageError $error) {
            echo 'error: ', $error->getMessage(), "\n";
        }
    }
}

$manager = new PackageManager();
$count = (int)fgets(STDIN);
for ($i = 0; $i < $count; $i++) {
    $manager->execute(rtrim(fgets(STDIN), "\r\n"));
}
