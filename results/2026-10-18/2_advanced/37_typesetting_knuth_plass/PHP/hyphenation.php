<?php

class Dictionary
{
    private array $words = [];

    public function __construct(array $lines, array $additions)
    {
        foreach (array_merge($lines, $additions) as $line) {
            $word = '';
            $points = [];
            foreach (str_split($line) as $character) {
                if ($character === '-') {
                    $points[] = strlen($word);
                } else {
                    $word .= $character;
                }
            }
            $this->words[$word] = $points;
        }
    }

    public function splitPoints(string $word, int $leftMinimum, int $rightMinimum): array
    {
        $points = [];
        $first = 0;
        $last = strlen($word);
        while ($first < $last && !preg_match('/[A-Za-z]/', $word[$first])) {
            $first++;
        }
        while ($last > $first && !preg_match('/[A-Za-z]/', $word[$last - 1])) {
            $last--;
        }
        $core = substr($word, $first, $last - $first);
        if (preg_match('/\A[A-Za-z]+\z/', $core)) {
            foreach ($this->words[strtolower($core)] ?? [] as $position) {
                if ($position >= $leftMinimum && strlen($core) - $position >= $rightMinimum) {
                    $points[] = (object) ['position' => $first + $position, 'hyphen' => true];
                }
            }
        }
        for ($index = 1; $index + 1 < strlen($word); $index++) {
            if ($word[$index] === '-' && preg_match('/[A-Za-z]/', $word[$index - 1]) && preg_match('/[A-Za-z]/', $word[$index + 1])) {
                $points[] = (object) ['position' => $index + 1, 'hyphen' => false];
            }
        }
        usort($points, fn($a, $b) => $a->position <=> $b->position);
        return $points;
    }
}
