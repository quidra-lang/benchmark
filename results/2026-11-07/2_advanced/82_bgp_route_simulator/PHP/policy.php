<?php

const NO_EXPORT = [65535, 65281];

function parseCommunity(string $text): array
{
    return $text === 'NO_EXPORT' ? NO_EXPORT : array_map(intval(...), explode(':', $text));
}

function parseCommunities(array $values): array
{
    $set = [];
    foreach ($values as $v) {
        $c = parseCommunity($v);
        $set[$c[0] . ':' . $c[1]] = $c;
    }
    $result = array_values($set);
    usort($result, fn($a, $b) => $a <=> $b);
    return $result;
}

function communitiesText(array $communities): string
{
    return $communities
        ? implode(',', array_map(fn($c) => $c === NO_EXPORT
            ? 'NO_EXPORT'
            : $c[0] . ':' . $c[1], $communities))
        : '-';
}

function editCommunities(array $communities, Rule $rule): array
{
    foreach ($rule->actions as [$action, $value]) {
        if ($action === 'ADD' && !in_array($value, $communities, true))
            $communities[] = $value;
        elseif ($action === 'REMOVE')
            $communities = array_values(array_filter($communities, fn($c) => $c !== $value));
    }
    usort($communities, fn($a, $b) => $a <=> $b);
    return $communities;
}

final class Rule
{
    public int $hits = 0;
    public array $settings = [];

    public function __construct(
        public string $name,
        public bool $active,
        public int $owner,
        public string $direction,
        public string $target,
        public array $conditions,
        public array $actions,
    ) {
        foreach ($actions as [$a, $v])
            $this->settings[$a] = $v;
    }

    public function has(string $action): bool
    {
        return array_key_exists($action, $this->settings);
    }

    public function value(string $action, mixed $default): mixed
    {
        return $this->settings[$action] ?? $default;
    }
}

final class Policies
{
    public array $lists = [], $rules = [], $byName = [];

    public function __construct()
    {
        foreach (file('input/policies.txt', FILE_IGNORE_NEW_LINES) as $line) {
            $f = explode(' ', $line);
            if ($f[0] === 'PLIST') {
                $bounds = [];
                for ($i = 4; $i < count($f); $i += 2)
                    $bounds[$f[$i]] = (int) $f[$i + 1];
                $length = parsePrefix($f[3])[1];
                $this->lists[$f[1]][] = [
                    $f[2] === 'PERMIT',
                    $f[3],
                    $bounds['GE'] ?? $length,
                    $bounds['LE'] ?? (isset($bounds['GE']) ? 32 : $length),
                ];
                continue;
            }
            $separator = array_search('THEN', $f, true);
            $conditions = [];
            for ($i = 6; $i < $separator; $i += 2) {
                $kind = $f[$i];
                $v = $f[$i + 1];
                $value = match ($kind) {
                    'CONTAINS', 'ORIGINAS' => (int) $v,
                    'LENGTH' => array_map(intval(...), explode('-', $v)),
                    'COMMUNITY' => parseCommunity($v),
                    default => $v,
                };
                $conditions[] = [$kind, $value];
            }
            $actions = [];
            for ($i = $separator + 1; $i < count($f);) {
                $action = $f[$i++];
                $v = null;
                if ($action !== 'DENY' && $action !== 'ALLOW') {
                    $v = $f[$i++];
                    $v = in_array($action, ['ADD', 'REMOVE'], true) ? parseCommunity($v) : (int) $v;
                }
                $actions[] = [$action, $v];
            }
            $r = new Rule($f[1], $f[2] === 'ON', (int) $f[3], $f[4], $f[5], $conditions, $actions);
            $this->rules[] = $r;
            $this->byName[$r->name] = $r;
        }
    }

    private function permitted(string $name, string $prefix): bool
    {
        [$address, $length] = parsePrefix($prefix);
        foreach ($this->lists[$name] as [$permit, $base, $low, $high])
            if ($low <= $length && $length <= $high && prefixContains($base, $address))
                return $permit;
        return false;
    }

    private function matches(
        Rule $rule,
        int $owner,
        Link $link,
        string $prefix,
        array $path,
        array $communities,
    ): bool {
        if (
            !$rule->active
            || $rule->owner !== $owner
            || !in_array($rule->target, ['*', (string) $link->other($owner), $link->name], true)
        )
            return false;
        foreach ($rule->conditions as [$kind, $value]) {
            $matches = match ($kind) {
                'PREFIX' => $this->permitted($value, $prefix),
                'CONTAINS' => in_array($value, $path, true),
                'ORIGINAS' => ($path ? $path[count($path) - 1] : $owner) === $value,
                'LENGTH' => $value[0] <= count($path) && count($path) <= $value[1],
                'COMMUNITY' => in_array($value, $communities, true),
            };
            if (!$matches)
                return false;
        }
        return true;
    }

    public function applied(
        string $direction,
        int $owner,
        Link $link,
        string $prefix,
        array $path,
        array $communities,
    ): ?Rule {
        foreach ($this->rules as $r)
            if (
                $r->direction === $direction
                && $this->matches($r, $owner, $link, $prefix, $path, $communities)
            )
                return $r;
        return null;
    }
}
