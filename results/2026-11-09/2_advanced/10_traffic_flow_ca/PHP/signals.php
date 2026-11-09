<?php
final class Phase {
    public int $duration;
    public string $token;
    public array $greens;
    public function __construct(string $text) { [$duration, $this->token] = explode(':', $text); $this->duration = (int)$duration; $this->greens = $this->token === '-' ? [] : explode(',', $this->token); }
}
final class Junction {
    public array $phases, $incoming = [];
    public int $cycle = 0;
    public function __construct(public string $node, public int $offset, array $tokens) { $this->phases = array_map(fn($token) => new Phase($token), $tokens); foreach ($this->phases as $phase) $this->cycle += $phase->duration; }
    public function green(string $segment, int $step): bool {
        if (!$this->phases) return true; $position = ($step - 1 + $this->offset) % $this->cycle;
        foreach ($this->phases as $phase) { if ($position < $phase->duration) return in_array($segment, $phase->greens, true); $position -= $phase->duration; }
    }
    public function planLines(): array {
        if (!$this->phases) return ["JUNCTION $this->node unsignalized"];
        $lines = ["JUNCTION $this->node signal cycle $this->cycle offset $this->offset"]; $begin = 0;
        foreach ($this->phases as $j => $phase) { $end = $begin + $phase->duration - 1; $lines[] = '  PHASE ' . ($j + 1) . " $begin-$end $phase->token"; $begin = $end + 1; } return $lines;
    }
}
