<?php
function reflect_words(array $words, array $replacements): array {
    $result = [];
    foreach ($words as $word) array_push($result, ...($replacements[$word] ?? [$word]));
    return $result;
}

function build_reply(string $template, array $bindings, array $replacements): string {
    $text = '';
    for ($index = 0; $index < strlen($template);) {
        $number = reference_number(substr($template, $index, 3));
        if ($number !== null) {
            $text .= implode(' ', reflect_words($bindings[$number - 1] ?? [], $replacements));
            $index += 3;
        } else $text .= $template[$index++];
    }
    return ucfirst(implode(' ', array_values(array_filter(explode(' ', $text), fn($word) => $word !== ''))));
}

function restated_words(array $arguments, array $bindings): array {
    $words = [];
    foreach ($arguments as $argument) {
        $number = reference_number($argument);
        array_push($words, ...($number === null ? [$argument] : ($bindings[$number - 1] ?? [])));
    }
    return $words;
}

function eliza_lines(string $text): array {
    $words = explode(' ', $text);
    $lines = ['ELIZA: ' . array_shift($words)];
    foreach ($words as $word) {
        $last = count($lines) - 1;
        if (strlen($lines[$last]) + strlen($word) + 1 <= 72) $lines[$last] .= " $word";
        else $lines[] = "       $word";
    }
    return $lines;
}
