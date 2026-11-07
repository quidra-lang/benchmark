<?php
declare(strict_types=1);

namespace MailThreads;

const BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function strictBase64(string $text): ?string
{
    if (strlen($text) % 4 !== 0) {
        return null;
    }
    $data = rtrim($text, '=');
    if (strlen($text) - strlen($data) >= 3) {
        return null;
    }
    $result = '';
    $buffer = $bits = 0;
    for ($position = 0; $position < strlen($data); $position++) {
        $value = strpos(BASE64_ALPHABET, $data[$position]);
        if ($value === false) {
            return null;
        }
        $buffer = $buffer * 64 + $value;
        $bits += 6;
        if ($bits >= 8) {
            $bits -= 8;
            $result .= chr($buffer >> $bits);
            $buffer &= (1 << $bits) - 1;
        }
    }
    return $result;
}

function decodeBase64Body(string $text): ?string
{
    $data = strictBase64(str_replace([" ", "\t", "\n"], '', $text));
    if ($data === null) {
        return null;
    }
    $data = str_replace("\r\n", "\n", $data);
    for ($position = 0; $position < strlen($data); $position++) {
        $byte = ord($data[$position]);
        if ($byte !== 9 && $byte !== 10 && ($byte < 32 || $byte > 126)) {
            return null;
        }
    }
    return $data;
}

function decodeQuotedPrintable(string $text): array
{
    $lines = explode("\n", $text);
    $output = '';
    $error = false;
    foreach ($lines as $index => $line) {
        $line = rtrim($line, " \t");
        $soft = str_ends_with($line, '=');
        if ($soft) {
            $line = substr($line, 0, -1);
        }
        $position = 0;
        while ($position < strlen($line)) {
            $char = $line[$position];
            $decoded = null;
            if ($char === '=') {
                $digits = substr($line, $position + 1, 2);
                if (preg_match('/\A[0-9A-Fa-f]{2}\z/', $digits) === 1) {
                    $value = (int)hexdec($digits);
                    if ($value === 9 || $value >= 32 && $value <= 126) {
                        $decoded = chr($value);
                    }
                }
            }
            if ($decoded !== null) {
                $output .= $decoded;
                $position += 3;
            } else {
                $output .= $char;
                $error = $error || $char === '=';
                $position++;
            }
        }
        if (!$soft && $index + 1 < count($lines)) {
            $output .= "\n";
        }
    }
    return [$output, $error];
}
