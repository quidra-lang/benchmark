<?php
declare(strict_types=1);

namespace IniValidator;

require_once __DIR__ . '/lexer.php';
require_once __DIR__ . '/ini_parser.php';
require_once __DIR__ . '/schema.php';
require_once __DIR__ . '/interpolate.php';
require_once __DIR__ . '/emitter.php';

const SIZE_FACTORS = ['' => 1, 'b' => 1, 'kb' => 1024, 'mb' => 1048576, 'gb' => 1073741824];
const DEFAULT_PORTS = ['http' => 80, 'https' => 443];

function parseInt(string $text): ?int
{
    if (preg_match('/\A([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))\z/', $text, $parts) !== 1) {
        return null;
    }
    if ($parts[2] !== '') {
        $value = (int) hexdec($parts[2]);
    } else {
        $digits = str_replace('_', '', $parts[3]);
        if (strlen($digits) > 12) {
            return null;
        }
        $value = (int) $digits;
    }
    return $parts[1] === '-' ? -$value : $value;
}

function parseSize(string $text): ?int
{
    if (preg_match('/\A([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*)\z/', $text, $parts) !== 1) {
        return null;
    }
    $factor = SIZE_FACTORS[strtolower($parts[3])] ?? null;
    if ($factor === null) {
        return null;
    }
    $fraction = $parts[2];
    if ($fraction === '') {
        return (int) $parts[1] * $factor;
    }
    $scaled = (int) $fraction * $factor;
    $divisor = 10 ** strlen($fraction);
    return $scaled % $divisor === 0 ? (int) $parts[1] * $factor + intdiv($scaled, $divisor) : null;
}

function parseDuration(string $text): ?int
{
    if (preg_match('/\A[0-9]{1,6}\z/', $text) === 1) {
        return (int) $text;
    }
    if ($text === '' || preg_match('/\A(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?\z/', $text, $parts) !== 1) {
        return null;
    }
    return (int) ($parts[1] ?? 0) * 3600 + (int) ($parts[2] ?? 0) * 60 + (int) ($parts[3] ?? 0);
}

function parseHost(string $text): ?string
{
    if (preg_match('/\A[0-9.]*\z/', $text) === 1) {
        $parts = explode('.', $text);
        if (count($parts) !== 4) {
            return null;
        }
        foreach ($parts as $part) {
            if (preg_match('/\A[0-9]{1,3}\z/', $part) !== 1 ||
                (strlen($part) > 1 && $part[0] === '0') || (int) $part > 255) {
                return null;
            }
        }
        return $text;
    }
    if (strlen($text) > 253) {
        return null;
    }
    foreach (explode('.', $text) as $label) {
        if (preg_match('/\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z/', $label) !== 1) {
            return null;
        }
    }
    return strtolower($text);
}

function parsePath(string $text): ?string
{
    if ($text === '' || strpbrk($text, " \n\t") !== false) {
        return null;
    }
    $absolute = str_starts_with($text, '/');
    $parts = [];
    foreach (explode('/', $text) as $part) {
        if ($part === '' || $part === '.') {
            continue;
        }
        if ($part !== '..') {
            $parts[] = $part;
        } elseif ($parts !== [] && $parts[count($parts) - 1] !== '..') {
            array_pop($parts);
        } elseif ($absolute) {
            return null;
        } else {
            $parts[] = '..';
        }
    }
    return $absolute ? '/' . implode('/', $parts) : ($parts === [] ? '.' : implode('/', $parts));
}

function parseUrl(string $text): ?string
{
    $parts = explode('://', $text, 2);
    if (count($parts) !== 2 || preg_match('/\A[A-Za-z][A-Za-z0-9+.-]*\z/', $parts[0]) !== 1) {
        return null;
    }
    [$scheme, $rest] = $parts;
    if (strpbrk($rest, '?#') !== false) {
        return null;
    }
    $parts = explode('/', $rest, 2);
    $authority = explode(':', $parts[0], 2);
    $host = parseHost($authority[0]);
    $path = parsePath('/' . ($parts[1] ?? ''));
    if ($host === null || $path === null) {
        return null;
    }
    $scheme = strtolower($scheme);
    $result = $scheme . '://' . $host;
    if (count($authority) === 2) {
        $port = $authority[1];
        if (preg_match('/\A[1-9][0-9]{0,4}\z/', $port) !== 1 || (int) $port > 65535) {
            return null;
        }
        if ((DEFAULT_PORTS[$scheme] ?? null) !== (int) $port) {
            $result .= ':' . $port;
        }
    }
    return $result . $path;
}

function parseDate(string $text): ?string
{
    if (preg_match('/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/', $text) !== 1) {
        return null;
    }
    [$year, $month, $day] = array_map(intval(...), explode('-', $text));
    if ($year < 1 || $month < 1 || $month > 12) {
        return null;
    }
    $days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$month - 1];
    if ($month === 2 && (($year % 4 === 0 && $year % 100 !== 0) || $year % 400 === 0)) {
        $days = 29;
    }
    return $day >= 1 && $day <= $days ? $text : null;
}

function parseScalar(string $kind, string $text, array $values = []): string|int|bool|null
{
    return match ($kind) {
        'string' => $text,
        'int' => parseInt($text),
        'bool' => match (strtolower($text)) {
            'true', 'yes', 'on', '1' => true,
            'false', 'no', 'off', '0' => false,
            default => null,
        },
        'enum' => in_array(strtolower($text), $values, true) ? strtolower($text) : null,
        'size' => parseSize($text),
        'duration' => parseDuration($text),
        'host' => parseHost($text),
        'path' => parsePath($text),
        'url' => parseUrl($text),
        'date' => parseDate($text),
    };
}

final class CheckFailure extends \RuntimeException
{
    public function __construct(public string $diagnosticCode, string $message)
    {
        parent::__construct($message);
    }
}

function invalidValue(string $key, string $kind, array $values, string $display): CheckFailure
{
    return $kind === 'enum'
        ? new CheckFailure('E_ENUM', "$key: $display is not one of " . implode(',', $values))
        : new CheckFailure('E_TYPE', "$key: $display is not a valid $kind");
}

function checkRange(string $key, Spec $spec, mixed $value): void
{
    $bounds = [];
    foreach (explode('..', $spec->get('range'), 2) as $text) {
        $bounds[] = $text === '' ? null : (in_array($spec->kind, ['string', 'list'], true)
            ? (int) $text : parseScalar($spec->kind, $text));
    }
    [$lower, $upper] = $bounds;
    $measure = match ($spec->kind) {
        'string' => strlen($value),
        'list' => count($value),
        default => $value,
    };
    if (($lower === null || $measure >= $lower) && ($upper === null || $measure <= $upper)) {
        return;
    }
    $display = match ($spec->kind) {
        'string' => "length $measure",
        'list' => "count $measure",
        default => $spec->has('secret') ? MASK : (string) $value,
    };
    $range = ($lower ?? '') . '..' . ($upper ?? '');
    throw new CheckFailure('E_RANGE', "$key: $display is out of range $range");
}

final class Definition
{
    public function __construct(
        public string $value,
        public array $origin,
        public int $number,
        public array $history,
    ) {}
}

final class OutputKey
{
    public string $kind;
    public bool $secret;
    public string $notation;

    public function __construct(public Definition $definition, public ?Spec $spec, public mixed $value)
    {
        $this->kind = $spec?->kind ?? 'string';
        $this->secret = $spec?->has('secret') ?? false;
        $this->notation = valueNotation($this->kind, $spec?->get('item', 'string'), $value);
    }
}

final class DocumentLibrary
{
    private array $documents = [];

    public function __construct(private string $directory) {}

    public function find(string $name): ?ParsedDocument
    {
        if (!array_key_exists($name, $this->documents)) {
            $path = $this->directory . '/' . $name . '.ini';
            $this->documents[$name] = file_exists($path)
                ? parseDocument($name, file($path, FILE_IGNORE_NEW_LINES)) : null;
        }
        return $this->documents[$name];
    }
}

final class Profile
{
    public string $name;
    public string $root;
    private array $overrides;
    private array $configuration = [];
    private int $definitionCount = 0;
    private array $parents = [];
    private array $reported = [];
    public array $outputs = [];
    public array $tree = [];
    public array $diagnostics = [];
    public array $overridden = [];
    public int $errors = 0;
    public int $warnings = 0;
    public int $documentKeys = 0;
    public int $manifestKeys = 0;
    public int $defaultKeys = 0;
    public int $dropped = 0;

    public function __construct(private int $number, string $line)
    {
        $words = explode(' ', $line);
        [$this->name, $this->root] = $words;
        $this->overrides = array_slice($words, 2);
    }

    private function report(array $origin, string $code, string $message): void
    {
        $diagnostic = [$origin[0], $origin[1], $code, $message];
        $this->reported[serialize($diagnostic)] = $diagnostic;
    }

    private function defineKey(string $key, string $value, array $origin): void
    {
        $history = $this->configuration[$key]->history ?? [];
        if ($history === [] || $history[count($history) - 1] !== $origin) {
            $history[] = $origin;
        }
        $this->configuration[$key] = new Definition($value, $origin, ++$this->definitionCount, $history);
    }

    public function process(Schema $schema, DocumentLibrary $library, array $earlier): void
    {
        $this->apply($library, $this->root, [$this->root]);
        foreach ($this->overrides as $override) {
            [$key, $value] = explode('=', $override, 2);
            $this->defineKey($key, $value, ['manifest', $this->number]);
        }
        $this->inheritSections();
        $this->resolveAliases($schema);
        $sections = array_values(array_unique(array_map(static fn ($key) => splitKey($key)[0], array_keys($this->configuration))));
        foreach ($schema->specs as $spec) {
            if ($spec->has('default')) {
                foreach ($schema->targetKeys($spec, $sections) as $key) {
                    if (!isset($this->configuration[$key])) {
                        $this->defineKey($key, $spec->get('default'), ['schema', $spec->line]);
                    }
                }
            }
        }
        $configured = array_fill_keys(array_keys($this->configuration), true);
        $this->checkTypes($schema);
        $this->checkOrder();
        $this->checkRequired($schema, $sections, $configured);
        $this->checkFixed($earlier);
        $this->summarize(count($configured));
    }

    private function apply(DocumentLibrary $library, string $name, array $chain): void
    {
        $document = $library->find($name);
        $this->tree[] = [count($chain) - 1, $name];
        foreach ($document->diagnostics as [$doc, $line, $code, $message]) {
            $this->report([$doc, $line], $code, $message);
        }
        foreach ($document->statements as $statement) {
            $origin = [$name, $statement->line];
            $key = $statement->target;
            switch ($statement->kind) {
                case 'assign':
                case 'append':
                    $value = $statement->value;
                    if ($statement->kind === 'append' && isset($this->configuration[$key]) && $this->configuration[$key]->value !== '') {
                        $value = $this->configuration[$key]->value . ',' . $value;
                    }
                    $this->defineKey($key, $value, $origin);
                    break;
                case 'unset':
                    if (isset($this->configuration[$key])) {
                        unset($this->configuration[$key]);
                    } else {
                        $this->report($origin, 'W_UNSET', "$key is not set");
                    }
                    break;
                case 'inherit':
                    $this->parents[$key] = [$statement->value, $origin];
                    break;
                case 'include':
                    $cycleStart = array_search($key, $chain, true);
                    if ($cycleStart !== false) {
                        $path = array_slice($chain, $cycleStart);
                        $path[] = $key;
                        $this->report($origin, 'E_INCLUDE_CYCLE', 'include cycle ' . implode(' -> ', $path));
                        $this->tree[] = [count($chain), $key . ' (cycle)'];
                    } elseif ($library->find($key) === null) {
                        $this->report($origin, 'E_INCLUDE_MISSING', "missing document $key");
                        $this->tree[] = [count($chain), $key . ' (missing)'];
                    } else {
                        $this->apply($library, $key, [...$chain, $key]);
                    }
                    break;
            }
        }
    }

    private function inheritSections(): void
    {
        $own = [];
        foreach ($this->configuration as $key => $definition) {
            [$section, $name] = splitKey($key);
            $own[$section][] = [$name, $definition];
        }
        foreach ($this->parents as $section => [$parent, $origin]) {
            $chain = [$section];
            $last = $section;
            while (isset($this->parents[$last]) && !in_array($this->parents[$last][0], $chain, true)) {
                $last = $this->parents[$last][0];
                $chain[] = $last;
            }
            if (isset($this->parents[$last])) {
                $chain[] = $this->parents[$last][0];
                $this->report($origin, 'E_INHERIT_CYCLE', 'inheritance cycle ' . implode(' -> ', $chain));
                continue;
            }
            if (!isset($this->parents[$parent]) && !isset($own[$parent])) {
                $this->report($origin, 'W_PARENT_EMPTY', "section $section inherits from empty section $parent");
            }
            foreach (array_slice($chain, 1) as $ancestor) {
                foreach ($own[$ancestor] ?? [] as [$name, $definition]) {
                    $key = $section . '.' . $name;
                    $this->configuration[$key] ??= $definition;
                }
            }
        }
    }

    private function resolveAliases(Schema $schema): void
    {
        foreach ($schema->specs as $spec) {
            if (!$spec->has('alias')) {
                continue;
            }
            $aliases = array_values(array_filter(explode(',', $spec->get('alias')), fn ($key) => isset($this->configuration[$key])));
            if ($aliases === []) {
                continue;
            }
            $candidates = isset($this->configuration[$spec->pattern]) ? [$spec->pattern, ...$aliases] : $aliases;
            $winner = $candidates[0];
            foreach ($candidates as $candidate) {
                if ($this->configuration[$candidate]->number > $this->configuration[$winner]->number) {
                    $winner = $candidate;
                }
            }
            $chosen = $this->configuration[$winner];
            foreach ($candidates as $candidate) {
                $origin = $this->configuration[$candidate]->origin;
                if ($candidate !== $spec->pattern) {
                    $this->report($origin, 'W_DEPRECATED', "$candidate is deprecated, use {$spec->pattern}");
                }
                if ($candidate !== $winner) {
                    $this->report($origin, 'W_SHADOWED', "$candidate is superseded by $winner at " . originText($chosen->origin));
                }
            }
            $this->configuration[$spec->pattern] = $chosen;
            foreach ($aliases as $alias) {
                unset($this->configuration[$alias]);
            }
        }
    }

    private function checkTypes(Schema $schema): void
    {
        $values = $origins = [];
        foreach ($this->configuration as $key => $definition) {
            $values[$key] = $definition->value;
            $origins[$key] = $definition->origin;
        }
        $expander = new Expander($values, $origins);
        foreach (orderedKeys(array_keys($this->configuration)) as $key) {
            $expander->expand($key);
        }
        foreach ($expander->diagnostics as [$doc, $line, $code, $message]) {
            $this->report([$doc, $line], $code, $message);
        }
        foreach (orderedKeys(array_keys($expander->results)) as $key) {
            $text = $expander->results[$key];
            if ($text === null) {
                continue;
            }
            $definition = $this->configuration[$key];
            $spec = $schema->specFor($key);
            if ($spec === null) {
                $this->report($definition->origin, 'W_UNKNOWN', "$key is not in the schema");
                $value = $text;
            } else {
                try {
                    $value = $this->normalize($key, $spec, $text, $definition->origin);
                } catch (CheckFailure $error) {
                    $this->report($definition->origin, $error->diagnosticCode, $error->getMessage());
                    continue;
                }
            }
            $this->outputs[$key] = new OutputKey($definition, $spec, $value);
        }
    }

    private function normalize(string $key, Spec $spec, string $text, array $origin): mixed
    {
        $values = $spec->values();
        if ($spec->kind !== 'list') {
            $value = parseScalar($spec->kind, $text, $values);
            if ($value === null) {
                throw invalidValue($key, $spec->kind, $values, $spec->has('secret') ? MASK : stringNotation($text));
            }
        } else {
            $value = [];
            $items = trim($text, ' ') === '' ? [] : array_map(static fn ($item) => trim($item, ' '), explode(',', $text));
            if (in_array('', $items, true)) {
                $this->report($origin, 'W_EMPTY_ITEM', "$key: empty list item ignored");
            }
            $itemKind = $spec->get('item', 'string');
            foreach ($items as $item) {
                if ($item === '') {
                    continue;
                }
                $parsed = parseScalar($itemKind, $item, $values);
                if ($parsed === null) {
                    $display = 'item ' . ($spec->has('secret') ? MASK : stringNotation($item));
                    throw invalidValue($key, $itemKind, $values, $display);
                }
                $value[] = $parsed;
            }
            if ($spec->has('unique')) {
                $seen = $unique = [];
                foreach ($value as $item) {
                    $notation = valueNotation($itemKind, null, $item);
                    if (!isset($seen[$notation])) {
                        $seen[$notation] = true;
                        $unique[] = $item;
                    }
                }
                if (count($unique) < count($value)) {
                    $this->report($origin, 'W_DUPLICATE_ITEM', "$key: duplicate items removed");
                }
                $value = $unique;
            }
        }
        if ($spec->has('range')) {
            checkRange($key, $spec, $value);
        }
        return $value;
    }

    private function checkOrder(): void
    {
        $remove = [];
        foreach (orderedKeys(array_keys($this->outputs)) as $key) {
            $output = $this->outputs[$key];
            if ($output->spec === null || !$output->spec->has('le')) {
                continue;
            }
            $limitKey = splitKey($key)[0] . '.' . $output->spec->get('le');
            $limit = $this->outputs[$limitKey] ?? null;
            if ($limit !== null && in_array($limit->kind, ['int', 'size', 'duration'], true) && $output->value > $limit->value) {
                $message = "$key: " . shown($output) . " is greater than $limitKey (" . shown($limit) . ')';
                $this->report($output->definition->origin, 'E_ORDER', $message);
                $remove[] = $key;
            }
        }
        foreach ($remove as $key) {
            unset($this->outputs[$key]);
        }
    }

    private function checkRequired(Schema $schema, array $sections, array $configured): void
    {
        foreach ($schema->specs as $spec) {
            if (!$spec->has('required')) {
                continue;
            }
            foreach ($schema->targetKeys($spec, $sections) as $key) {
                if (isset($configured[$key])) {
                    continue;
                }
                if (!$spec->has('when')) {
                    $this->report([$this->root, 0], 'E_REQUIRED', "$key is required");
                } else {
                    $conditionKey = splitKey($key)[0] . '.' . $spec->get('when');
                    $condition = $this->outputs[$conditionKey] ?? null;
                    if ($condition !== null && $condition->value === true) {
                        $this->report([$this->root, 0], 'E_REQUIRED', "$key is required when $conditionKey is true");
                    }
                }
            }
        }
    }

    private function checkFixed(array $earlier): void
    {
        foreach (orderedKeys(array_keys($this->outputs)) as $key) {
            $output = $this->outputs[$key];
            if ($output->spec === null || !$output->spec->has('fixed')) {
                continue;
            }
            foreach ($earlier as $reference) {
                if (isset($reference->outputs[$key])) {
                    if ($reference->outputs[$key]->notation !== $output->notation) {
                        $this->report($output->definition->origin, 'E_FIXED', "$key: value differs from profile {$reference->name}");
                        unset($this->outputs[$key]);
                    }
                    break;
                }
            }
        }
    }

    private function summarize(int $configuredCount): void
    {
        $this->diagnostics = array_values($this->reported);
        usort($this->diagnostics, static fn ($a, $b) => strcmp($a[0], $b[0]) ?: ($a[1] <=> $b[1]) ?: strcmp($a[2], $b[2]) ?: strcmp($a[3], $b[3]));
        foreach ($this->diagnostics as $diagnostic) {
            if (str_starts_with($diagnostic[2], 'E_')) {
                ++$this->errors;
            } else {
                ++$this->warnings;
            }
        }
        foreach (orderedKeys(array_keys($this->outputs)) as $key) {
            $definition = $this->outputs[$key]->definition;
            if (count($definition->history) >= 2) {
                $this->overridden[] = [$key, $definition->history];
            }
            match ($definition->origin[0]) {
                'manifest' => ++$this->manifestKeys,
                'schema' => ++$this->defaultKeys,
                default => ++$this->documentKeys,
            };
        }
        $this->dropped = $configuredCount - count($this->outputs);
    }
}

final class ProfileDiff
{
    public string $first;
    public string $second;
    public array $entries = [];
    public int $added = 0;
    public int $removed = 0;
    public int $changed = 0;

    public function __construct(Profile $first, Profile $second)
    {
        $this->first = $first->name;
        $this->second = $second->name;
        foreach (orderedKeys(array_keys($first->outputs + $second->outputs)) as $key) {
            $before = $first->outputs[$key] ?? null;
            $after = $second->outputs[$key] ?? null;
            if ($before === null) {
                ++$this->added;
                $this->entries[] = ['+', $key, $before, $after];
            } elseif ($after === null) {
                ++$this->removed;
                $this->entries[] = ['-', $key, $before, $after];
            } elseif ($before->notation !== $after->notation) {
                ++$this->changed;
                $this->entries[] = ['~', $key, $before, $after];
            }
        }
    }
}

function main(): void
{
    $schema = new Schema('input/schema.txt');
    $library = new DocumentLibrary('input/conf');
    $profiles = $diffs = [];
    foreach (file('input/manifest.txt', FILE_IGNORE_NEW_LINES) as $index => $line) {
        $profile = new Profile($index + 1, $line);
        $profile->process($schema, $library, $profiles);
        if ($profiles !== []) {
            $diffs[] = new ProfileDiff($profiles[count($profiles) - 1], $profile);
        }
        $profiles[] = $profile;
    }
    writeOutputs('output', $profiles, $diffs);
}

main();
