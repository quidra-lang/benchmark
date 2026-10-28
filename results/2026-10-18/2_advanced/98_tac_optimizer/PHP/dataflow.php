<?php

function reachingTransfer(TacInstruction $i, int $number, array $state): array
{
    if ($i->destination === null)
        return $state;
    foreach ($state as $key => [$v, $n])
        if ($v === $i->destination)
            unset($state[$key]);
    $pair = [$i->destination, $number];
    $state[tupleKey($pair)] = $pair;
    return $state;
}

function liveTransfer(TacInstruction $i, array $state): array
{
    if ($i->destination !== null)
        unset($state[$i->destination]);
    foreach ($i->usedVariables() as $v)
        $state[$v] = true;
    return $state;
}

function expressionTransfer(TacInstruction $i, int $number, array $state): array
{
    $e = $i->expression();
    if ($e !== null)
        $state[tupleKey($e)] = $e;
    foreach ($state as $key => $v)
        if (
            $i->kind === 'store' && $v[0] === 'load' && $v[1] === $i->name
            || $i->kind === 'call' && $v[0] === 'load'
            || $i->destination !== null && in_array($i->destination, array_slice($v, 2), true)
        )
            unset($state[$key]);
    return $state;
}

function copyTransfer(TacInstruction $i, int $number, array $state): array
{
    if ($i->destination !== null)
        foreach ($state as $key => $pair)
            if (in_array($i->destination, $pair, true))
                unset($state[$key]);
    if ($i->kind === 'copy' && is_string($i->a) && $i->destination !== $i->a) {
        $pair = [$i->destination, $i->a];
        $state[tupleKey($pair)] = $pair;
    }
    return $state;
}

final class DataFlow
{
    public array
        $iterations = [],
        $reachingIn,
        $reachingOut,
        $liveIn,
        $liveOut,
        $expressionIn,
        $expressionOut,
        $copyIn,
        $copyOut,
        $reachingBefore,
        $expressionBefore,
        $copyBefore,
        $liveBefore = [],
        $liveAfter = []
    ;

    public function __construct(
        public CFG $graph,
    ) {
        $expressions = $copies = [];
        foreach ($graph->instructions as $number => $i)
            if (isset($graph->reachable[$graph->blockOf[$number]])) {
                $e = $i->expression();
                if ($e !== null)
                    $expressions[tupleKey($e)] = $e;
                if ($i->kind === 'copy' && is_string($i->a) && $i->destination !== $i->a) {
                    $pair = [$i->destination, $i->a];
                    $copies[tupleKey($pair)] = $pair;
                }
            }
        [$this->reachingIn, $this->reachingOut] = $this->forward('reaching', reachingTransfer(...), []);
        [$this->liveIn, $this->liveOut] = $this->liveness();
        [$this->expressionIn, $this->expressionOut] = $this->forward(
            'expressions',
            expressionTransfer(...),
            $expressions,
        );
        [$this->copyIn, $this->copyOut] = $this->forward('copies', copyTransfer(...), $copies);
        $this->reachingBefore = $this->boundaries($this->reachingIn, reachingTransfer(...));
        $this->expressionBefore = $this->boundaries($this->expressionIn, expressionTransfer(...));
        $this->copyBefore = $this->boundaries($this->copyIn, copyTransfer(...));
        foreach (numberKeys($graph->reachable) as $b) {
            $state = $this->liveOut[$b];
            foreach (array_reverse($graph->blocks[$b]->instructions) as $n) {
                $this->liveAfter[$n] = $state;
                $state = liveTransfer($graph->instructions[$n], $state);
                $this->liveBefore[$n] = $state;
            }
        }
    }

    private function forward(string $kind, callable $transfer, array $universe): array
    {
        $g = $this->graph;
        $incoming = $outgoing = [];
        foreach ($g->reachable as $n => $_)
            $outgoing[$n] = $universe;
        $iterations = 0;
        do {
            ++$iterations;
            $changed = false;
            foreach ($g->reversePostorder as $n) {
                $preds = $g->reachablePredecessors[$n];
                if ($kind === 'reaching') {
                    $state = [];
                    foreach ($preds as $p)
                        $state += $outgoing[$p];
                    if ($n === 1)
                        foreach ($g->function->parameters as $p) {
                            $pair = [$p, 0];
                            $state[tupleKey($pair)] = $pair;
                        }
                } elseif ($n === 1)
                    $state = [];
                else {
                    $state = $outgoing[$preds[0]];
                    foreach (array_slice($preds, 1) as $p)
                        $state = array_intersect_key($state, $outgoing[$p]);
                }
                $incoming[$n] = $state;
                foreach ($g->blocks[$n]->instructions as $i)
                    $state = $transfer($g->instructions[$i], $i, $state);
                if (!sameSet($state, $outgoing[$n])) {
                    $outgoing[$n] = $state;
                    $changed = true;
                }
            }
        } while ($changed);
        $this->iterations[$kind] = $iterations;
        return [$incoming, $outgoing];
    }

    private function liveness(): array
    {
        $g = $this->graph;
        $incoming = $outgoing = [];
        foreach ($g->reachable as $n => $_)
            $incoming[$n] = [];
        $iterations = 0;
        do {
            ++$iterations;
            $changed = false;
            foreach ($g->postorder as $n) {
                $state = [];
                foreach ($g->blocks[$n]->successors as $s)
                    $state += $incoming[$s];
                $outgoing[$n] = $state;
                foreach (array_reverse($g->blocks[$n]->instructions) as $i)
                    $state = liveTransfer($g->instructions[$i], $state);
                if (!sameSet($state, $incoming[$n])) {
                    $incoming[$n] = $state;
                    $changed = true;
                }
            }
        } while ($changed);
        $this->iterations['liveness'] = $iterations;
        return [$incoming, $outgoing];
    }

    private function boundaries(array $incoming, callable $transfer): array
    {
        $r = [];
        foreach (numberKeys($this->graph->reachable) as $b) {
            $state = $incoming[$b];
            foreach ($this->graph->blocks[$b]->instructions as $n) {
                $r[$n] = $state;
                $state = $transfer($this->graph->instructions[$n], $n, $state);
            }
        }
        return $r;
    }
}
