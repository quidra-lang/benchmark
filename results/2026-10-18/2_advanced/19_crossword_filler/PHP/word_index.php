<?php
declare(strict_types=1);

namespace Crossword;

const UPPERCASE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

function isValidWord(string $text): bool
{
    return preg_match('/\A[A-Z]{3,15}\z/', $text) === 1;
}

function isValidInteger(string $text, int $low, int $high): bool
{
    return strlen($text) <= strlen((string)$high) && preg_match('/\A[1-9][0-9]*\z/', $text) === 1
        && (int)$text >= $low && (int)$text <= $high;
}

function wordLineError(string $line): ?string
{
    if (substr_count($line, ' ') !== 1) {
        return 'bad format';
    }
    [$word, $score] = explode(' ', $line);
    if (!isValidWord($word)) {
        return 'bad word';
    }
    return isValidInteger($score, 1, 100) ? null : 'bad score';
}

function clueLineError(string $line): ?string
{
    if (substr_count($line, '|') !== 1) {
        return 'bad format';
    }
    [$word, $clue] = explode('|', $line);
    if (!isValidWord($word)) {
        return 'bad word';
    }
    return strlen($clue) < 1 || strlen($clue) > 60 || $clue[0] === ' ' || $clue[strlen($clue) - 1] === ' ' ? 'bad clue' : null;
}

function wordMatches(string $word, string $pattern): bool
{
    for ($position = 0; $position < strlen($pattern); $position++) {
        if ($pattern[$position] !== '.' && $pattern[$position] !== $word[$position]) {
            return false;
        }
    }
    return true;
}

final class WordIndex
{
    public array $ranked;
    public array $byLength = [];
    public array $byLetter = [];

    public function __construct(public array $scores)
    {
        $this->ranked = array_keys($scores);
        usort($this->ranked, static fn(string $a, string $b): int => ($scores[$b] <=> $scores[$a]) ?: strcmp($a, $b));
        foreach ($this->ranked as $word) {
            $length = strlen($word);
            $this->byLength[$length][] = $word;
            for ($position = 0; $position < $length; $position++) {
                $this->byLetter[$length . ':' . $position . ':' . $word[$position]][] = $word;
            }
        }
    }

    public function candidates(string $pattern, int $minScore, array $used): array
    {
        $length = strlen($pattern);
        $pool = $this->byLength[$length] ?? [];
        for ($position = 0; $position < $length; $position++) {
            if ($pattern[$position] !== '.') {
                $bucket = $this->byLetter[$length . ':' . $position . ':' . $pattern[$position]] ?? [];
                if (count($bucket) < count($pool)) {
                    $pool = $bucket;
                }
            }
        }
        $result = [];
        foreach ($pool as $word) {
            if ($this->scores[$word] < $minScore) {
                break;
            }
            if (!isset($used[$word]) && wordMatches($word, $pattern)) {
                $result[] = $word;
            }
        }
        return $result;
    }
}
