<?php

const BODY_KINDS = ['paragraph', 'item', 'enum', 'quote', 'term'];
const DIRECTIVES = ['width', 'indent', 'align', 'page', 'header', 'footer', 'newpage', 'hyphenation', 'bib',
    'title', 'author', 'h1', 'h2', 'item', 'enum', 'quote', 'term', 'table', 'verbatim', 'toc', 'lot', 'index', 'bibliography'];
const PREAMBLE = ['page', 'header', 'footer'];
const EMPTY_ARGUMENT = ['newpage', 'verbatim', 'toc', 'lot', 'index', 'bibliography'];
const NONEMPTY_ARGUMENT = ['title', 'author', 'h1', 'h2', 'item', 'enum', 'quote'];

function splitFirst(string $text, string $separator): array
{
    $index = strpos($text, $separator);
    return $index === false ? [$text, ''] : [substr($text, 0, $index), substr($text, $index + strlen($separator))];
}

function bibliographyEntry(string $argument): ?object
{
    [$key, $rest] = splitFirst($argument, ' ');
    $parts = explode('|', $rest);
    if (!preg_match('/\A[a-z0-9]+\z/', $key) || count($parts) !== 3 || $parts[0] === '' || !preg_match('/\A[0-9]{4}\z/', $parts[1]) || $parts[2] === '') {
        return null;
    }
    return (object) ['key' => $key, 'author' => $parts[0], 'year' => $parts[1], 'title' => $parts[2]];
}

function validArgument(string $name, string $argument): bool
{
    if (in_array($name, ['width', 'indent', 'page'], true)) {
        [$minimum, $maximum] = ['width' => [20, 80], 'indent' => [0, 8], 'page' => [10, 100]][$name];
        return preg_match('/\A[0-9]{1,9}\z/', $argument) && (int) $argument >= $minimum && (int) $argument <= $maximum;
    }
    if ($name === 'align') return in_array($argument, ['left', 'right', 'center', 'justify'], true);
    if ($name === 'header' || $name === 'footer') return count(explode('|', $argument)) === 3;
    if (in_array($name, EMPTY_ARGUMENT, true)) return $argument === '';
    if (in_array($name, NONEMPTY_ARGUMENT, true)) return $argument !== '';
    if ($name === 'hyphenation') {
        foreach (explode(' ', $argument) as $word) {
            if (!preg_match('/\A[a-z]+(?:-[a-z]+)*\z/', $word)) return false;
        }
        return true;
    }
    if ($name === 'bib') return bibliographyEntry($argument) !== null;
    if ($name === 'term') {
        $position = strpos($argument, '|');
        return $position !== false && $position > 0 && $position < strlen($argument) - 1;
    }
    if ($name === 'table') return (bool) preg_match('/\A[lrc]+\z/', splitFirst($argument, ' ')[0]);
    return false;
}

function labeled(string $text): object
{
    $position = strrpos($text, ' {#');
    return $position !== false && str_ends_with($text, '}')
        ? (object) ['text' => substr($text, 0, $position), 'label' => substr($text, $position + 3, -1)]
        : (object) ['text' => $text, 'label' => null];
}

function parseDocument(array $lines): object
{
    $document = (object) ['blocks' => [], 'warnings' => [], 'dictionaryWords' => [], 'bibliography' => [],
        'pageWidth' => null, 'pageHeight' => 40, 'header' => ['', '', ''], 'footer' => ['', '', '']];
    $settings = ['width' => 60, 'indent' => 0, 'align' => 'left'];
    $accepted = [];
    $open = $inner = null;
    $pendingBreak = false;
    $create = function ($kind, $line) use ($document, &$settings, &$pendingBreak) {
        $block = (object) array_merge(['id' => count($document->blocks), 'kind' => $kind, 'line' => $line], $settings, ['pageBreak' => $pendingBreak]);
        $pendingBreak = false;
        if ($document->pageWidth === null) $document->pageWidth = $settings['width'];
        $document->blocks[] = $block;
        return $block;
    };
    foreach ($lines as $index => $text) {
        $line = $index + 1;
        if ($inner !== null) {
            if ($text === '.end') $inner = null;
            else $inner->inner[] = (object) compact('line', 'text');
            continue;
        }
        if ($text === '') {
            $open = null;
            continue;
        }
        if (!str_starts_with($text, '.')) {
            if ($open === null) {
                $open = $create('paragraph', $line);
                $open->bodyLines = [];
            }
            $open->bodyLines[] = (object) compact('line', 'text');
            continue;
        }
        $open = null;
        [$name, $argument] = splitFirst(substr($text, 1), ' ');
        $warning = null;
        if (!in_array($name, DIRECTIVES, true)) $warning = 'unknown directive .' . $name;
        elseif (!validArgument($name, $argument)) $warning = 'bad argument for .' . $name;
        elseif (in_array($name, PREAMBLE, true) && $document->blocks) $warning = '.' . $name . ' ignored after the preamble';
        elseif (in_array($name, PREAMBLE, true) && isset($accepted[$name])) $warning = 'duplicate .' . $name;
        if ($warning !== null) {
            $document->warnings[] = (object) ['line' => $line, 'message' => $warning];
            continue;
        }
        if ($name === 'width' || $name === 'indent') $settings[$name] = (int) $argument;
        elseif ($name === 'align') $settings['align'] = $argument;
        elseif (in_array($name, PREAMBLE, true)) {
            $accepted[$name] = true;
            if ($name === 'page') $document->pageHeight = (int) $argument;
            else $document->$name = explode('|', $argument);
        } elseif ($name === 'newpage') $pendingBreak = true;
        elseif ($name === 'hyphenation') $document->dictionaryWords = array_merge($document->dictionaryWords, explode(' ', $argument));
        elseif ($name === 'bib') {
            $entry = bibliographyEntry($argument);
            $entry->line = $line;
            $document->bibliography[] = $entry;
        } else {
            $block = $create($name, $line);
            if (in_array($name, BODY_KINDS, true)) {
                $body = $argument;
                if ($name === 'term') [$block->term, $body] = splitFirst($argument, '|');
                $block->bodyLines = [(object) ['line' => $line, 'text' => $body]];
                $open = $block;
            } elseif ($name === 'h1' || $name === 'h2') {
                $value = labeled($argument);
                $block->text = $value->text;
                $block->label = $value->label;
            } elseif ($name === 'title' || $name === 'author') $block->text = $argument;
            elseif ($name === 'table' || $name === 'verbatim') {
                if ($name === 'table') {
                    [$columns, $caption] = splitFirst($argument, ' ');
                    $value = labeled($caption);
                    $block->columns = $columns;
                    $block->caption = $value->text;
                    $block->label = $value->label;
                }
                $block->inner = [];
                $inner = $block;
            }
        }
    }
    if ($inner !== null) $document->warnings[] = (object) ['line' => $inner->line, 'message' => 'unterminated ' . $inner->kind];
    if ($document->pageWidth === null) $document->pageWidth = 60;
    return $document;
}
