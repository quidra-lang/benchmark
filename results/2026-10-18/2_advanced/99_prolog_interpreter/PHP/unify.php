<?php

final class Trail
{
    private array $bindings = [];

    public function mark(): int
    {
        return count($this->bindings);
    }

    public function undo(int $mark): void
    {
        while (count($this->bindings) > $mark) {
            $v = array_pop($this->bindings);
            $v->binding = null;
        }
    }

    public function unify(mixed $left, mixed $right): bool
    {
        $pending = [[$left, $right]];
        while ($pending) {
            [$left, $right] = array_pop($pending);
            $left = dereference($left);
            $right = dereference($right);
            if ($left === $right)
                continue;
            if ($left instanceof PrologVariable) {
                $left->binding = $right;
                $this->bindings[] = $left;
            } elseif ($right instanceof PrologVariable) {
                $right->binding = $left;
                $this->bindings[] = $right;
            } elseif ($left instanceof Compound && $right instanceof Compound) {
                if ($left->name !== $right->name || count($left->args) !== count($right->args))
                    return false;
                for ($i = count($left->args) - 1; $i >= 0; --$i)
                    $pending[] = [$left->args[$i], $right->args[$i]];
            } elseif ($left !== $right)
                return false;
        }
        return true;
    }
}

function identical(mixed $left, mixed $right): bool
{
    $pending = [[$left, $right]];
    while ($pending) {
        [$left, $right] = array_pop($pending);
        $left = dereference($left);
        $right = dereference($right);
        if ($left === $right)
            continue;
        if ($left instanceof PrologVariable || $right instanceof PrologVariable)
            return false;
        if ($left instanceof Compound && $right instanceof Compound) {
            if ($left->name !== $right->name || count($left->args) !== count($right->args))
                return false;
            for ($i = count($left->args) - 1; $i >= 0; --$i)
                $pending[] = [$left->args[$i], $right->args[$i]];
        } elseif ($left !== $right)
            return false;
    }
    return true;
}
