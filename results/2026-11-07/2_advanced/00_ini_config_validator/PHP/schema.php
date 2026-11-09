<?php
declare(strict_types=1);

namespace IniValidator;

function splitKey(string $key): array
{
    $dot = strrpos($key, '.');
    return [substr($key, 0, $dot), substr($key, $dot + 1)];
}

function orderedKeys(array $keys): array
{
    usort($keys, static function (string $a, string $b): int {
        [$sectionA, $nameA] = splitKey($a);
        [$sectionB, $nameB] = splitKey($b);
        return strcmp($sectionA, $sectionB) ?: strcmp($nameA, $nameB);
    });
    return $keys;
}

final class Spec
{
    public string $pattern;
    public string $kind;
    public string $key;
    public array $sectionParts;
    public bool $wildcard;
    public array $attributes = [];

    public function __construct(public int $line, array $words)
    {
        [$this->pattern, $this->kind] = $words;
        [$section, $this->key] = splitKey($this->pattern);
        $this->sectionParts = explode('.', $section);
        $this->wildcard = in_array('*', $this->sectionParts, true);
        foreach (array_slice($words, 2) as $attribute) {
            $parts = explode('=', $attribute, 2);
            $this->attributes[$parts[0]] = $parts[1] ?? '';
        }
    }

    public function has(string $name): bool
    {
        return array_key_exists($name, $this->attributes);
    }

    public function get(string $name, ?string $default = null): ?string
    {
        return $this->attributes[$name] ?? $default;
    }

    public function values(): array
    {
        return $this->has('values') ? explode(',', $this->get('values')) : [];
    }

    public function matches(string $section): bool
    {
        $parts = explode('.', $section);
        if (count($parts) !== count($this->sectionParts)) {
            return false;
        }
        foreach ($parts as $i => $part) {
            if ($this->sectionParts[$i] !== '*' && $this->sectionParts[$i] !== $part) {
                return false;
            }
        }
        return true;
    }
}

final class Schema
{
    public array $specs = [];
    private array $exact = [];

    public function __construct(string $path)
    {
        foreach (file($path, FILE_IGNORE_NEW_LINES) as $index => $line) {
            if (trim($line, ' ') === '' || str_starts_with($line, '#')) {
                continue;
            }
            $spec = new Spec($index + 1, explode(' ', $line));
            $this->specs[] = $spec;
            if (!$spec->wildcard) {
                $this->exact[$spec->pattern] = $spec;
            }
        }
    }

    public function specFor(string $key): ?Spec
    {
        if (isset($this->exact[$key])) {
            return $this->exact[$key];
        }
        [$section, $name] = splitKey($key);
        foreach ($this->specs as $spec) {
            if ($spec->wildcard && $spec->key === $name && $spec->matches($section)) {
                return $spec;
            }
        }
        return null;
    }

    public function targetKeys(Spec $spec, array $sections): array
    {
        if (!$spec->wildcard) {
            return [$spec->pattern];
        }
        sort($sections, SORT_STRING);
        $keys = [];
        foreach ($sections as $section) {
            $key = $section . '.' . $spec->key;
            if ($spec->matches($section) && $this->specFor($key) === $spec) {
                $keys[] = $key;
            }
        }
        return $keys;
    }
}
