<?php

function lzwEncode(string $data): array
{
    $writer = new BitWriter();
    $stats = ['codes' => 0, 'clears' => 0, 'widths' => [0, 0, 0, 0], 'longest' => 0];
    $dictionary = [];
    $next = 258;
    $sinceClear = 0;
    $initialize = function () use (&$dictionary, &$next): void {
        $dictionary = [];
        for ($code = 0; $code < 256; $code++) {
            $dictionary["\0" . chr($code)] = $code;
        }
        $next = 258;
    };
    $emit = function (int $code, int $length = 0) use ($writer, &$stats, &$sinceClear): void {
        $width = min(12, bits(258 + $sinceClear));
        $writer->write($code, $width);
        $stats['codes']++;
        $stats['widths'][$width - 9]++;
        $stats['longest'] = max($stats['longest'], $length);
        if ($code === 256) {
            $stats['clears']++;
            $sinceClear = 0;
        } else {
            $sinceClear++;
        }
    };
    $initialize();
    $emit(256);
    $word = '';
    $size = strlen($data);
    for ($i = 0; $i < $size; $i++) {
        $character = $data[$i];
        $extended = $word . $character;
        if (isset($dictionary["\0" . $extended])) {
            $word = $extended;
        } else {
            $emit($dictionary["\0" . $word], strlen($word));
            $dictionary["\0" . $extended] = $next++;
            if ($next === 4096) {
                $emit(256);
                $initialize();
            }
            $word = $character;
        }
    }
    if ($word !== '') {
        $emit($dictionary["\0" . $word], strlen($word));
    }
    $emit(257);
    return ['payload' => $writer->finish(), 'statistics' => $stats];
}

function lzwDecode(string $payload, int $originalLength, string &$output): void
{
    $reader = new BitReader($payload);
    $dictionary = [];
    $next = 258;
    $previous = null;
    $sinceClear = 0;
    $initialize = function () use (&$dictionary, &$next, &$previous): void {
        $dictionary = [];
        for ($code = 0; $code < 256; $code++) {
            $dictionary[$code] = chr($code);
        }
        $next = 258;
        $previous = null;
    };
    $initialize();
    while (true) {
        $count = $sinceClear;
        $code = $reader->read(min(12, bits(258 + $count)));
        if ($code === 256) {
            $initialize();
            $sinceClear = 0;
            continue;
        }
        $sinceClear++;
        if ($code === 257) {
            if (strlen($output) < $originalLength) {
                throw new DecodingError('early_end');
            }
            return;
        }
        if ($count === 3838) {
            throw new DecodingError('bad_code');
        }
        if ($previous === null) {
            if ($code >= 256) {
                throw new DecodingError('bad_code');
            }
            $sequence = $dictionary[$code];
        } elseif ($code < $next) {
            $sequence = $dictionary[$code];
        } elseif ($code === $next) {
            $sequence = $previous . $previous[0];
        } else {
            throw new DecodingError('bad_code');
        }
        if (strlen($output) + strlen($sequence) > $originalLength) {
            throw new DecodingError('overrun');
        }
        $output .= $sequence;
        if ($previous !== null) {
            $dictionary[$next++] = $previous . $sequence[0];
        }
        $previous = $sequence;
    }
}
