<?php

require_once __DIR__ . '/document_parser.php';
require_once __DIR__ . '/hyphenation.php';
require_once __DIR__ . '/line_breaker.php';
require_once __DIR__ . '/page_builder.php';
require_once __DIR__ . '/renderer.php';

function readLines(string $filename): array
{
    return file($filename, FILE_IGNORE_NEW_LINES);
}

function registerDocument(object $document): void
{
    $document->labels = [];
    $document->entries = [];
    $document->headings = [];
    $document->tables = [];
    $document->bodies = [];
    $chapter = $section = $tableNumber = 0;
    foreach ($document->blocks as $index => $block) {
        $previous = $document->blocks[$index - 1] ?? null;
        if ($block->kind === 'h1') {
            $chapter++;
            $section = 0;
            $block->number = (string) $chapter;
            if ($index > 0) $block->pageBreak = true;
        } elseif ($block->kind === 'h2') {
            $section++;
            $block->number = $chapter . '.' . $section;
        } elseif ($block->kind === 'enum') {
            $block->number = ($previous->kind ?? null) === 'enum' ? $previous->number + 1 : 1;
        } elseif ($block->kind === 'table' && $block->caption !== '') {
            $block->number = ++$tableNumber;
            $document->tables[] = $block;
        }
        if ($block->kind === 'h1' || $block->kind === 'h2') $document->headings[] = $block;
        if (($block->label ?? null) !== null) {
            if (isset($document->labels[$block->label])) {
                $document->warnings[] = (object) ['line' => $block->line, 'message' => 'duplicate label ' . $block->label];
                $block->label = null;
            } else $document->labels[$block->label] = $block;
        }
        if ($block->kind === 'paragraph' && in_array($previous->kind ?? null, ['h1', 'h2'], true)) $block->indent = 0;
        if (in_array($block->kind, BODY_KINDS, true)) {
            $block->bodyNumber = count($document->bodies) + 1;
            $document->bodies[] = $block;
        }
    }
    foreach ($document->bibliography as $entry) {
        if (isset($document->entries[$entry->key])) {
            $document->warnings[] = (object) ['line' => $entry->line, 'message' => 'duplicate bibliography key ' . $entry->key];
        } else {
            $entry->cited = false;
            $document->entries[$entry->key] = $entry;
        }
    }
}

function parseBodyLine(object $document, object $bodyLine): array
{
    $tokens = [];
    $text = $bodyLine->text;
    $warn = function ($message) use ($document, $bodyLine) {
        $document->warnings[] = (object) ['line' => $bodyLine->line, 'message' => $message];
    };
    $position = 0;
    while ($position < strlen($text)) {
        $opening = strpos($text, '{', $position);
        if ($opening === false) {
            $tokens[] = substr($text, $position);
            break;
        }
        if ($opening > $position) $tokens[] = substr($text, $position, $opening - $position);
        $closing = strpos($text, '}', $opening + 1);
        if ($closing === false) {
            $warn('unclosed brace');
            $tokens[] = substr($text, $opening);
            break;
        }
        $content = substr($text, $opening + 1, $closing - $opening - 1);
        $colon = strpos($content, ':');
        $kind = $colon === false ? $content : substr($content, 0, $colon);
        $argument = $colon === false ? '' : substr($content, $colon + 1);
        if ($colon === false || $argument === '' || !in_array($kind, ['ref', 'page', 'fn', 'idx', 'cite'], true)) {
            $warn('bad command {' . $content . '}');
        } else {
            $command = (object) compact('kind', 'argument');
            if (($kind === 'ref' || $kind === 'page') && !isset($document->labels[$argument])) $warn('undefined label ' . $argument);
            if ($kind === 'cite') {
                foreach (explode(',', $argument) as $key) {
                    if (isset($document->entries[$key])) $document->entries[$key]->cited = true;
                    else $warn('undefined citation ' . $key);
                }
            }
            if ($kind === 'fn') {
                $command->number = count($document->footnotes) + 1;
                $document->footnotes[] = (object) ['number' => $command->number, 'text' => $argument];
            } elseif ($kind === 'idx') {
                $command->number = count($document->indexMarks) + 1;
                $document->indexMarks[] = (object) ['number' => $command->number, 'phrase' => $argument];
            }
            $tokens[] = $command;
        }
        $position = $closing + 1;
    }
    return $tokens;
}

function checkDocument(object $document): void
{
    $document->footnotes = [];
    $document->indexMarks = [];
    foreach ($document->blocks as $block) {
        if ($block->kind === 'table') {
            $rows = [];
            foreach ($block->inner as $inner) {
                $cells = array_map('trim', explode('|', $inner->text));
                if (count($cells) !== strlen($block->columns)) {
                    $document->warnings[] = (object) ['line' => $inner->line, 'message' => 'table row has ' . count($cells)
                        . ' cells, expected ' . strlen($block->columns)];
                }
                $cells = array_slice($cells, 0, strlen($block->columns));
                while (count($cells) < strlen($block->columns)) $cells[] = '';
                $rows[] = $cells;
            }
            $block->tableLines = tableRows($rows, $block->columns);
            if ($block->caption !== '') array_unshift($block->tableLines, 'Table ' . $block->number . '. ' . $block->caption);
            $maximum = 0;
            foreach ($block->tableLines as $line) $maximum = max($maximum, strlen($line));
            if ($maximum > $block->width) $document->warnings[] = (object) ['line' => $block->line, 'message' => 'table too wide by ' . ($maximum - $block->width)];
        } elseif ($block->kind === 'verbatim') {
            foreach ($block->inner as $inner) {
                if (strlen($inner->text) > $block->width) {
                    $document->warnings[] = (object) ['line' => $inner->line, 'message' => 'verbatim line too long by ' . (strlen($inner->text) - $block->width)];
                }
            }
        } elseif (in_array($block->kind, BODY_KINDS, true)) {
            $block->body = [];
            foreach ($block->bodyLines as $index => $bodyLine) {
                if ($index > 0) $block->body[] = ' ';
                $block->body = array_merge($block->body, parseBodyLine($document, $bodyLine));
            }
        }
    }
    foreach ($document->entries as $entry) {
        if (!$entry->cited) $document->warnings[] = (object) ['line' => $entry->line, 'message' => 'unused bibliography entry ' . $entry->key];
    }
    usort($document->warnings, fn($a, $b) => $a->line <=> $b->line);
}

function bibliographyLabels(object $document): void
{
    $entries = array_values(array_filter($document->entries, fn($entry) => $entry->cited));
    foreach ($entries as $entry) {
        $surnames = explode(' and ', $entry->author);
        if (count($surnames) === 1) $stem = substr($surnames[0], 0, 3);
        elseif (count($surnames) <= 4) $stem = implode('', array_map(fn($name) => $name[0], $surnames));
        else $stem = implode('', array_map(fn($name) => $name[0], array_slice($surnames, 0, 3))) . '+';
        $entry->base = $stem . substr($entry->year, -2);
    }
    usort($entries, fn($a, $b) => strcmp($a->base, $b->base) ?: strcmp($a->author, $b->author)
        ?: strcmp($a->title, $b->title) ?: strcmp($a->key, $b->key));
    for ($start = 0; $start < count($entries);) {
        $end = $start + 1;
        while ($end < count($entries) && $entries[$end]->base === $entries[$start]->base) $end++;
        for ($index = $start; $index < $end; $index++) {
            $entries[$index]->label = $entries[$index]->base . ($end - $start === 1 ? '' : chr(97 + $index - $start));
        }
        $start = $end;
    }
    $document->cited = $entries;
}

function prepareIndex(object $document): void
{
    $parents = [];
    $makeEntry = fn($name) => (object) ['name' => $name, 'marks' => [], 'crossReferences' => [], 'children' => []];
    foreach ($document->indexMarks as $mark) {
        $bar = strpos($mark->phrase, '|');
        $entryPart = $bar === false ? $mark->phrase : substr($mark->phrase, 0, $bar);
        $crossReference = $bar === false ? null : substr($mark->phrase, $bar + 1);
        $exclamation = strpos($entryPart, '!');
        $parentName = $exclamation === false ? $entryPart : substr($entryPart, 0, $exclamation);
        if (!isset($parents[$parentName])) $parents[$parentName] = $makeEntry($parentName);
        $entry = $parents[$parentName];
        if ($exclamation !== false) {
            $childName = substr($entryPart, $exclamation + 1);
            if (!isset($entry->children[$childName])) $entry->children[$childName] = $makeEntry($childName);
            $entry = $entry->children[$childName];
        }
        if ($crossReference === null) $entry->marks[] = $mark->number;
        else $entry->crossReferences[$crossReference] = true;
    }
    $order = fn($a, $b) => strcmp(strtolower($a->name), strtolower($b->name)) ?: strcmp($a->name, $b->name);
    $parents = array_values($parents);
    usort($parents, $order);
    $lines = [];
    $previousGroup = null;
    foreach ($parents as $parent) {
        $group = preg_match('/[A-Za-z]/', $parent->name[0]) ? strtoupper($parent->name[0]) : 'Symbols';
        if ($group !== $previousGroup) $lines[] = (object) ['text' => $group];
        $previousGroup = $group;
        $lines[] = (object) ['entry' => $parent, 'child' => false];
        $children = array_values($parent->children);
        usort($children, $order);
        foreach ($children as $child) $lines[] = (object) ['entry' => $child, 'child' => true];
    }
    $document->indexLines = $lines;
}

function citationText(object $document, string $argument): string
{
    $labels = [];
    $missing = false;
    foreach (explode(',', $argument) as $key) {
        if (isset($document->entries[$key])) $labels[$document->entries[$key]->label] = true;
        else $missing = true;
    }
    $parts = array_keys($labels);
    sort($parts, SORT_STRING);
    if ($missing) $parts[] = '?';
    return '[' . implode(', ', $parts) . ']';
}

function expandBody(object $document, object $block, array $pageValues): object
{
    $text = '';
    $marks = [];
    foreach ($block->body as $token) {
        if (is_string($token)) $text .= $token;
        elseif ($token->kind === 'ref') $text .= isset($document->labels[$token->argument]) ? $document->labels[$token->argument]->number : '??';
        elseif ($token->kind === 'page') $text .= isset($document->labels[$token->argument]) ? $pageValues[$token->argument] : '??';
        elseif ($token->kind === 'cite') $text .= citationText($document, $token->argument);
        elseif ($token->kind === 'fn') {
            $marks[] = (object) ['kind' => 'fn', 'number' => $token->number, 'offset' => strlen($text)];
            $text .= '[' . $token->number . ']';
        } elseif ($token->kind === 'idx') {
            $marks[] = (object) ['kind' => 'idx', 'number' => $token->number, 'offset' => strlen($text) - 1];
        }
    }
    preg_match_all('/[^ ]+/', $text, $matches, PREG_OFFSET_CAPTURE);
    $words = [];
    $ranges = [];
    foreach ($matches[0] as [$word, $start]) {
        $words[] = $word;
        $ranges[] = (object) ['start' => $start, 'end' => $start + strlen($word)];
    }
    $word = 0;
    foreach ($marks as $mark) {
        while ($mark->offset >= $ranges[$word]->end) $word++;
        $mark->word = $word;
        $mark->position = $mark->offset - $ranges[$word]->start;
    }
    return (object) compact('words', 'marks');
}

function lineProblem(array $words, int $firstCapacity, int $laterCapacity, Dictionary $dictionary, array $parameters): object
{
    $offsets = [];
    $points = [(object) ['startWord' => 0, 'startPosition' => 0, 'mid' => false, 'hyphen' => false]];
    $offset = 0;
    foreach ($words as $word => $text) {
        $offsets[] = $offset;
        $offset += strlen($text) + 1;
        foreach ($dictionary->splitPoints($text, $parameters['left_min'], $parameters['right_min']) as $split) {
            $points[] = (object) ['startWord' => $word, 'startPosition' => $split->position, 'endWord' => $word,
                'endPosition' => $split->position, 'mid' => true, 'hyphen' => $split->hyphen];
        }
        $points[] = (object) ['startWord' => $word + 1, 'startPosition' => 0, 'endWord' => $word,
            'endPosition' => strlen($text), 'mid' => false, 'hyphen' => false];
    }
    $measure = function ($a, $b) use ($points, $offsets, $firstCapacity, $laterCapacity) {
        $start = $points[$a];
        $end = $points[$b];
        $length = $offsets[$end->endWord] + $end->endPosition - $offsets[$start->startWord] - $start->startPosition + (int) $end->hyphen;
        $capacity = $a === 0 ? $firstCapacity : $laterCapacity;
        return (object) ['a' => $a, 'b' => $b, 'firstWord' => $start->startWord, 'firstPosition' => $start->startPosition,
            'lastWord' => $end->endWord, 'lastPosition' => $end->endPosition, 'length' => $length, 'capacity' => $capacity,
            'slack' => $capacity - $length, 'gaps' => $end->endWord - $start->startWord, 'last' => $b === count($points) - 1, 'mid' => $end->mid];
    };
    return (object) compact('words', 'points', 'measure');
}

function breakText(array $words, array $marks, int $firstCapacity, int $laterCapacity, string $alignment,
    callable $prefix, Dictionary $dictionary, array $parameters, string $method): object
{
    $problem = lineProblem($words, $firstCapacity, $laterCapacity, $dictionary, $parameters);
    $breaking = $method === 'kp' ? optimal($problem, $parameters) : greedy($problem, $parameters);
    $lines = [];
    $start = 0;
    foreach ($breaking->breaks as $end) {
        $line = ($problem->measure)($start, $end);
        $line->pieces = [];
        for ($word = $line->firstWord; $word <= $line->lastWord; $word++) {
            $first = $word === $line->firstWord ? $line->firstPosition : 0;
            $last = $word === $line->lastWord ? $line->lastPosition : strlen($words[$word]);
            $line->pieces[] = str_replace('~', ' ', substr($words[$word], $first, $last - $first));
        }
        if ($problem->points[$end]->hyphen) $line->pieces[count($line->pieces) - 1] .= '-';
        $line->marks = array_values(array_filter($marks, fn($mark) => $mark->word >= $line->firstWord && $mark->word <= $line->lastWord
            && ($mark->word !== $line->firstWord || $mark->position >= $line->firstPosition)
            && ($mark->word !== $line->lastWord || $mark->position < $line->lastPosition)));
        $line->footnotes = [];
        foreach ($line->marks as $mark) if ($mark->kind === 'fn') $line->footnotes[] = $mark->number;
        $line->text = $prefix(count($lines)) . displayLine($line, $alignment);
        $lines[] = $line;
        $start = $end;
    }
    return (object) ['lines' => $lines, 'cost' => $breaking->cost];
}

function bodyStyle(object $block): object
{
    if ($block->kind === 'paragraph') return (object) ['first' => $block->width - $block->indent, 'later' => $block->width,
        'prefix' => fn($index) => $index === 0 ? str_repeat(' ', $block->indent) : ''];
    if ($block->kind === 'item') return (object) ['first' => $block->width - 2, 'later' => $block->width - 2,
        'prefix' => fn($index) => $index === 0 ? '- ' : '  '];
    if ($block->kind === 'enum') return (object) ['first' => $block->width - 4, 'later' => $block->width - 4,
        'prefix' => fn($index) => $index === 0 ? str_pad((string) $block->number, 2, ' ', STR_PAD_LEFT) . '. ' : '    '];
    if ($block->kind === 'quote') return (object) ['first' => $block->width - 8, 'later' => $block->width - 8, 'prefix' => fn($index) => '    '];
    return (object) ['first' => $block->width - 12, 'later' => $block->width - 12,
        'prefix' => fn($index) => $index === 0 && strlen($block->term) <= 10 ? str_pad($block->term, 12) : str_repeat(' ', 12)];
}

function plainLines(array $strings): array
{
    return array_map(fn($text) => (object) ['text' => $text, 'marks' => [], 'footnotes' => []], $strings);
}

function typesetBlocks(object $document, Dictionary $dictionary, array $parameters, string $method, array $pageValues): object
{
    $blocks = [];
    $bodies = [];
    $references = [];
    $footnotes = [];
    foreach ($document->footnotes as $note) {
        $prefix = '[' . $note->number . '] ';
        $capacity = $document->pageWidth - strlen($prefix);
        $words = array_values(array_filter(explode(' ', $note->text), fn($word) => $word !== ''));
        $footnotes[$note->number] = breakText($words, [], $capacity, $capacity, 'left',
            fn($index) => $index === 0 ? $prefix : str_repeat(' ', strlen($prefix)), $dictionary, $parameters, $method);
    }
    $add = function ($source, $type, $list, $lines, $first) use (&$blocks) {
        if ($first) $lines[0]->blockStart = $source;
        $blocks[] = (object) ['type' => $type, 'list' => $list, 'lines' => $lines, 'pageBreak' => $first && $source->pageBreak];
    };
    foreach ($document->blocks as $block) {
        if (in_array($block->kind, BODY_KINDS, true)) {
            $expanded = expandBody($document, $block, $pageValues);
            $style = bodyStyle($block);
            $broken = breakText($expanded->words, $expanded->marks, $style->first, $style->later, $block->align,
                $style->prefix, $dictionary, $parameters, $method);
            $bodies[$block->id] = $broken;
            $lines = $block->kind === 'term' && strlen($block->term) > 10 ? array_merge(plainLines([$block->term]), $broken->lines) : $broken->lines;
            $add($block, 'flow', in_array($block->kind, ['item', 'enum', 'term'], true), $lines, true);
        } elseif ($block->kind === 'title' || $block->kind === 'author') {
            $text = $block->kind === 'title' ? strtoupper($block->text) : $block->text;
            $add($block, 'heading', false, plainLines([str_repeat(' ', intdiv($block->width - strlen($text), 2)) . $text]), true);
        } elseif ($block->kind === 'h1' || $block->kind === 'h2') {
            $text = $block->number . ' ' . ($block->kind === 'h1' ? strtoupper($block->text) : $block->text);
            $add($block, 'heading', false, plainLines([$text, str_repeat($block->kind === 'h1' ? '=' : '-', strlen($text))]), true);
        } elseif ($block->kind === 'table') {
            $add($block, 'solid', false, plainLines($block->tableLines), true);
        } elseif ($block->kind === 'verbatim') {
            $add($block, 'flow', false, plainLines(array_map(fn($line) => $line->text, $block->inner)), true);
        } elseif ($block->kind === 'toc' || $block->kind === 'lot') {
            $contents = $block->kind === 'toc';
            $add($block, 'heading', false, plainLines($contents ? ['CONTENTS', '========'] : ['TABLES', '======']), true);
            $targets = $contents ? $document->headings : $document->tables;
            $lines = [];
            foreach ($targets as $target) {
                $left = $contents ? ($target->kind === 'h2' ? '  ' : '') . $target->number . ' ' . $target->text
                    : 'Table ' . $target->number . '. ' . $target->caption;
                $lines[] = (object) ['text' => '', 'marks' => [], 'footnotes' => [],
                    'dynamic' => (object) ['kind' => 'listing', 'target' => $target->id, 'left' => $left, 'width' => $block->width]];
            }
            $add($block, 'flow', false, $lines, false);
        } elseif ($block->kind === 'index') {
            $add($block, 'heading', false, plainLines(['INDEX', '=====']), true);
            $lines = [];
            foreach ($document->indexLines as $item) {
                $lines[] = isset($item->entry) ? (object) ['text' => '', 'marks' => [], 'footnotes' => [],
                    'dynamic' => (object) ['kind' => 'index', 'entry' => $item->entry, 'child' => $item->child]] : plainLines([$item->text])[0];
            }
            $add($block, 'flow', false, $lines, false);
        } elseif ($block->kind === 'bibliography') {
            $add($block, 'heading', false, plainLines(['REFERENCES', '==========']), true);
            $prefixWidth = 0;
            foreach ($document->cited as $entry) $prefixWidth = max($prefixWidth, strlen($entry->label) + 3);
            $entries = [];
            foreach ($document->cited as $entry) {
                $text = $entry->author . '. ' . $entry->year . '. ' . $entry->title;
                $prefix = str_pad('[' . $entry->label . ']', $prefixWidth);
                $capacity = $block->width - $prefixWidth;
                $words = array_values(array_filter(explode(' ', $text), fn($word) => $word !== ''));
                $broken = breakText($words, [], $capacity, $capacity, 'left',
                    fn($index) => $index === 0 ? $prefix : str_repeat(' ', $prefixWidth), $dictionary, $parameters, $method);
                $entries[] = (object) compact('entry', 'broken');
                $add($block, 'flow', true, $broken->lines, false);
            }
            $references[$block->id] = $entries;
        }
    }
    return (object) compact('blocks', 'bodies', 'references', 'footnotes');
}

function roman(int $number): string
{
    return str_repeat('x', intdiv($number, 10)) . ['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix'][$number % 10];
}

function numberPages(object $document, array $rawPages): object
{
    $pages = [];
    $blockPages = [];
    foreach ($rawPages as $page) {
        $page->chapterStart = ($page->content[0]->blockStart->kind ?? null) === 'h1';
        if ($page->chapterStart && (count($pages) + 1) % 2 === 0) {
            $pages[] = (object) ['serial' => count($pages) + 1, 'blank' => true, 'content' => [], 'footnotes' => [], 'height' => 0, 'endsByForce' => true];
        }
        $page->serial = count($pages) + 1;
        $pages[] = $page;
        foreach ($page->content as $line) if (isset($line->blockStart)) $blockPages[$line->blockStart->id] = $page;
    }
    $firstChapter = null;
    foreach ($document->headings as $block) {
        if ($block->kind === 'h1') {
            $firstChapter = $block;
            break;
        }
    }
    $frontMatter = $firstChapter !== null ? $blockPages[$firstChapter->id]->serial - 1 : 0;
    $indexPages = [];
    foreach ($pages as $page) {
        $page->bodyNumber = $page->serial - $frontMatter;
        $page->display = $page->serial <= $frontMatter ? roman($page->serial) : (string) $page->bodyNumber;
        foreach ($page->content as $line) {
            foreach ($line->marks as $mark) if ($mark->kind === 'idx') $indexPages[$mark->number] = $page->bodyNumber;
        }
    }
    $labelValues = [];
    foreach ($document->labels as $label => $block) $labelValues[$label] = $blockPages[$block->id]->display;
    return (object) compact('pages', 'blockPages', 'indexPages', 'frontMatter', 'labelValues');
}

function pageList(array $numbers): string
{
    $ordered = array_values(array_unique($numbers));
    sort($ordered, SORT_NUMERIC);
    $pieces = [];
    for ($start = 0; $start < count($ordered);) {
        $end = $start + 1;
        while ($end < count($ordered) && $ordered[$end] === $ordered[$end - 1] + 1) $end++;
        if ($end - $start >= 3) $pieces[] = $ordered[$start] . '-' . $ordered[$end - 1];
        else for ($index = $start; $index < $end; $index++) $pieces[] = (string) $ordered[$index];
        $start = $end;
    }
    return implode(', ', $pieces);
}

function indexText(object $entry, bool $child, array $indexPages): string
{
    $text = ($child ? '  ' : '') . $entry->name;
    $pages = pageList(array_map(fn($number) => $indexPages[$number], $entry->marks));
    if ($pages !== '') $text .= ', ' . $pages;
    $references = array_keys($entry->crossReferences);
    sort($references, SORT_STRING);
    if ($references) $text .= ', see ' . implode(', ', $references);
    return $text;
}

function renderPages(object $document, object $layout, object $numbered): void
{
    $chapter = '';
    $section = '';
    foreach ($numbered->pages as $page) {
        if ($page->blank) {
            $page->body = array_fill(0, $document->pageHeight, '');
            $page->header = '';
            $page->footer = '';
            continue;
        }
        foreach ($page->content as $line) {
            $dynamic = $line->dynamic ?? null;
            if (($dynamic->kind ?? null) === 'listing') {
                $number = $numbered->blockPages[$dynamic->target]->display;
                $dots = str_repeat('.', $dynamic->width - strlen($dynamic->left) - strlen($number) - 2);
                $line->text = $dynamic->left . ' ' . $dots . ' ' . $number;
            } elseif (($dynamic->kind ?? null) === 'index') {
                $line->text = indexText($dynamic->entry, $dynamic->child, $numbered->indexPages);
            }
            $block = $line->blockStart ?? null;
            if (($block->kind ?? null) === 'h1') {
                $chapter = $block->number . ' ' . $block->text;
                $section = '';
            } elseif (($block->kind ?? null) === 'h2') {
                $section = $block->number . ' ' . $block->text;
            }
        }
        $values = ['page' => $page->display, 'pages' => (string) (count($numbered->pages) - $numbered->frontMatter),
            'chapter' => $chapter, 'section' => $section];
        $page->header = $page->chapterStart ? '' : runningHead($document->header, $values, $document->pageWidth, $page->serial);
        $page->footer = runningHead($document->footer, $values, $document->pageWidth, $page->serial);
        $page->body = array_merge(array_map(fn($line) => $line->text, $page->content), array_fill(0, $document->pageHeight - $page->height, ''));
        if ($page->footnotes) {
            $page->body[] = '----------';
            foreach ($page->footnotes as $number) {
                foreach ($layout->footnotes[$number]->lines as $line) $page->body[] = $line->text;
            }
        }
    }
}

function layoutDocument(object $document, Dictionary $dictionary, array $parameters, string $method): object
{
    $current = array_fill_keys(array_keys($document->labels), '??');
    while (true) {
        $layout = typesetBlocks($document, $dictionary, $parameters, $method, $current);
        $rawPages = choosePages($layout->blocks, $document->pageHeight, $parameters, $layout->footnotes);
        $numbered = numberPages($document, $rawPages);
        $unchanged = true;
        foreach ($numbered->labelValues as $label => $value) {
            if ($current[$label] !== $value) $unchanged = false;
        }
        if ($unchanged) {
            renderPages($document, $layout, $numbered);
            return (object) array_merge((array) $layout, (array) $numbered);
        }
        $current = $numbered->labelValues;
    }
}

function layoutWarnings(object $document, object $layout, array $parameters, string $method): array
{
    $lines = [];
    $examine = function ($name, $broken, $justify) use (&$lines, $method, $parameters) {
        foreach ($broken->lines as $index => $line) {
            if ($line->slack < 0) $lines[] = $method . ': ' . $name . ' line ' . ($index + 1) . ': overfull by ' . (-$line->slack);
            elseif ($justify && !$line->last && $line->slack >= $parameters['underfull_slack']) {
                $lines[] = $method . ': ' . $name . ' line ' . ($index + 1) . ': underfull, slack ' . $line->slack;
            }
        }
    };
    $hyphenated = 0;
    foreach ($document->blocks as $block) {
        if (in_array($block->kind, BODY_KINDS, true)) {
            $broken = $layout->bodies[$block->id];
            $examine('paragraph ' . $block->bodyNumber, $broken, $block->align === 'justify');
            foreach ($broken->lines as $line) if ($line->mid) $hyphenated++;
        } elseif ($block->kind === 'bibliography') {
            foreach ($layout->references[$block->id] as $item) $examine('reference ' . $item->entry->label, $item->broken, false);
        }
    }
    foreach ($document->footnotes as $note) $examine('footnote ' . $note->number, $layout->footnotes[$note->number], false);
    foreach ($layout->pages as $page) {
        if ($page->blank || $page->endsByForce) continue;
        $empty = $document->pageHeight - $page->height;
        if ($empty >= $parameters['underfull_page']) $lines[] = $method . ': page ' . $page->serial . ': underfull, ' . $empty . ' empty lines';
    }
    $lines[] = $method . ': ' . count($layout->pages) . ' pages, ' . $hyphenated . ' hyphenated lines';
    return $lines;
}

function statistics(object $document, object $optimal, object $greedy): array
{
    $lines = ['paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy'];
    $totals = [0, 0, 0, 0];
    foreach ($document->bodies as $block) {
        $first = $optimal->bodies[$block->id];
        $second = $greedy->bodies[$block->id];
        $values = [count($first->lines), $first->cost, count($second->lines), $second->cost];
        foreach ($values as $index => $value) $totals[$index] += $value;
        $lines[] = implode(',', array_merge([$block->bodyNumber], $values));
    }
    $lines[] = implode(',', array_merge(['total'], $totals));
    return $lines;
}

function writeLines(string $filename, array $lines): void
{
    file_put_contents('output/' . $filename, $lines ? implode("\n", $lines) . "\n" : '');
}

$parameters = [];
foreach (readLines('input/params.txt') as $line) {
    [$name, $value] = explode(' ', $line);
    $parameters[$name] = (int) $value;
}
$document = parseDocument(readLines('input/document.txt'));
registerDocument($document);
checkDocument($document);
bibliographyLabels($document);
prepareIndex($document);
$dictionary = new Dictionary(readLines('input/hyphenation.txt'), $document->dictionaryWords);
$optimal = layoutDocument($document, $dictionary, $parameters, 'kp');
$greedy = layoutDocument($document, $dictionary, $parameters, 'greedy');
$log = array_map(fn($warning) => 'line ' . $warning->line . ': ' . $warning->message, $document->warnings);
$log = array_merge($log, layoutWarnings($document, $optimal, $parameters, 'kp'), layoutWarnings($document, $greedy, $parameters, 'greedy'));
if (!is_dir('output')) mkdir('output', 0777, true);
writeLines('pages.txt', pageLines($optimal->pages));
writeLines('greedy_pages.txt', pageLines($greedy->pages));
writeLines('stats.csv', statistics($document, $optimal, $greedy));
writeLines('log.txt', $log);
