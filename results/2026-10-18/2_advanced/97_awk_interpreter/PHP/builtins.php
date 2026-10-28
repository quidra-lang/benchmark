<?php

final class RuntimeIssue extends RuntimeException
{
    public function __construct(
        public array $position,
        string $message,
    ) {
        parent::__construct($message);
    }
}

function formatOutput(array $arguments, array $position): string
{
    $fmt = toString($arguments[0]);
    $out = '';
    $i = 0;
    $arg = 1;
    $n = strlen($fmt);
    while ($i < $n) {
        if ($fmt[$i] !== '%') {
            $out .= $fmt[$i++];
            continue;
        }
        ++$i;
        if ($i < $n && $fmt[$i] === '%') {
            $out .= '%';
            ++$i;
            continue;
        }
        $flags = '';
        while ($i < $n && str_contains('-0', $fmt[$i]))
            $flags .= $fmt[$i++];
        $start = $i;
        while ($i < $n && ctype_digit($fmt[$i]))
            ++$i;
        $width = (int) substr($fmt, $start, $i - $start);
        $precision = null;
        if ($i < $n && $fmt[$i] === '.') {
            $start = ++$i;
            while ($i < $n && ctype_digit($fmt[$i]))
                ++$i;
            $precision = (int) substr($fmt, $start, $i - $start);
        }
        if ($i === $n || !str_contains('discxo', $fmt[$i]))
            throw new RuntimeIssue($position, 'invalid format');
        $conversion = $fmt[$i++];
        if (!isset($arguments[$arg]))
            throw new RuntimeIssue($position, 'not enough arguments');
        $v = $arguments[$arg++];
        $numeric = str_contains('dixo', $conversion);
        if ($numeric) {
            $integer = toNumber($v);
            $digits = match ($conversion) {
                'x' => dechex(abs($integer)),
                'o' => decoct(abs($integer)),
                default => (string) abs($integer),
            };
            if ($precision !== null)
                $digits =
                    $precision === 0 && $integer === 0 ? '' : str_pad($digits, $precision, '0', STR_PAD_LEFT);
            $body = ($integer < 0 ? '-' : '') . $digits;
        } elseif ($conversion === 's') {
            $body = toString($v);
            if ($precision !== null)
                $body = substr($body, 0, $precision);
        } else {
            if ($v->kind === 'number' || $v->kind === 'strnum') {
                $code = toNumber($v);
                if ($code !== 10 && ($code < 32 || $code > 126))
                    throw new RuntimeIssue($position, 'invalid character code');
                $body = chr($code);
            } else
                $body = substr(toString($v), 0, 1);
        }
        $missing = $width - strlen($body);
        if ($missing > 0) {
            if (str_contains($flags, '-'))
                $body .= str_repeat(' ', $missing);
            elseif ($numeric && str_contains($flags, '0') && $precision === null)
                $body = str_starts_with($body, '-')
                    ? '-' . str_repeat('0', $missing) . substr($body, 1)
                    : str_repeat('0', $missing) . $body;
            else
                $body = str_repeat(' ', $missing) . $body;
        }
        $out .= $body;
    }
    return $out;
}

function invokeBuiltin(string $name, array $args, array $position): AwkValue
{
    if ($name === 'sprintf')
        return vString(formatOutput($args, $position));
    if ($name === 'int')
        return vNumber(toNumber($args[0]));
    $s = toString($args[0]);
    if ($name === 'substr') {
        $start = toNumber($args[1]);
        $end = count($args) === 3 ? $start + toNumber($args[2]) : strlen($s) + 1;
        $start = max($start, 1);
        $end = min($end, strlen($s) + 1);
        return vString($end > $start ? substr($s, $start - 1, $end - $start) : '');
    }
    if ($name === 'index') {
        $needle = toString($args[1]);
        $found = $needle === '' ? false : strpos($s, $needle);
        return vNumber($found === false ? 0 : $found + 1);
    }
    return vString($name === 'toupper' ? strtoupper($s) : strtolower($s));
}
