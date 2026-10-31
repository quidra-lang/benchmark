<?php

function permissionKey(string $action, string $type): string
{
    return $action . "\0" . $type;
}

class Rbac
{
    public array $roles = [];
    public array $permissions = [];
    public array $ssd = [];
    public array $dsd = [];
    public array $assignments = [];
    public array $byUser = [];
    public array $diagnostics = [];
    private ?array $cachedClosures = null;

    public function __construct(array $lines)
    {
        $records = [];
        foreach ($lines as $index => $line) {
            $records[] = (object) ['fields' => explode(' ', $line), 'line' => $index + 1];
        }
        foreach (['ROLE', 'INHERITS', 'PERMIT', 'SSD', 'DSD', 'ASSIGN'] as $keyword) {
            foreach ($records as $record) {
                if ($record->fields[0] !== $keyword) {
                    continue;
                }
                $reason = $this->accept($record->fields);
                if ($reason !== null) {
                    $this->diagnostics[] = (object) ['line' => $record->line, 'keyword' => $keyword, 'reason' => $reason];
                }
            }
            if ($keyword === 'INHERITS') {
                $closures = [];
                foreach ($this->roles as $role => $value) {
                    $closures[$role] = $this->closure([$role]);
                }
                $this->cachedClosures = $closures;
            }
        }
        usort($this->diagnostics, fn($a, $b) => $a->line <=> $b->line);
    }

    public function closure(array $seeds): array
    {
        $found = [];
        if ($this->cachedClosures !== null) {
            foreach ($seeds as $seed) {
                foreach ($this->cachedClosures[$seed] as $role => $unused) {
                    $found[$role] = true;
                }
            }
            return $found;
        }
        $pending = $seeds;
        for ($i = 0; $i < count($pending); $i++) {
            $role = $pending[$i];
            if (isset($found[$role])) {
                continue;
            }
            $found[$role] = true;
            foreach ($this->roles[$role]->juniors as $junior => $unused) {
                $pending[] = $junior;
            }
        }
        return $found;
    }

    private function pathVisit(string $role, string $target, array &$failed): ?array
    {
        if ($role === $target) {
            return [$role];
        }
        if (isset($failed[$role])) {
            return null;
        }
        $juniors = array_keys($this->roles[$role]->juniors);
        sort($juniors, SORT_STRING);
        foreach ($juniors as $junior) {
            $rest = $this->pathVisit($junior, $target, $failed);
            if ($rest !== null) {
                return array_merge([$role], $rest);
            }
        }
        $failed[$role] = true;
        return null;
    }

    public function assigned(string $user, int $day): array
    {
        $result = [];
        foreach ($this->byUser[$user] ?? [] as $assignment) {
            if ($assignment->first <= $day && $day <= $assignment->last) {
                $result[$assignment->role] = true;
            }
        }
        return array_keys($result);
    }

    public function authorized(string $user, int $day): array
    {
        return $this->closure($this->assigned($user, $day));
    }

    private function accept(array $fields): ?string
    {
        $keyword = $fields[0];
        $name = $fields[1];
        if ($keyword === 'ROLE') {
            if (isset($this->roles[$name])) {
                return 'duplicate role ' . $name;
            }
            $this->roles[$name] = (object) ['juniors' => [], 'permissions' => []];
        } elseif ($keyword === 'INHERITS') {
            $junior = $fields[2];
            foreach ([$name, $junior] as $role) {
                if (!isset($this->roles[$role])) {
                    return 'unknown role ' . $role;
                }
            }
            if (isset($this->roles[$name]->juniors[$junior])) {
                return 'duplicate inheritance ' . $name . ' ' . $junior;
            }
            $failed = [];
            $path = $this->pathVisit($junior, $name, $failed);
            if ($path !== null) {
                return 'cycle ' . implode(' > ', array_merge([$name], $path));
            }
            $this->roles[$name]->juniors[$junior] = true;
        } elseif ($keyword === 'PERMIT') {
            [, $role, $action, $type] = $fields;
            if (!isset($this->roles[$role])) {
                return 'unknown role ' . $role;
            }
            $key = permissionKey($action, $type);
            if (isset($this->roles[$role]->permissions[$key])) {
                return 'duplicate permission ' . $role . ' ' . $action . ' ' . $type;
            }
            $this->roles[$role]->permissions[$key] = true;
            $this->permissions[] = (object) compact('role', 'action', 'type');
        } elseif ($keyword === 'SSD' || $keyword === 'DSD') {
            $constraints = $keyword === 'SSD' ? $this->ssd : $this->dsd;
            foreach ($constraints as $constraint) {
                if ($constraint->name === $name) {
                    return 'duplicate constraint ' . $name;
                }
            }
            $roles = explode(',', $fields[3]);
            foreach ($roles as $role) {
                if (!isset($this->roles[$role])) {
                    return 'unknown role ' . $role;
                }
            }
            $cardinality = (int) $fields[2];
            if ($cardinality < 2 || $cardinality > count($roles)) {
                return 'bad cardinality ' . $name . ' ' . $cardinality;
            }
            $constraint = (object) compact('name', 'cardinality', 'roles');
            if ($keyword === 'SSD') {
                $this->ssd[] = $constraint;
            } else {
                $this->dsd[] = $constraint;
            }
        } else {
            $role = $fields[2];
            if (!isset($this->roles[$role])) {
                return 'unknown role ' . $role;
            }
            $first = (int) $fields[3];
            $last = (int) $fields[4];
            if (!($first >= 1 && $first <= $last && $last <= 365)) {
                return 'bad range ' . $first . ' ' . $last;
            }
            foreach ($this->ssd as $constraint) {
                for ($day = $first; $day <= $last; $day++) {
                    $authorized = $this->closure(array_merge($this->assigned($name, $day), [$role]));
                    $overlap = array_values(array_filter($constraint->roles, fn($item) => isset($authorized[$item])));
                    sort($overlap, SORT_STRING);
                    if (count($overlap) >= $constraint->cardinality) {
                        return 'ssd ' . $constraint->name . ' day ' . $day . ' roles ' . implode(',', $overlap);
                    }
                }
            }
            $assignment = (object) ['user' => $name, 'role' => $role, 'first' => $first, 'last' => $last];
            $this->assignments[] = $assignment;
            $this->byUser[$name][] = $assignment;
        }
        return null;
    }
}

function readRbac(): Rbac
{
    return new Rbac(file('input/rbac.txt', FILE_IGNORE_NEW_LINES));
}
