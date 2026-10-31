<?php

foreach (['lexer', 'parser', 'doc_builder', 'printer', 'report'] as $module)
    require_once __DIR__ . "/$module.php";
function attachComments(array $tokens, array $items): void
{
    $before = null;
    $after = [];
    $next = null;
    for ($i = count($items) - 1; $i >= 0; --$i) {
        $after[$i] = $next;
        if (!$items[$i]->isComment())
            $next = $items[$i];
    }
    foreach ($items as $i => $c) {
        if (!$c->isComment()) {
            $before = $c;
            continue;
        }
        $following = $items[$i + 1] ?? null;
        $n = $after[$i];
        $c->ownLine = $c->kind === 'line_comment' || $following === null || $following->line > $c->line;
        if ($before !== null && $before->line === $c->line && ($n === null || $n->line > $c->line))
            $before->trailing[] = $c;
        else {
            $target = $n ?? $tokens[count($tokens) - 1];
            $target->leading[] = $c;
        }
    }
}

function checkCommentPositions(array $tokens): void
{
    foreach ($tokens as $t)
        foreach ($t->leading as $c)
            if ($t->trailingComma || $c->ownLine && !$t->allowed)
                throw new SourceError($c->line, $c->column, 'comment not allowed here');
}

final class DocumentFormatter
{
    private int $indent, $maxBlank;
    private string $space, $keywordGap;
    private Doc $operatorBreak;
    private bool $kr;
    private array $originalTrailing;
    public ?Doc $firstFunctionDoc = null;
    public ?string $firstFunctionName = null;

    public function __construct(
        private array $profile,
        private array $tokens,
    ) {
        $this->indent = $profile['indent'];
        $this->maxBlank = $profile['max_blank_lines'];
        $this->space = $profile['space_around_operators'] ? ' ' : '';
        $this->operatorBreak = mark($profile['space_around_operators'] ? 'line' : 'softline');
        $this->keywordGap = $profile['space_after_keyword'] ? ' ' : '';
        $this->kr = $profile['brace_style'] === 'kr';
        $this->originalTrailing = array_map(fn($t) => (bool) $t->trailing, $tokens);
    }

    private function sep(int $blank): Doc
    {
        return concat(array_fill(0, 1 + min($blank, $this->maxBlank), mark('hardline')));
    }

    private function preBlank(SourceToken $t): int
    {
        return ($t->leading[0] ?? $t)->blank;
    }

    private function comments(array $comments, ?SourceToken $following): Doc
    {
        $parts = [];
        foreach ($comments as $i => $c) {
            $parts[] = $c->text;
            $next = $comments[$i + 1] ?? $following;
            if ($next !== null) {
                if ($c->ownLine)
                    $parts[] = $this->sep($next->blank);
                else
                    $parts[] = ' ';
            }
        }
        return concat($parts);
    }

    private function t(SourceToken $t, ?array $leading = null): Doc
    {
        return concat(
            $this->comments($leading ?? $t->leading, $t),
            $t->text,
            $t->trailing ? suffix(implode(' ', array_map(fn($c) => $c->text, $t->trailing))) : null,
        );
    }

    private function splitComments(SourceToken $t): array
    {
        $last = -1;
        foreach ($t->leading as $i => $c)
            if ($c->ownLine)
                $last = $i;
        return [array_slice($t->leading, 0, $last + 1), array_slice($t->leading, $last + 1)];
    }

    private function closingComments(array $comments, bool $preceding): ?Doc
    {
        return !$comments
            ? null
            : concat($preceding ? $this->sep($comments[0]->blank) : null, $this->comments($comments, null));
    }

    public function wholeFile(array $items, SourceToken $end): Doc
    {
        $parts = [];
        foreach ($items as $i => $item) {
            if ($i)
                $parts[] = $this->sep($this->preBlank($item->first));
            $d = $this->item($item);
            $parts[] = $d;
            if ($item->tag === 'function' && $this->firstFunctionDoc === null) {
                $this->firstFunctionDoc = $d;
                $this->firstFunctionName = $item->name->text;
            }
        }
        if ($end->leading) {
            if ($items)
                $parts[] = $this->sep($end->leading[0]->blank);
            $parts[] = $this->comments($end->leading, null);
        }
        return concat($parts);
    }

    private function item(object $e): Doc
    {
        return $e->tag === 'function'
            ? concat(
                $this->t($e->typ),
                ' ',
                $this->t($e->name),
                $this->listDoc($e->parameters),
                mark('hardline'),
                $this->block($e->body),
            )
            : $this->variable($e);
    }

    private function parameter(object $e): Doc
    {
        $parts = [$this->t($e->typ), ' ', $this->t($e->name)];
        foreach ($e->brackets as [$left, $right])
            array_push($parts, $this->t($left), $this->t($right));
        return concat($parts);
    }

    private function variable(object $e): Doc
    {
        $parts = [$this->t($e->typ), ' ', $this->t($e->name)];
        foreach ($e->dimensions as [$left, $expr, $right])
            array_push(
                $parts,
                $this->t($left),
                $expr === null ? null : $this->expr($expr, 0),
                $this->t($right),
            );
        if ($e->equals !== null)
            array_push(
                $parts,
                $this->space,
                $this->t($e->equals),
                $this->space,
                $this->initializer($e->initializer),
            );
        if ($e->semi !== null)
            $parts[] = $this->t($e->semi);
        return concat($parts);
    }

    private function initializer(object $e): Doc
    {
        return $e->tag === 'list' ? $this->listDoc($e) : $this->expr($e, 0);
    }

    private function listDoc(object $e): Doc
    {
        if (!$e->elements)
            return concat($this->t($e->left), $this->t($e->right));
        $forced = false;
        for ($i = $e->left->index; $i < $e->right->index; ++$i)
            if ($this->originalTrailing[$i]) {
                $forced = true;
                break;
            }
        $contents = [mark('softline')];
        foreach ($e->elements as $i => $item) {
            if ($i)
                array_push($contents, $this->t($e->commas[$i - 1]), mark('line'));
            $contents[] = $item->tag === 'parameter'
                ? $this->parameter($item)
                : ($e->role === '{' ? $this->initializer($item) : $this->expr($item, 0));
        }
        if ($e->role === '{') {
            $contents[] = ifBreak(',', '');
            if ($e->trailing !== null && $e->trailing->trailing)
                $contents[] = suffix(implode(' ', array_map(fn($c) => $c->text, $e->trailing->trailing)));
        }
        return group([
            $forced ? mark('break_parent') : null,
            $this->t($e->left),
            nest($this->indent, $contents),
            mark('softline'),
            $this->t($e->right),
        ]);
    }

    private function block(object $e): Doc
    {
        [$own, $inline] = $this->splitComments($e->right);
        if (!$e->statements && !$own)
            return concat($this->t($e->left), $this->t($e->right, $inline));
        $body = [mark('hardline')];
        foreach ($e->statements as $i => $s) {
            if ($i)
                $body[] = $this->sep($this->preBlank($s->first));
            $body[] = $this->statement($s);
        }
        $body[] = $this->closingComments($own, (bool) $e->statements);
        return concat(
            $this->t($e->left),
            nest($this->indent, $body),
            mark('hardline'),
            $this->t($e->right, $inline),
        );
    }

    private function body(object $e): Doc
    {
        $separator = $this->kr ? ' ' : mark('hardline');
        if ($e->tag === 'block')
            return concat($separator, $this->block($e));
        if ($this->profile['add_braces'])
            return concat($separator, '{', nest($this->indent, [
                mark('hardline'),
                $this->statement($e),
            ]), mark('hardline'), '}');
        return nest($this->indent, [mark('hardline'), $this->statement($e)]);
    }

    private function simple(object $e): Doc
    {
        return $e->tag === 'assign'
            ? concat(
                $this->expr($e->left, 0),
                $this->space,
                $this->t($e->op),
                $this->space,
                $this->expr($e->right, 0),
            )
            : $this->expr($e->expr, 0);
    }

    private function ifStatement(object $e): Doc
    {
        $parts = [
            $this->t($e->keyword),
            $this->keywordGap,
            $this->t($e->left),
            $this->expr($e->test, 0),
            $this->t($e->right),
            $this->body($e->body),
        ];
        if ($e->elseToken !== null) {
            $separator = $this->kr && ($e->body->tag === 'block' || $this->profile['add_braces'])
                ? ' '
                : mark('hardline');
            array_push($parts, $separator, $this->t($e->elseToken));
            if ($e->alternative->tag === 'if')
                array_push($parts, ' ', $this->ifStatement($e->alternative));
            else
                $parts[] = $this->body($e->alternative);
        }
        return concat($parts);
    }

    private function forStatement(object $e): Doc
    {
        $parts = [];
        if ($e->initial !== null)
            $parts[] = $e->initial->tag === 'variable'
                ? $this->variable($e->initial)
                : $this->simple($e->initial);
        $parts[] = $this->t($e->firstSemi);
        if ($e->condition !== null)
            array_push($parts, mark('line'), $this->expr($e->condition, 0));
        $parts[] = $this->t($e->secondSemi);
        if ($e->update !== null)
            array_push($parts, mark('line'), $this->simple($e->update));
        return concat(
            $this->t($e->keyword),
            $this->keywordGap,
            $this->t($e->left),
            group(align($parts)),
            $this->t($e->right),
            $this->body($e->body),
        );
    }

    private function clause(object $e): Doc
    {
        $parts = [$this->t($e->label)];
        if ($e->value !== null)
            array_push($parts, ' ', $this->expr($e->value, 0));
        $parts[] = $this->t($e->colon);
        if ($e->statements) {
            $body = [mark('hardline')];
            foreach ($e->statements as $i => $s) {
                if ($i)
                    $body[] = $this->sep($this->preBlank($s->first));
                $body[] = $this->statement($s);
            }
            $parts[] = nest($this->indent, $body);
        }
        return concat($parts);
    }

    private function switchStatement(object $e): Doc
    {
        [$own, $inline] = $this->splitComments($e->closing);
        $header = [
            $this->t($e->keyword),
            $this->keywordGap,
            $this->t($e->left),
            $this->expr($e->test, 0),
            $this->t($e->right),
            $this->kr ? ' ' : mark('hardline'),
            $this->t($e->opening),
        ];
        if (!$e->clauses && !$own)
            return concat($header, $this->t($e->closing, $inline));
        $body = [mark('hardline')];
        foreach ($e->clauses as $i => $c) {
            if ($i)
                $body[] = $this->sep($this->preBlank($c->label));
            $body[] = $this->clause($c);
        }
        $body[] = $this->closingComments($own, (bool) $e->clauses);
        return concat(
            $header,
            nest($this->profile['indent_case_labels'] ? $this->indent : 0, $body),
            mark('hardline'),
            $this->t($e->closing, $inline),
        );
    }

    private function statement(object $e): Doc
    {
        return match ($e->tag) {
            'block' => $this->block($e),
            'variable' => $this->variable($e),
            'simple_stmt' => concat($this->simple($e->value), $this->t($e->semi)),
            'return' => concat(
                $this->t($e->keyword),
                $e->expr === null ? null : [' ', $this->expr($e->expr, 0)],
                $this->t($e->semi),
            ),
            'flow' => concat($this->t($e->keyword), $this->t($e->semi)),
            'if' => $this->ifStatement($e),
            'for' => $this->forStatement($e),
            'switch' => $this->switchStatement($e),
            'while' => concat(
                $this->t($e->keyword),
                $this->keywordGap,
                $this->t($e->left),
                $this->expr($e->test, 0),
                $this->t($e->right),
                $this->body($e->body),
            ),
        };
    }

    private function lastToken(object $e): SourceToken
    {
        return match ($e->tag) {
            'primary' => $e->value,
            'paren', 'index' => $e->right,
            'unary' => $this->lastToken($e->operand),
            'binary' => $this->lastToken($e->right),
            'conditional' => $this->lastToken($e->no),
            'call' => $e->arguments->right,
            'member' => $e->member,
        };
    }

    private function opened(object $e, int $minimum): object
    {
        while ($this->profile['remove_parens'] && $e->tag === 'paren') {
            $inner = $e->inner;
            if (($inner->level ?? 8) < $minimum || $e->left->leading || $e->right->leading)
                break;
            $first = $inner->first;
            $last = $this->lastToken($inner);
            $first->trailing = [...$e->left->trailing, ...$first->trailing];
            $last->trailing = [...$last->trailing, ...$e->right->trailing];
            $e->left->trailing = $e->right->trailing = [];
            $e = $inner;
        }
        return $e;
    }

    private function binary(object $e): Doc
    {
        $p = $e->level;
        $ops = $operands = [];
        $x = $e;
        while ($x->tag === 'binary' && $x->level === $p) {
            $ops[] = $x->op;
            $operands[] = $x->right;
            $x = $this->opened($x->left, $p);
        }
        $ops = array_reverse($ops);
        $operands = array_reverse($operands);
        $parts = [];
        foreach ($ops as $i => $op)
            array_push(
                $parts,
                $this->operatorBreak,
                $this->t($op),
                $this->space,
                $this->expr($operands[$i], $p + 1),
            );
        return group([$this->expr($x, $p), nest($this->indent, $parts)]);
    }

    private function conditional(object $e): Doc
    {
        $parts = [];
        $x = $e;
        while (true) {
            array_push(
                $parts,
                $this->operatorBreak,
                $this->t($x->question),
                $this->space,
                $this->expr($x->yes, 0),
                $this->operatorBreak,
                $this->t($x->colon),
                $this->space,
            );
            $g = $this->opened($x->no, 0);
            if ($g->tag !== 'conditional') {
                $parts[] = $this->expr($g, 0);
                break;
            }
            $parts[] = $this->expr($g->test, 1);
            $x = $g;
        }
        return group([$this->expr($e->test, 1), nest($this->indent, $parts)]);
    }

    private function postfixPiece(object $e): Doc
    {
        return match ($e->tag) {
            'call' => $this->listDoc($e->arguments),
            'index' => concat($this->t($e->left), $this->expr($e->index, 0), $this->t($e->right)),
            'member' => concat($this->t($e->dot), $this->t($e->member)),
        };
    }

    private function postfix(object $e): Doc
    {
        $ops = [];
        $x = $e;
        while (in_array($x->tag, ['call', 'index', 'member'], true)) {
            $ops[] = $x;
            $x = $this->opened($x->target, 8);
        }
        $ops = array_reverse($ops);
        $segments = [[]];
        foreach ($ops as $op) {
            if ($op->tag === 'member')
                $segments[] = [];
            $segments[count($segments) - 1][] = $op;
        }
        $calls = [];
        foreach ($segments as $i => $segment)
            if ($i && array_any($segment, fn($op) => $op->tag === 'call'))
                $calls[] = $i;
        $head = $this->expr($x, 8);
        if (count($calls) < 2)
            return concat($head, array_map($this->postfixPiece(...), $ops));
        $before = $after = [];
        foreach ($segments as $i => $segment) {
            if ($i < $calls[0])
                array_push($before, ...array_map($this->postfixPiece(...), $segment));
            else
                array_push($after, mark('softline'), ...array_map($this->postfixPiece(...), $segment));
        }
        return group([$head, $before, nest($this->indent, $after)]);
    }

    private function expr(object $e, int $minimum): Doc
    {
        $e = $this->opened($e, $minimum);
        return match ($e->tag) {
            'primary' => $this->t($e->value),
            'paren' => concat($this->t($e->left), $this->expr($e->inner, 0), $this->t($e->right)),
            'unary' => concat($this->t($e->op), $this->expr($e->operand, 8)),
            'binary' => $this->binary($e),
            'conditional' => $this->conditional($e),
            default => $this->postfix($e),
        };
    }
}

function renderOnce(array $lines, array $profile): object
{
    [$tokens, $comments, $items] = lexicalAnalysis($lines);
    attachComments($tokens, $items);
    $syntax = new SourceParser($tokens)->parse();
    checkCommentPositions($tokens);
    $builder = new DocumentFormatter($profile, $tokens);
    $end = $tokens[count($tokens) - 1];
    if (!$syntax && !$end->leading)
        return (object) ['lines' => [], 'comments' => $comments, 'document' => null, 'builder' => $builder];
    $document = $builder->wholeFile($syntax, $end);
    return (object) [
        'lines' => layout($document, $profile),
        'comments' => $comments,
        'document' => $document,
        'builder' => $builder,
    ];
}

function main(): void
{
    $profiles = [];
    $current = '';
    foreach (file('input/style.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if ($line === '')
            continue;
        if ($line[0] === '[') {
            $current = substr($line, 1, -1);
            $profiles[$current] = [];
        } else {
            [$key, $value] = explode('=', $line, 2);
            $profiles[$current][$key] = in_array(
                $key,
                ['width', 'indent', 'max_blank_lines', 'comment_column'],
                true,
            )
                ? (int) $value
                : ($value === 'yes' ? true : ($value === 'no' ? false : $value));
        }
    }
    $sources = [];
    foreach (file('input/sources.txt', FILE_IGNORE_NEW_LINES) as $line) {
        if (str_starts_with($line, '=== ')) {
            [, $name, $profile] = explode(' ', $line);
            $sources[] = (object) ['header' => $line, 'name' => $name, 'profile' => $profile, 'lines' => []];
        } else
            $sources[count($sources) - 1]->lines[] = $line;
    }
    $formatted = $idempotency = $diagnostics = $trees = $changes = [];
    foreach ($sources as $source) {
        $name = $source->name;
        $profile = $profiles[$source->profile];
        $original = array_map(fn($s) => rtrim($s, ' '), $source->lines);
        $formatted[] = $source->header;
        $trees[] = $changes[] = "=== $name";
        try {
            $first = renderOnce($source->lines, $profile);
        } catch (SourceError $e) {
            array_push($formatted, ...$original);
            $idempotency[] = "$name: skipped (syntax error)";
            $diagnostics[] = "$name:{$e->sourceLine}:{$e->column}: error: " . $e->getMessage();
            $trees[] = 'syntax error';
            $changes[] = 'skipped (syntax error)';
            continue;
        }
        array_push($formatted, ...$first->lines);
        try {
            $second = renderOnce($first->lines, $profile);
            if ($first->lines === $second->lines)
                $idempotency[] = "$name: stable";
            else {
                $difference = 0;
                $n = min(count($first->lines), count($second->lines));
                while ($difference < $n && $first->lines[$difference] === $second->lines[$difference])
                    ++$difference;
                $idempotency[] = "$name: unstable at line " . ($difference + 1);
            }
        } catch (SourceError $e) {
            $idempotency[] =
                "$name: unstable (second pass: {$e->sourceLine}:{$e->column}: " . $e->getMessage() . ')';
        }
        $longest = 0;
        foreach ($first->lines as $i => $line) {
            $length = strlen($line);
            $longest = max($longest, $length);
            if ($length > $profile['width'])
                $diagnostics[] =
                    "$name:" . ($i + 1) . ": warning: line too long ($length > {$profile['width']})";
        }
        $groups = iterator_to_array(allGroups($first->document), false);
        $broken = count(array_filter($groups, fn($g) => in_array($g->mode, ['break', 'forced'], true)));
        $forced = count(array_filter($groups, fn($g) => $g->mode === 'forced'));
        $trees[] =
            'metrics lines='
            . count($first->lines)
            . " longest=$longest comments="
            . count($first->comments)
            . ' groups='
            . count($groups)
            . " broken=$broken forced=$forced";
        if ($first->builder->firstFunctionDoc === null)
            $trees[] = 'no function';
        else {
            $trees[] = 'function ' . $first->builder->firstFunctionName;
            array_push($trees, ...docTree($first->builder->firstFunctionDoc));
        }
        array_push($changes, ...diffLines($original, $first->lines));
    }
    if (!$diagnostics)
        $diagnostics = ['no diagnostics'];
    if (!is_dir('output'))
        mkdir('output');
    foreach ([
        'formatted.txt' => $formatted,
        'idempotency.txt' => $idempotency,
        'diagnostics.txt' => $diagnostics,
        'doc_tree.txt' => $trees,
        'changes.txt' => $changes,
    ] as $name => $lines)
        file_put_contents('output/' . $name, implode("\n", $lines) . "\n");
}

main();
