<?php

function parseFactor($name) {
    if (preg_match('/^C\(([^)]+)\)$/', $name, $m)) {
        return ['name' => $name, 'column' => $m[1], 'kind' => 'categorical'];
    }
    if (preg_match('/^I\(([^)^]+)\^([23])\)$/', $name, $m)) {
        return ['name' => $name, 'column' => $m[1], 'kind' => 'power', 'power' => (int)$m[2]];
    }
    return ['name' => $name, 'column' => $name, 'kind' => 'numeric'];
}

function combinations($values, $count, $start = 0, $prefix = []) {
    if ($count === 0) return [$prefix];
    $result = [];
    for ($i = $start; $i <= count($values) - $count; $i++) {
        $next = $prefix;
        $next[] = $values[$i];
        foreach (combinations($values, $count - 1, $i + 1, $next) as $group) $result[] = $group;
    }
    return $result;
}

function parseFormula($line, $number) {
    $parts = explode(' weights=', $line);
    $original = $parts[0];
    $weight = $parts[1] ?? null;
    [$response, $expressions] = explode(' ~ ', $original);
    $terms = [];
    $seen = [];
    $factorColumns = [];
    foreach (explode(' + ', $expressions) as $expression) {
        $star = str_contains($expression, '*');
        $factors = array_map('parseFactor', explode($star ? '*' : ':', $expression));
        $expanded = [];
        if ($star) {
            for ($size = 1; $size <= count($factors); $size++) {
                foreach (combinations($factors, $size) as $group) $expanded[] = $group;
            }
        } else {
            $expanded[] = $factors;
        }
        foreach ($expanded as $group) {
            $names = array_column($group, 'name');
            $keyNames = $names;
            sort($keyNames, SORT_STRING);
            $key = implode('|', $keyNames);
            if (isset($seen[$key])) continue;
            $seen[$key] = true;
            $terms[] = ['id' => count($terms), 'name' => implode(':', $names), 'factors' => $group];
            foreach ($group as $factor) {
                if (!in_array($factor['column'], $factorColumns, true)) $factorColumns[] = $factor['column'];
            }
        }
    }
    $variables = $factorColumns;
    $variables[] = $response;
    if ($weight !== null) $variables[] = $weight;
    return compact('number', 'original', 'response', 'weight', 'terms', 'factorColumns', 'variables');
}

function contained($first, $second) {
    if (count($first['factors']) >= count($second['factors'])) return false;
    $names = array_column($second['factors'], 'name');
    foreach ($first['factors'] as $factor) {
        if (!in_array($factor['name'], $names, true)) return false;
    }
    return true;
}

function formatFormula($model, $terms) {
    return $model['response'] . ' ~ ' . ($terms ? implode(' + ', array_column($terms, 'name')) : '1');
}

function modelRows($model, $data) {
    $rows = [];
    foreach ($data['rows'] as $row) {
        $used = true;
        foreach ($model['variables'] as $name) if ($row['values'][$name] === null) $used = false;
        if ($used) $rows[] = $row;
    }
    $levels = [];
    foreach ($model['terms'] as $term) foreach ($term['factors'] as $factor) {
        $name = $factor['column'];
        if ($factor['kind'] !== 'categorical' || isset($levels[$name])) continue;
        $labels = [];
        foreach ($rows as $row) $labels[$row['values'][$name]] = true;
        $levels[$name] = array_keys($labels);
        sort($levels[$name], SORT_STRING);
    }
    return ['rows' => $rows, 'levels' => $levels];
}

function columnsFor($terms, $levels) {
    $columns = [['name' => '(Intercept)', 'term' => null, 'components' => []]];
    foreach ($terms as $term) {
        $tuples = [[]];
        foreach ($term['factors'] as $factor) {
            $components = [];
            if ($factor['kind'] === 'categorical') {
                foreach (array_slice($levels[$factor['column']], 1) as $level) {
                    $component = $factor;
                    $component['name'] .= $level;
                    $component['level'] = $level;
                    $components[] = $component;
                }
            } else {
                $components[] = $factor;
            }
            $next = [];
            foreach ($components as $component) foreach ($tuples as $tuple) {
                $tuple[] = $component;
                $next[] = $tuple;
            }
            $tuples = $next;
        }
        foreach ($tuples as $tuple) {
            $columns[] = ['name' => implode(':', array_column($tuple, 'name')), 'term' => $term['id'], 'components' => $tuple];
        }
    }
    return $columns;
}

function columnValues($columns, $row) {
    $values = [];
    foreach ($columns as $column) {
        $product = 1.0;
        foreach ($column['components'] as $component) {
            $raw = $row['values'][$component['column']];
            if ($component['kind'] === 'categorical') $value = $raw === $component['level'] ? 1.0 : 0.0;
            elseif ($component['kind'] === 'power') $value = $component['power'] === 2 ? $raw * $raw : $raw * $raw * $raw;
            else $value = $raw;
            $product *= $value;
        }
        $values[] = $product;
    }
    return $values;
}

function design($model, $rows, $levels, $terms) {
    $columns = columnsFor($terms, $levels);
    $matrix = $response = $weights = [];
    foreach ($rows as $row) {
        $matrix[] = columnValues($columns, $row);
        $response[] = $row['values'][$model['response']];
        $weights[] = $model['weight'] === null ? 1.0 : $row['values'][$model['weight']];
    }
    return compact('columns', 'matrix', 'response', 'weights');
}

function predictable($model, $levels, $row) {
    foreach ($model['factorColumns'] as $name) {
        $value = $row['values'][$name];
        if ($value === null || (isset($levels[$name]) && !in_array($value, $levels[$name], true))) return false;
    }
    return true;
}
