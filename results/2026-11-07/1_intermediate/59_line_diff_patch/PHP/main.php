<?php

declare(strict_types=1);

const DATA_COMMANDS = ['FILE', 'PATCH', 'EDIT'];
const FORMATS_WITH_ARGUMENT = ['IFDEF', 'UNIFIED', 'CONTEXT', 'SIDE'];
const OFFSETS = [0, 1, -1, 2, -2, 3, -3];
const GRAPH_WIDTH = 20;
const NUMBER_PAIR = '/\A([0-9]{1,4})(?:,([0-9]{1,4}))?\z/';
const MARKER_PREFIXES = ['<<<<<<<' => 'start', '|||||||' => 'base', '>>>>>>>' => 'end'];
const SEPARATOR = '=======';

final class CommandError extends Exception
{
}

function rangeR(int $start, int $count): string
{
    if ($count >= 2) {
        return ($start + 1) . ',' . ($start + $count);
    }
    if ($count === 1) {
        return (string) ($start + 1);
    }
    return (string) $start;
}

function rangeU(int $start, int $count): string
{
    if ($count >= 2) {
        return ($start + 1) . ",$count";
    }
    if ($count === 1) {
        return (string) ($start + 1);
    }
    return "$start,0";
}

function rangeM(int $start, int $count): string
{
    return ($start + 1) . ",$count";
}

function prefixed(string $prefix, array $lines): array
{
    return array_map(fn (string $line): string => $prefix . $line, $lines);
}

function comparisonKey(string $line, array $options): string
{
    if (in_array('ICASE', $options, true)) {
        $line = strtolower($line);
    }
    if (in_array('IWHITE', $options, true)) {
        $line = str_replace(' ', '', $line);
    }
    if (in_array('ISPACE', $options, true)) {
        $line = preg_replace('/ {2,}/', ' ', $line);
    }
    return $line;
}

function matchedPairs(array $first, array $second): array
{
    $rows = count($first);
    $columns = count($second);
    $table = array_fill(0, $rows + 1, array_fill(0, $columns + 1, 0));
    for ($i = 1; $i <= $rows; $i++) {
        for ($j = 1; $j <= $columns; $j++) {
            if ($first[$i - 1] === $second[$j - 1]) {
                $table[$i][$j] = $table[$i - 1][$j - 1] + 1;
            } else {
                $table[$i][$j] = max($table[$i - 1][$j], $table[$i][$j - 1]);
            }
        }
    }
    $pairs = [[$rows + 1, $columns + 1]];
    $i = $rows;
    $j = $columns;
    while ($i >= 1 && $j >= 1) {
        if ($first[$i - 1] === $second[$j - 1]) {
            $pairs[] = [$i, $j];
            $i--;
            $j--;
        } elseif ($table[$i - 1][$j] >= $table[$i][$j - 1]) {
            $i--;
        } else {
            $j--;
        }
    }
    $pairs[] = [0, 0];
    return array_reverse($pairs);
}

final readonly class ChangeBlock
{
    public function __construct(
        public int $p,
        public int $q,
        public int $x,
        public int $y,
    ) {
    }

    public function letter(): string
    {
        if ($this->x >= 1 && $this->y >= 1) {
            return 'c';
        }
        return $this->y === 0 ? 'd' : 'a';
    }
}

function changeBlocks(array $first, array $second): array
{
    $pairs = matchedPairs($first, $second);
    $blocks = [];
    for ($index = 0; $index + 1 < count($pairs); $index++) {
        [$i, $j] = $pairs[$index];
        [$nextI, $nextJ] = $pairs[$index + 1];
        if ($nextI - $i > 1 || $nextJ - $j > 1) {
            $blocks[] = new ChangeBlock($i, $j, $nextI - $i - 1, $nextJ - $j - 1);
        }
    }
    return $blocks;
}

function walk(array $blocks, int $oldStart, int $newStart, int $oldEnd): array
{
    $steps = [];
    $oldIndex = $oldStart;
    $newIndex = $newStart;
    foreach ($blocks as $block) {
        while ($oldIndex < $block->p) {
            $steps[] = [$oldIndex, $newIndex, null];
            $oldIndex++;
            $newIndex++;
        }
        $steps[] = [$oldIndex, $newIndex, $block];
        $oldIndex = $block->p + $block->x;
        $newIndex = $block->q + $block->y;
    }
    while ($oldIndex < $oldEnd) {
        $steps[] = [$oldIndex, $newIndex, null];
        $oldIndex++;
        $newIndex++;
    }
    return $steps;
}

function sideRow(string $left, string $symbol, string $right, int $width): string
{
    $row = str_pad(substr($left, 0, $width), $width) . " $symbol " . substr($right, 0, $width);
    return rtrim($row, ' ');
}

function statGraph(int $inserted, int $deleted): string
{
    $total = $inserted + $deleted;
    if ($total <= GRAPH_WIDTH) {
        $plus = $inserted;
        $minus = $deleted;
    } else {
        $plus = intdiv(GRAPH_WIDTH * $inserted, $total);
        $minus = intdiv(GRAPH_WIDTH * $deleted, $total);
        if ($inserted >= 1 && $plus === 0) {
            $plus = 1;
        }
        if ($deleted >= 1 && $minus === 0) {
            $minus = 1;
        }
    }
    return str_repeat('+', $plus) . str_repeat('-', $minus);
}

final readonly class Hunk
{
    public int $oldStart;
    public int $oldCount;
    public int $newStart;
    public int $newCount;

    public function __construct(public array $blocks, int $context, int $oldTotal)
    {
        $first = $blocks[0];
        $last = $blocks[count($blocks) - 1];
        $before = min($context, $first->p);
        $after = min($context, $oldTotal - $last->p - $last->x);
        $this->oldStart = $first->p - $before;
        $this->oldCount = $last->p + $last->x + $after - $this->oldStart;
        $this->newStart = $first->q - $before;
        $this->newCount = $last->q + $last->y + $after - $this->newStart;
    }

    public function steps(): array
    {
        return walk($this->blocks, $this->oldStart, $this->newStart, $this->oldStart + $this->oldCount);
    }
}

final readonly class LineDiff
{
    public array $blocks;

    public function __construct(private array $old, private array $new, array $options = [])
    {
        $key = fn (string $line): string => comparisonKey($line, $options);
        $this->blocks = changeBlocks(array_map($key, $old), array_map($key, $new));
    }

    public function deleted(ChangeBlock $block): array
    {
        return array_slice($this->old, $block->p, $block->x);
    }

    public function inserted(ChangeBlock $block): array
    {
        return array_slice($this->new, $block->q, $block->y);
    }

    public function hunks(int $context): array
    {
        $groups = [];
        $previous = null;
        foreach ($this->blocks as $block) {
            if ($previous !== null && $block->p - ($previous->p + $previous->x) <= 2 * $context) {
                $groups[count($groups) - 1][] = $block;
            } else {
                $groups[] = [$block];
            }
            $previous = $block;
        }
        return array_map(fn (array $group): Hunk => new Hunk($group, $context, count($this->old)), $groups);
    }

    public function normal(): array
    {
        $lines = [];
        foreach ($this->blocks as $block) {
            $letter = $block->letter();
            $lines[] = rangeR($block->p, $block->x) . $letter . rangeR($block->q, $block->y);
            array_push($lines, ...prefixed('< ', $this->deleted($block)));
            if ($letter === 'c') {
                $lines[] = '---';
            }
            array_push($lines, ...prefixed('> ', $this->inserted($block)));
        }
        return $lines;
    }

    public function ed(): array
    {
        $lines = [];
        foreach (array_reverse($this->blocks) as $block) {
            $letter = $block->letter();
            $lines[] = rangeR($block->p, $block->x) . $letter;
            if ($letter !== 'd') {
                array_push($lines, ...$this->inserted($block));
                $lines[] = '.';
            }
        }
        return $lines;
    }

    public function rcs(): array
    {
        $lines = [];
        foreach ($this->blocks as $block) {
            if ($block->x >= 1) {
                $lines[] = 'd' . ($block->p + 1) . ' ' . $block->x;
            }
            if ($block->y >= 1) {
                $lines[] = 'a' . ($block->p + $block->x) . ' ' . $block->y;
                array_push($lines, ...$this->inserted($block));
            }
        }
        return $lines;
    }

    public function ifdef(string $macro): array
    {
        $lines = [];
        foreach (walk($this->blocks, 0, 0, count($this->old)) as [$oldIndex, , $block]) {
            if ($block === null) {
                $lines[] = $this->old[$oldIndex];
            } elseif ($block->x >= 1 && $block->y >= 1) {
                $lines[] = "#ifndef $macro";
                array_push($lines, ...$this->deleted($block));
                $lines[] = "#else /* $macro */";
                array_push($lines, ...$this->inserted($block));
                $lines[] = "#endif /* $macro */";
            } elseif ($block->y === 0) {
                $lines[] = "#ifndef $macro";
                array_push($lines, ...$this->deleted($block));
                $lines[] = "#endif /* ! $macro */";
            } else {
                $lines[] = "#ifdef $macro";
                array_push($lines, ...$this->inserted($block));
                $lines[] = "#endif /* $macro */";
            }
        }
        return $lines;
    }

    public function unified(int $context, string $oldName, string $newName): array
    {
        $lines = ["--- $oldName", "+++ $newName"];
        foreach ($this->hunks($context) as $hunk) {
            $oldRange = rangeU($hunk->oldStart, $hunk->oldCount);
            $newRange = rangeU($hunk->newStart, $hunk->newCount);
            $lines[] = "@@ -$oldRange +$newRange @@";
            foreach ($hunk->steps() as [$oldIndex, , $block]) {
                if ($block === null) {
                    $lines[] = ' ' . $this->old[$oldIndex];
                } else {
                    array_push($lines, ...prefixed('-', $this->deleted($block)));
                    array_push($lines, ...prefixed('+', $this->inserted($block)));
                }
            }
        }
        return $lines;
    }

    public function context(int $context, string $oldName, string $newName): array
    {
        $lines = ["*** $oldName", "--- $newName"];
        foreach ($this->hunks($context) as $hunk) {
            $lines[] = str_repeat('*', 15);
            $lines[] = '*** ' . rangeR($hunk->oldStart, $hunk->oldCount) . ' ****';
            if (array_sum(array_column($hunk->blocks, 'x')) > 0) {
                foreach ($hunk->steps() as [$oldIndex, , $block]) {
                    if ($block === null) {
                        $lines[] = '  ' . $this->old[$oldIndex];
                    } else {
                        $marker = $block->y >= 1 ? '! ' : '- ';
                        array_push($lines, ...prefixed($marker, $this->deleted($block)));
                    }
                }
            }
            $lines[] = '--- ' . rangeR($hunk->newStart, $hunk->newCount) . ' ----';
            if (array_sum(array_column($hunk->blocks, 'y')) > 0) {
                foreach ($hunk->steps() as [, $newIndex, $block]) {
                    if ($block === null) {
                        $lines[] = '  ' . $this->new[$newIndex];
                    } else {
                        $marker = $block->x >= 1 ? '! ' : '+ ';
                        array_push($lines, ...prefixed($marker, $this->inserted($block)));
                    }
                }
            }
        }
        return $lines;
    }

    public function sideBySide(int $width): array
    {
        $lines = [];
        foreach (walk($this->blocks, 0, 0, count($this->old)) as [$oldIndex, $newIndex, $block]) {
            if ($block === null) {
                $lines[] = sideRow($this->old[$oldIndex], ' ', $this->new[$newIndex], $width);
                continue;
            }
            for ($row = 0; $row < max($block->x, $block->y); $row++) {
                if ($row < $block->x && $row < $block->y) {
                    $left = $this->old[$block->p + $row];
                    $symbol = '|';
                    $right = $this->new[$block->q + $row];
                } elseif ($row < $block->x) {
                    $left = $this->old[$block->p + $row];
                    $symbol = '<';
                    $right = '';
                } else {
                    $left = '';
                    $symbol = '>';
                    $right = $this->new[$block->q + $row];
                }
                $lines[] = sideRow($left, $symbol, $right, $width);
            }
        }
        return $lines;
    }
}

final class TokenTotals
{
    public int $deleted = 0;
    public int $inserted = 0;
    public int $common = 0;
}

function splitTokens(string $line, bool $byWord): array
{
    return $byWord ? preg_split('/\s+/', $line, -1, PREG_SPLIT_NO_EMPTY) : str_split($line);
}

function deletion(array $tokens, string $separator): string
{
    return '[-' . implode($separator, $tokens) . '-]';
}

function insertion(array $tokens, string $separator): string
{
    return '{+' . implode($separator, $tokens) . '+}';
}

function compareTokens(
    array $oldTokens,
    array $newTokens,
    string $separator,
    TokenTotals $totals,
): string {
    $parts = [];
    $blocks = changeBlocks($oldTokens, $newTokens);
    foreach (walk($blocks, 0, 0, count($oldTokens)) as [$oldIndex, , $block]) {
        if ($block === null) {
            $parts[] = $oldTokens[$oldIndex];
            $totals->common++;
            continue;
        }
        if ($block->x >= 1) {
            $parts[] = deletion(array_slice($oldTokens, $block->p, $block->x), $separator);
        }
        if ($block->y >= 1) {
            $parts[] = insertion(array_slice($newTokens, $block->q, $block->y), $separator);
        }
        $totals->deleted += $block->x;
        $totals->inserted += $block->y;
    }
    return implode($separator, $parts);
}

final class PatchHunk
{
    public array $body = [];

    public function __construct(
        public readonly int $lineNumber,
        public readonly int $oldStart,
        public readonly int $oldCount,
        public readonly int $newStart,
        public readonly int $newCount,
    ) {
    }

    public function sequences(bool $reverse): array
    {
        $oldKinds = $reverse ? [' ', '+'] : [' ', '-'];
        $newKinds = $reverse ? [' ', '-'] : [' ', '+'];
        $old = [];
        $new = [];
        foreach ($this->body as [$kind, $text]) {
            if (in_array($kind, $oldKinds, true)) {
                $old[] = $text;
            }
            if (in_array($kind, $newKinds, true)) {
                $new[] = $text;
            }
        }
        return [$old, $new];
    }

    public function start(bool $reverse): int
    {
        return $reverse ? $this->newStart : $this->oldStart;
    }

    public function leadingContext(): int
    {
        $count = 0;
        while ($count < count($this->body) && $this->body[$count][0] === ' ') {
            $count++;
        }
        return $count;
    }

    public function trailingContext(): int
    {
        $count = 0;
        $size = count($this->body);
        while ($count < $size && $this->body[$size - 1 - $count][0] === ' ') {
            $count++;
        }
        return $count;
    }
}

final readonly class HunkMatch
{
    public function __construct(
        public int $fuzz,
        public int $delta,
        public int $position,
        public array $lines,
    ) {
    }

    public function report(int $number): string
    {
        $text = "Hunk #$number succeeded at " . ($this->position + 1);
        if ($this->fuzz >= 1) {
            $text .= " with fuzz {$this->fuzz}";
        }
        if (abs($this->delta) === 1) {
            $text .= " (offset {$this->delta} line)";
        } elseif ($this->delta !== 0) {
            $text .= " (offset {$this->delta} lines)";
        }
        return $text;
    }
}

function parseRange(string $text, string $sign): ?array
{
    if (!str_starts_with($text, $sign) || preg_match(NUMBER_PAIR, substr($text, 1), $match) !== 1) {
        return null;
    }
    $start = (int) $match[1];
    $count = isset($match[2]) ? (int) $match[2] : 1;
    if ($start === 0 && $count !== 0) {
        return null;
    }
    return [$start, $count];
}

function parseHunkHeader(string $line, int $lineNumber): PatchHunk
{
    $parts = explode(' ', $line);
    $oldRange = null;
    $newRange = null;
    if (count($parts) === 4 && $parts[0] === '@@' && $parts[3] === '@@') {
        $oldRange = parseRange($parts[1], '-');
        $newRange = parseRange($parts[2], '+');
    }
    if ($oldRange === null || $newRange === null) {
        throw new CommandError("PATCH ERROR line $lineNumber: bad hunk header");
    }
    return new PatchHunk($lineNumber, $oldRange[0], $oldRange[1], $newRange[0], $newRange[1]);
}

function parsePatch(array $patchLines): array
{
    $total = count($patchLines);
    $index = 0;
    while ($index < $total && !str_starts_with($patchLines[$index], '@@')) {
        $index++;
    }
    if ($index === $total) {
        throw new CommandError('PATCH ERROR no hunks');
    }
    $hunks = [];
    while ($index < $total) {
        $hunk = parseHunkHeader($patchLines[$index], $index + 1);
        $index++;
        $oldSeen = 0;
        $newSeen = 0;
        while ($oldSeen < $hunk->oldCount || $newSeen < $hunk->newCount) {
            if ($index === $total) {
                throw new CommandError("PATCH ERROR line {$hunk->lineNumber}: truncated hunk");
            }
            $line = $patchLines[$index];
            $kind = $line[0];
            $inOld = $kind === ' ' || $kind === '-';
            $inNew = $kind === ' ' || $kind === '+';
            if (
                strlen($line) < 2
                || !($inOld || $inNew)
                || ($inOld && $oldSeen === $hunk->oldCount)
                || ($inNew && $newSeen === $hunk->newCount)
            ) {
                throw new CommandError('PATCH ERROR line ' . ($index + 1) . ': bad hunk line');
            }
            $hunk->body[] = [$kind, substr($line, 1)];
            if ($inOld) {
                $oldSeen++;
            }
            if ($inNew) {
                $newSeen++;
            }
            $index++;
        }
        $kinds = array_column($hunk->body, 0);
        if (!in_array('-', $kinds, true) && !in_array('+', $kinds, true)) {
            throw new CommandError("PATCH ERROR line {$hunk->lineNumber}: no changes");
        }
        $hunks[] = $hunk;
    }
    return $hunks;
}

function searchHunk(
    PatchHunk $hunk,
    array $lines,
    int $adjustment,
    bool $reverse,
    int $maxFuzz,
): ?HunkMatch {
    [$old, $new] = $hunk->sequences($reverse);
    $start = $hunk->start($reverse);
    $expected = $old !== [] ? $start - 1 + $adjustment : $start + $adjustment;
    $leading = $hunk->leadingContext();
    $trailing = $hunk->trailingContext();
    for ($fuzz = 0; $fuzz <= $maxFuzz; $fuzz++) {
        $head = min($fuzz, $leading);
        $tail = min($fuzz, $trailing);
        $oldPart = array_slice($old, $head, count($old) - $head - $tail);
        $newPart = array_slice($new, $head, count($new) - $head - $tail);
        foreach (OFFSETS as $delta) {
            $position = $expected + $head + $delta;
            $length = count($oldPart);
            if ($position < 0 || $position + $length > count($lines)) {
                continue;
            }
            if (array_slice($lines, $position, $length) === $oldPart) {
                array_splice($lines, $position, $length, $newPart);
                return new HunkMatch($fuzz, $delta, $position, $lines);
            }
        }
    }
    return null;
}

function parseEditCommand(string $line): ?array
{
    $instruction = substr($line, -1);
    $address = substr($line, 0, -1);
    if (!in_array($instruction, ['a', 'c', 'd'], true) || preg_match(NUMBER_PAIR, $address, $match) !== 1) {
        return null;
    }
    if ($instruction === 'a' && isset($match[2])) {
        return null;
    }
    $first = (int) $match[1];
    $last = isset($match[2]) ? (int) $match[2] : $first;
    return [$instruction, $first, $last];
}

function runEditScript(array $lines, array $script): array
{
    $executed = 0;
    $index = 0;
    while ($index < count($script)) {
        $lineNumber = $index + 1;
        $command = parseEditCommand($script[$index]);
        if ($command === null) {
            throw new CommandError("EDIT ERROR line $lineNumber: bad command");
        }
        [$instruction, $first, $last] = $command;
        $valid = $instruction === 'a'
            ? $first <= count($lines)
            : 1 <= $first && $first <= $last && $last <= count($lines);
        if (!$valid) {
            throw new CommandError("EDIT ERROR line $lineNumber: bad range");
        }
        $index++;
        $text = [];
        if ($instruction !== 'd') {
            $end = $index;
            while ($end < count($script) && $script[$end] !== '.') {
                $end++;
            }
            if ($end === count($script)) {
                throw new CommandError("EDIT ERROR line $lineNumber: missing terminator");
            }
            $text = array_slice($script, $index, $end - $index);
            $index = $end + 1;
        }
        if ($instruction === 'a') {
            array_splice($lines, $first, 0, $text);
        } else {
            array_splice($lines, $first - 1, $last - $first + 1, $text);
        }
        $executed++;
    }
    return [$lines, $executed];
}

final readonly class Chunk
{
    public function __construct(
        public string $kind,
        public int $baseStart,
        public int $oursStart,
        public int $theirsStart,
        public array $base,
        public array $ours,
        public array $theirs,
    ) {
    }

    public function location(): string
    {
        return 'base ' . rangeM($this->baseStart, count($this->base))
            . ' a ' . rangeM($this->oursStart, count($this->ours))
            . ' b ' . rangeM($this->theirsStart, count($this->theirs));
    }
}

function chunkKind(array $base, array $ours, array $theirs): string
{
    if ($ours === $base) {
        return 'b';
    }
    if ($theirs === $base) {
        return 'a';
    }
    if ($ours === $theirs) {
        return 'both';
    }
    return 'conflict';
}

function matchTable(array $first, array $second): array
{
    $matches = array_fill(0, count($first) + 2, 0);
    foreach (array_slice(matchedPairs($first, $second), 1, -1) as [$i, $j]) {
        $matches[$i] = $j;
    }
    return $matches;
}

function threeWayChunks(array $base, array $ours, array $theirs): array
{
    $oursMatch = matchTable($base, $ours);
    $theirsMatch = matchTable($base, $theirs);
    $chunks = [];
    $x = 0;
    $y = 0;
    $z = 0;
    while ($x < count($base) || $y < count($ours) || $z < count($theirs)) {
        if ($x < count($base) && $oursMatch[$x + 1] === $y + 1 && $theirsMatch[$x + 1] === $z + 1) {
            $chunks[] = new Chunk('stable', $x, $y, $z, [$base[$x]], [$ours[$y]], [$theirs[$z]]);
            $x++;
            $y++;
            $z++;
            continue;
        }
        $anchor = $x + 1;
        while ($anchor <= count($base) && ($oursMatch[$anchor] === 0 || $theirsMatch[$anchor] === 0)) {
            $anchor++;
        }
        if ($anchor <= count($base)) {
            $nextX = $anchor - 1;
            $nextY = $oursMatch[$anchor] - 1;
            $nextZ = $theirsMatch[$anchor] - 1;
        } else {
            $nextX = count($base);
            $nextY = count($ours);
            $nextZ = count($theirs);
        }
        $basePart = array_slice($base, $x, $nextX - $x);
        $oursPart = array_slice($ours, $y, $nextY - $y);
        $theirsPart = array_slice($theirs, $z, $nextZ - $z);
        $kind = chunkKind($basePart, $oursPart, $theirsPart);
        $chunks[] = new Chunk($kind, $x, $y, $z, $basePart, $oursPart, $theirsPart);
        [$x, $y, $z] = [$nextX, $nextY, $nextZ];
    }
    return $chunks;
}

function kindCounts(array $chunks): string
{
    $counts = ['a' => 0, 'b' => 0, 'both' => 0, 'conflict' => 0];
    foreach ($chunks as $chunk) {
        if ($chunk->kind !== 'stable') {
            $counts[$chunk->kind]++;
        }
    }
    return vsprintf('a=%d b=%d both=%d conflicts=%d', $counts);
}

function commonPrefixLength(array $first, array $second): int
{
    $length = 0;
    while ($length < count($first) && $length < count($second) && $first[$length] === $second[$length]) {
        $length++;
    }
    return $length;
}

function commonSuffixLength(array $first, array $second, int $limit): int
{
    $length = 0;
    while (
        $length < $limit
        && $first[count($first) - 1 - $length] === $second[count($second) - 1 - $length]
    ) {
        $length++;
    }
    return $length;
}

function conflictLines(
    Chunk $chunk,
    string $mode,
    string $baseName,
    string $oursName,
    string $theirsName,
): array {
    if ($mode === 'OURS') {
        return $chunk->ours;
    }
    if ($mode === 'THEIRS') {
        return $chunk->theirs;
    }
    if ($mode === 'DIFF3') {
        return [
            "<<<<<<< $oursName",
            ...$chunk->ours,
            "||||||| $baseName",
            ...$chunk->base,
            SEPARATOR,
            ...$chunk->theirs,
            ">>>>>>> $theirsName",
        ];
    }
    $ours = $chunk->ours;
    $theirs = $chunk->theirs;
    $head = commonPrefixLength($ours, $theirs);
    $tail = commonSuffixLength($ours, $theirs, min(count($ours), count($theirs)) - $head);
    $oursMiddle = array_slice($ours, $head, count($ours) - $head - $tail);
    $theirsMiddle = array_slice($theirs, $head, count($theirs) - $head - $tail);
    $middle = $mode === 'UNION'
        ? [...$oursMiddle, ...$theirsMiddle]
        : ["<<<<<<< $oursName", ...$oursMiddle, SEPARATOR, ...$theirsMiddle, ">>>>>>> $theirsName"];
    return [...array_slice($ours, 0, $head), ...$middle, ...array_slice($ours, count($ours) - $tail)];
}

function markerKind(string $line): ?string
{
    if ($line === SEPARATOR) {
        return 'separator';
    }
    $kind = MARKER_PREFIXES[substr($line, 0, 7)] ?? null;
    if ($kind !== null && (strlen($line) === 7 || $line[7] === ' ')) {
        return $kind;
    }
    return null;
}

function nextMarker(array $lines, int $index): int
{
    $index++;
    while ($index < count($lines) && markerKind($lines[$index]) === null) {
        $index++;
    }
    return $index;
}

final readonly class ConflictRegion
{
    public function __construct(
        public int $start,
        public int $end,
        public array $ours,
        public ?array $base,
        public array $theirs,
    ) {
    }

    public function part(string $side): array
    {
        return match ($side) {
            'OURS' => $this->ours,
            'THEIRS' => $this->theirs,
            'BASE' => $this->base,
            default => [...$this->ours, ...$this->theirs],
        };
    }
}

function regionAt(array $lines, int $start): ?ConflictRegion
{
    if (markerKind($lines[$start]) !== 'start') {
        return null;
    }
    $middle = nextMarker($lines, $start);
    $baseMarker = null;
    if ($middle < count($lines) && markerKind($lines[$middle]) === 'base') {
        $baseMarker = $middle;
        $middle = nextMarker($lines, $middle);
    }
    if ($middle === count($lines) || markerKind($lines[$middle]) !== 'separator') {
        return null;
    }
    $end = nextMarker($lines, $middle);
    if ($end === count($lines) || markerKind($lines[$end]) !== 'end') {
        return null;
    }
    if ($baseMarker === null) {
        $ours = array_slice($lines, $start + 1, $middle - $start - 1);
        $base = null;
    } else {
        $ours = array_slice($lines, $start + 1, $baseMarker - $start - 1);
        $base = array_slice($lines, $baseMarker + 1, $middle - $baseMarker - 1);
    }
    $theirs = array_slice($lines, $middle + 1, $end - $middle - 1);
    return new ConflictRegion($start + 1, $end + 1, $ours, $base, $theirs);
}

function conflictRegions(array $lines): array
{
    $regions = [];
    $index = 0;
    while ($index < count($lines)) {
        $region = regionAt($lines, $index);
        if ($region === null) {
            $index++;
        } else {
            $regions[] = $region;
            $index = $region->end;
        }
    }
    return $regions;
}

final class Workspace
{
    private array $files = [];
    private array $history = [];

    public function execute(array $words, array $data): void
    {
        $arguments = array_slice($words, 1);
        try {
            match ($words[0]) {
                'FILE' => $this->loadFile($arguments, $data),
                'COPY' => $this->copy($arguments),
                'PRINT' => $this->printFile($arguments),
                'FILES' => $this->listFiles(),
                'DIFF' => $this->diff($arguments),
                'WORDDIFF' => $this->tokenDiff($arguments, true),
                'CHARDIFF' => $this->tokenDiff($arguments, false),
                'STAT' => $this->stat($arguments),
                'PATCH' => $this->patch($arguments, $data),
                'EDIT' => $this->edit($arguments, $data),
                'DIFF3' => $this->diff3($arguments),
                'MERGE' => $this->merge($arguments),
                'CONFLICTS' => $this->conflicts($arguments),
                'RESOLVE' => $this->resolve($arguments),
                'UNDO' => $this->undo($arguments),
            };
        } catch (CommandError $error) {
            $this->emit($error->getMessage());
        }
    }

    private function emit(string ...$lines): void
    {
        foreach ($lines as $line) {
            echo $line, "\n";
        }
    }

    private function requireFiles(string ...$names): void
    {
        foreach ($names as $name) {
            if (!array_key_exists($name, $this->files)) {
                throw new CommandError("ERROR no such file $name");
            }
        }
    }

    private function save(string $name, array $lines): void
    {
        $this->history[$name][] = $this->files[$name] ?? null;
        $this->files[$name] = $lines;
    }

    private function loadFile(array $arguments, array $data): void
    {
        $name = $arguments[0];
        $this->save($name, $data);
        $this->emit("FILE $name lines=" . count($data));
    }

    private function copy(array $arguments): void
    {
        [$source, $target] = $arguments;
        $this->requireFiles($source);
        $lines = $this->files[$source];
        $this->save($target, $lines);
        $this->emit("COPY $source $target lines=" . count($lines));
    }

    private function printFile(array $arguments): void
    {
        $name = $arguments[0];
        $this->requireFiles($name);
        $lines = $this->files[$name];
        $this->emit("PRINT $name lines=" . count($lines));
        foreach ($lines as $index => $line) {
            $this->emit(sprintf('%3d| %s', $index + 1, $line));
        }
    }

    private function listFiles(): void
    {
        $names = array_map(strval(...), array_keys($this->files));
        sort($names, SORT_STRING);
        $this->emit('FILES count=' . count($names));
        foreach ($names as $name) {
            $lineCount = count($this->files[$name]);
            $undoCount = count($this->history[$name]);
            $this->emit("$name lines=$lineCount undo=$undoCount");
        }
    }

    private function undo(array $arguments): void
    {
        $name = $arguments[0];
        if (empty($this->history[$name])) {
            throw new CommandError("ERROR nothing to undo $name");
        }
        $state = array_pop($this->history[$name]);
        if ($state === null) {
            unset($this->files[$name]);
            $this->emit("UNDO $name removed");
        } else {
            $this->files[$name] = $state;
            $this->emit("UNDO $name lines=" . count($state));
        }
    }

    private function diff(array $arguments): void
    {
        [$oldName, $newName, $form] = $arguments;
        $this->requireFiles($oldName, $newName);
        $parameter = null;
        $options = array_slice($arguments, 3);
        if (in_array($form, FORMATS_WITH_ARGUMENT, true)) {
            $parameter = $arguments[3];
            $options = array_slice($arguments, 4);
        }
        $diff = new LineDiff($this->files[$oldName], $this->files[$newName], $options);
        if ($diff->blocks === []) {
            $this->emit("Files $oldName and $newName are identical");
            return;
        }
        $lines = match ($form) {
            'BRIEF' => ["Files $oldName and $newName differ"],
            'NORMAL' => $diff->normal(),
            'ED' => $diff->ed(),
            'RCS' => $diff->rcs(),
            'IFDEF' => $diff->ifdef($parameter),
            'UNIFIED' => $diff->unified((int) $parameter, $oldName, $newName),
            'CONTEXT' => $diff->context((int) $parameter, $oldName, $newName),
            default => $diff->sideBySide((int) $parameter),
        };
        $this->emit(...$lines);
    }

    private function tokenDiff(array $arguments, bool $byWord): void
    {
        [$oldName, $newName] = $arguments;
        $this->requireFiles($oldName, $newName);
        $old = $this->files[$oldName];
        $new = $this->files[$newName];
        $diff = new LineDiff($old, $new);
        if ($diff->blocks === []) {
            $this->emit("Files $oldName and $newName are identical");
            return;
        }
        $separator = $byWord ? ' ' : '';
        $totals = new TokenTotals();
        foreach ($diff->blocks as $block) {
            for ($row = 0; $row < max($block->x, $block->y); $row++) {
                $oldNumber = $block->p + $row + 1;
                $newNumber = $block->q + $row + 1;
                if ($row < $block->x && $row < $block->y) {
                    $oldTokens = splitTokens($old[$oldNumber - 1], $byWord);
                    $newTokens = splitTokens($new[$newNumber - 1], $byWord);
                    $text = compareTokens($oldTokens, $newTokens, $separator, $totals);
                    $this->emit("a$oldNumber b$newNumber: $text");
                } elseif ($row < $block->x) {
                    $oldTokens = splitTokens($old[$oldNumber - 1], $byWord);
                    $totals->deleted += count($oldTokens);
                    $this->emit("a$oldNumber: " . deletion($oldTokens, $separator));
                } else {
                    $newTokens = splitTokens($new[$newNumber - 1], $byWord);
                    $totals->inserted += count($newTokens);
                    $this->emit("b$newNumber: " . insertion($newTokens, $separator));
                }
            }
        }
        $this->emit(sprintf(
            '%s deleted=%d inserted=%d common=%d',
            $byWord ? 'WORDS' : 'CHARS',
            $totals->deleted,
            $totals->inserted,
            $totals->common,
        ));
    }

    private function stat(array $arguments): void
    {
        [$oldName, $newName] = $arguments;
        $this->requireFiles($oldName, $newName);
        $old = $this->files[$oldName];
        $new = $this->files[$newName];
        $diff = new LineDiff($old, $new, array_slice($arguments, 2));
        $deleted = array_sum(array_column($diff->blocks, 'x'));
        $inserted = array_sum(array_column($diff->blocks, 'y'));
        $total = $deleted + $inserted;
        $unchanged = count($old) - $deleted;
        $summary = "$oldName -> $newName | $total";
        if ($total > 0) {
            $summary .= ' ' . statGraph($inserted, $deleted);
        }
        $this->emit($summary);
        $lineTotal = count($old) + count($new);
        $similarity = $lineTotal > 0 ? intdiv(200 * $unchanged, $lineTotal) : 100;
        $this->emit(sprintf(
            'changes=%d insertions=%d deletions=%d unchanged=%d similarity=%d%%',
            count($diff->blocks),
            $inserted,
            $deleted,
            $unchanged,
            $similarity,
        ));
    }

    private function patch(array $arguments, array $data): void
    {
        $name = $arguments[0];
        $this->requireFiles($name);
        $options = array_slice($arguments, 2);
        $reverse = in_array('REVERSE', $options, true);
        $dryRun = in_array('DRYRUN', $options, true);
        $fuzzIndex = array_search('FUZZ', $options, true);
        $maxFuzz = $fuzzIndex === false ? 0 : (int) $options[$fuzzIndex + 1];
        $hunks = parsePatch($data);
        $this->emit(($dryRun ? 'checking file ' : 'patching file ') . $name);
        $lines = $this->files[$name];
        $first = $hunks[0];
        if (
            searchHunk($first, $lines, 0, $reverse, $maxFuzz) === null
            && searchHunk($first, $lines, 0, !$reverse, $maxFuzz) !== null
        ) {
            $this->emit('Reversed (or previously applied) patch detected! Skipping patch.');
            $this->emit('RESULT applied=0 failed=0 ignored=' . count($hunks) . ' lines=' . count($lines));
            return;
        }
        $adjustment = 0;
        $applied = 0;
        $failed = 0;
        foreach ($hunks as $index => $hunk) {
            $number = $index + 1;
            $match = searchHunk($hunk, $lines, $adjustment, $reverse, $maxFuzz);
            if ($match === null) {
                $failed++;
                $this->emit("Hunk #$number FAILED at " . $hunk->start($reverse));
                continue;
            }
            [$old, $new] = $hunk->sequences($reverse);
            $lines = $match->lines;
            $adjustment += $match->delta + count($new) - count($old);
            $applied++;
            $this->emit($match->report($number));
        }
        $this->emit("RESULT applied=$applied failed=$failed ignored=0 lines=" . count($lines));
        if (!$dryRun && $applied >= 1) {
            $this->save($name, $lines);
        }
    }

    private function edit(array $arguments, array $data): void
    {
        $name = $arguments[0];
        $this->requireFiles($name);
        [$lines, $executed] = runEditScript($this->files[$name], $data);
        $this->emit("EDIT $name commands=$executed lines=" . count($lines));
        $this->save($name, $lines);
    }

    private function threeWay(string $baseName, string $oursName, string $theirsName): array
    {
        $this->requireFiles($baseName, $oursName, $theirsName);
        return threeWayChunks(
            $this->files[$baseName],
            $this->files[$oursName],
            $this->files[$theirsName],
        );
    }

    private function diff3(array $arguments): void
    {
        [$baseName, $oursName, $theirsName] = $arguments;
        $chunks = $this->threeWay($baseName, $oursName, $theirsName);
        $changes = array_filter($chunks, fn (Chunk $chunk): bool => $chunk->kind !== 'stable');
        foreach ($changes as $chunk) {
            $this->emit("==== {$chunk->kind} " . $chunk->location());
            $this->emit(...prefixed('O ', $chunk->base));
            if ($chunk->kind !== 'b') {
                $this->emit(...prefixed('A ', $chunk->ours));
            }
            if ($chunk->kind === 'b' || $chunk->kind === 'conflict') {
                $this->emit(...prefixed('B ', $chunk->theirs));
            }
        }
        $this->emit('DIFF3 chunks=' . count($changes) . ' ' . kindCounts($chunks));
    }

    private function merge(array $arguments): void
    {
        [$baseName, $oursName, $theirsName, $target] = $arguments;
        $mode = $arguments[4] ?? 'MARKERS';
        $chunks = $this->threeWay($baseName, $oursName, $theirsName);
        $result = [];
        $conflicts = [];
        foreach ($chunks as $chunk) {
            if ($chunk->kind === 'b') {
                array_push($result, ...$chunk->theirs);
            } elseif ($chunk->kind === 'conflict') {
                $lines = conflictLines($chunk, $mode, $baseName, $oursName, $theirsName);
                array_push($result, ...$lines);
                $conflicts[] = $chunk;
            } else {
                array_push($result, ...$chunk->ours);
            }
        }
        $this->emit("MERGE $target lines=" . count($result) . ' ' . kindCounts($chunks));
        foreach ($conflicts as $index => $chunk) {
            $this->emit('CONFLICT ' . ($index + 1) . ' ' . $chunk->location());
        }
        $this->save($target, $result);
    }

    private function conflicts(array $arguments): void
    {
        $name = $arguments[0];
        $this->requireFiles($name);
        $regions = conflictRegions($this->files[$name]);
        $this->emit("CONFLICTS $name count=" . count($regions));
        foreach ($regions as $index => $region) {
            $base = $region->base === null ? 'none' : count($region->base);
            $this->emit(sprintf(
                '%d: lines %d-%d ours=%d base=%s theirs=%d',
                $index + 1,
                $region->start,
                $region->end,
                count($region->ours),
                $base,
                count($region->theirs),
            ));
        }
    }

    private function resolve(array $arguments): void
    {
        [$name, $numberText, $side] = $arguments;
        $this->requireFiles($name);
        $number = (int) $numberText;
        $lines = $this->files[$name];
        $regions = conflictRegions($lines);
        if (count($regions) < $number) {
            throw new CommandError("ERROR no conflict $number in $name");
        }
        $region = $regions[$number - 1];
        if ($side === 'BASE' && $region->base === null) {
            throw new CommandError("ERROR no base section in conflict $number");
        }
        $content = [
            ...array_slice($lines, 0, $region->start - 1),
            ...$region->part($side),
            ...array_slice($lines, $region->end),
        ];
        $remaining = count(conflictRegions($content));
        $this->emit("RESOLVE $name $number $side lines=" . count($content) . " remaining=$remaining");
        $this->save($name, $content);
    }
}

function main(): void
{
    $lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
    $workspace = new Workspace();
    $position = 1;
    $commandCount = (int) $lines[0];
    for ($command = 0; $command < $commandCount; $command++) {
        $words = explode(' ', $lines[$position]);
        $position++;
        $data = [];
        if (in_array($words[0], DATA_COMMANDS, true)) {
            $count = (int) $words[2];
            $data = array_slice($lines, $position, $count);
            $position += $count;
        }
        $workspace->execute($words, $data);
    }
}

main();
