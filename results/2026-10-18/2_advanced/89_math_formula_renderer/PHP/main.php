<?php

foreach (['lexer', 'parser', 'boxes', 'layout', 'canvas'] as $module)
    require_once __DIR__ . "/$module.php";
const STACKED_COMMANDS = ['\\sum', '\\prod', '\\lim', '\\max', '\\min'];

const BRACE_ACCENTS = ['overbrace', 'underbrace'];

const DELIMITER_PAIRS = ['(' => ')', '[' => ']', '|' => '|', '\\{' => '\\}'];

final class Formula
{
    public array $nodes = [], $tokens = [], $warnings = [];
    public ?Token $tag = null, $label = null;
    public ?string $tagString = null;
    public ?array $error = null;

    public function __construct(
        public int $number,
        public string $line,
    ) {
        try {
            $this->tokens = tokenize($line);
            checkBraces($this->tokens);
            $parser = new FormulaParser($this->tokens);
            $this->nodes = $parser->parse();
            $this->tag = $parser->tag;
            $this->label = $parser->label;
        } catch (FormulaError $error) {
            $this->error = [$error->column, $error->getMessage()];
        }
    }
}

function referenceTable(array $formulas): array
{
    $counter = 0;
    foreach ($formulas as $f)
        if ($f->error === null) {
            if ($f->tag !== null)
                $f->tagString = '(' . $f->tag->value . ')';
            elseif ($f->label !== null)
                $f->tagString = '(' . ++$counter . ')';
        }
    $references = [];
    foreach ($formulas as $f)
        if ($f->error === null && $f->label !== null) {
            $label = $f->label;
            if (isset($references[$label->value]))
                $f->warnings[] = [$label->column, 'duplicate label "' . $label->value . '"'];
            else
                $references[$label->value] = $f->tagString;
        }
    return $references;
}

function walkNodes(MathNode $node): Generator
{
    yield $node;
    if ($node->kind === 'matrix') {
        foreach ($node->children as $row)
            foreach ($row as $cell)
                yield from walkNodes($cell);
    } else
        foreach ($node->children as $child)
            if ($child !== null)
                yield from walkNodes($child);
}

function collectWarnings(Formula $formula, array $references): void
{
    $names = [];
    foreach (array_keys(symbolCommands()) as $name)
        if (ctype_alpha(substr($name, 1)))
            $names[substr($name, 1)] = true;
    foreach ($formula->nodes as $element)
        foreach (walkNodes($element) as $n) {
            if ($n->kind === 'identifier' && isset($names[$n->value]))
                $formula->warnings[] = [$n->column, $n->value . ' is a command name; write \\' . $n->value];
            elseif ($n->kind === 'reference' && !isset($references[$n->value]))
                $formula->warnings[] = [$n->column, 'undefined reference "' . $n->value . '"'];
            elseif ($n->kind === 'delim') {
                [$left, $right] = $n->value;
                if ($left !== '.' && $right !== '.' && (DELIMITER_PAIRS[$left] ?? null) !== $right)
                    $formula->warnings[] = [$n->column, '\\left' . $left . ' closed by \\right' . $right];
            }
        }
    usort($formula->warnings, fn($a, $b) => $a[0] <=> $b[0]);
}

function center(Box $box, int $width): int
{
    return intdiv($width - $box->width, 2);
}

function drawDelimiter(Box $box, string $delimiter, int $x, int $height): void
{
    foreach (delimiterGlyph($delimiter, $height) as $y => $character)
        $box->draw($character, $x, $y);
}

function delimiterString(string $delimiter): string
{
    return $delimiter === '.' ? '' : substr($delimiter, -1);
}

final class Typesetter
{
    public function __construct(
        private array $params,
        private array $references,
    ) {}

    public function typeset(MathNode $n, string $style = 'normal'): Box
    {
        if (in_array($n->kind, [...ATOM_KINDS, 'reference'], true))
            return $this->atom($n, $style);
        return $this->{$n->kind}($n, $style);
    }

    private function atom(MathNode $n, string $style): Box
    {
        if ($n->kind === 'text') {
            $description = 'text "' . $n->value . '"';
            $display = $n->value;
        } elseif ($n->kind === 'reference') {
            $description = 'eqref "' . $n->value . '"';
            $display = $this->references[$n->value] ?? '(??)';
        } else {
            $description = 'atom "' . $n->value . '"';
            $display = $n->kind === 'command' ? symbolCommands()[$n->value][0] : $n->value;
        }
        if ($n->kind === 'command' && isset(LARGE_GLYPHS[$n->value]) && $style === 'normal') {
            $glyph = LARGE_GLYPHS[$n->value];
            $box = new Box(strlen($glyph[0]), 3, 1, $description);
            foreach ($glyph as $y => $line)
                $box->draw($line, 0, $y);
        } else {
            $box = new Box(strlen($display), 1, 0, $description);
            $box->draw($display);
        }
        return $box;
    }

    private function row(MathNode $n, string $style): Box
    {
        [, $gaps] = spacing($n->children, $style, $this->params);
        return rowBox(array_map(fn($child) => $this->typeset($child, $style), $n->children), $gaps);
    }

    private function script(MathNode $n, string $style): Box
    {
        [$baseNode, $subNode, $supNode] = $n->children;
        $base = $this->typeset($baseNode, $style);
        $sub = $subNode === null ? null : $this->typeset($subNode, 'script');
        $sup = $supNode === null ? null : $this->typeset($supNode, 'script');
        $sw = $sub?->width ?? 0;
        $sh = $sub?->height ?? 0;
        $pw = $sup?->width ?? 0;
        $ph = $sup?->height ?? 0;
        $stacked =
            $style === 'normal'
            && (
                $baseNode->kind === 'command'
                && in_array($baseNode->value, STACKED_COMMANDS, true)
                || $baseNode->kind === 'accent'
                && in_array($baseNode->value, BRACE_ACCENTS, true)
            );
        if ($stacked) {
            $w = max($base->width, $sw, $pw);
            $box = new Box($w, $ph + $base->height + $sh, $ph + $base->baseline, 'limits');
            $box->add($base, center($base, $w), $ph, 'base: ');
            if ($sub !== null)
                $box->add($sub, center($sub, $w), $ph + $base->height, 'sub: ');
            if ($sup !== null)
                $box->add($sup, center($sup, $w), 0, 'sup: ');
            return $box;
        }
        $tp = ($base->baseline === 0 ? -1 : 0) - $ph + 1;
        $ts = $base->descent() === 0 ? $base->height : $base->height - 1;
        $top = $sup === null ? 0 : min(0, $tp);
        $bottom = $sub === null ? $base->height - 1 : max($base->height - 1, $ts + $sh - 1);
        $box = new Box($base->width + max($sw, $pw), $bottom - $top + 1, $base->baseline - $top, 'scripts');
        $box->add($base, 0, -$top, 'base: ');
        if ($sub !== null)
            $box->add($sub, $base->width, $ts - $top, 'sub: ');
        if ($sup !== null)
            $box->add($sup, $base->width, $tp - $top, 'sup: ');
        return $box;
    }

    private function frac(MathNode $n, string $style): Box
    {
        [$numerator, $denominator] = array_map(fn($child) => $this->typeset($child, $style), $n->children);
        if ($style === 'normal') {
            $w = max($numerator->width, $denominator->width) + 2;
            $box = new Box($w, $numerator->height + 1 + $denominator->height, $numerator->height, 'frac');
            $box->add($numerator, center($numerator, $w), 0, 'num: ');
            $box->add($denominator, center($denominator, $w), $numerator->height + 1, 'den: ');
            $box->draw(str_repeat('-', $w), 0, $numerator->height);
            return $box;
        }
        if (in_array($n->children[0]->kind, ['row', 'frac'], true))
            $numerator = $this->delimit($numerator, '(', ')');
        if (in_array($n->children[1]->kind, ['row', 'frac'], true))
            $denominator = $this->delimit($denominator, '(', ')');
        $slash = new Box(1, 1, 0, 'atom "/"');
        $slash->draw('/');
        return rowBox([$numerator, $slash, $denominator], [0, 0], 'slash', ['num: ', '', 'den: ']);
    }

    private function binom(MathNode $n, string $style): Box
    {
        [$upper, $lower] = array_map(fn($child) => $this->typeset($child, $style), $n->children);
        $w = max($upper->width, $lower->width);
        $h = $upper->height + 1 + $lower->height;
        $box = new Box($w + 2, $h, $upper->height, 'binom');
        $box->add($upper, center($upper, $w) + 1, 0, 'upper: ');
        $box->add($lower, center($lower, $w) + 1, $upper->height + 1, 'lower: ');
        drawDelimiter($box, '(', 0, $h);
        drawDelimiter($box, ')', $w + 1, $h);
        return $box;
    }

    private function overset(MathNode $n, string $style): Box
    {
        return $this->placed($n, $style, true);
    }

    private function underset(MathNode $n, string $style): Box
    {
        return $this->placed($n, $style, false);
    }

    private function placed(MathNode $n, string $style, bool $over): Box
    {
        $placed = $this->typeset($n->children[0], 'script');
        $base = $this->typeset($n->children[1], $style);
        $w = max($placed->width, $base->width);
        $box = new Box(
            $w,
            $placed->height + $base->height,
            $base->baseline + ($over ? $placed->height : 0),
            $over ? 'overset' : 'underset',
        );
        if ($over) {
            $box->add($placed, center($placed, $w), 0, 'over: ');
            $box->add($base, center($base, $w), $placed->height, 'base: ');
        } else {
            $box->add($base, center($base, $w), 0, 'base: ');
            $box->add($placed, center($placed, $w), $base->height, 'under: ');
        }
        return $box;
    }

    private function radical(Box $body, ?Box $index = null): Box
    {
        $k = $body->height;
        $e = $index === null ? 0 : max(0, $index->width - 1);
        $top = $index === null ? 0 : max(0, $index->height - $k);
        $box = new Box(
            $e + $k + 1 + $body->width,
            $k + 1 + $top,
            $body->baseline + 1 + $top,
            $index === null ? 'sqrt' : 'root',
        );
        $box->draw(str_repeat('_', $body->width), $e + $k + 1, $top);
        $box->draw('\\', $e, $k + $top);
        for ($r = 1; $r <= $k; ++$r)
            $box->draw('/', $e + $k - $r + 1, $r + $top);
        if ($index !== null) {
            $box->add($index, 0, $k - $index->height + $top, 'index: ');
            $box->add($body, $e + $k + 1, 1 + $top, 'body: ');
        } else
            $box->add($body, $e + $k + 1, 1);
        return $box;
    }

    private function sqrt(MathNode $n, string $style): Box
    {
        return $this->radical($this->typeset($n->children[0], $style));
    }

    private function root(MathNode $n, string $style): Box
    {
        return $this->radical(
            $this->typeset($n->children[1], $style),
            $this->typeset($n->children[0], 'script'),
        );
    }

    private function delimit(Box $body, string $left, string $right): Box
    {
        $wl = $left === '.' ? 0 : 1;
        $wr = $right === '.' ? 0 : 1;
        $box = new Box($wl + $body->width + $wr, $body->height, $body->baseline, "delim $left $right");
        $box->add($body, $wl, 0);
        drawDelimiter($box, $left, 0, $body->height);
        drawDelimiter($box, $right, $wl + $body->width, $body->height);
        return $box;
    }

    private function delim(MathNode $n, string $style): Box
    {
        return $this->delimit($this->typeset($n->children[0], $style), ...$n->value);
    }

    private function matrix(MathNode $n, string $style): Box
    {
        $cells = array_map(fn($row) => array_map(fn($cell) => $this->typeset(
            $cell,
            $style,
        ), $row), $n->children);
        $rows = count($cells);
        $cols = count($cells[0]);
        $widths = $ascents = $heights = [];
        for ($j = 0; $j < $cols; ++$j)
            $widths[] = max(array_map(fn($row) => $row[$j]->width, $cells));
        foreach ($cells as $row) {
            $ascent = max(array_map(fn($cell) => $cell->baseline, $row));
            $descent = max(array_map(fn($cell) => $cell->descent(), $row));
            $ascents[] = $ascent;
            $heights[] = $ascent + $descent + 1;
        }
        $cg = $this->params['col_gap'];
        $rg = $this->params['row_gap'];
        $wb = array_sum($widths) + ($cg * ($cols - 1));
        $hb = array_sum($heights) + ($rg * ($rows - 1));
        $environment = $n->value;
        $shift = $environment === 'matrix' ? 0 : 2;
        $extra = $environment === 'matrix' ? 0 : ($environment === 'cases' ? 2 : 4);
        $box = new Box($wb + $extra, $hb, intdiv($hb - 1, 2), "$environment rows=$rows cols=$cols");
        $y = 0;
        foreach ($cells as $i => $row) {
            $x = $shift;
            foreach ($row as $j => $cell) {
                $offset = $environment === 'cases' ? 0 : center($cell, $widths[$j]);
                $box->add(
                    $cell,
                    $x + $offset,
                    $y + $ascents[$i] - $cell->baseline,
                    'cell ' . ($i + 1) . ',' . ($j + 1) . ': ',
                );
                $x += $widths[$j] + $cg;
            }
            $y += $heights[$i] + $rg;
        }
        if ($environment === 'cases')
            drawDelimiter($box, '\\{', 0, $hb);
        elseif ($environment !== 'matrix') {
            [$left, $right] = [
                'pmatrix' => ['(', ')'],
                'bmatrix' => ['[', ']'],
                'vmatrix' => ['|', '|'],
            ][$environment];
            drawDelimiter($box, $left, 0, $hb);
            drawDelimiter($box, $right, $wb + 3, $hb);
        }
        return $box;
    }

    private function accent(MathNode $n, string $style): Box
    {
        $body = $this->typeset($n->children[0], $style);
        $name = $n->value;
        $w = $body->width;
        if (in_array($name, ['hat', 'dot', 'tilde'], true))
            $w = max($w, 1);
        elseif ($name === 'vec')
            $w = max($w, 2);
        elseif (in_array($name, BRACE_ACCENTS, true))
            $w += 2;
        $box = new Box($w, $body->height + 1, $body->baseline + ($name === 'underbrace' ? 0 : 1), $name);
        if ($name === 'underbrace') {
            $box->add($body, 1, 0);
            $box->draw('\\' . str_repeat('-', $body->width) . '/', 0, $body->height);
        } elseif ($name === 'overbrace') {
            $box->add($body, 1, 1);
            $box->draw('/' . str_repeat('-', $body->width) . '\\');
        } else {
            $box->add($body, 0, 1);
            if ($name === 'overline')
                $box->draw(str_repeat('_', $w));
            elseif ($name === 'vec')
                $box->draw(str_repeat('-', $w - 1) . '>');
            else
                $box->draw(['hat' => '^', 'dot' => '.', 'tilde' => '~'][$name], intdiv($w - 1, 2));
        }
        return $box;
    }
}

function buildLines(array $breaks, array $types, array $boxes, array $starts, array $params): array
{
    $result = [];
    $position = 0;
    $alignment = null;
    $breaks = array_keys($breaks);
    sort($breaks, SORT_NUMERIC);
    while ($position < count($boxes)) {
        $indent = $position === 0
            ? 0
            : (
                $alignment === null
                    ? $params['indent']
                    : (
                        $types[$position][0] === 'relation'
                            ? $alignment[0]
                            : $alignment[0] + $alignment[1] + $params['rel_space']
                    )
            );
        $ends = array_values(array_filter($breaks, fn($end) => $end > $position));
        $ends[] = count($boxes);
        $candidates = $fitting = [];
        foreach ($ends as $end) {
            $width = $starts[$end - 1] + $boxes[$end - 1]->width - $starts[$position];
            $candidates[] = [$end, $width];
            if (($indent + $width) <= $params['width'])
                $fitting[] = [$end, $width];
        }
        [$end, $width] = $fitting ? $fitting[count($fitting) - 1] : $candidates[0];
        $result[] = [$position, $end, $indent, $width];
        if ($position === 0)
            for ($i = 0; $i < $end; ++$i)
                if ($types[$i][0] === 'relation') {
                    $alignment = [$starts[$i], $boxes[$i]->width];
                    break;
                }
        $position = $end;
    }
    return $result;
}

function placeFormula(Formula $f, Typesetter $typesetter, array $params): array
{
    $nodes = $f->nodes;
    [$types, $gaps] = spacing($nodes, 'normal', $params);
    $boxes = array_map(fn($n) => $typesetter->typeset($n), $nodes);
    $starts = [];
    $x = 0;
    foreach ($boxes as $i => $box) {
        $starts[] = $x;
        $x += $box->width + ($gaps[$i] ?? 0);
    }
    $relations = $plusMinus = $punctuation = [];
    for ($i = 1; $i < count($nodes); ++$i) {
        if ($types[$i][0] === 'relation')
            $relations[$i] = true;
        if (
            $nodes[$i]->kind === 'symbol'
            && in_array($nodes[$i]->value, ['+', '-'], true)
            && $types[$i][0] === 'binary'
        )
            $plusMinus[$i] = true;
        if ($types[$i - 1][1] === 'punctuation')
            $punctuation[$i] = true;
    }
    foreach ([$relations, $relations + $plusMinus, $relations + $plusMinus + $punctuation] as $breaks) {
        $plan = buildLines($breaks, $types, $boxes, $starts, $params);
        if (array_all($plan, fn($line) => ($line[2] + $line[3]) <= $params['width']))
            break;
    }
    $roots = $overfull = [];
    $width = $height = 0;
    foreach ($plan as $i => [$start, $end, $indent, $lineWidth]) {
        $line = rowBox(
            array_slice($boxes, $start, $end - $start),
            array_slice($gaps, $start, $end - $start - 1),
            'line ' . ($i + 1),
        );
        $roots[] = [$line, $indent, $height];
        $height += $line->height;
        $width = max($width, $indent + $line->width);
        if (($indent + $lineWidth) > $params['width'])
            $overfull[] = [$i + 1, $indent + $lineWidth];
    }
    if ($f->tagString !== null) {
        $tag = $f->tagString;
        $tx = $params['width'] - strlen($tag);
        [$last, $lx, $ly] = $roots[count($roots) - 1];
        if ($tx >= ($lx + $last->width + 2))
            $ty = $ly + $last->baseline;
        else
            $ty = $height++;
        $box = new Box(strlen($tag), 1, 0, 'tag "' . $tag . '"');
        $box->draw($tag);
        $roots[] = [$box, $tx, $ty];
        $width = max($width, $tx + $box->width);
    }
    return [$roots, count($plan), $width, $height, $overfull];
}

function treeNotation(MathNode $n): string
{
    $kind = $n->kind;
    if (in_array($kind, ['identifier', 'number', 'command'], true))
        return $n->value;
    if ($kind === 'symbol')
        return "'" . $n->value . "'";
    if ($kind === 'text')
        return '"' . $n->value . '"';
    if ($kind === 'reference')
        return '(eqref "' . $n->value . '")';
    if ($kind === 'row')
        return (
            '(row'
            . ($n->children ? ' ' . implode(' ', array_map(treeNotation(...), $n->children)) : '')
            . ')'
        );
    if ($kind === 'matrix')
        return (
            '('
            . $n->value
            . ' '
            . implode(' ', array_map(
                fn($row) => '[' . implode(' ', array_map(treeNotation(...), $row)) . ']',
                $n->children,
            ))
            . ')'
        );
    if ($kind === 'delim') {
        $delimiters = array_map(fn($s) => strlen($s) === 1 ? "'$s'" : $s, $n->value);
        return '(delim ' . implode(' ', $delimiters) . ' ' . treeNotation($n->children[0]) . ')';
    }
    if ($kind === 'script') {
        [$base, $sub, $sup] = $n->children;
        $name = $sub === null ? 'sup' : ($sup === null ? 'sub' : 'subsup');
        $children = array_values(array_filter($n->children, fn($child) => $child !== null));
    } else {
        $name = $kind === 'accent' ? $n->value : $kind;
        $children = $n->children;
    }
    return '(' . $name . ' ' . implode(' ', array_map(treeNotation(...), $children)) . ')';
}

final class LinearNotation
{
    public function __construct(
        private array $params,
        private array $references,
    ) {}

    public function row(array $nodes, string $style = 'normal'): string
    {
        [, $gaps] = spacing($nodes, $style, $this->params);
        $text = '';
        foreach ($nodes as $i => $n) {
            if ($i)
                $text .= str_repeat(' ', $gaps[$i - 1]);
            $text .= $this->node($n, $style);
        }
        return $text;
    }

    private function parenthesize(MathNode $n, string $style, array $kinds): string
    {
        $text = $this->node($n, $style);
        return in_array($n->kind, $kinds, true) ? '(' . $text . ')' : $text;
    }

    private function node(MathNode $n, string $style = 'normal'): string
    {
        $kind = $n->kind;
        if (in_array($kind, ['identifier', 'number', 'symbol', 'text'], true))
            return $n->value;
        if ($kind === 'command')
            return symbolCommands()[$n->value][0];
        if ($kind === 'reference')
            return $this->references[$n->value] ?? '(??)';
        if ($kind === 'row')
            return $this->row($n->children, $style);
        if ($kind === 'frac')
            return implode('/', array_map(fn($child) => $this->parenthesize(
                $child,
                $style,
                ['row', 'frac'],
            ), $n->children));
        if ($kind === 'script') {
            [$base, $sub, $sup] = $n->children;
            $text = $this->parenthesize($base, $style, ['row', 'frac', 'script']);
            if ($sub !== null)
                $text .= '_' . $this->parenthesize($sub, 'script', ['row', 'frac']);
            if ($sup !== null)
                $text .= '^' . $this->parenthesize($sup, 'script', ['row', 'frac']);
            return $text;
        }
        if ($kind === 'delim')
            return (
                delimiterString($n->value[0])
                . $this->node($n->children[0], $style)
                . delimiterString($n->value[1])
            );
        if ($kind === 'matrix')
            return (
                $n->value
                . '['
                . implode('; ', array_map(fn($row) => implode(', ', array_map(fn($cell) => $this->node(
                    $cell,
                    $style,
                ), $row)), $n->children))
                . ']'
            );
        if ($kind === 'root' || $kind === 'overset' || $kind === 'underset')
            return (
                $kind
                . '('
                . $this->node($n->children[0], 'script')
                . ', '
                . $this->node($n->children[1], $style)
                . ')'
            );
        $name = $kind === 'accent' ? $n->value : $kind;
        return (
            $name
            . '('
            . implode(', ', array_map(fn($child) => $this->node($child, $style), $n->children))
            . ')'
        );
    }
}

function diagnostic(Formula $f, int $column, string $message, bool $warning = false): array
{
    return [
        "formula {$f->number}, column $column: " . ($warning ? 'warning: ' : '') . $message,
        '  ' . $f->line,
        str_repeat(' ', $column + 1) . '^',
    ];
}

function main(): void
{
    $params = [];
    foreach (file('input/params.txt', FILE_IGNORE_NEW_LINES) as $line) {
        [$key, $value] = explode(' ', $line);
        $params[$key] = (int) $value;
    }
    $formulas = [];
    foreach (file('input/formulas.txt', FILE_IGNORE_NEW_LINES) as $i => $line)
        $formulas[] = new Formula($i + 1, $line);
    $references = referenceTable($formulas);
    $typesetter = new Typesetter($params, $references);
    $linear = new LinearNotation($params, $references);
    $rendered = $boxes = $trees = $errors = $kinds = [];
    $totalBoxes = $maxDepth = $valid = $errorCount = $warningCount = $overfullCount = 0;
    foreach ($formulas as $i => $f) {
        if ($i)
            $rendered[] = '';
        $rendered[] = 'formula ' . $f->number;
        if ($f->error !== null) {
            ++$errorCount;
            $rendered[] = '(error)';
            $boxes[] = "formula {$f->number}: error";
            $trees[] = "formula {$f->number}: error";
            array_push($errors, ...diagnostic($f, ...$f->error));
            continue;
        }
        ++$valid;
        collectWarnings($f, $references);
        [$roots, $lineCount, $width, $height, $overfull] = placeFormula($f, $typesetter, $params);
        array_push($rendered, ...drawBoxes($roots, $width, $height));
        $entries = boxLines($roots);
        $depth = max(array_column($entries, 1)) + 1;
        $totalBoxes += count($entries);
        $maxDepth = max($maxDepth, $depth);
        $boxes[] =
            "formula {$f->number}: lines=$lineCount width=$width height=$height boxes="
            . count($entries)
            . " depth=$depth";
        foreach ($entries as [$line, $level, $kind]) {
            $boxes[] = $line;
            $kinds[$kind] = ($kinds[$kind] ?? 0) + 1;
        }
        $trees[] = "formula {$f->number}: " . implode(' ', array_map(treeNotation(...), $f->nodes));
        $text = rtrim($linear->row($f->nodes), ' ');
        $trees[] = '  linear:' . ($text !== '' ? ' ' . $text : '');
        if ($f->tagString !== null)
            $trees[] = '  tag: ' . $f->tagString;
        $warningCount += count($f->warnings);
        foreach ($f->warnings as [$column, $message])
            array_push($errors, ...diagnostic($f, $column, $message, true));
        $overfullCount += count($overfull);
        foreach ($overfull as [$number, $occupied])
            $errors[] = "formula {$f->number}: line $number is overfull (width $occupied > {$params['width']})";
    }
    $boxes[] = "summary: boxes=$totalBoxes max_depth=$maxDepth";
    ksort($kinds, SORT_STRING);
    foreach ($kinds as $kind => $count)
        $boxes[] = "  $kind: $count";
    $errors[] =
        'formulas='
        . count($formulas)
        . " rendered=$valid errors=$errorCount warnings=$warningCount overfull=$overfullCount";
    if (!is_dir('output'))
        mkdir('output');
    foreach ([
        'rendered.txt' => $rendered,
        'boxes.txt' => $boxes,
        'trees.txt' => $trees,
        'errors.txt' => $errors,
    ] as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

main();
