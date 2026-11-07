<?php
declare(strict_types=1);

namespace Crossword;

final class GridState
{
    public array $used = [];

    public function __construct(public array $letters, public array $words)
    {
        foreach ($words as $word) {
            if ($word !== null) {
                $this->used[$word] = true;
            }
        }
    }

    public function copy(): self { return new self($this->letters, $this->words); }

    public function pattern(Slot $slot): string
    {
        $pattern = '';
        foreach ($slot->cells as $cell) {
            $pattern .= $this->letters[$cell];
        }
        return $pattern;
    }

    public function assign(Slot $slot, string $word): array
    {
        $filled = [];
        foreach ($slot->cells as $position => $cell) {
            if ($this->letters[$cell] === '.') {
                $this->letters[$cell] = $word[$position];
                $filled[] = $cell;
            }
        }
        $this->words[$slot->index] = $word;
        $this->used[$word] = true;
        return $filled;
    }

    public function unassign(Slot $slot, array $filled): void
    {
        foreach ($filled as $cell) {
            $this->letters[$cell] = '.';
        }
        unset($this->used[$this->words[$slot->index]]);
        $this->words[$slot->index] = null;
    }
}

final class Attempt
{
    public GridState $state;
    public GridState $best;
    public int $nodes = 0;
    public int $backtracks = 0;
    public int $prunes = 0;
    public int $deadEnds = 0;
    public array $sequence = [];
    public int $maxDepth = 0;
    public array $failures;
    public array $trace = [];
    public string $outcome;

    public function __construct(
        public Layout $layout,
        public WordIndex $index,
        GridState $initial,
        public int $minScore,
        public int $budget
    ) {
        $this->state = $initial->copy();
        $this->best = $initial->copy();
        $this->failures = array_fill(0, count($layout->slots), 0);
    }

    public function run(): void
    {
        $this->outcome = match ($this->search()) {
            'complete' => 'filled',
            'fail' => 'unfillable',
            'abort' => 'budget',
        };
    }

    public function finalState(): GridState { return $this->outcome === 'filled' ? $this->state : $this->best; }

    private function candidates(Slot $slot): array
    {
        return $this->index->candidates($this->state->pattern($slot), $this->minScore, $this->state->used);
    }

    private function chooseSlot(): array
    {
        $chosen = null;
        $chosenWords = null;
        foreach ($this->layout->slots as $slot) {
            if ($this->state->words[$slot->index] !== null) {
                continue;
            }
            $words = $this->candidates($slot);
            if ($chosen === null || count($words) < count($chosenWords)) {
                $chosen = $slot;
                $chosenWords = $words;
            }
        }
        return [$chosen, $chosenWords];
    }

    private function wipedOutSlot(Slot $slot): ?Slot
    {
        foreach ($slot->crossings as $index) {
            $crossing = $this->layout->slots[$index];
            if ($this->state->words[$index] === null && $this->candidates($crossing) === []) {
                return $crossing;
            }
        }
        return null;
    }

    private function search(): string
    {
        [$slot, $words] = $this->chooseSlot();
        if ($slot === null) {
            return 'complete';
        }
        if ($words === []) {
            $this->deadEnds++;
            $this->failures[$slot->index]++;
            return 'fail';
        }
        foreach ($words as $word) {
            if ($this->nodes === $this->budget) {
                return 'abort';
            }
            $this->nodes++;
            $filled = $this->state->assign($slot, $word);
            $this->sequence[] = $slot;
            $wiped = $this->wipedOutSlot($slot);
            if ($this->nodes <= 10) {
                $this->trace[] = $slot->label . '=' . $word . ($wiped === null ? '' : '!');
            }
            if ($wiped !== null) {
                $this->prunes++;
                $this->failures[$wiped->index]++;
                $result = 'fail';
            } else {
                if (count($this->sequence) > $this->maxDepth) {
                    $this->maxDepth = count($this->sequence);
                    $this->best = $this->state->copy();
                }
                $result = $this->search();
            }
            if ($result !== 'fail') {
                return $result;
            }
            $this->state->unassign($slot, $filled);
            array_pop($this->sequence);
            $this->backtracks++;
        }
        return 'fail';
    }
}
