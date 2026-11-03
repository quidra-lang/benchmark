<?php

class ConflictGraph
{
    public array $vertices;
    public array $shared = [];

    public function __construct(array $vertices, array $studentCourses)
    {
        sort($vertices, SORT_STRING);
        $this->vertices = $vertices;
        foreach ($vertices as $id) {
            $this->shared[id_key($id)] = [];
        }
        foreach ($studentCourses as $list) {
            for ($i = 0; $i < count($list); $i++) {
                for ($j = $i + 1; $j < count($list); $j++) {
                    $first = id_key($list[$i]);
                    $second = id_key($list[$j]);
                    $this->shared[$first][$second] = ($this->shared[$first][$second] ?? 0) + 1;
                    $this->shared[$second][$first] = ($this->shared[$second][$first] ?? 0) + 1;
                }
            }
        }
    }

    public function neighbours(string $id): array
    {
        return $this->shared[id_key($id)] ?? [];
    }

    public function degree(string $id): int
    {
        return count($this->neighbours($id));
    }

    public function sharedTotal(string $id): int
    {
        return array_sum($this->neighbours($id));
    }

    public function edges(): array
    {
        $edges = [];
        foreach ($this->vertices as $first) {
            foreach (sorted_ids($this->neighbours($first)) as $second) {
                if (strcmp($first, $second) < 0) {
                    $edges[] = [$first, $second, $this->shared[id_key($first)][id_key($second)]];
                }
            }
        }
        return $edges;
    }

    public function components(): array
    {
        $seen = [];
        $components = [];
        foreach ($this->vertices as $vertex) {
            if (isset($seen[id_key($vertex)])) {
                continue;
            }
            $seen[id_key($vertex)] = true;
            $component = [$vertex];
            for ($index = 0; $index < count($component); $index++) {
                foreach ($this->neighbours($component[$index]) as $key => $shared) {
                    if (!isset($seen[$key])) {
                        $seen[$key] = true;
                        $component[] = substr($key, 1);
                    }
                }
            }
            sort($component, SORT_STRING);
            $components[] = $component;
        }
        usort($components, fn($a, $b) => count($b) <=> count($a) ?: strcmp($a[0], $b[0]));
        return $components;
    }

    public function greedyClique(array $candidates): array
    {
        $clique = [];
        while ($candidates) {
            usort($candidates, fn($a, $b) => $this->degree($b) <=> $this->degree($a) ?: strcmp($a, $b));
            $chosen = $candidates[0];
            $clique[] = $chosen;
            $neighbours = $this->neighbours($chosen);
            $candidates = array_values(array_filter($candidates, fn($id) => isset($neighbours[id_key($id)])));
        }
        return $clique;
    }

    public function kempeChain(array $assignment, string $start, int $firstSlot, int $secondSlot): array
    {
        $chain = [$start];
        $seen = [id_key($start) => true];
        for ($index = 0; $index < count($chain); $index++) {
            foreach ($this->neighbours($chain[$index]) as $key => $shared) {
                $slot = $assignment[$key] ?? null;
                if (!isset($seen[$key]) && ($slot === $firstSlot || $slot === $secondSlot)) {
                    $seen[$key] = true;
                    $chain[] = substr($key, 1);
                }
            }
        }
        sort($chain, SORT_STRING);
        return $chain;
    }
}

function reachable(array $arrows, string $source, string $target): bool
{
    $stack = [$source];
    $seen = [id_key($source) => true];
    while ($stack) {
        $node = array_pop($stack);
        if ($node === $target) {
            return true;
        }
        foreach ($arrows[id_key($node)] ?? [] as $successor) {
            $key = id_key($successor);
            if (!isset($seen[$key])) {
                $seen[$key] = true;
                $stack[] = $successor;
            }
        }
    }
    return false;
}
