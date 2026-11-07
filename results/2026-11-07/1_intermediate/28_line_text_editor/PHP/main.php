<?php
declare(strict_types=1);

final class CommandError extends RuntimeException {}
enum ElementKind { case Number; case Offset; case Current; case Last; case Mark; case Forward; case Backward; case Separator; case All; }
enum Kind
{
    case Blank; case Append; case Insert; case Change; case PrintLines; case Numbered; case Listed;
    case Number; case Count; case Yank; case Marks; case History; case Files; case Delete; case Put;
    case Join; case JoinSpaced; case Window; case Indent; case Unindent; case Undo; case Redo;
    case ChangeCase; case Read; case Write; case WriteAppend; case Edit; case WritePrint; case Mark;
    case Move; case Copy; case Sort; case Substitute; case GlobalLines; case InverseGlobal;
}

final readonly class Element
{
    public function __construct(
        public ElementKind $kind, public int $value = 0, public string $symbol = '', public string $text = '',
    ) {}
}

final readonly class Address
{
    public function __construct(public array $left, public ?array $right = null, public string $separator = '') {}
    public function count(): int { return $this->right !== null ? 2 : ($this->left === [] ? 0 : 1); }
}

final readonly class Delimited
{
    public function __construct(public string $text, public array $replacement, public string $raw) {}
}

final class Cursor
{
    public function __construct(public readonly string $text, public int $position = 0) {}
    public function ended(): bool { return $this->position === strlen($this->text); }
    public function rest(): string { return substr($this->text, $this->position); }
}

final class Command
{
    public int $count = 0;
    public string $suffix = '', $caseMode = '', $name = '', $pattern = '', $options = '';
    public ?array $replacement = null;
    public bool $all = false;
    public array $destination = [];
    public ?Command $subcommand = null;
    public function __construct(public readonly Kind $kind) {}
}

function digit(string $c): bool { return $c !== '' && ord($c) >= 48 && ord($c) <= 57; }
function digits(string $text): bool { return $text !== '' && strspn($text, '0123456789') === strlen($text); }
function printSuffix(string $c): bool { return $c === 'p' || $c === 'n' || $c === 'l'; }
function sortForm(string $text): bool { return $text === 'sort' || str_starts_with($text, 'sort '); }

function delimited(Cursor $cursor, string $delimiter): Delimited
{
    $start = $cursor->position;
    $text = '';
    $replacement = [];
    while (!$cursor->ended()) {
        $c = $cursor->text[$cursor->position++];
        if ($c === $delimiter) {
            return new Delimited($text, $replacement, substr($cursor->text, $start, $cursor->position - $start - 1));
        }
        $escaped = $c === '\\';
        if ($escaped) {
            if ($cursor->ended()) break;
            $c = $cursor->text[$cursor->position++];
        }
        $text .= $c;
        $replacement[] = $c === '&' && !$escaped ? null : $c;
    }
    throw new CommandError('missing delimiter');
}

function scanAddress(Cursor $cursor): array
{
    $elements = [];
    while (!$cursor->ended()) {
        $c = $cursor->text[$cursor->position];
        if (digit($c)) {
            $start = $cursor->position++;
            while (!$cursor->ended() && digit($cursor->text[$cursor->position])) $cursor->position++;
            $elements[] = new Element(ElementKind::Number, (int)substr($cursor->text, $start, $cursor->position - $start));
        } elseif ($c === '+' || $c === '-') {
            $start = ++$cursor->position;
            while (!$cursor->ended() && digit($cursor->text[$cursor->position])) $cursor->position++;
            $value = $cursor->position === $start ? 1 : (int)substr($cursor->text, $start, $cursor->position - $start);
            $elements[] = new Element(ElementKind::Offset, $c === '+' ? $value : -$value);
        } elseif ($c === "'") {
            $cursor->position++;
            $elements[] = new Element(ElementKind::Mark, symbol: $cursor->ended() ? '' : $cursor->text[$cursor->position++]);
        } elseif ($c === '/' || $c === '?') {
            $cursor->position++;
            $elements[] = new Element($c === '/' ? ElementKind::Forward : ElementKind::Backward, text: delimited($cursor, $c)->text);
        } else {
            $kind = match ($c) {
                '.' => ElementKind::Current, '$' => ElementKind::Last,
                ',', ';' => ElementKind::Separator, '%' => ElementKind::All, default => null,
            };
            if ($kind === null) break;
            $elements[] = new Element($kind, symbol: $c);
            $cursor->position++;
        }
    }
    return $elements;
}

function expression(array $elements): bool
{
    foreach ($elements as $i => $element) {
        if ($element->kind === ElementKind::Offset) continue;
        if ($i !== 0 || $element->kind === ElementKind::Separator || $element->kind === ElementKind::All) return false;
    }
    return true;
}

function addressForm(array $elements): Address
{
    if (count($elements) === 1 && $elements[0]->kind === ElementKind::All) {
        return new Address([new Element(ElementKind::Number, 1)], [new Element(ElementKind::Last)], ',');
    }
    $separator = null;
    foreach ($elements as $i => $element) {
        if ($element->kind !== ElementKind::Separator) continue;
        if ($separator !== null) throw new CommandError('bad address');
        $separator = $i;
    }
    if ($separator === null) {
        if (!expression($elements)) throw new CommandError('bad address');
        return new Address($elements);
    }
    $left = array_slice($elements, 0, $separator);
    $right = array_slice($elements, $separator + 1);
    if (!expression($left) || !expression($right)) throw new CommandError('bad address');
    return new Address($left, $right, $elements[$separator]->symbol);
}

function optionalCount(string $argument): int
{
    if ($argument === '') return 0;
    if (!digits($argument) || (int)$argument === 0) throw new CommandError('invalid suffix');
    return (int)$argument;
}

function suffix(string $argument): string
{
    if ($argument !== '' && !printSuffix($argument)) throw new CommandError('invalid suffix');
    return $argument;
}

function fileName(string $argument): string
{
    if (preg_match('/\A [a-z0-9]{1,8}\z/', $argument) !== 1) throw new CommandError('invalid file name');
    return substr($argument, 1);
}

function substitution(string $argument): Command
{
    $command = new Command(Kind::Substitute);
    $command->count = 1;
    $flags = $argument;
    if (strspn($argument, 'gpnl0123456789') !== strlen($argument)) {
        $delimiter = $argument[0];
        if ($delimiter === ' ' || $delimiter === '\\') throw new CommandError('missing delimiter');
        $cursor = new Cursor($argument, 1);
        $command->pattern = delimited($cursor, $delimiter)->text;
        $replacement = delimited($cursor, $delimiter);
        if ($replacement->raw !== '%') $command->replacement = $replacement->replacement;
        $flags = $cursor->rest();
    }
    $hasCount = false;
    $position = 0;
    while ($position < strlen($flags)) {
        $c = $flags[$position++];
        if ($c === 'g' && !$command->all) {
            $command->all = true;
        } elseif (printSuffix($c) && $command->suffix === '') {
            $command->suffix = $c;
        } elseif (digit($c) && !$hasCount) {
            $start = $position - 1;
            while ($position < strlen($flags) && digit($flags[$position])) $position++;
            $command->count = (int)substr($flags, $start, $position - $start);
            if ($command->count === 0) throw new CommandError('invalid suffix');
            $hasCount = true;
        } else {
            throw new CommandError('invalid suffix');
        }
    }
    return $command;
}

function parseCommand(string $text): Command
{
    if (sortForm($text)) {
        $options = $text === 'sort' ? '' : substr($text, 5);
        if (($text !== 'sort' && $options === '') || strspn($options, 'ruin') !== strlen($options) ||
            count(array_unique(str_split($options))) !== strlen($options) ||
            (str_contains($options, 'i') && str_contains($options, 'n'))) {
            throw new CommandError('invalid suffix');
        }
        $command = new Command(Kind::Sort);
        $command->options = $options;
        return $command;
    }
    $first = $text === '' ? '' : $text[0];
    $argument = substr($text, 1);
    $plain = [
        '' => Kind::Blank, 'a' => Kind::Append, 'i' => Kind::Insert, 'c' => Kind::Change,
        'p' => Kind::PrintLines, 'n' => Kind::Numbered, 'l' => Kind::Listed, '=' => Kind::Number,
        '#' => Kind::Count, 'y' => Kind::Yank, 'K' => Kind::Marks, 'h' => Kind::History, 'f' => Kind::Files,
    ];
    if (isset($plain[$first])) {
        if ($argument !== '') throw new CommandError('invalid suffix');
        return new Command($plain[$first]);
    }
    switch ($first) {
        case 'd': case 'x': case 'j': case 'J':
            $command = new Command(match ($first) { 'd' => Kind::Delete, 'x' => Kind::Put, 'j' => Kind::Join, default => Kind::JoinSpaced });
            $command->suffix = suffix($argument);
            return $command;
        case 'z': case '>': case '<': case 'u':
            $command = new Command(match ($first) { 'z' => Kind::Window, '>' => Kind::Indent, '<' => Kind::Unindent, default => Kind::Undo });
            $command->count = optionalCount($argument);
            return $command;
        case '~':
            if ($argument !== '' && $argument !== 'u' && $argument !== 'l') throw new CommandError('invalid suffix');
            $command = new Command(Kind::ChangeCase);
            $command->caseMode = $argument;
            return $command;
        case 'r':
            if ($argument === '' || digits($argument)) {
                $command = new Command(Kind::Redo);
                $command->count = optionalCount($argument);
            } else {
                $command = new Command(Kind::Read);
                $command->name = fileName($argument);
            }
            return $command;
        case 'w':
            if ($argument === '') return new Command(Kind::WritePrint);
            $command = new Command(Kind::Write);
            $command->name = fileName($argument);
            return $command;
        case 'W': case 'e':
            $command = new Command($first === 'W' ? Kind::WriteAppend : Kind::Edit);
            $command->name = fileName($argument);
            return $command;
        case 'k':
            if (preg_match('/\A[a-z]\z/', $argument) !== 1) throw new CommandError('invalid mark');
            $command = new Command(Kind::Mark);
            $command->name = $argument;
            return $command;
        case 'm': case 't':
            $cursor = new Cursor($argument);
            $destination = scanAddress($cursor);
            if ($destination === [] || !expression($destination)) throw new CommandError('invalid destination');
            $command = new Command($first === 'm' ? Kind::Move : Kind::Copy);
            $command->destination = $destination;
            $command->suffix = suffix($cursor->rest());
            return $command;
        case 's': return substitution($argument);
        case 'g': case 'v':
            if ($argument === '' || $argument[0] === ' ' || $argument[0] === '\\') throw new CommandError('missing delimiter');
            $cursor = new Cursor($argument, 1);
            $pattern = delimited($cursor, $argument[0])->text;
            $subcommand = $cursor->ended() ? 'p' : $cursor->rest();
            if (!str_contains('pnldmtjJs><~aicx', $subcommand[0]) || sortForm($subcommand)) throw new CommandError('invalid global command');
            $command = new Command($first === 'g' ? Kind::GlobalLines : Kind::InverseGlobal);
            $command->pattern = $pattern;
            $command->subcommand = parseCommand($subcommand);
            return $command;
        default: throw new CommandError('unknown command');
    }
}

function hasText(string $line): bool
{
    try {
        $cursor = new Cursor($line);
        scanAddress($cursor);
        $command = $cursor->rest();
        if (in_array($command, ['a', 'i', 'c'], true)) return true;
        if (strlen($command) < 2 || ($command[0] !== 'g' && $command[0] !== 'v') ||
            $command[1] === ' ' || $command[1] === '\\') return false;
        $global = new Cursor($command, 2);
        delimited($global, $command[1]);
        return in_array($global->rest(), ['a', 'i', 'c'], true);
    } catch (CommandError) {
        return false;
    }
}

final readonly class Line
{
    public function __construct(public int $id, public string $text) {}
}

final readonly class HistoryRecord
{
    public function __construct(public string $command, public array $lines, public int $current) {}
}

final class EditorState
{
    public array $lines = [], $cut = [], $undo = [], $redo = [], $files = [];
    public int $current = 0, $displayCount = 5, $nextId = 1;
    public array $marks;
    public ?string $pattern = null;
    public ?array $replacement = null;
    public function __construct() { $this->marks = array_fill(0, 26, null); }
}

function noAddress(Kind $kind): bool
{
    return in_array($kind, [Kind::Undo, Kind::Redo, Kind::History, Kind::Marks, Kind::Files, Kind::Edit], true);
}
function oneAddress(Kind $kind): bool
{
    return in_array($kind, [Kind::Append, Kind::Insert, Kind::Put, Kind::Number, Kind::Read, Kind::Mark, Kind::Window], true);
}
function modifies(Command $command): bool
{
    return match ($command->kind) {
        Kind::Append, Kind::Insert, Kind::Change, Kind::Delete, Kind::Put, Kind::Join, Kind::JoinSpaced,
        Kind::Move, Kind::Copy, Kind::Substitute, Kind::Indent, Kind::Unindent, Kind::ChangeCase,
        Kind::Sort, Kind::Read, Kind::Edit => true,
        Kind::GlobalLines, Kind::InverseGlobal => modifies($command->subcommand),
        default => false,
    };
}

final class Editor
{
    public array $output = [];
    public function __construct(private readonly EditorState $state) {}

    private function pattern(string $search): string
    {
        if ($search !== '') $this->state->pattern = $search;
        return $this->state->pattern ?? throw new CommandError('no previous pattern');
    }

    private function locate(int $id): ?int
    {
        foreach ($this->state->lines as $index => $line) if ($line->id === $id) return $index;
        return null;
    }

    private function evaluate(array $elements): int
    {
        $state = $this->state;
        $value = $state->current;
        foreach ($elements as $element) {
            switch ($element->kind) {
                case ElementKind::Offset: $value += $element->value; break;
                case ElementKind::Number: $value = $element->value; break;
                case ElementKind::Current: $value = $state->current; break;
                case ElementKind::Last: $value = count($state->lines); break;
                case ElementKind::Mark:
                    if (preg_match('/\A[a-z]\z/', $element->symbol) !== 1) throw new CommandError('invalid mark');
                    $id = $state->marks[ord($element->symbol) - 97];
                    $index = $id === null ? null : $this->locate($id);
                    if ($index === null) throw new CommandError('mark not set');
                    $value = $index + 1;
                    break;
                case ElementKind::Forward: case ElementKind::Backward:
                    $pattern = $this->pattern($element->text);
                    $size = count($state->lines);
                    $forward = $element->kind === ElementKind::Forward;
                    $index = $forward ? $state->current : $state->current - 2;
                    $value = 0;
                    for ($checked = 0; $checked < $size; $checked++) {
                        if ($index >= $size) $index = 0;
                        if ($index < 0) $index = $size - 1;
                        if (str_contains($state->lines[$index]->text, $pattern)) {
                            $value = $index + 1;
                            break;
                        }
                        $index += $forward ? 1 : -1;
                    }
                    if ($value === 0) throw new CommandError('no match');
                    break;
                default: throw new LogicException('invalid address form');
            }
        }
        return $value;
    }

    private function addresses(Address $address): array
    {
        if ($address->count() === 0) return [];
        if ($address->count() === 1) return [$this->evaluate($address->left)];
        $left = $address->left === [] ? ($address->separator === ',' ? 1 : $this->state->current) : $this->evaluate($address->left);
        if ($address->separator === ';') {
            if ($left < 0 || $left > count($this->state->lines)) throw new CommandError('address out of range');
            $this->state->current = $left;
        }
        $right = $address->right === [] ? count($this->state->lines) : $this->evaluate($address->right);
        return [$left, $right];
    }

    private function range(Command $command, array $addresses): array
    {
        $kind = $command->kind;
        $size = count($this->state->lines);
        if (noAddress($kind)) return [0, 0];
        if (oneAddress($kind)) {
            $a = $addresses !== [] ? $addresses[0] : match ($kind) {
                Kind::Number, Kind::Read => $size, Kind::Window => $this->state->current + 1,
                default => $this->state->current,
            };
            $minimum = $kind === Kind::Mark || $kind === Kind::Window ? 1 : 0;
            if ($a < $minimum || $a > $size) throw new CommandError('address out of range');
            return [$a, $a];
        }
        if ($addresses !== []) {
            $a = $addresses[0];
            $b = $addresses[count($addresses) - 1];
        } elseif (in_array($kind, [Kind::WritePrint, Kind::Write, Kind::WriteAppend, Kind::Count], true)) {
            return [1, $size];
        } elseif (in_array($kind, [Kind::GlobalLines, Kind::InverseGlobal, Kind::Sort], true)) {
            $a = 1;
            $b = $size;
        } else {
            $a = $this->state->current;
            $b = $a + ($kind === Kind::Join || $kind === Kind::JoinSpaced ? 1 : 0);
        }
        if ($a < 1 || $b < 1 || $a > $size || $b > $size) throw new CommandError('address out of range');
        if ($a > $b || $a === $b && ($kind === Kind::Join || $kind === Kind::JoinSpaced)) throw new CommandError('invalid range');
        return [$a, $b];
    }

    public function process(string $line, array $text, EditorState $before): void
    {
        $cursor = new Cursor($line);
        $address = addressForm(scanAddress($cursor));
        $command = parseCommand($cursor->rest());
        if (noAddress($command->kind) && $address->count() !== 0) throw new CommandError('unexpected address');
        if (oneAddress($command->kind) && $address->count() === 2) throw new CommandError('too many addresses');
        [$a, $b] = $this->range($command, $this->addresses($address));
        $this->execute($command, $a, $b, $text);
        if (count($this->state->lines) > 200) throw new CommandError('buffer full');
        if (modifies($command)) {
            $this->state->undo[] = new HistoryRecord($line, $before->lines, $before->current);
            $this->state->redo = [];
        }
    }

    private function printLine(int $number, string $form = 'p'): void
    {
        $text = $this->state->lines[$number - 1]->text;
        if ($form === 'n') {
            $this->output[] = str_pad((string)$number, 3, ' ', STR_PAD_LEFT) . ' ' . $text;
        } elseif ($form === 'l') {
            $text = str_replace('\\', '\\\\', $text) . '$';
            while (strlen($text) > 40) {
                $this->output[] = substr($text, 0, 39) . '\\';
                $text = substr($text, 39);
            }
            $this->output[] = $text;
        } else {
            $this->output[] = $text;
        }
    }

    private function contents(int $a, int $b): array
    {
        return array_map(static fn(Line $line): string => $line->text, array_slice($this->state->lines, $a - 1, $b - $a + 1));
    }
    private function bytes(array $lines): int { return count($lines) + array_sum(array_map('strlen', $lines)); }

    private function insert(int $position, array $text): void
    {
        $lines = [];
        foreach ($text as $value) $lines[] = new Line($this->state->nextId++, $value);
        array_splice($this->state->lines, $position, 0, $lines);
        $this->state->current = $position + count($lines);
    }

    private function history(bool $undo, int $count): void
    {
        $source = $undo ? $this->state->undo : $this->state->redo;
        $target = $undo ? $this->state->redo : $this->state->undo;
        if (count($source) < $count) throw new CommandError($undo ? 'nothing to undo' : 'nothing to redo');
        for ($i = 0; $i < $count; $i++) {
            $record = array_pop($source);
            $target[] = new HistoryRecord($record->command, $this->state->lines, $this->state->current);
            $this->state->lines = $record->lines;
            $this->state->current = $record->current;
        }
        if ($undo) {
            $this->state->undo = $source;
            $this->state->redo = $target;
        } else {
            $this->state->redo = $source;
            $this->state->undo = $target;
        }
    }

    private function sort(Command $command, int $a, int $b): void
    {
        $numeric = str_contains($command->options, 'n');
        $insensitive = str_contains($command->options, 'i');
        $reverse = str_contains($command->options, 'r');
        $key = static function (Line $line) use ($numeric, $insensitive): int|string {
            if ($numeric) return preg_match('/\A-?[0-9]+/', $line->text, $match) === 1 ? (int)$match[0] : 0;
            return $insensitive ? strtolower($line->text) : $line->text;
        };
        $compare = static fn(Line $left, Line $right): int => $numeric ? $key($left) <=> $key($right) : strcmp($key($left), $key($right));
        $ordered = array_slice($this->state->lines, $a - 1, $b - $a + 1);
        usort($ordered, static fn(Line $left, Line $right): int => ($reverse ? -1 : 1) * $compare($left, $right));
        $result = [];
        foreach ($ordered as $line) {
            if (str_contains($command->options, 'u') && $result !== [] && $compare($result[count($result) - 1], $line) === 0) continue;
            $result[] = $line;
        }
        array_splice($this->state->lines, $a - 1, $b - $a + 1, $result);
        $this->state->current = $a + count($result) - 1;
    }

    private function substitute(Command $command, int $a, int $b, bool $global): int
    {
        $pattern = $this->pattern($command->pattern);
        $replacement = $command->replacement ?? $this->state->replacement ?? throw new CommandError('no previous substitution');
        $this->state->replacement = $replacement;
        $expanded = '';
        foreach ($replacement as $part) $expanded .= $part ?? $pattern;
        $substituted = 0;
        for ($number = $a; $number <= $b; $number++) {
            $line = $this->state->lines[$number - 1];
            $result = '';
            $position = $occurrences = 0;
            while (($match = strpos($line->text, $pattern, $position)) !== false) {
                $result .= substr($line->text, $position, $match - $position);
                $occurrences++;
                $result .= $occurrences === $command->count || $command->all && $occurrences >= $command->count ? $expanded : $pattern;
                $position = $match + strlen($pattern);
            }
            if ($occurrences < $command->count) continue;
            $result .= substr($line->text, $position);
            if (strlen($result) > 80) throw new CommandError('line too long');
            if ($result === '' || str_ends_with($result, ' ')) throw new CommandError('bad line');
            $this->state->lines[$number - 1] = new Line($line->id, $result);
            $this->state->current = $number;
            $substituted++;
        }
        if ($substituted === 0 && !$global) throw new CommandError('no match');
        if ($substituted !== 0 && $command->suffix !== '') $this->printLine($this->state->current, $command->suffix);
        return $substituted;
    }

    private function execute(Command $command, int $a, int $b, array $text, bool $global = false): int
    {
        $state = $this->state;
        $kind = $command->kind;
        switch ($kind) {
            case Kind::Blank: $this->printLine($b); $state->current = $b; break;
            case Kind::PrintLines: case Kind::Numbered: case Kind::Listed:
                $form = $kind === Kind::PrintLines ? 'p' : ($kind === Kind::Numbered ? 'n' : 'l');
                for ($i = $a; $i <= $b; $i++) $this->printLine($i, $form);
                $state->current = $b;
                break;
            case Kind::Window:
                if ($command->count !== 0) $state->displayCount = $command->count;
                $end = min(count($state->lines), $a + $state->displayCount - 1);
                for ($i = $a; $i <= $end; $i++) $this->printLine($i);
                $state->current = $end;
                break;
            case Kind::Number: $this->output[] = (string)$a; break;
            case Kind::Count:
                $counted = $this->contents($a, $b);
                $words = $chars = 0;
                foreach ($counted as $value) {
                    $words += count(preg_split('/ +/', $value, -1, PREG_SPLIT_NO_EMPTY));
                    $chars += strlen($value);
                }
                $this->output[] = 'count lines=' . count($counted) . " words=$words chars=$chars";
                break;
            case Kind::WritePrint:
                for ($i = $a; $i <= $b; $i++) $this->printLine($i);
                $this->output[] = 'lines=' . ($b - $a + 1) . ' bytes=' . $this->bytes($this->contents($a, $b));
                break;
            case Kind::Append: $this->insert($a, $text); break;
            case Kind::Insert: $this->insert(max($a, 1) - 1, $text); break;
            case Kind::Change: case Kind::Delete:
                $state->cut = $this->contents($a, $b);
                array_splice($state->lines, $a - 1, $b - $a + 1);
                if ($kind === Kind::Change && $text !== []) $this->insert($a - 1, $text);
                else $state->current = min($a, count($state->lines));
                break;
            case Kind::Yank: $state->cut = $this->contents($a, $b); break;
            case Kind::Put:
                if ($state->cut === []) throw new CommandError('nothing to put');
                $this->insert($a, $state->cut);
                break;
            case Kind::Move: case Kind::Copy:
                $destination = $this->evaluate($command->destination);
                if ($destination < 0 || $destination > count($state->lines)) throw new CommandError('address out of range');
                if ($kind === Kind::Copy) {
                    $this->insert($destination, $this->contents($a, $b));
                } else {
                    if ($a <= $destination && $destination < $b) throw new CommandError('invalid destination');
                    $moved = array_splice($state->lines, $a - 1, $b - $a + 1);
                    $position = $destination < $a ? $destination : $destination - count($moved);
                    array_splice($state->lines, $position, 0, $moved);
                    $state->current = $position + count($moved);
                }
                break;
            case Kind::Join: case Kind::JoinSpaced:
                $pieces = $this->contents($a, $b);
                if ($kind === Kind::JoinSpaced) {
                    for ($i = 1; $i < count($pieces); $i++) $pieces[$i] = ltrim($pieces[$i], ' ');
                }
                $joined = implode($kind === Kind::Join ? '' : ' ', $pieces);
                if (strlen($joined) > 80) throw new CommandError('line too long');
                $state->lines[$a - 1] = new Line($state->lines[$a - 1]->id, $joined);
                array_splice($state->lines, $a, $b - $a);
                $state->current = $a;
                break;
            case Kind::Indent: case Kind::Unindent: case Kind::ChangeCase:
                $width = $command->count === 0 ? 4 : $command->count;
                for ($i = $a - 1; $i < $b; $i++) {
                    $line = $state->lines[$i];
                    $changed = $line->text;
                    if ($kind === Kind::Indent) {
                        if (strlen($changed) + $width > 80) throw new CommandError('line too long');
                        $changed = str_repeat(' ', $width) . $changed;
                    } elseif ($kind === Kind::Unindent) {
                        $changed = substr($changed, min($width, strspn($changed, ' ')));
                    } elseif ($command->caseMode === 'u') {
                        $changed = strtoupper($changed);
                    } elseif ($command->caseMode === 'l') {
                        $changed = strtolower($changed);
                    } else {
                        $changed = strtr($changed, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ');
                    }
                    $state->lines[$i] = new Line($line->id, $changed);
                }
                $state->current = $b;
                break;
            case Kind::Sort: $this->sort($command, $a, $b); break;
            case Kind::Substitute: return $this->substitute($command, $a, $b, $global);
            case Kind::Mark: $state->marks[ord($command->name) - 97] = $state->lines[$a - 1]->id; break;
            case Kind::Marks:
                $marks = [];
                foreach ($state->marks as $i => $id) {
                    $index = $id === null ? null : $this->locate($id);
                    if ($index !== null) $marks[] = chr(97 + $i) . '=' . ($index + 1);
                }
                $this->output[] = 'marks ' . ($marks === [] ? 'none' : implode(' ', $marks));
                break;
            case Kind::Undo: case Kind::Redo: $this->history($kind === Kind::Undo, $command->count === 0 ? 1 : $command->count); break;
            case Kind::History:
                $this->output[] = 'history undo=' . count($state->undo) . ' redo=' . count($state->redo);
                foreach (array_reverse($state->undo) as $i => $record) $this->output[] = 'undo ' . ($i + 1) . ': ' . $record->command;
                foreach (array_reverse($state->redo) as $i => $record) $this->output[] = 'redo ' . ($i + 1) . ': ' . $record->command;
                break;
            case Kind::GlobalLines: case Kind::InverseGlobal:
                $pattern = $this->pattern($command->pattern);
                $selected = [];
                foreach (array_slice($state->lines, $a - 1, $b - $a + 1) as $line) {
                    if (str_contains($line->text, $pattern) === ($kind === Kind::GlobalLines)) $selected[] = $line->id;
                }
                if ($selected === []) throw new CommandError('no match');
                $subcommand = $command->subcommand;
                $substituted = 0;
                foreach ($selected as $id) {
                    $index = $this->locate($id);
                    if ($index === null) continue;
                    $state->current = $index + 1;
                    [$first, $last] = $this->range($subcommand, []);
                    $substituted += $this->execute($subcommand, $first, $last, $text, true);
                }
                if ($subcommand->kind === Kind::Substitute && $substituted === 0) throw new CommandError('no match');
                break;
            case Kind::Write: case Kind::WriteAppend: case Kind::Read: case Kind::Edit:
                if ($kind === Kind::Write || $kind === Kind::WriteAppend) {
                    $written = $this->contents($a, $b);
                    $state->files[$command->name] = $kind === Kind::WriteAppend
                        ? array_merge($state->files[$command->name] ?? [], $written) : $written;
                } else {
                    if (!isset($state->files[$command->name])) throw new CommandError('no such file');
                    if ($kind === Kind::Edit) $state->lines = [];
                    $this->insert($kind === Kind::Edit ? 0 : $a, $state->files[$command->name]);
                }
                $file = $state->files[$command->name];
                $this->output[] = "file {$command->name} lines=" . count($file) . ' bytes=' . $this->bytes($file);
                break;
            case Kind::Files:
                $names = array_map('strval', array_keys($state->files));
                sort($names, SORT_STRING);
                $parts = [];
                foreach ($names as $name) $parts[] = $name . '=' . count($state->files[$name]);
                $this->output[] = 'files ' . ($parts === [] ? 'none' : implode(' ', $parts));
                break;
        }
        if ($command->suffix !== '' && $state->current >= 1) $this->printLine($state->current, $command->suffix);
        return 0;
    }
}

$state = new EditorState();
while (($input = fgets(STDIN)) !== false) {
    $line = rtrim($input, "\r\n");
    if ($line === 'Q') break;
    $text = [];
    if (hasText($line)) {
        while (($input = fgets(STDIN)) !== false) {
            $value = rtrim($input, "\r\n");
            if ($value === '.') break;
            $text[] = $value;
        }
    }
    try {
        $next = clone $state;
        $editor = new Editor($next);
        $editor->process($line, $text, $state);
        $state = $next;
        if ($editor->output !== []) echo implode("\n", $editor->output), "\n";
    } catch (CommandError $error) {
        echo '? ', $error->getMessage(), "\n";
    }
}
