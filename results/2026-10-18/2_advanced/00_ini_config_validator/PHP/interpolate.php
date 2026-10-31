<?php
declare(strict_types=1);

namespace IniValidator;

final class Expander
{
    public array $results = [];
    public array $diagnostics = [];
    private array $inProgress = [];
    private array $cycleKeys = [];

    public function __construct(private array $values, private array $origins) {}

    private function report(string $key, string $code, string $message): void
    {
        [$document, $line] = $this->origins[$key];
        $this->diagnostics[] = [$document, $line, $code, $message];
    }

    public function expand(string $key): ?string
    {
        if (!array_key_exists($key, $this->results)) {
            $this->inProgress[] = $key;
            $result = $this->evaluate($key);
            array_pop($this->inProgress);
            $this->results[$key] = $result;
        }
        return $this->results[$key];
    }

    private function evaluate(string $key): ?string
    {
        $value = $this->values[$key];
        [$section] = splitKey($key);
        $result = '';
        for ($position = 0; $position < strlen($value);) {
            if (substr($value, $position, 2) !== '${') {
                $result .= $value[$position] === LITERAL_DOLLAR ? '$' : $value[$position];
                ++$position;
                continue;
            }
            $close = strpos($value, '}', $position + 2);
            if ($close === false || !isSectionName(substr($value, $position + 2, $close - $position - 2))) {
                $this->report($key, 'E_BAD_REF', "$key: invalid reference");
                return null;
            }
            $reference = substr($value, $position + 2, $close - $position - 2);
            $target = str_contains($reference, '.') ? $reference : $section . '.' . $reference;
            if (!array_key_exists($target, $this->values)) {
                $this->report($key, 'E_UNDEFINED', "$key: undefined reference $target");
                return null;
            }
            $cycleStart = array_search($target, $this->inProgress, true);
            if ($cycleStart !== false) {
                $path = array_slice($this->inProgress, $cycleStart);
                $path[] = $target;
                $this->report($target, 'E_CYCLE', 'interpolation cycle ' . implode(' -> ', $path));
                foreach ($path as $cycleKey) {
                    $this->cycleKeys[$cycleKey] = true;
                }
                $expanded = null;
            } else {
                $expanded = $this->expand($target);
            }
            if ($expanded === null) {
                if (!isset($this->cycleKeys[$key])) {
                    $this->report($key, 'E_DEPENDENCY', "$key: depends on failed key $target");
                }
                return null;
            }
            $result .= $expanded;
            $position = $close + 1;
        }
        return $result;
    }
}
