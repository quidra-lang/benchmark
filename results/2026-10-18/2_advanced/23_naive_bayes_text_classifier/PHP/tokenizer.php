<?php
declare(strict_types=1);

namespace TextClassifier;

final class Tokens
{
    public int $rawCount = 0;
    public int $stopwordCount = 0;
    public int $shortCount = 0;
    public array $words = [];
    public array $bigrams = [];
    public array $bigramTerms;

    public function __construct(string $text, array $stopwords)
    {
        preg_match_all('/[a-z0-9]+/', strtolower($text), $matches);
        foreach ($matches[0] as $word) {
            $this->rawCount++;
            if (isset($stopwords['#' . $word])) {
                $this->stopwordCount++;
            } elseif (strlen($word) === 1) {
                $this->shortCount++;
            } else {
                $this->words[] = $word;
            }
        }
        for ($index = 0; $index + 1 < count($this->words); $index++) {
            $this->bigrams[] = $this->words[$index] . '_' . $this->words[$index + 1];
        }
        $this->bigramTerms = array_merge($this->words, $this->bigrams);
    }

    public function terms(bool $useBigrams): array { return $useBigrams ? $this->bigramTerms : $this->words; }
}

function isBigram(string $term): bool { return str_contains($term, '_'); }
