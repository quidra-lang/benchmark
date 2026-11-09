<?php
declare(strict_types=1);

namespace IniValidator;

function isName(string $text): bool
{
    return preg_match('/\A[a-z][a-z0-9_]*\z/', $text) === 1;
}

function isSectionName(string $text): bool
{
    return preg_match('/\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z/', $text) === 1;
}

function trimmedSegments(array $segments): array
{
    $segments[0] = ltrim($segments[0], ' ');
    $last = count($segments) - 1;
    $segments[$last] = rtrim($segments[$last], ' ');
    return $segments;
}

final class Statement
{
    public function __construct(
        public string $kind,
        public int $line,
        public string $target,
        public string $value = '',
    ) {}
}

final class ParsedDocument
{
    public array $statements = [];
    public array $diagnostics = [];
}

function parseDocument(string $name, array $physical): ParsedDocument
{
    $document = new ParsedDocument();
    $section = $base = null;
    $assigned = [];
    $report = static function (int $line, string $code, string $message) use ($document, $name): void {
        $document->diagnostics[] = [$name, $line, $code, $message];
    };
    foreach (logicalLines($physical) as $line) {
        $number = $line->number;
        if ($line->error !== null) {
            $report($number, ...$line->error);
            continue;
        }
        $segments = trimmedSegments($line->segments);
        $first = $segments[0];
        if (count($segments) === 1 && $first === '') {
            continue;
        }
        if (str_starts_with($first, '[')) {
            $parts = explode(':', substr($first, 1, -1), 2);
            $header = trim($parts[0], ' ');
            $parent = isset($parts[1]) ? trim($parts[1], ' ') : null;
            $relative = str_starts_with($header, '.') && isSectionName(substr($header, 1));
            if (count($segments) !== 1 || !str_ends_with($first, ']') ||
                ($parent !== null && !isSectionName($parent)) ||
                (!$relative && !isSectionName($header))) {
                $report($number, 'E_SECTION', 'invalid section header');
                $section = null;
            } elseif ($relative && $base === null) {
                $report($number, 'E_SECTION', 'relative section without base');
                $section = null;
            } else {
                if ($relative) {
                    $section = $base . $header;
                } else {
                    $section = $base = $header;
                }
                if ($parent !== null) {
                    $document->statements[] = new Statement('inherit', $number, $section, $parent);
                }
            }
            continue;
        }
        if (str_starts_with($first, '@')) {
            $words = explode(' ', preg_replace('/ +/', ' ', $first));
            if (count($segments) !== 1 || count($words) !== 2 ||
                !in_array($words[0], ['@include', '@unset'], true) || !isName($words[1])) {
                $report($number, 'E_SYNTAX', 'invalid directive');
            } elseif ($words[0] === '@include') {
                $document->statements[] = new Statement('include', $number, $words[1]);
            } elseif ($section === null) {
                $report($number, 'E_NO_SECTION', 'no current section');
            } else {
                $document->statements[] = new Statement('unset', $number, $section . '.' . $words[1]);
            }
            continue;
        }
        $hasEquals = false;
        for ($i = 0; $i < count($segments); $i += 2) {
            $hasEquals = $hasEquals || str_contains($segments[$i], '=');
        }
        if (!$hasEquals) {
            $report($number, 'E_SYNTAX', 'invalid line');
            continue;
        }
        $equals = strpos($first, '=');
        if ($equals === false) {
            $report($number, 'E_SYNTAX', 'invalid key');
            continue;
        }
        $key = trim(substr($first, 0, $equals), ' ');
        $append = str_ends_with($key, '+');
        if ($append) {
            $key = rtrim(substr($key, 0, -1), ' ');
        }
        if (!isName($key)) {
            $report($number, 'E_SYNTAX', 'invalid key');
            continue;
        }
        $segments[0] = substr($first, $equals + 1);
        $segments = trimmedSegments($segments);
        if (count($segments) === 1) {
            $value = $segments[0];
        } elseif (count($segments) === 3 && $segments[0] === '' && $segments[2] === '') {
            $value = $segments[1];
        } else {
            $report($number, 'E_SYNTAX', 'invalid value');
            continue;
        }
        if ($section === null) {
            $report($number, 'E_NO_SECTION', 'no current section');
            continue;
        }
        $fullKey = $section . '.' . $key;
        if (!$append) {
            if (isset($assigned[$fullKey])) {
                $report($number, 'W_DUPLICATE', "$fullKey already set at line {$assigned[$fullKey]}");
            }
            $assigned[$fullKey] = $number;
        }
        $document->statements[] = new Statement($append ? 'append' : 'assign', $number, $fullKey, $value);
    }
    return $document;
}
