<?php
declare(strict_types=1);

enum Style: string { case APA = 'APA'; case IEEE = 'IEEE'; case CHICAGO = 'CHICAGO'; case MLA = 'MLA'; }
final class CommandError extends RuntimeException {}
final class LoadError extends RuntimeException {
    public function __construct(public readonly int $sourceLine, string $message) { parent::__construct($message); }
}

const KNOWN_FIELDS = ['author', 'editor', 'title', 'journal', 'booktitle', 'edition', 'volume', 'number', 'pages',
    'publisher', 'institution', 'school', 'address', 'howpublished', 'month', 'year', 'doi', 'note'];
const SMALL_WORDS = ['a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'from', 'in', 'into', 'nor', 'of', 'on',
    'or', 'over', 'per', 'so', 'the', 'to', 'up', 'via', 'with', 'yet'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const MONTH_SHORT = ['Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'June', 'July', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.'];

function isLetter(string $c): bool { return isLower($c) || isUpper($c); }
function isLower(string $c): bool { return ord($c) >= 97 && ord($c) <= 122; }
function isUpper(string $c): bool { return ord($c) >= 65 && ord($c) <= 90; }
function isDigit(string $c): bool { return ord($c) >= 48 && ord($c) <= 57; }
function digits(string $text): bool { return $text !== '' && strspn($text, '0123456789') === strlen($text); }
function lower(string $text): string { return strtr($text, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'); }
function upper(string $text): string { return strtr($text, 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'); }
function plain(string $text): string { return str_replace(['{', '}'], '', $text); }
function letters(string $text): string {
    $result = '';
    for ($i = 0; $i < strlen($text); $i++) if (isLetter($text[$i])) $result .= lower($text[$i]);
    return $result;
}
function splitTop(string $text, string $separator): array {
    $parts = [];
    $depth = 0; $start = 0; $i = 0;
    while ($i < strlen($text)) {
        if ($depth === 0 && substr($text, $i, strlen($separator)) === $separator) {
            $parts[] = substr($text, $start, $i - $start);
            $i += strlen($separator);
            $start = $i;
            continue;
        }
        if ($text[$i] === '{') $depth++;
        if ($text[$i] === '}') $depth--;
        $i++;
    }
    $parts[] = substr($text, $start);
    return $parts;
}
function accent(string $text, int $i): ?array {
    if ($i + 1 >= strlen($text) || $text[$i] !== '\\') return null;
    $command = $text[$i + 1];
    if ($command === '&') return ['&', 2];
    $symbol = str_contains("'\"`^~=.", $command);
    if ($i + 4 < strlen($text) && ($symbol || str_contains('cuvH', $command)) &&
        $text[$i + 2] === '{' && isLetter($text[$i + 3]) && $text[$i + 4] === '}') return [$text[$i + 3], 5];
    return $symbol && $i + 2 < strlen($text) && isLetter($text[$i + 2]) ? [$text[$i + 2], 3] : null;
}
function normalize(string $text): string {
    $result = '';
    for ($i = 0; $i < strlen($text);) {
        $wrapped = $text[$i] === '{' ? accent($text, $i + 1) : null;
        if ($wrapped !== null && $i + $wrapped[1] + 1 < strlen($text) && $text[$i + $wrapped[1] + 1] === '}') {
            $result .= $wrapped[0];
            $i += $wrapped[1] + 2;
        } else {
            $direct = accent($text, $i);
            if ($direct === null) $result .= $text[$i++];
            else { $result .= $direct[0]; $i += $direct[1]; }
        }
    }
    return trim(preg_replace('/ +/', ' ', str_replace('~', ' ', $result)), ' ');
}
function titleCase(string $text, Style $style): string {
    if ($style === Style::IEEE) return $text;
    if ($style === Style::APA) {
        $result = $text; $depth = 0;
        for ($i = 0; $i < strlen($text); $i++) {
            if ($text[$i] === '{') $depth++;
            elseif ($text[$i] === '}') $depth--;
            elseif ($depth === 0 && isLetter($text[$i])) {
                $result[$i] = $i === 0 || $i >= 2 && substr($text, $i - 2, 2) === ': ' ? upper($text[$i]) : lower($text[$i]);
            }
        }
        return $result;
    }
    $words = splitTop($text, ' ');
    foreach ($words as $i => $word) {
        if (str_starts_with($word, '{')) continue;
        $makeLower = $i > 0 && $i + 1 < count($words) && !str_ends_with($words[$i - 1], ':') && in_array(letters($word), SMALL_WORDS, true);
        $depth = 0;
        for ($j = 0; $j < strlen($word); $j++) {
            if ($word[$j] === '{') $depth++;
            elseif ($word[$j] === '}') $depth--;
            elseif (isLetter($word[$j])) {
                if ($makeLower) {
                    if ($depth === 0) $word[$j] = lower($word[$j]);
                } else {
                    if ($depth === 0) $word[$j] = upper($word[$j]);
                    break;
                }
            }
        }
        $words[$i] = $word;
    }
    return implode(' ', $words);
}
function listNames(array $names, string $conjunction, bool $listB = false): string {
    if (count($names) === 1) return $names[0];
    if ($listB && count($names) === 2) return $names[0] . ' ' . $conjunction . ' ' . $names[1];
    return implode(', ', array_slice($names, 0, -1)) . ', ' . $conjunction . ' ' . $names[count($names) - 1];
}

final readonly class Person {
    public function __construct(public string $first, public string $von, public string $last, public string $jr) {}

    public static function parse(string $text): self {
        $parts = array_map(static fn(string $part): string => trim($part, ' '), splitTop($text, ','));
        $words = splitTop($parts[0], ' ');
        $firstLower = -1; $lastLower = -1;
        for ($i = 0; $i + 1 < count($words); $i++) {
            if (isLower($words[$i][0])) {
                if ($firstLower < 0) $firstLower = $i;
                $lastLower = $i;
            }
        }
        $join = static fn(int $start, int $end): string => implode(' ', array_slice($words, $start, $end - $start));
        if (count($parts) === 1) {
            return $firstLower < 0 ? new self($join(0, count($words) - 1), '', $words[count($words) - 1], '')
                : new self($join(0, $firstLower), $join($firstLower, $lastLower + 1), $join($lastLower + 1, count($words)), '');
        }
        return new self($parts[count($parts) - 1], $join(0, $lastLower + 1), $join($lastLower + 1, count($words)), count($parts) === 3 ? $parts[1] : '');
    }
    public function same(self $other): bool {
        return $this->first === $other->first && $this->von === $other->von && $this->last === $other->last && $this->jr === $other->jr;
    }
    public function surname(): string { return plain($this->von === '' ? $this->last : $this->von . ' ' . $this->last); }
    public function initials(): string {
        $words = [];
        foreach (explode(' ', plain($this->first)) as $word) {
            if ($word === '') continue;
            $pieces = [];
            foreach (explode('-', $word) as $piece) {
                for ($i = 0; $i < strlen($piece); $i++) {
                    if (isLetter($piece[$i])) { $pieces[] = upper($piece[$i]) . '.'; break; }
                }
            }
            $words[] = implode('-', $pieces);
        }
        return implode(' ', $words);
    }
    public function notation(bool $inverted, bool $initials): string {
        $given = $initials ? $this->initials() : plain($this->first);
        $result = $this->surname();
        if ($this->first !== '') $result = $inverted ? $result . ', ' . $given : $given . ' ' . $result;
        if ($this->jr !== '') $result .= ', ' . plain($this->jr);
        return $result;
    }
}
final readonly class NameList {
    public function __construct(public array $names, public bool $etAl) {}
    public static function parse(string $text): self {
        $parts = splitTop($text, ' and ');
        $etAl = $parts[count($parts) - 1] === 'others';
        if ($etAl) array_pop($parts);
        return new self(array_map(Person::parse(...), $parts), $etAl);
    }
    public function single(): bool { return count($this->names) === 1 && !$this->etAl; }
    public function same(self $other): bool {
        if ($this->etAl !== $other->etAl || count($this->names) !== count($other->names)) return false;
        foreach ($this->names as $i => $name) if (!$name->same($other->names[$i])) return false;
        return true;
    }
    public function authors(Style $style): string {
        $values = [];
        foreach ($this->names as $i => $name) $values[] = $name->notation(
            $style === Style::APA || $style !== Style::IEEE && $i === 0, $style === Style::APA || $style === Style::IEEE);
        return match ($style) {
            Style::APA => $this->etAl ? implode(', ', $values) . ', et al.'
                : (count($values) > 20 ? implode(', ', array_slice($values, 0, 19)) . ', . . . ' . $values[count($values) - 1] : listNames($values, '&')),
            Style::IEEE => $this->etAl || count($values) >= 7 ? $values[0] . ' et al.' : listNames($values, 'and', true),
            Style::CHICAGO => $this->etAl || count($values) >= 11 ? implode(', ', array_slice($values, 0, 7)) . ', et al.' : listNames($values, 'and'),
            Style::MLA => $this->etAl || count($values) >= 3 ? $values[0] . ', et al.' : listNames($values, 'and'),
        };
    }
    public function editors(Style $style): string {
        $values = array_map(static fn(Person $name): string => $name->notation(false, $style === Style::APA || $style === Style::IEEE), $this->names);
        return $this->etAl ? $values[0] . ' et al.' : listNames($values, $style === Style::APA ? '&' : 'and', true);
    }
}
final class Entry {
    public readonly ?NameList $authors;
    public readonly ?NameList $editors;
    public readonly string $sortLast;
    public readonly string $sortTitle;
    public string $suffix = '';

    public function __construct(public readonly int $index, public readonly string $type, public readonly string $key, public readonly array $fields) {
        $this->authors = isset($fields['author']) ? NameList::parse($fields['author']) : null;
        $this->editors = isset($fields['editor']) ? NameList::parse($fields['editor']) : null;
        $this->sortLast = lower(plain($this->primary()->names[0]->last));
        $title = lower($this->value('title'));
        foreach (['a ', 'an ', 'the '] as $prefix) {
            if (str_starts_with($title, $prefix)) { $title = substr($title, strlen($prefix)); break; }
        }
        $this->sortTitle = $title;
    }
    public function primary(): NameList { return $this->authors ?? $this->editors; }
    public function value(string $field): string { return plain($this->fields[$field] ?? ''); }
    public function year(Style $style): string { return $this->value('year') . ($style === Style::APA || $style === Style::CHICAGO ? $this->suffix : ''); }
    public static function compare(self $a, self $b): int {
        foreach ([[$a->sortLast, $b->sortLast], [$a->value('year'), $b->value('year')], [$a->sortTitle, $b->sortTitle], [$a->key, $b->key]] as [$x, $y]) {
            $order = strcmp($x, $y);
            if ($order !== 0) return $order;
        }
        return 0;
    }
}

final class Database {
    private const REQUIRED = [
        'article' => ['author', 'title', 'journal', 'year'], 'book' => ['author', 'title', 'publisher', 'year'],
        'inproceedings' => ['author', 'title', 'booktitle', 'year'], 'incollection' => ['author', 'title', 'booktitle', 'publisher', 'year'],
        'techreport' => ['author', 'title', 'institution', 'year'], 'phdthesis' => ['author', 'title', 'school', 'year'], 'misc' => ['author', 'title', 'year'],
    ];
    private array $macros = [];
    public array $entries = [];
    public array $byKey = [];
    public array $messages = [];

    public function __construct(array $lines) {
        $monthKeys = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
        foreach ($monthKeys as $i => $key) $this->macros[$key] = MONTHS[$i];
        for ($i = 0; $i < count($lines); $i++) {
            $text = $lines[$i];
            if ($text === '' || str_starts_with($text, '%')) continue;
            if (str_starts_with($text, '@string{')) {
                $separator = strpos($text, ' = ');
                $name = substr($text, 8, $separator - 8);
                try {
                    $value = $this->evaluate(substr($text, $separator + 3, -1), $i + 1);
                    if (isset($this->macros[$name])) throw new LoadError($i + 1, 'duplicate macro');
                    $this->macros[$name] = $value;
                } catch (LoadError $error) { $this->report($name, $error); }
            } else {
                $end = $i + 1;
                while ($lines[$end] !== '}') $end++;
                $brace = strpos($text, '{');
                $type = substr($text, 1, $brace - 1);
                $key = substr($text, $brace + 1, -1);
                try { $this->readEntry($lines, $i, $end, $type, $key); }
                catch (LoadError $error) { $this->report($key, $error); }
                $i = $end;
            }
        }
        $this->assignSuffixes();
        $this->messages[] = 'LOADED entries=' . count($this->entries) . ' macros=' . (count($this->macros) - 12) . ' errors=' . count($this->messages);
    }
    private function report(string $name, LoadError $error): void {
        $this->messages[] = "ERROR line {$error->sourceLine}: $name: " . $error->getMessage();
    }
    private function evaluate(string $expression, int $line): string {
        $depth = 0;
        for ($i = 0; $i < strlen($expression); $i++) {
            if ($expression[$i] === '{') $depth++;
            if ($expression[$i] === '}') $depth--;
            if ($depth < 0) throw new LoadError($line, 'unbalanced braces');
        }
        if ($depth !== 0) throw new LoadError($line, 'unbalanced braces');
        $result = '';
        foreach (explode(' # ', $expression) as $term) {
            if ($term[0] === '{' || $term[0] === '"') $result .= substr($term, 1, -1);
            elseif (isDigit($term[0])) $result .= $term;
            elseif (isset($this->macros[$term])) $result .= $this->macros[$term];
            else throw new LoadError($line, "unknown macro '$term'");
        }
        return $result;
    }
    private function readEntry(array $lines, int $start, int $end, string $type, string $key): void {
        if (!array_key_exists($type, self::REQUIRED)) throw new LoadError($start + 1, "unknown type '$type'");
        if (isset($this->byKey[':' . $key])) throw new LoadError($start + 1, 'duplicate key');
        $fields = [];
        for ($i = $start + 1; $i < $end; $i++) {
            $separator = strpos($lines[$i], ' = ');
            $name = substr($lines[$i], 2, $separator - 2);
            $expression = substr($lines[$i], $separator + 3);
            if (str_ends_with($expression, ',')) $expression = substr($expression, 0, -1);
            $value = $this->evaluate($expression, $i + 1);
            if (isset($fields[$name])) throw new LoadError($i + 1, "duplicate field '$name'");
            $fields[$name] = normalize($value);
        }
        foreach (self::REQUIRED[$type] as $name) {
            if (!isset($fields[$name]) && !($type === 'book' && $name === 'author' && isset($fields['editor']))) {
                throw new LoadError($end + 1, "missing field '$name'");
            }
        }
        $entry = new Entry(count($this->entries), $type, $key, $fields);
        $this->entries[] = $entry;
        $this->byKey[':' . $key] = $entry;
    }
    private function assignSuffixes(): void {
        $done = [];
        foreach ($this->entries as $entry) {
            if (isset($done[$entry->index])) continue;
            $group = array_values(array_filter($this->entries, static fn(Entry $other): bool =>
                $entry->primary()->same($other->primary()) && $entry->fields['year'] === $other->fields['year']));
            usort($group, static fn(Entry $a, Entry $b): int => strcmp($a->sortTitle, $b->sortTitle) ?: strcmp($a->key, $b->key));
            foreach ($group as $i => $other) {
                $done[$other->index] = true;
                if (count($group) > 1) $other->suffix = chr(97 + $i);
            }
        }
    }
}

enum PartKind { case Literal; case Field; case Optional; }
final readonly class TemplatePart {
    public function __construct(public PartKind $kind, public string $text = '', public array $children = []) {}
}
final class ReferenceFormatter {
    private const TEMPLATES = [
        'APA' => [
            '{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>',
            '{author}. ({year}). {title}< ({edition})>. {publisher}.',
            '{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>',
            '{author}. ({year}). {title}< (Report No. {number})>. {institution}.',
            '{author}. ({year}). {title} [Doctoral dissertation, {school}].',
            '{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>',
        ],
        'IEEE' => [
            '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
            '{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.',
            '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
            '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
            '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
            '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>',
        ],
        'CHICAGO' => [
            '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
            '{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.',
            '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
            '{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.',
            '{author}. {year}. "{title}." PhD diss., {school}.',
            '{author}. {year}. {title}.< {howpublished}.>< {note}.>',
        ],
        'MLA' => [
            '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
            '{author}. {title}.< {edition},> {publisher}, {year}.',
            '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
            '{author}. {title}. {institution}, {year}.< Technical Report {number}.>',
            '{author}. {title}. {year}. {school}, PhD dissertation.',
            '{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>',
        ],
    ];
    private array $parsed = [];
    public function __construct() {
        foreach (self::TEMPLATES as $style => $templates) {
            foreach ($templates as $text) {
                $position = 0;
                $this->parsed[$style][] = self::parse($text, $position);
            }
        }
    }
    private static function parse(string $text, int &$i): array {
        $parts = [];
        while ($i < strlen($text) && $text[$i] !== '>') {
            if ($text[$i] === '{') {
                $end = strpos($text, '}', $i);
                $parts[] = new TemplatePart(PartKind::Field, substr($text, $i + 1, $end - $i - 1));
                $i = $end + 1;
            } elseif ($text[$i] === '<') {
                $i++;
                $parts[] = new TemplatePart(PartKind::Optional, children: self::parse($text, $i));
                $i++;
            } else $parts[] = new TemplatePart(PartKind::Literal, $text[$i++]);
        }
        return $parts;
    }
    private static function editorSuffix(Entry $entry, Style $style): string {
        if ($entry->authors !== null) return '';
        $single = $entry->primary()->single();
        return match ($style) {
            Style::APA => $single ? ' (Ed.)' : ' (Eds.)', Style::IEEE => $single ? ', Ed.' : ', Eds.',
            Style::CHICAGO => $single ? ', ed.' : ', eds.', Style::MLA => $single ? ', editor' : ', editors',
        };
    }
    private static function edition(string $value): string {
        if (!digits($value)) return $value . ' ed.';
        $number = (int)$value;
        $suffix = in_array($number % 100, [11, 12, 13], true) ? 'th' : match ($number % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', default => 'th' };
        return $value . $suffix . ' ed.';
    }
    private static function values(Entry $entry, Style $style, bool $repeated): array {
        $result = array_map(plain(...), $entry->fields);
        $result['author'] = ($repeated ? '---' : $entry->primary()->authors($style)) . self::editorSuffix($entry, $style);
        $result['editor'] = $entry->editors?->editors($style) ?? '';
        $result['eds'] = $entry->editors === null ? '' : ($entry->editors->single() ? 'Ed.' : 'Eds.');
        $result['title'] = plain(titleCase($entry->fields['title'], $style));
        $result['year'] = $entry->year($style);
        $result['pp'] = '';
        if (isset($entry->fields['pages'])) {
            $result['pages'] = str_replace('--', '-', $entry->value('pages'));
            $result['pp'] = (str_contains($result['pages'], '-') ? 'pp. ' : 'p. ') . $result['pages'];
        }
        if (isset($entry->fields['edition'])) $result['edition'] = self::edition($entry->value('edition'));
        $month = $entry->value('month');
        $index = array_search($month, MONTHS, true);
        $result['mon'] = $index === false ? $month : MONTH_SHORT[$index];
        return $result;
    }
    private static function render(array $parts, array $fields, string &$result): void {
        foreach ($parts as $part) {
            if ($part->kind === PartKind::Field) {
                $result .= $fields[$part->text] ?? '';
            } elseif ($part->kind === PartKind::Optional) {
                $visible = true;
                foreach ($part->children as $child) {
                    if ($child->kind === PartKind::Field && ($fields[$child->text] ?? '') === '') { $visible = false; break; }
                }
                if ($visible) self::render($part->children, $fields, $result);
            } elseif ($part->text !== '.' || $result === '' || !str_contains('.?!', $result[strlen($result) - 1])) $result .= $part->text;
        }
    }
    public function reference(Entry $entry, Style $style, int $number, bool $repeated = false): string {
        $type = match ($entry->type) { 'article' => 0, 'book' => 1, 'inproceedings', 'incollection' => 2, 'techreport' => 3, 'phdthesis' => 4, default => 5 };
        $result = '';
        self::render($this->parsed[$style->value][$type], self::values($entry, $style, $repeated), $result);
        return ($style === Style::IEEE ? "[$number] " : '') . $result;
    }
}

final readonly class Citation {
    public function __construct(public int $start, public int $end, public string $kind, public array $entries) {}
}
final class CitationManager {
    private array $record = [];
    private array $recorded = [];
    private ReferenceFormatter $formatter;
    public function __construct(private readonly Database $database) { $this->formatter = new ReferenceFormatter(); }
    private function lookup(string $key): Entry { return $this->database->byKey[':' . $key] ?? throw new CommandError("unknown key '$key'"); }
    private function ieeeOrder(): array {
        $rest = array_values(array_filter($this->database->entries, fn(Entry $entry): bool => !isset($this->recorded[$entry->index])));
        usort($rest, static fn(Entry $a, Entry $b): int => strcmp($a->key, $b->key));
        return array_merge($this->record, $rest);
    }
    private function ieeeNumbers(): array {
        $numbers = [];
        foreach ($this->ieeeOrder() as $i => $entry) $numbers[$entry->index] = $i + 1;
        return $numbers;
    }
    private static function shortName(Entry $entry, Style $style, bool $parenthetical): string {
        $names = array_map(static fn(Person $name): string => $name->surname(), $entry->primary()->names);
        if ($entry->primary()->etAl || count($names) >= ($style === Style::CHICAGO ? 4 : 3)) return $names[0] . ' et al.';
        return match (count($names)) {
            1 => $names[0], 2 => $names[0] . ($style === Style::APA && $parenthetical ? ' & ' : ' and ') . $names[1],
            3 => $names[0] . ', ' . $names[1] . ', and ' . $names[2],
        };
    }
    private static function numberRanges(array $numbers): string {
        sort($numbers, SORT_NUMERIC);
        $parts = [];
        for ($i = 0; $i < count($numbers);) {
            $end = $i;
            while ($end + 1 < count($numbers) && $numbers[$end + 1] === $numbers[$end] + 1) $end++;
            if ($end - $i >= 2) $parts[] = "[{$numbers[$i]}]-[{$numbers[$end]}]";
            else for ($j = $i; $j <= $end; $j++) $parts[] = "[{$numbers[$j]}]";
            $i = $end + 1;
        }
        return implode(', ', $parts);
    }
    private static function citationText(Citation $citation, Style $style, array $numbers): string {
        $entries = $citation->entries;
        if ($citation->kind === 'citeauthor') return implode('; ', array_map(static fn(Entry $entry): string => self::shortName($entry, $style, false), $entries));
        if ($citation->kind === 'citeyear') return implode(', ', array_map(static fn(Entry $entry): string => $entry->year($style), $entries));
        $parenthetical = $citation->kind !== 'citet';
        if ($style === Style::IEEE) {
            return $parenthetical ? self::numberRanges(array_map(static fn(Entry $entry): int => $numbers[$entry->index], $entries))
                : implode('; ', array_map(static fn(Entry $entry): string => self::shortName($entry, $style, false) . ' [' . $numbers[$entry->index] . ']', $entries));
        }
        if ($style === Style::MLA) {
            $text = implode('; ', array_map(static fn(Entry $entry): string => self::shortName($entry, $style, $parenthetical), $entries));
            return $parenthetical ? '(' . $text . ')' : $text;
        }
        if ($parenthetical) usort($entries, Entry::compare(...));
        $groups = [];
        for ($i = 0; $i < count($entries);) {
            $name = self::shortName($entries[$i], $style, $parenthetical);
            $end = $i + 1;
            while ($end < count($entries) && self::shortName($entries[$end], $style, $parenthetical) === $name) $end++;
            $years = implode(', ', array_map(static fn(Entry $entry): string => $entry->year($style), array_slice($entries, $i, $end - $i)));
            $groups[] = $parenthetical ? $name . ($style === Style::APA ? ', ' : ' ') . $years : $name . ' (' . $years . ')';
            $i = $end;
        }
        $text = implode('; ', $groups);
        return $parenthetical ? '(' . $text . ')' : $text;
    }
    private function cite(string $text, Style $style): string {
        $citations = [];
        for ($start = strpos($text, '\\'); $start !== false;) {
            $brace = strpos($text, '{', $start); $end = strpos($text, '}', $brace);
            $seen = []; $entries = [];
            foreach (explode(',', substr($text, $brace + 1, $end - $brace - 1)) as $key) {
                $entry = $this->lookup($key);
                if (!isset($seen[$entry->index])) { $seen[$entry->index] = true; $entries[] = $entry; }
            }
            $citations[] = new Citation($start, $end + 1, substr($text, $start + 1, $brace - $start - 1), $entries);
            $start = strpos($text, '\\', $end + 1);
        }
        foreach ($citations as $citation) {
            foreach ($citation->entries as $entry) {
                if (!isset($this->recorded[$entry->index])) { $this->recorded[$entry->index] = true; $this->record[] = $entry; }
            }
        }
        $numbers = $this->ieeeNumbers();
        $result = ''; $position = 0;
        foreach ($citations as $citation) {
            $result .= substr($text, $position, $citation->start - $position) . self::citationText($citation, $style, $numbers);
            $position = $citation->end;
        }
        return $result . substr($text, $position);
    }
    private static function baseKey(Entry $entry): string {
        $result = letters(plain($entry->primary()->names[0]->last));
        foreach (str_split($entry->fields['year']) as $c) if (isDigit($c)) $result .= $c;
        foreach (explode(' ', $entry->value('title')) as $word) {
            $candidate = letters($word);
            if ($candidate !== '' && !in_array($candidate, SMALL_WORDS, true)) { $result .= $candidate; break; }
        }
        return $result;
    }
    private function keygen(): array {
        $bases = array_map(self::baseKey(...), $this->database->entries);
        $counts = []; $used = []; $output = [];
        foreach ($bases as $base) $counts[':' . $base] = ($counts[':' . $base] ?? 0) + 1;
        foreach ($bases as $i => $base) {
            $generated = $base;
            if ($counts[':' . $base] > 1) {
                $ordinal = $used[':' . $base] ?? 0;
                $used[':' . $base] = $ordinal + 1;
                $generated .= chr(97 + $ordinal);
            }
            $output[] = $this->database->entries[$i]->key . ' -> ' . $generated;
        }
        return $output;
    }
    private static function unknownFields(Entry $entry): array {
        $names = array_values(array_diff(array_keys($entry->fields), KNOWN_FIELDS));
        sort($names, SORT_STRING);
        return $names;
    }
    private function check(): array {
        $output = []; $titles = [];
        foreach ($this->database->entries as $entry) {
            $warnings = [];
            if (isset($entry->fields['pages'])) {
                $pages = $entry->value('pages');
                if (str_contains($pages, '-') && !str_contains($pages, '--')) $warnings[] = 'pages use a single hyphen';
                $parts = array_values(array_filter(explode('-', $pages), static fn(string $part): bool => $part !== ''));
                if (count($parts) === 2 && digits($parts[0]) && digits($parts[1]) && (int)$parts[0] > (int)$parts[1]) $warnings[] = 'pages are reversed';
            }
            $year = $entry->value('year');
            if (strlen($year) !== 4 || !digits($year)) $warnings[] = 'year is not 4 digits';
            $title = $entry->value('title');
            $hasLower = false; $upperCount = 0;
            foreach (str_split($title) as $c) { if (isLower($c)) $hasLower = true; if (isUpper($c)) $upperCount++; }
            if (!$hasLower && $upperCount >= 2) $warnings[] = 'title is all caps';
            if ($entry->type === 'article' && !isset($entry->fields['doi'])) $warnings[] = 'article has no doi';
            $titleKey = ':' . lower($title);
            if (isset($titles[$titleKey])) $warnings[] = 'same title as ' . $titles[$titleKey];
            else $titles[$titleKey] = $entry->key;
            foreach (self::unknownFields($entry) as $field) $warnings[] = "unknown field '$field'";
            foreach ($warnings as $warning) $output[] = "WARN {$entry->key}: $warning";
        }
        $output[] = 'CHECK warnings=' . count($output);
        return $output;
    }
    private static function exportEntry(Entry $entry): array {
        $fields = array_values(array_filter(KNOWN_FIELDS, static fn(string $field): bool => isset($entry->fields[$field])));
        $fields = array_merge($fields, self::unknownFields($entry));
        $output = ['@' . $entry->type . '{' . $entry->key . ','];
        foreach ($fields as $i => $field) $output[] = '  ' . $field . ' = {' . $entry->fields[$field] . '}' . ($i + 1 < count($fields) ? ',' : '');
        $output[] = '}';
        return $output;
    }
    private function stats(): array {
        $types = []; $years = []; $authors = []; $pairs = [];
        foreach ($this->database->entries as $entry) {
            $types[$entry->type] = ($types[$entry->type] ?? 0) + 1;
            $year = ':' . $entry->value('year');
            $years[$year] = ($years[$year] ?? 0) + 1;
            if ($entry->authors === null) continue;
            $names = [];
            foreach ($entry->authors->names as $name) {
                $full = $name->notation(false, false);
                $names[':' . $full] = $full;
                $authors[':' . $full] = true;
            }
            $names = array_values($names);
            sort($names, SORT_STRING);
            for ($i = 0; $i < count($names); $i++) {
                for ($j = $i + 1; $j < count($names); $j++) {
                    $a = ':' . $names[$i]; $b = ':' . $names[$j];
                    $pairs[$a][$b] = ($pairs[$a][$b] ?? 0) + 1;
                }
            }
        }
        $output = ['ENTRIES ' . count($this->database->entries)];
        ksort($types, SORT_STRING); ksort($years, SORT_STRING);
        foreach ($types as $type => $count) $output[] = "TYPE $type $count";
        foreach ($years as $year => $count) $output[] = 'YEAR ' . substr($year, 1) . ' ' . $count;
        $output[] = 'AUTHORS ' . count($authors);
        $best = null;
        foreach ($pairs as $a => $seconds) {
            foreach ($seconds as $b => $count) {
                if ($best === null || $count > $best[2] || $count === $best[2] &&
                    (strcmp($a, $best[0]) < 0 || $a === $best[0] && strcmp($b, $best[1]) < 0)) $best = [$a, $b, $count];
            }
        }
        $output[] = $best === null ? 'PAIR none' : 'PAIR ' . substr($best[0], 1) . ' & ' . substr($best[1], 1) . ' ' . $best[2];
        return $output;
    }
    public function execute(string $line): array {
        $command = explode(' ', $line, 2)[0];
        $expected = match ($command) {
            'FORMAT', 'CITE', 'SEARCH' => 2, 'BIBLIOGRAPHY', 'EXPORT' => 1, 'KEYGEN', 'CHECK', 'STATS' => 0,
            default => throw new CommandError("unknown command '$command'"),
        };
        $words = in_array($command, ['CITE', 'SEARCH'], true) ? explode(' ', $line, 3) : explode(' ', $line);
        if ($command === 'FORMAT' ? count($words) - 1 < $expected : count($words) - 1 !== $expected) throw new CommandError('wrong number of arguments');
        $style = Style::APA;
        if (in_array($command, ['FORMAT', 'BIBLIOGRAPHY', 'CITE'], true)) {
            $style = Style::tryFrom($words[1]) ?? throw new CommandError("unknown style '{$words[1]}'");
        }
        $output = [];
        switch ($command) {
            case 'FORMAT':
                $numbers = $this->ieeeNumbers();
                foreach (array_slice($words, 2) as $key) {
                    $entry = $this->database->byKey[':' . $key] ?? null;
                    $output[] = $entry === null ? "ERROR unknown key '$key'" : $this->formatter->reference($entry, $style, $numbers[$entry->index]);
                }
                break;
            case 'BIBLIOGRAPHY':
                $output[] = $style === Style::MLA ? 'Works Cited' : 'References';
                $numbers = $this->ieeeNumbers();
                $entries = $style === Style::IEEE ? $this->ieeeOrder() : $this->database->entries;
                if ($style !== Style::IEEE) usort($entries, Entry::compare(...));
                $previous = null;
                foreach ($entries as $entry) {
                    $repeated = ($style === Style::CHICAGO || $style === Style::MLA) && $previous !== null && $previous->same($entry->primary());
                    $output[] = $this->formatter->reference($entry, $style, $numbers[$entry->index], $repeated);
                    $previous = $entry->primary();
                }
                break;
            case 'CITE': return [$this->cite($words[2], $style)];
            case 'KEYGEN': return $this->keygen();
            case 'CHECK': return $this->check();
            case 'SEARCH':
                $matches = []; $needle = lower($words[2]);
                foreach ($this->database->entries as $entry) {
                    if (isset($entry->fields[$words[1]]) && str_contains(lower($entry->value($words[1])), $needle)) $matches[] = $entry->key;
                }
                return $matches === [] ? ['MATCHES 0'] : ['MATCHES ' . count($matches) . ': ' . implode(' ', $matches)];
            case 'EXPORT': return self::exportEntry($this->lookup($words[1]));
            case 'STATS': return $this->stats();
        }
        return $output;
    }
}

$lines = [];
while (($input = fgets(STDIN)) !== false) {
    $text = rtrim($input, "\r\n");
    if ($text === '%%') break;
    $lines[] = $text;
}
$database = new Database($lines);
foreach ($database->messages as $message) echo $message, "\n";
$manager = new CitationManager($database);
$count = (int)trim(fgets(STDIN));
for ($i = 0; $i < $count; $i++) {
    try {
        foreach ($manager->execute(rtrim(fgets(STDIN), "\r\n")) as $message) echo $message, "\n";
    } catch (CommandError $error) { echo 'ERROR ', $error->getMessage(), "\n"; }
}
