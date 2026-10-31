<?php

final class GHNode
{
    public bool $entering = false;
    public ?self $next = null, $previous = null, $other = null;

    public function __construct(
        public Point $point,
        public int $side,
        public Line $line,
        public ?int $crossing = null,
    ) {}
}

final class GHGraph
{
    public array $nodes = [[], []], $initialInside = [[], []], $crossings = [];
    public int $na = 0, $nb = 0;

    public function __construct(
        public array $first,
        public array $second,
    ) {
        $sequences = [$first, $second];
        $slots = [[], []];
        $serial = 0;
        foreach ($first as $ri => $ring)
            foreach ($ring as $ei => $a)
                foreach ($second as $rj => $other)
                    foreach ($other as $ej => $c) {
                        $b = $ring[($ei + 1) % count($ring)];
                        $d = $other[($ej + 1) % count($other)];
                        $found = crossing($a->point, $b->point, $c->point, $d->point);
                        if ($found === null)
                            continue;
                        [$t, $u, $p] = $found;
                        $one = new GHNode($p, 0, $a->line, $serial);
                        $two = new GHNode($p, 1, $c->line, $serial++);
                        $one->other = $two;
                        $two->other = $one;
                        $slots[0][$ri][$ei][] = [$t, $one];
                        $slots[1][$rj][$ej][] = [$u, $two];
                    }
        foreach ($sequences as $side => $sequence)
            foreach ($sequence as $ri => $ring) {
                $nodes = [];
                foreach ($ring as $ei => $v) {
                    $nodes[] = new GHNode($v->point, $side, $v->line);
                    $inserted = $slots[$side][$ri][$ei] ?? [];
                    usort($inserted, fn($a, $b) => ($a[0][0] * $b[0][1]) <=> ($b[0][0] * $a[0][1]));
                    foreach ($inserted as [$position, $node])
                        $nodes[] = $node;
                }
                $n = count($nodes);
                foreach ($nodes as $i => $node) {
                    $node->previous = $nodes[($i - 1 + $n) % $n];
                    $node->next = $nodes[($i + 1) % $n];
                }
                $state = interior($sequences[1 - $side], $ring[0]->point);
                $this->initialInside[$side][] = $state;
                foreach ($nodes as $node)
                    if ($node->crossing !== null) {
                        $node->entering = !$state;
                        $state = !$state;
                        if ($side === 0)
                            $this->crossings[] = $node;
                    }
                $this->nodes[$side][] = $nodes;
            }
        $this->na = count(array_filter($this->initialInside[0]));
        $this->nb = count(array_filter($this->initialInside[1]));
    }

    public function traverse(bool $invertFirst, bool $invertSecond): array
    {
        $inverted = [$invertFirst, $invertSecond];
        $visited = $result = [];
        foreach ($this->crossings as $start) {
            if (isset($visited[$start->crossing]))
                continue;
            $ring = [];
            $current = $start;
            while (true) {
                $visited[$current->crossing] = true;
                $forward = $current->entering !== $inverted[$current->side];
                $ring[] = new Vertex($current->point, $forward ? $current->line : $current->previous->line);
                $stopped = $forward ? $current->next : $current->previous;
                while ($stopped->crossing === null) {
                    $ring[] = new Vertex(
                        $stopped->point,
                        $forward ? $stopped->line : $stopped->previous->line,
                    );
                    $stopped = $forward ? $stopped->next : $stopped->previous;
                }
                if ($stopped->crossing === $start->crossing)
                    break;
                $current = $stopped->other;
            }
            $result[] = $ring;
        }
        foreach ([$this->first, $this->second] as $side => $sequence)
            foreach ($sequence as $i => $ring)
                if (
                    !array_any($this->nodes[$side][$i], fn($n) => $n->crossing !== null)
                    && $this->initialInside[$side][$i] !== $inverted[$side]
                )
                    $result[] = $ring;
        return $result;
    }
}
