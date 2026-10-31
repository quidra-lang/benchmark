<?php

final readonly class Clause
{
    public function __construct(
        public mixed $head,
        public mixed $body,
        public string $file,
        public int $line,
    ) {}

    public function copy(): array
    {
        return copyTerms($this->head, $this->body);
    }
}

final class Database
{
    public array $predicates = [], $indicators = [];

    public function add(Clause $c): void
    {
        $indicator = indicator($c->head);
        $key = serialize($indicator);
        $this->indicators[$key] = $indicator;
        $this->predicates[$key][] = $c;
    }

    public function candidates(mixed $goal): array
    {
        $key = indicator($goal);
        $clauses = $this->predicates[serialize($key)];
        if ($key[1] === 0)
            return $clauses;
        return array_values(array_filter($clauses, fn($c) => sameKind($goal->args[0], $c->head->args[0])));
    }
}
