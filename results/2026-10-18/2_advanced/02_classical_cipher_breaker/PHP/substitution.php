<?php
declare(strict_types=1);

namespace CipherBenchmark;

function modulo(int $number, int $modulus = 26): int
{
    return ($number % $modulus + $modulus) % $modulus;
}

function inverse(int $number): int
{
    for ($i = 1; $i < 26; $i++) {
        if (($i * $number) % 26 === 1) {
            return $i;
        }
    }
    throw new \LogicException('Invalid affine key');
}

function applySubstitution(string $text, string $cipher, string $key, bool $encrypt): string
{
    $a = 1;
    $b = 0;
    if ($cipher === 'caesar') {
        $b = (int) $key;
    } elseif ($cipher === 'affine') {
        [$a, $b] = array_map('intval', explode(',', $key));
    }
    $inverse = $cipher === 'affine' ? inverse($a) : 1;
    $plain = [];
    $index = 0;
    $output = '';
    for ($i = 0, $length = strlen($text); $i < $length; $i++) {
        $char = $text[$i];
        if (!letter($char)) {
            $output .= $char;
            continue;
        }
        $x = value($char);
        $shift = 0;
        if ($cipher === 'vigenere') {
            $shift = value($key[$index % strlen($key)]);
        } elseif ($cipher === 'autokey') {
            $shift = $index < strlen($key) ? value($key[$index])
                : $plain[$index - strlen($key)];
        }
        $y = match ($cipher) {
            'caesar' => modulo($x + ($encrypt ? $b : -$b)),
            'affine' => $encrypt ? modulo($a * $x + $b) : modulo($inverse * ($x - $b)),
            'vigenere', 'autokey' => modulo($x + ($encrypt ? $shift : -$shift)),
            default => throw new \LogicException('Unknown cipher'),
        };
        $plain[] = $encrypt ? $x : $y;
        $output .= chr((ord($char) >= 97 ? 97 : 65) + $y);
        $index++;
    }
    return $output;
}
