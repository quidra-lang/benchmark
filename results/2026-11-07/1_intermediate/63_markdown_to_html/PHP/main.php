<?php

declare(strict_types=1);

const WHITESPACE = " \n";
const PUNCTUATION = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
const TOC_MARKER = "\0toc\0";

function escapeHtml(string $text): string
{
    return strtr($text, ['&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;']);
}

function stripTags(string $text): string
{
    return preg_replace('/<[^>]*>/', '', $text);
}

function normalizeLabel(string $text): string
{
    return trim(preg_replace('/[ \n]+/', ' ', strtolower($text)), ' ');
}

function skipSpace(string $text, int $at): int
{
    while ($at < strlen($text) && str_contains(WHITESPACE, $text[$at])) {
        $at++;
    }
    return $at;
}

function escapedRead(string $text, int $at, string $stops): array
{
    $result = '';
    while ($at < strlen($text) && !str_contains($stops, $text[$at])) {
        if ($text[$at] === '\\' && $at + 1 < strlen($text) && str_contains(PUNCTUATION, $text[$at + 1])) {
            $at++;
        }
        $result .= $text[$at++];
    }
    return [$result, $at];
}

function openingFence(string $line): ?array
{
    if (!preg_match('/\A(`{3,}|~{3,})/', $line, $match)) {
        return null;
    }
    $fence = $match[0];
    $info = trim(substr($line, strlen($fence)), ' ');
    if ($fence[0] === '`' && str_contains($info, '`')) {
        return null;
    }
    return [$fence, $info];
}

function atxHeading(string $line): ?array
{
    if (!preg_match('/\A(#{1,6})(?: |\z)/', $line, $match)) {
        return null;
    }
    $text = trim(substr($line, strlen($match[1])), ' ');
    $trimmed = rtrim($text, '#');
    if ($trimmed === '' || str_ends_with($trimmed, ' ')) {
        $text = trim($trimmed, ' ');
    }
    return ['kind' => 'heading', 'text' => $text, 'number' => strlen($match[1])];
}

function isRule(string $line): bool
{
    return preg_match('/\A(?:-{3,}|\*{3,}|_{3,})\z/', str_replace(' ', '', $line)) === 1;
}

function listMarker(string $line): ?array
{
    if (isRule($line) || !preg_match('/\A(?:([-*+])|([0-9]{1,9})([.)])) +/', $line, $match)) {
        return null;
    }
    $ordered = ($match[2] ?? '') !== '';
    return [
        $ordered ? $match[3] : $match[1], $ordered,
        $ordered ? (int) $match[2] : 1, substr($line, strlen($match[0])),
    ];
}

function interruptsParagraph(string $line): bool
{
    return !str_starts_with($line, ' ') && (
        openingFence($line) !== null || atxHeading($line) !== null || isRule($line)
        || str_starts_with($line, '>') || listMarker($line) !== null
    );
}

function splitCells(string $line): array
{
    $text = trim($line, ' ');
    $at = str_starts_with($text, '|') ? 1 : 0;
    $cells = [''];
    $separator = false;
    while ($at < strlen($text)) {
        $char = $text[$at++];
        $separator = false;
        $last = array_key_last($cells);
        if ($char === '\\' && $at < strlen($text)) {
            if ($text[$at] !== '|') {
                $cells[$last] .= '\\';
            }
            $cells[$last] .= $text[$at++];
        } elseif ($char === '|') {
            $cells[] = '';
            $separator = true;
        } else {
            $cells[$last] .= $char;
        }
    }
    if ($separator) {
        array_pop($cells);
    }
    return array_map(fn(string $cell): string => trim($cell, ' '), $cells);
}

final class BlockParser
{
    public array $references = [];
    public array $footnotes = [];

    public function parse(array $lines): array
    {
        $blocks = [];
        $at = 0;
        while ($at < count($lines)) {
            $line = $lines[$at];
            if ($line === '') {
                $at++;
                continue;
            }
            if (str_starts_with($line, '    ')) {
                $end = $at;
                while ($end < count($lines) && ($lines[$end] === '' || str_starts_with($lines[$end], '    '))) {
                    $end++;
                }
                while ($lines[$end - 1] === '') {
                    $end--;
                }
                $blocks[] = ['kind' => 'code', 'text' => '', 'lines' => array_map(
                    fn(string $row): string => substr($row, 4), array_slice($lines, $at, $end - $at),
                )];
                $at = $end;
                continue;
            }
            if (!str_starts_with($line, ' ')) {
                if (($fence = openingFence($line)) !== null) {
                    [$marker, $info] = $fence;
                    $code = [];
                    $at++;
                    while ($at < count($lines)) {
                        $row = $lines[$at++];
                        if (strlen($row) >= strlen($marker) && strspn($row, $marker[0]) === strlen($row)) {
                            break;
                        }
                        $code[] = $row;
                    }
                    $blocks[] = ['kind' => 'code', 'text' => explode(' ', $info)[0], 'lines' => $code];
                    continue;
                }
                if (($heading = atxHeading($line)) !== null) {
                    $blocks[] = $heading;
                    $at++;
                    continue;
                }
                if (isRule($line)) {
                    $blocks[] = ['kind' => 'rule'];
                    $at++;
                    continue;
                }
                if (str_starts_with($line, '>')) {
                    $content = [];
                    while ($at < count($lines) && str_starts_with($lines[$at], '>')) {
                        $row = substr($lines[$at++], 1);
                        $content[] = str_starts_with($row, ' ') ? substr($row, 1) : $row;
                    }
                    $alert = preg_match('/\A\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\z/', $content[0], $match) === 1;
                    if ($alert) {
                        array_shift($content);
                    }
                    $blocks[] = ['kind' => $alert ? 'alert' : 'quote', 'text' => $alert ? $match[1] : '', 'children' => $this->parse($content)];
                    continue;
                }
                if (($marker = listMarker($line)) !== null) {
                    [$kind, $ordered, $number] = $marker;
                    $items = [];
                    while (true) {
                        $content = [$marker[3]];
                        $at++;
                        while ($at < count($lines) && str_starts_with($lines[$at], '  ')) {
                            $content[] = substr($lines[$at++], 2);
                        }
                        $items[] = $this->parse($content);
                        $following = $at;
                        while ($following < count($lines) && $lines[$following] === '') {
                            $following++;
                        }
                        $marker = $following < count($lines) ? listMarker($lines[$following]) : null;
                        if ($marker === null || $marker[0] !== $kind || $marker[1] !== $ordered) {
                            break;
                        }
                        $at = $following;
                    }
                    $blocks[] = ['kind' => 'list', 'ordered' => $ordered, 'number' => $number, 'items' => $items];
                    continue;
                }
                if ($this->definition($line)) {
                    $at++;
                    continue;
                }
                if ($at + 1 < count($lines) && str_contains($line, '|') && str_contains($lines[$at + 1], '|')) {
                    $header = splitCells($line);
                    $delimiters = splitCells($lines[$at + 1]);
                    if (count($header) === count($delimiters) && array_filter($delimiters, fn(string $cell): bool => preg_match('/\A:?-+:?\z/', $cell) !== 1) === []) {
                        $alignments = array_map(
                            fn(string $cell): ?string => str_starts_with($cell, ':')
                                ? (str_ends_with($cell, ':') ? 'center' : 'left') : (str_ends_with($cell, ':') ? 'right' : null),
                            $delimiters,
                        );
                        $rows = [];
                        $at += 2;
                        while ($at < count($lines) && str_contains($lines[$at], '|')) {
                            $rows[] = array_pad(array_slice(splitCells($lines[$at++]), 0, count($header)), count($header), '');
                        }
                        $blocks[] = ['kind' => 'table', 'alignments' => $alignments, 'lines' => $header, 'rows' => $rows];
                        continue;
                    }
                }
            }
            $text = [ltrim($line, ' ')];
            $at++;
            $level = null;
            while ($at < count($lines) && $lines[$at] !== '') {
                if (preg_match('/\A(?:={3,}|-{3,})\z/', $lines[$at])) {
                    $level = $lines[$at++][0] === '=' ? 1 : 2;
                    break;
                }
                if (interruptsParagraph($lines[$at])) {
                    break;
                }
                $text[] = ltrim($lines[$at++], ' ');
            }
            $text = implode("\n", $text);
            $blocks[] = ['kind' => $level !== null ? 'heading' : ($text === '[TOC]' ? 'toc' : 'paragraph'), 'text' => $text, 'number' => $level];
        }
        return $blocks;
    }

    private function definition(string $line): bool
    {
        if (preg_match('/\A\[\^([A-Za-z0-9_-]+)\]:(.*)\z/', $line, $match) && trim($match[2], ' ') !== '') {
            $name = strtolower($match[1]);
            $this->footnotes[$name] ??= trim($match[2], ' ');
            return true;
        }
        if (!str_starts_with($line, '[')) {
            return false;
        }
        $close = strpos($line, ']');
        if ($close === false || ($line[$close + 1] ?? '') !== ':') {
            return false;
        }
        $label = substr($line, 1, $close - 1);
        if (str_contains($label, '[') || trim($label, ' ') === '' || str_starts_with($label, '^')) {
            return false;
        }
        [$url, $end] = escapedRead($line, skipSpace($line, $close + 2), ' ');
        if ($url === '') {
            return false;
        }
        $at = skipSpace($line, $end);
        $title = null;
        if ($at < strlen($line)) {
            if ($at === $end || !str_contains('"\'', $line[$at])) {
                return false;
            }
            [$title, $end] = escapedRead($line, $at + 1, $line[$at]);
            if ($end !== strlen($line) - 1) {
                return false;
            }
        }
        $this->references[normalizeLabel($label)] ??= [$url, $title];
        return true;
    }
}

function runEnd(string $text, int $at): int
{
    $char = $text[$at++];
    while ($at < strlen($text) && $text[$at] === $char) {
        $at++;
    }
    return $at;
}

function backtickCloser(string $text, int $at, int $length): ?int
{
    while (($at = strpos($text, '`', $at)) !== false) {
        $end = runEnd($text, $at);
        if ($end - $at === $length) {
            return $at;
        }
        $at = $end;
    }
    return null;
}

function closingBracket(string $text, int $at): ?int
{
    $depth = 0;
    while ($at < strlen($text)) {
        $char = $text[$at];
        if ($char === '\\') {
            $at += 2;
            continue;
        }
        if ($char === '`') {
            $end = runEnd($text, $at);
            $close = backtickCloser($text, $end, $end - $at);
            $at = $close === null ? $end : $close + $end - $at;
            continue;
        }
        if ($char === '[') {
            $depth++;
        } elseif ($char === ']' && --$depth === 0) {
            return $at;
        }
        $at++;
    }
    return null;
}

final readonly class Delimiter
{
    public function __construct(public string $char, public int $length, public bool $canOpen, public bool $canClose) {}
}

function emphasis(array $pieces, int $start = 0, ?int $end = null): string
{
    $end ??= count($pieces);
    $html = '';
    for ($at = $start; $at < $end; $at++) {
        $piece = $pieces[$at];
        if (is_string($piece)) {
            $html .= $piece;
            continue;
        }
        $close = $end;
        if ($piece->canOpen) {
            for ($index = $at + 1; $index < $end; $index++) {
                $other = $pieces[$index];
                if ($other instanceof Delimiter && $other->char === $piece->char && $other->length === $piece->length && $other->canClose) {
                    $close = $index;
                    break;
                }
            }
        }
        if ($close === $end) {
            $html .= str_repeat($piece->char, $piece->length);
        } else {
            [$opening, $closing] = $piece->char === '~' ? ['<del>', '</del>'] : match ($piece->length) {
                1 => ['<em>', '</em>'], 2 => ['<strong>', '</strong>'], 3 => ['<em><strong>', '</strong></em>'],
            };
            $html .= $opening . emphasis($pieces, $at + 1, $close) . $closing;
            $at = $close;
        }
    }
    return $html;
}

final class Renderer
{
    private array $usedIds = [];
    private array $headings = [];
    private array $noteNumbers = [];
    private array $noteCounts = [];

    public function __construct(private array $references, private array $footnotes) {}

    private function inline(string $text, bool $links = true, bool $notes = true): string
    {
        $pieces = [];
        $at = 0;
        while ($at < strlen($text)) {
            $char = $text[$at];
            $following = $text[$at + 1] ?? '';
            if ($char === '\\') {
                if ($following !== '' && str_contains(PUNCTUATION, $following)) {
                    $pieces[] = escapeHtml($following);
                    $at += 2;
                } elseif ($following === "\n") {
                    $pieces[] = "<br />\n";
                    $at += 2;
                } else {
                    $pieces[] = '\\';
                    $at++;
                }
                continue;
            }
            if ($char === '`') {
                $end = runEnd($text, $at);
                $close = backtickCloser($text, $end, $end - $at);
                if ($close === null) {
                    $pieces[] = substr($text, $at, $end - $at);
                    $at = $end;
                } else {
                    $code = str_replace("\n", ' ', substr($text, $end, $close - $end));
                    if (str_starts_with($code, ' ') && str_ends_with($code, ' ') && trim($code, ' ') !== '') {
                        $code = substr($code, 1, -1);
                    }
                    $pieces[] = '<code>' . escapeHtml($code) . '</code>';
                    $at = $close + $end - $at;
                }
                continue;
            }
            if ($links && $char === '<' && ($close = strpos($text, '>', $at + 1)) !== false) {
                $target = substr($text, $at + 1, $close - $at - 1);
                $href = null;
                if (!preg_match('/[ \n<]/', $target) && preg_match('~\Ahttps?://.+~s', $target)) {
                    $href = $target;
                } elseif (preg_match('/\A[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/', $target)) {
                    $href = 'mailto:' . $target;
                }
                if ($href !== null) {
                    $pieces[] = '<a href="' . escapeHtml($href) . '">' . escapeHtml($target) . '</a>';
                    $at = $close + 1;
                    continue;
                }
            }
            if ($links && ($at === 0 || str_contains(" \n*_~(", $text[$at - 1])) && preg_match('~\Ahttps?://[^ \n<]*~', substr($text, $at), $match)) {
                $url = rtrim($match[0], '.,:;!?*_~)');
                if ($url !== 'http://' && $url !== 'https://') {
                    $pieces[] = '<a href="' . escapeHtml($url) . '">' . escapeHtml($url) . '</a>';
                    $at += strlen($url);
                    continue;
                }
            }
            if ($char === '[' || ($char === '!' && $following === '[')) {
                if ($links && $notes && substr($text, $at, 2) === '[^' && ($close = strpos($text, ']', $at + 2)) !== false) {
                    $name = strtolower(substr($text, $at + 2, $close - $at - 2));
                    if (array_key_exists($name, $this->footnotes)) {
                        $pieces[] = $this->footnoteReference($name);
                        $at = $close + 1;
                        continue;
                    }
                }
                $image = $char === '!';
                $opening = $at + ($image ? 1 : 0);
                if (($image || $links) && ($close = closingBracket($text, $opening)) !== null) {
                    $label = substr($text, $opening + 1, $close - $opening - 1);
                    if (($destination = $this->destination($text, $close + 1, $label)) !== null) {
                        [[$url, $title], $end] = $destination;
                        $attribute = $title === null ? '' : ' title="' . escapeHtml($title) . '"';
                        $content = $this->inline($label, false, false);
                        $pieces[] = $image
                            ? '<img src="' . escapeHtml($url) . '" alt="' . stripTags($content) . '"' . $attribute . ' />'
                            : '<a href="' . escapeHtml($url) . '"' . $attribute . '>' . $content . '</a>';
                        $at = $end;
                        continue;
                    }
                }
            }
            if (str_contains('*_~', $char)) {
                $end = runEnd($text, $at);
                $length = $end - $at;
                $before = $at === 0 ? ' ' : $text[$at - 1];
                $after = $text[$end] ?? ' ';
                $canOpen = !str_contains(WHITESPACE, $after);
                $canClose = !str_contains(WHITESPACE, $before);
                if ($char === '_' && ctype_alnum($before) && ctype_alnum($after)) {
                    $canOpen = $canClose = false;
                }
                $pieces[] = ($char !== '~' && $length <= 3) || ($char === '~' && $length === 2)
                    ? new Delimiter($char, $length, $canOpen, $canClose) : str_repeat($char, $length);
                $at = $end;
            } else {
                $pieces[] = escapeHtml($char);
                $at++;
            }
        }
        return emphasis($pieces);
    }

    private function destination(string $text, int $at, string $label): ?array
    {
        if (($text[$at] ?? '') === '[') {
            $close = strpos($text, ']', $at + 1);
            if ($close !== false && !str_contains(substr($text, $at + 1, $close - $at - 1), '[')) {
                $name = substr($text, $at + 1, $close - $at - 1);
                $reference = $this->references[normalizeLabel($name === '' ? $label : $name)] ?? null;
                return $reference === null ? null : [$reference, $close + 1];
            }
        } elseif (($text[$at] ?? '') === '(') {
            [$url, $end] = escapedRead($text, skipSpace($text, $at + 1), " \n)");
            $position = skipSpace($text, $end);
            $title = null;
            $valid = true;
            if ($position > $end && $position < strlen($text) && str_contains('"\'', $text[$position])) {
                [$title, $end] = escapedRead($text, $position + 1, $text[$position]);
                $valid = $end < strlen($text);
                if ($valid) {
                    $position = skipSpace($text, $end + 1);
                }
            }
            if ($valid && ($text[$position] ?? '') === ')') {
                return [[$url, $title], $position + 1];
            }
        }
        $reference = $this->references[normalizeLabel($label)] ?? null;
        return $reference === null ? null : [$reference, $at];
    }

    public function document(array $blocks): string
    {
        $html = $this->renderBlocks($blocks);
        $html = str_replace(TOC_MARKER, $this->tableOfContents(), $html);
        return $html . ($this->noteNumbers === [] ? '' : $this->footnoteList());
    }

    private function renderBlocks(array $blocks): string
    {
        return implode('', array_map(fn(array $block): string => $this->render($block) . "\n", $blocks));
    }

    private function render(array $block): string
    {
        switch ($block['kind']) {
            case 'heading': return $this->heading($block['number'], $block['text']);
            case 'paragraph': return '<p>' . $this->inline($block['text']) . '</p>';
            case 'rule': return '<hr />';
            case 'code':
                $attribute = $block['text'] === '' ? '' : ' class="language-' . escapeHtml($block['text']) . '"';
                $code = implode('', array_map(fn(string $line): string => escapeHtml($line) . "\n", $block['lines']));
                return "<pre><code$attribute>$code</code></pre>";
            case 'quote': return "<blockquote>\n" . $this->renderBlocks($block['children']) . '</blockquote>';
            case 'alert':
                $kind = strtolower($block['text']);
                return '<div class="alert alert-' . $kind . '">' . "\n" . '<p class="alert-title">' . ucfirst($kind) . "</p>\n" . $this->renderBlocks($block['children']) . '</div>';
            case 'list':
                $tag = $block['ordered'] ? 'ol' : 'ul';
                $attribute = $block['ordered'] && $block['number'] !== 1 ? ' start="' . $block['number'] . '"' : '';
                $items = implode('', array_map(fn(array $item): string => $this->renderItem($item) . "\n", $block['items']));
                return "<$tag$attribute>\n$items</$tag>";
            case 'table':
                $html = "<table>\n<thead>\n<tr>\n" . $this->tableCells('th', $block, $block['lines']) . "</tr>\n</thead>\n";
                if ($block['rows'] !== []) {
                    $html .= "<tbody>\n";
                    foreach ($block['rows'] as $row) {
                        $html .= "<tr>\n" . $this->tableCells('td', $block, $row) . "</tr>\n";
                    }
                    $html .= "</tbody>\n";
                }
                return $html . '</table>';
            case 'toc': return TOC_MARKER;
        }
        return '';
    }

    private function heading(int $level, string $text): string
    {
        $start = strrpos($text, ' {#');
        $candidate = $start !== false && str_ends_with($text, '}') ? substr($text, $start + 3, -1) : '';
        if (preg_match('/\A[A-Za-z0-9_-]+\z/', $candidate)) {
            $id = $candidate;
            $text = rtrim(substr($text, 0, $start), ' ');
        } else {
            $base = str_replace([' ', "\n"], '-', preg_replace('/[^a-z0-9_ \n-]/', '', strtolower($text)));
            if ($base === '') {
                $base = 'heading';
            }
            $id = $base;
            for ($suffix = 1; isset($this->usedIds[$id]); $suffix++) {
                $id = "$base-$suffix";
            }
        }
        $this->usedIds[$id] = true;
        $html = $this->inline($text);
        $this->headings[] = ['level' => $level, 'id' => $id, 'label' => stripTags($html), 'children' => []];
        return "<h$level id=\"$id\">$html</h$level>";
    }

    private function renderItem(array $blocks): string
    {
        $html = '<li>';
        foreach ($blocks as $index => $block) {
            if ($block['kind'] === 'paragraph') {
                $text = $block['text'];
                if ($index === 0 && strlen($text) > 4 && in_array(substr($text, 0, 4), ['[ ] ', '[x] ', '[X] '], true)) {
                    $checked = $text[1] === ' ' ? '' : ' checked=""';
                    $html .= '<input type="checkbox"' . $checked . ' disabled="" /> ';
                    $text = substr($text, 4);
                }
                $html .= $this->inline($text);
            } else {
                if (!str_ends_with($html, "\n")) {
                    $html .= "\n";
                }
                $html .= $this->render($block) . "\n";
            }
        }
        return $html . '</li>';
    }

    private function tableCells(string $tag, array $table, array $cells): string
    {
        $html = '';
        foreach ($cells as $index => $cell) {
            $alignment = $table['alignments'][$index];
            $style = $alignment === null ? '' : " style=\"text-align:$alignment\"";
            $html .= "<$tag$style>" . $this->inline($cell) . "</$tag>\n";
        }
        return $html;
    }

    private function tocList(array $indices): string
    {
        $html = "<ul>\n";
        foreach ($indices as $index) {
            $entry = $this->headings[$index];
            $html .= '<li><a href="#' . $entry['id'] . '">' . $entry['label'] . '</a>';
            if ($entry['children'] !== []) {
                $html .= "\n" . $this->tocList($entry['children']) . "\n";
            }
            $html .= "</li>\n";
        }
        return $html . '</ul>';
    }

    private function tableOfContents(): string
    {
        if ($this->headings === []) {
            return "<nav class=\"toc\">\n</nav>";
        }
        $roots = [];
        $parents = [];
        foreach ($this->headings as $index => $entry) {
            while ($parents !== [] && $this->headings[$parents[array_key_last($parents)]]['level'] >= $entry['level']) {
                array_pop($parents);
            }
            if ($parents === []) {
                $roots[] = $index;
            } else {
                $this->headings[$parents[array_key_last($parents)]]['children'][] = $index;
            }
            $parents[] = $index;
        }
        return "<nav class=\"toc\">\n" . $this->tocList($roots) . "\n</nav>";
    }

    private function referenceId(int $number, int $count): string
    {
        return "fnref-$number" . ($count === 1 ? '' : "-$count");
    }

    private function footnoteReference(string $name): string
    {
        if (!isset($this->noteNumbers[$name])) {
            $this->noteNumbers[$name] = count($this->noteNumbers) + 1;
            $this->noteCounts[$name] = 0;
        }
        $number = $this->noteNumbers[$name];
        $id = $this->referenceId($number, ++$this->noteCounts[$name]);
        return "<sup id=\"$id\"><a href=\"#fn-$number\">$number</a></sup>";
    }

    private function footnoteList(): string
    {
        $html = "<section class=\"footnotes\">\n<ol>\n";
        foreach ($this->noteNumbers as $name => $number) {
            $body = $this->inline($this->footnotes[$name], notes: false);
            $backlinks = [];
            for ($count = 1; $count <= $this->noteCounts[$name]; $count++) {
                $backlinks[] = '<a href="#' . $this->referenceId($number, $count) . '">&#8617;</a>';
            }
            $html .= "<li id=\"fn-$number\">$body " . implode(' ', $backlinks) . "</li>\n";
        }
        return $html . "</ol>\n</section>\n";
    }
}

$lines = [];
while (($line = fgets(STDIN)) !== false) {
    $line = rtrim($line, "\r\n");
    if ($line === '@@END@@') {
        break;
    }
    $lines[] = $line;
}
$parser = new BlockParser();
$blocks = $parser->parse($lines);
echo (new Renderer($parser->references, $parser->footnotes))->document($blocks);
