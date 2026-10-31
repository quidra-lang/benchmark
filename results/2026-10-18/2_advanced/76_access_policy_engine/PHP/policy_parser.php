<?php

function targetLiteral(string $text)
{
    if (str_starts_with($text, '"')) {
        return substr($text, 1, -1);
    }
    if ($text === 'true' || $text === 'false') {
        return $text === 'true';
    }
    return (int) $text;
}

function parseTarget(string $text): array
{
    $result = [];
    foreach (explode(' | ', $text) as $alternative) {
        $clauses = [];
        foreach (explode(' & ', $alternative) as $clause) {
            [$reference, $operation, $literal] = explode(' ', $clause, 3);
            $mandatory = str_ends_with($reference, '!');
            $clauses[] = (object) ['reference' => $mandatory ? substr($reference, 0, -1) : $reference,
                'mandatory' => $mandatory, 'operation' => $operation, 'literal' => targetLiteral($literal)];
        }
        $result[] = $clauses;
    }
    return $result;
}

function argumentsList(string $text): array
{
    if ($text === '') {
        return [];
    }
    $arguments = [];
    foreach (explode(';', $text) as $part) {
        $part = trim($part);
        $separator = strpos($part, '=');
        $arguments[] = (object) ['name' => substr($part, 0, $separator), 'expression' => parseExpression(substr($part, $separator + 1))];
    }
    return $arguments;
}

function readPolicies(): object
{
    $elements = [];
    $stack = [];
    foreach (file('input/policies.txt', FILE_IGNORE_NEW_LINES) as $raw) {
        $line = ltrim($raw, ' ');
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }
        $fields = explode(' ', $line);
        $keyword = $fields[0];
        if (in_array($keyword, ['POLICYSET', 'POLICY', 'RULE'], true)) {
            $parent = count($stack) ? $stack[count($stack) - 1] : null;
            $element = (object) ['kind' => strtolower($keyword), 'id' => $fields[1], 'parent' => $parent,
                'targets' => [], 'condition' => null, 'obligations' => [], 'advice' => [], 'children' => [], 'index' => count($elements)];
            if ($keyword === 'RULE') {
                $element->effect = $fields[2];
            } else {
                $element->algorithm = $fields[2];
            }
            if ($parent !== null) {
                $parent->children[] = $element;
            }
            $elements[] = $element;
            $stack[] = $element;
        } elseif ($keyword === 'END') {
            array_pop($stack);
        } else {
            $element = $stack[count($stack) - 1];
            if ($keyword === 'TARGET') {
                $element->targets[] = parseTarget(substr($line, 7));
            } elseif ($keyword === 'CONDITION') {
                $element->condition = parseExpression(substr($line, 10));
            } else {
                $item = (object) ['effect' => $fields[1], 'id' => $fields[2], 'arguments' => argumentsList(implode(' ', array_slice($fields, 3)))];
                if ($keyword === 'OBLIGATION') {
                    $element->obligations[] = $item;
                } else {
                    $element->advice[] = $item;
                }
            }
        }
    }
    $rules = array_values(array_filter($elements, fn($element) => $element->kind === 'rule'));
    return (object) ['root' => $elements[0], 'elements' => $elements, 'rules' => $rules];
}
