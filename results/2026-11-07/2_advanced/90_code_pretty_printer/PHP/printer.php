<?php

function fits(int $remaining, array $candidate, array $rest): bool
{
    if ($remaining < 0)
        return false;
    $check = [$candidate];
    $next = count($rest) - 1;
    while (true) {
        if (!$check) {
            if ($next < 0)
                return true;
            $check[] = $rest[$next--];
        }
        [$indent, $mode, $d] = array_pop($check);
        switch ($d->kind) {
            case 'text':
                $remaining -= strlen($d->value);
                break;
            case 'if_break':
                $remaining -= strlen($mode === 'break' ? $d->value : $d->flat);
                break;
            case 'line':
                if ($mode === 'break')
                    return true;
                --$remaining;
                break;
            case 'softline':
                if ($mode === 'break')
                    return true;
                break;
            case 'hardline':
                return true;
            case 'concat':
                foreach (array_reverse($d->items) as $child)
                    $check[] = [$indent, $mode, $child];
                break;
            case 'group':
                $check[] = [$indent, $d->forced ? 'break' : $mode, $d->child];
                break;
            case 'nest':
            case 'align':
                $check[] = [$indent, $mode, $d->child];
                break;
        }
        if ($remaining < 0)
            return false;
    }
}

function layout(Doc $document, array $profile): array
{
    $result = [];
    $current = '';
    $pending = [];
    $stack = [[0, 'break', $document]];
    $finalize = function () use (&$result, &$current, &$pending, $profile): void {
        $out = rtrim($current, ' ');
        if ($pending) {
            $s = implode(' ', $pending);
            $q = $profile['comment_column'];
            if ($q > 0 && strlen($out) < ($q - 1) && ($q - 1 + strlen($s)) <= $profile['width'])
                $out .= str_repeat(' ', $q - 1 - strlen($out)) . $s;
            else
                $out .= ' ' . $s;
            $pending = [];
        }
        $result[] = $out;
    };
    while ($stack) {
        [$i, $mode, $d] = array_pop($stack);
        switch ($d->kind) {
            case 'text':
                $current .= $d->value;
                break;
            case 'if_break':
                $current .= $mode === 'break' ? $d->value : $d->flat;
                break;
            case 'line':
            case 'softline':
                if ($mode === 'flat') {
                    if ($d->kind === 'line')
                        $current .= ' ';
                    break;
                }
            case 'hardline':
                $finalize();
                $current = str_repeat(' ', $i);
                break;
            case 'concat':
                foreach (array_reverse($d->items) as $child)
                    $stack[] = [$i, $mode, $child];
                break;
            case 'nest':
                $stack[] = [$i + $d->amount, $mode, $d->child];
                break;
            case 'align':
                $stack[] = [strlen($current), $mode, $d->child];
                break;
            case 'suffix':
                $pending[] = $d->value;
                break;
            case 'group':
                $d->mode = $mode === 'flat'
                    ? 'flat'
                    : (
                        $d->forced
                            ? 'forced'
                            : (
                                fits($profile['width'] - strlen($current), [$i, 'flat', $d->child], $stack)
                                    ? 'flat'
                                    : 'break'
                            )
                    );
                $stack[] = [$i, $d->mode === 'flat' ? 'flat' : 'break', $d->child];
                break;
        }
    }
    $finalize();
    return $result;
}
