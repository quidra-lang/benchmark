<?php

function numberKeys(array $set): array
{
    $keys = array_keys($set);
    sort($keys, SORT_NUMERIC);
    return $keys;
}

function sameSet(array $a, array $b): bool
{
    return !array_diff_key($a, $b) && !array_diff_key($b, $a);
}

function tupleKey(array $tuple): string
{
    return serialize($tuple);
}

final class Block
{
    public int $end = 0;
    public array $instructions = [], $predecessors = [], $successors = [];

    public function __construct(
        public int $number,
        public array $labels,
        public int $start,
    ) {}
}

final class NaturalLoop
{
    public int $depth = 0;
    public array $exits = [], $outside = [];

    public function __construct(
        public int $header,
        public array $latches,
        public array $blocks,
    ) {}
}

final class CFG
{
    public array
        $blocks = [],
        $instructions = [],
        $positions = [],
        $blockOf = [],
        $reachable = [],
        $postorder = [],
        $reversePostorder = [],
        $reachablePredecessors = [],
        $dominators = [],
        $immediate = [],
        $loops = [],
        $depth = []
    ;

    public function __construct(
        public TacFunction $function,
    ) {
        $pending = [];
        $firstLabel = null;
        $current = null;
        $previous = null;
        foreach ($function->code as $index => $line) {
            if (is_string($line)) {
                if (!$pending)
                    $firstLabel = $index;
                $pending[] = $line;
                continue;
            }
            $number = count($this->instructions) + 1;
            if ($current === null || $pending || in_array($previous, ['goto', 'if', 'return'], true)) {
                $start = $pending ? $firstLabel : $index;
                if ($current !== null)
                    $current->end = $start;
                $current = new Block(count($this->blocks) + 1, $pending, $start);
                $this->blocks[$current->number] = $current;
                $pending = [];
            }
            $this->instructions[$number] = $line;
            $this->positions[$number] = $index;
            $this->blockOf[$number] = $current->number;
            $current->instructions[] = $number;
            $previous = $line->kind;
        }
        $current->end = count($function->code);
        $labels = [];
        foreach ($this->blocks as $number => $b)
            foreach ($b->labels as $l)
                $labels[$l] = $number;
        foreach ($this->blocks as $number => $b) {
            $last = $this->instructions[$b->instructions[count($b->instructions) - 1]];
            $b->successors = match ($last->kind) {
                'goto' => [$labels[$last->name]],
                'if' => array_values(array_unique([$number + 1, $labels[$last->name]])),
                'return' => [],
                default => [$number + 1],
            };
            foreach ($b->successors as $s)
                $this->blocks[$s]->predecessors[] = $number;
        }
        $visit = function (int $n) use (&$visit): void {
            $this->reachable[$n] = true;
            foreach ($this->blocks[$n]->successors as $s)
                if (!isset($this->reachable[$s]))
                    $visit($s);
            $this->postorder[] = $n;
        };
        $visit(1);
        $this->reversePostorder = array_reverse($this->postorder);
        foreach ($this->reachable as $number => $_) {
            $this->reachablePredecessors[$number] = array_values(array_filter(
                $this->blocks[$number]->predecessors,
                fn($p) => isset($this->reachable[$p]),
            ));
            $this->dominators[$number] = $this->reachable;
        }
        $this->dominators[1] = [1 => true];
        do {
            $changed = false;
            foreach (array_slice($this->reversePostorder, 1) as $number) {
                $preds = $this->reachablePredecessors[$number];
                $value = $this->dominators[$preds[0]];
                foreach (array_slice($preds, 1) as $p)
                    $value = array_intersect_key($value, $this->dominators[$p]);
                $value[$number] = true;
                if (!sameSet($value, $this->dominators[$number])) {
                    $this->dominators[$number] = $value;
                    $changed = true;
                }
            }
        } while ($changed);
        $this->immediate[1] = null;
        foreach (numberKeys($this->reachable) as $number)
            if ($number !== 1) {
                $best = null;
                foreach ($this->dominators[$number] as $p => $_)
                    if (
                        $p !== $number
                        && ($best === null || count($this->dominators[$p]) > count($this->dominators[$best]))
                    )
                        $best = $p;
                $this->immediate[$number] = $best;
            }
        foreach (numberKeys($this->reachable) as $header) {
            $latches = array_values(array_filter(
                $this->reachablePredecessors[$header],
                fn($n) => isset($this->dominators[$n][$header]),
            ));
            if (!$latches)
                continue;
            $members = [$header => true] + array_fill_keys($latches, true);
            $pending = array_values(array_filter($latches, fn($n) => $n !== $header));
            while ($pending) {
                $number = array_pop($pending);
                foreach ($this->reachablePredecessors[$number] as $p)
                    if (!isset($members[$p])) {
                        $members[$p] = true;
                        $pending[] = $p;
                    }
            }
            $this->loops[] = new NaturalLoop($header, $latches, $members);
        }
        foreach ($this->blocks as $number => $_) {
            $this->depth[$number] = 0;
            foreach ($this->loops as $loop)
                if (isset($loop->blocks[$number]))
                    ++$this->depth[$number];
        }
        foreach ($this->loops as $loop) {
            foreach ($this->loops as $other)
                if (isset($other->blocks[$loop->header]))
                    ++$loop->depth;
            foreach ($loop->blocks as $number => $_) {
                $b = $this->blocks[$number];
                $outside = [];
                foreach ($b->successors as $s)
                    if (!isset($loop->blocks[$s]))
                        $outside[$s] = true;
                $loop->outside += $outside;
                if (
                    $outside
                    || $this->instructions[$b->instructions[count($b->instructions) - 1]]->kind === 'return'
                )
                    $loop->exits[$number] = true;
            }
        }
    }
}
