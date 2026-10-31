<?php

const PROPERTIES = ['ELECTION_SAFETY', 'LEADER_COMPLETENESS', 'LOG_MATCHING', 'STATE_MACHINE_SAFETY', 'COMMITTED_KEPT'];

class Checker
{
    public array $leaders = [];
    public array $committed = [];
    public array $applied = [];
    public array $violations = [0, 0, 0, 0, 0];
    public int $elected = 0;
    public int $ticks = 0;
    public int $pairs = 0;
    public int $applies = 0;
    public int $truncations = 0;
    public int $removed = 0;

    public function leader(RaftNode $node): void
    {
        $this->elected++;
        if (!isset($this->leaders[$node->currentTerm])) $this->leaders[$node->currentTerm] = $node->number;
        elseif ($this->leaders[$node->currentTerm] !== $node->number) $this->violations[0]++;
        foreach ($this->committed as $index => $record) if ($index > $node->lastIndex() || $node->term($index) !== $record->term) {
            $this->violations[1]++;
            break;
        }
    }

    public function commit(RaftNode $node, int $first, int $last, int $time): void
    {
        for ($index = $first; $index <= $last; $index++) if (!isset($this->committed[$index])) {
            $this->committed[$index] = (object) ['term' => $node->term($index), 'time' => $time];
        }
    }

    public function apply(int $index, object $entry, ?string $result): void
    {
        $this->applies++;
        if (!isset($this->applied[$index])) $this->applied[$index] = (object) ['entry' => copyEntry($entry), 'result' => $result];
        elseif (!sameEntry($this->applied[$index]->entry, $entry)) $this->violations[3]++;
    }

    public function truncate(RaftNode $node, int $first): void
    {
        $this->truncations++;
        for ($index = $first; $index <= $node->lastIndex(); $index++) {
            $this->removed++;
            if (isset($this->committed[$index]) && $this->committed[$index]->term === $node->term($index)) $this->violations[4]++;
        }
    }

    public function matching(array $nodes): void
    {
        $this->ticks++;
        for ($a = 0; $a < count($nodes); $a++) for ($b = $a + 1; $b < count($nodes); $b++) {
            $this->pairs++;
            $first = $nodes[$a];
            $second = $nodes[$b];
            $greatest = min($first->lastIndex(), $second->lastIndex());
            while ($greatest > 0 && $first->term($greatest) !== $second->term($greatest)) $greatest--;
            for ($index = 1; $index <= $greatest; $index++) if (!sameEntry($first->entry($index), $second->entry($index))) {
                $this->violations[2]++;
                break;
            }
        }
    }

    public function lines(int $maximumTerm): array
    {
        $details = ['terms ' . $maximumTerm . ' leaders ' . count($this->leaders) . ' elected ' . $this->elected,
            'checks ' . $this->elected . ' committed ' . count($this->committed),
            'checks ' . $this->ticks . ' pairs ' . $this->pairs,
            'applies ' . $this->applies . ' indices ' . count($this->applied),
            'truncations ' . $this->truncations . ' removed ' . $this->removed];
        $lines = [];
        foreach (PROPERTIES as $i => $property) $lines[] = $property . ' ' . ($this->violations[$i] === 0 ? 'OK' : 'FAIL')
            . ' violations ' . $this->violations[$i] . ' ' . $details[$i];
        return $lines;
    }
}
