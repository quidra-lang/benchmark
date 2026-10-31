<?php
namespace Segments;

function read_rules(string $path): array
{
    $rules = [];
    foreach (read_lines($path) as $line) {
        $words = explode(' ', $line);
        $conditions = [];
        for ($index = 1; $index < count($words); $index += 3) {
            $conditions[] = ['feature' => array_search($words[$index], FEATURE_NAMES, true),
                'comparison' => $words[$index + 1], 'threshold' => (float)$words[$index + 2]];
        }
        $rules[] = ['name' => $words[0], 'conditions' => $conditions];
    }
    return $rules;
}

function rule_number(array $center, array $rules): int
{
    foreach ($rules as $index => $rule) {
        $holds = true;
        foreach ($rule['conditions'] as $condition) {
            $value = $center[$condition['feature']];
            if (!($condition['comparison'] === '>' ? $value > $condition['threshold'] : $value < $condition['threshold'])) {
                $holds = false;
                break;
            }
        }
        if ($holds) return $index;
    }
    throw new \LogicException('Missing fallback rule');
}

function original_center(array $center, array $scaling): array
{
    $values = [];
    foreach ($center as $feature => $component) {
        $value = $scaling[$feature]['mean'] + $scaling[$feature]['sd'] * $component;
        $values[] = root_feature($feature) ? $value * $value : $value;
    }
    return $values;
}
