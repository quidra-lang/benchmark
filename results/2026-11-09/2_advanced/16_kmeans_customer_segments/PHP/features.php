<?php
namespace Segments;

const FEATURE_NAMES = ['recency', 'frequency', 'monetary', 'basket', 'categories', 'tenure'];

function root_feature(int $feature): bool
{
    return $feature >= 1 && $feature <= 3;
}

function transform_values(array $raw): array
{
    return array_map(fn($feature) => root_feature($feature) ? sqrt($raw[$feature]) : (float)$raw[$feature], array_keys($raw));
}

function customer_features(array $orders, int $day): array
{
    $groups = orders_by_customer(array_values(array_filter($orders, fn($order) => $order['net'] > 0)));
    $keys = array_keys($groups);
    usort($keys, fn($a, $b) => strcmp(substr($a, 1), substr($b, 1)));
    $customers = [];
    foreach ($keys as $key) {
        $purchases = $groups[$key];
        $first = $last = $purchases[0]['day'];
        $spend = 0;
        $categories = [];
        foreach ($purchases as $order) {
            $first = min($first, $order['day']);
            $last = max($last, $order['day']);
            $spend += $order['net'];
            foreach ($order['rows'] as $row) $categories[$row['category']] = ($categories[$row['category']] ?? 0) + $row['amount'];
        }
        $monetary = $spend / 100;
        $frequency = count($purchases);
        $raw = [$day - $last, $frequency, $monetary, $monetary / $frequency,
            count(array_filter($categories, fn($amount) => $amount > 0)), $day - $first];
        $customers[] = ['id' => substr($key, 1), 'orders' => $purchases, 'spend' => $spend,
            'category_spend' => $categories, 'raw' => $raw, 'transformed' => transform_values($raw)];
    }
    return $customers;
}

function ordered_sum(array $values): float
{
    $total = 0.0;
    foreach ($values as $value) $total += $value;
    return $total;
}

function mean(array $values): float
{
    return ordered_sum($values) / count($values);
}

function sample_sd(array $values): float
{
    $average = mean($values);
    $total = 0.0;
    foreach ($values as $value) {
        $difference = $value - $average;
        $total += $difference * $difference;
    }
    return sqrt($total / (count($values) - 1));
}

function fit_scaling(array $customers): array
{
    $scaling = [];
    foreach (FEATURE_NAMES as $feature => $name) {
        $raw = array_map(fn($customer) => $customer['raw'][$feature], $customers);
        $transformed = array_map(fn($customer) => $customer['transformed'][$feature], $customers);
        $scaling[] = ['raw_mean' => mean($raw), 'raw_sd' => sample_sd($raw),
            'mean' => mean($transformed), 'sd' => sample_sd($transformed)];
    }
    return $scaling;
}

function standardize(array $values, array $scaling): array
{
    return array_map(fn($feature) => $scaling[$feature]['sd'] == 0 ? 0.0
        : ($values[$feature] - $scaling[$feature]['mean']) / $scaling[$feature]['sd'], array_keys($values));
}

function correlation(array $points, int $first, int $second): float
{
    $total = 0.0;
    foreach ($points as $point) $total += $point[$first] * $point[$second];
    return $total / (count($points) - 1);
}
