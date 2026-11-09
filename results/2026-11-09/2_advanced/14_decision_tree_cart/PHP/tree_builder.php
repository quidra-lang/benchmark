<?php

function half_text(int $value): string
{
    return intdiv($value, 2) . '.' . (5 * ($value % 2));
}

class Split
{
    public function __construct(public TreeAttribute $attribute, public int $point)
    {
    }

    public function goesLeft(int $value): bool
    {
        return $this->attribute->integer ? 2 * $value <= $this->point : $value === $this->point;
    }

    public function condition(bool $left): string
    {
        $attribute = $this->attribute;
        return $attribute->name . ($attribute->integer
            ? ($left ? ' <= ' : ' > ') . half_text($this->point)
            : ($left ? ' = ' : ' != ') . $attribute->values[$this->point]);
    }
}

class TreeNode
{
    public int $size;
    public int $prediction;
    public int $errors;
    public ?Split $split = null;
    public array $surrogates = [];
    public string $default = 'left';
    public ?TreeNode $left = null;
    public ?TreeNode $right = null;

    public function __construct(public int $number, public int $depth, public array $counts)
    {
        $this->size = array_sum($counts);
        $this->prediction = majority($counts);
        $this->errors = $this->size - $counts[$this->prediction];
    }
}

function candidates(TreeAttribute $attribute, array $rows): array
{
    $values = [];
    foreach ($rows as $row) {
        $values[$row->values[$attribute->index]] = true;
    }
    $values = array_keys($values);
    sort($values, SORT_NUMERIC);
    $result = [];
    if (count($values) < 2) {
        return $result;
    }
    foreach ($values as $index => $value) {
        if (!$attribute->integer || $index + 1 < count($values)) {
            $point = $attribute->integer ? $value + $values[$index + 1] : $value;
            $result[] = new Split($attribute, $point);
        }
    }
    return $result;
}

class TreeBuilder
{
    public function __construct(public array $attributes, public int $classCount, public array $settings)
    {
    }

    public function bestSplit(array $rows, array $attributes): ?array
    {
        $best = null;
        foreach ($attributes as $attribute) {
            foreach (candidates($attribute, $rows) as $split) {
                $left = [];
                $right = [];
                foreach ($rows as $row) {
                    if ($split->goesLeft($row->values[$attribute->index])) {
                        $left[] = $row;
                    } else {
                        $right[] = $row;
                    }
                }
                if (count($left) < $this->settings['min_samples_leaf'] || count($right) < $this->settings['min_samples_leaf']) {
                    continue;
                }
                $value = evaluation_value(class_counts($left, $this->classCount), class_counts($right, $this->classCount));
                if ($best === null || compare_fractions($value, $best['value']) > 0) {
                    $best = ['split' => $split, 'left' => $left, 'right' => $right, 'value' => $value];
                }
            }
        }
        return $best;
    }

    public function findSurrogates(array $rows, Split $primary, int $leftSize, int $rightSize): array
    {
        $result = [];
        foreach ($this->attributes as $attribute) {
            if ($attribute === $primary->attribute) {
                continue;
            }
            $best = null;
            foreach (candidates($attribute, $rows) as $split) {
                $agreement = 0;
                foreach ($rows as $row) {
                    if ($split->goesLeft($row->values[$attribute->index]) === $primary->goesLeft($row->values[$primary->attribute->index])) {
                        $agreement++;
                    }
                }
                $score = max($agreement, count($rows) - $agreement);
                if ($best === null || $score > $best['score']) {
                    $best = ['split' => $split, 'direction' => $agreement >= count($rows) - $agreement ? 'left' : 'right', 'score' => $score];
                }
            }
            if ($best !== null && $best['score'] > max($leftSize, $rightSize)) {
                $result[] = $best;
            }
        }
        usort($result, fn($a, $b) => $b['score'] <=> $a['score'] ?: $a['split']->attribute->index <=> $b['split']->attribute->index);
        return array_slice($result, 0, $this->settings['max_surrogates']);
    }

    public function grow(array $rows, int $number = 1, int $depth = 0): TreeNode
    {
        $node = new TreeNode($number, $depth, class_counts($rows, $this->classCount));
        if ($node->errors === 0 || $depth === $this->settings['max_depth'] || count($rows) < $this->settings['min_samples_split']) {
            return $node;
        }
        $best = $this->bestSplit($rows, $this->attributes);
        if ($best === null || !improves($best['value'], $node->counts)) {
            return $node;
        }
        $node->split = $best['split'];
        $node->default = count($best['left']) >= count($best['right']) ? 'left' : 'right';
        $node->surrogates = $this->findSurrogates($rows, $node->split, count($best['left']), count($best['right']));
        $node->left = $this->grow($best['left'], 2 * $number, $depth + 1);
        $node->right = $this->grow($best['right'], 2 * $number + 1, $depth + 1);
        return $node;
    }
}
