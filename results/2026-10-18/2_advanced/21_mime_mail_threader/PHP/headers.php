<?php
declare(strict_types=1);

namespace MailThreads;

const ADDRESS_SPECIALS = '<>:;@,.';
const ADDRESS_WORD_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~";
const MIME_SPECIALS = '/;=';
const MIME_EXCLUDED = '()<>@,;:\\"/[]?=';

final class Header
{
    public array $fields = [];
    public array $invalidLines = [];

    public function value(string $name): ?string
    {
        $name = strtolower($name);
        foreach ($this->fields as [$fieldName, $value]) {
            if ($fieldName === $name) {
                return $value;
            }
        }
        return null;
    }

    public function count(string $name): int
    {
        $name = strtolower($name);
        $count = 0;
        foreach ($this->fields as [$fieldName, $_]) {
            $count += (int)($fieldName === $name);
        }
        return $count;
    }
}

final class Token
{
    public function __construct(public string $kind, public string $text, public bool $spaced) {}
}

function splitWords(string $text): array
{
    return preg_split('/[ \t]+/', $text, -1, PREG_SPLIT_NO_EMPTY);
}

function collapseWhitespace(string $text): string { return implode(' ', splitWords($text)); }

function parseFields(array $lines): Header
{
    $header = new Header();
    $inField = false;
    foreach ($lines as [$number, $text]) {
        if ($text[0] === ' ' || $text[0] === "\t") {
            if ($inField) {
                $header->fields[count($header->fields) - 1][1] .= $text;
            } else {
                $header->invalidLines[] = $number;
            }
            continue;
        }
        $colon = strpos($text, ':');
        $name = $colon === false ? '' : substr($text, 0, $colon);
        $inField = preg_match('/\A[!-~]+\z/', $name) === 1;
        if ($inField) {
            $header->fields[] = [strtolower($name), substr($text, $colon + 1)];
        } else {
            $header->invalidLines[] = $number;
        }
    }
    foreach ($header->fields as $index => [$name, $value]) {
        $header->fields[$index] = [$name, trim($value, " \t")];
    }
    return $header;
}

function removeComments(string $text): ?string
{
    $result = '';
    $depth = 0;
    for ($position = 0; $position < strlen($text); $position++) {
        $char = $text[$position];
        if ($depth === 0) {
            if ($char === '(') {
                $depth = 1;
                $result .= ' ';
            } else {
                $result .= $char;
            }
        } elseif ($char === '\\') {
            $position++;
        } elseif ($char === '(') {
            $depth++;
        } elseif ($char === ')') {
            $depth--;
        }
    }
    return $depth === 0 ? $result : null;
}

function skipComment(string $text, int $position): ?int
{
    $depth = 0;
    while ($position < strlen($text)) {
        $char = $text[$position];
        if ($char === '\\') {
            $position += 2;
            continue;
        }
        if ($char === '(') {
            $depth++;
        } elseif ($char === ')') {
            $depth--;
            if ($depth === 0) {
                return $position + 1;
            }
        }
        $position++;
    }
    return null;
}

function readQuoted(string $text, int $position): ?array
{
    $chars = '';
    $position++;
    while ($position < strlen($text)) {
        $char = $text[$position];
        if ($char === '"') {
            return [$chars, $position + 1];
        }
        if ($char === '\\') {
            $position++;
            if ($position === strlen($text)) {
                return null;
            }
            $char = $text[$position];
        }
        $chars .= $char;
        $position++;
    }
    return null;
}

function tokenize(string $text, string $specials, string $wordChars): ?array
{
    $tokens = [];
    $position = 0;
    $spaced = false;
    while ($position < strlen($text)) {
        $char = $text[$position];
        if ($char === ' ' || $char === "\t") {
            $spaced = true;
            $position++;
            continue;
        }
        if ($char === '(') {
            $position = skipComment($text, $position);
            if ($position === null) {
                return null;
            }
            $spaced = true;
            continue;
        }
        if ($char === '"') {
            $quoted = readQuoted($text, $position);
            if ($quoted === null) {
                return null;
            }
            [$value, $position] = $quoted;
            $tokens[] = new Token('quoted', $value, $spaced);
        } elseif (str_contains($specials, $char)) {
            $tokens[] = new Token($char, $char, $spaced);
            $position++;
        } elseif (str_contains($wordChars, $char)) {
            $end = $position + 1;
            while ($end < strlen($text) && str_contains($wordChars, $text[$end])) {
                $end++;
            }
            $tokens[] = new Token('word', substr($text, $position, $end - $position), $spaced);
            $position = $end;
        } else {
            return null;
        }
        $spaced = false;
    }
    return $tokens;
}

function tokenizeAddress(string $text): ?array { return tokenize($text, ADDRESS_SPECIALS, ADDRESS_WORD_CHARS); }
function tokenizeMime(string $text): ?array
{
    $wordChars = '';
    for ($code = 33; $code <= 126; $code++) {
        if (!str_contains(MIME_EXCLUDED, chr($code))) {
            $wordChars .= chr($code);
        }
    }
    return tokenize($text, MIME_SPECIALS, $wordChars);
}

function decodeQ(string $text): ?string
{
    $result = '';
    $position = 0;
    while ($position < strlen($text)) {
        $char = $text[$position];
        if ($char === '_') {
            $result .= ' ';
            $position++;
        } elseif ($char === '=') {
            $digits = substr($text, $position + 1, 2);
            if (preg_match('/\A[0-9A-Fa-f]{2}\z/', $digits) !== 1) {
                return null;
            }
            $result .= chr((int)hexdec($digits));
            $position += 3;
        } else {
            $result .= $char;
            $position++;
        }
    }
    return $result;
}

function decodeWord(string $word): array
{
    if (strlen($word) < 4 || !str_starts_with($word, '=?') || !str_ends_with($word, '?=')) {
        return [$word, false, false];
    }
    $pieces = explode('?', substr($word, 2, -2));
    if (count($pieces) !== 3 || in_array('', $pieces, true)) {
        return [$word, false, false];
    }
    $decoded = null;
    if (strtolower($pieces[0]) === 'us-ascii') {
        $decoded = match (strtolower($pieces[1])) {
            'q' => decodeQ($pieces[2]),
            'b' => strictBase64($pieces[2]),
            default => null,
        };
    }
    if ($decoded !== null) {
        for ($position = 0; $position < strlen($decoded); $position++) {
            $byte = ord($decoded[$position]);
            if ($byte < 32 || $byte > 126) {
                $decoded = null;
                break;
            }
        }
    }
    return $decoded === null ? [$word, false, true] : [$decoded, true, false];
}

function decodeUnstructured(string $value): array
{
    $parts = [];
    $error = $previous = false;
    foreach (splitWords($value) as $word) {
        [$text, $decoded, $failed] = decodeWord($word);
        if ($parts !== [] && !($decoded && $previous)) {
            $parts[] = ' ';
        }
        $parts[] = $text;
        $previous = $decoded;
        $error = $error || $failed;
    }
    return [collapseWhitespace(implode('', $parts)), $error];
}

function parseParameters(string $value, bool $withSubtype): ?array
{
    $tokens = tokenizeMime($value);
    if ($tokens === null || $tokens === [] || $tokens[0]->kind !== 'word') {
        return null;
    }
    $mainType = strtolower($tokens[0]->text);
    $subtype = '';
    $position = 1;
    if ($withSubtype) {
        if (count($tokens) < 3 || $tokens[1]->kind !== '/' || $tokens[2]->kind !== 'word') {
            return null;
        }
        $subtype = strtolower($tokens[2]->text);
        $position = 3;
    }
    $parameters = [];
    while ($position < count($tokens)) {
        if ($position + 3 >= count($tokens) || $tokens[$position]->kind !== ';' || $tokens[$position + 1]->kind !== 'word'
            || $tokens[$position + 2]->kind !== '=' || !in_array($tokens[$position + 3]->kind, ['word', 'quoted'], true)) {
            return null;
        }
        $name = '#' . strtolower($tokens[$position + 1]->text);
        if (!array_key_exists($name, $parameters)) {
            $parameters[$name] = $tokens[$position + 3]->text;
        }
        $position += 4;
    }
    return [$mainType, $subtype, $parameters];
}
