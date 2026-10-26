<?php
namespace Segments;

function read_lines(string $path): array
{
    return file($path, FILE_IGNORE_NEW_LINES);
}

function read_params(string $path): array
{
    $settings = [];
    foreach (read_lines($path) as $line) {
        $fields = explode(' ', $line);
        $key = array_shift($fields);
        $settings[$key] = match ($key) {
            'METHODS' => $fields,
            'K_RANGE', 'ORDER_BINS' => array_map('intval', $fields),
            'OUTLIER_SD' => (float)$fields[0],
            default => (int)$fields[0],
        };
    }
    return $settings;
}

function read_transactions(string $path): array
{
    $data = ['rows' => [], 'customers' => [], 'count' => 0, 'duplicates' => 0, 'zero' => 0];
    $seen = [];
    foreach (array_slice(read_lines($path), 1) as $line) {
        [$customer, $day, $order, $category, $amount] = explode(',', $line);
        $data['count']++;
        $data['customers']['#'.$customer] = $customer;
        if (isset($seen['#'.$line])) {
            $data['duplicates']++;
        } elseif ((int)$amount === 0) {
            $data['zero']++;
        } else {
            $data['rows'][] = ['customer' => $customer, 'day' => (int)$day, 'order' => $order,
                'category' => $category, 'amount' => (int)$amount];
        }
        $seen['#'.$line] = true;
    }
    return $data;
}

function group_orders(array $rows, int $first, int $last): array
{
    $orders = [];
    foreach ($rows as $row) {
        if ($row['day'] < $first || $row['day'] > $last) continue;
        $key = '#'.$row['order'];
        if (!isset($orders[$key])) {
            $orders[$key] = ['id' => $row['order'], 'customer' => $row['customer'],
                'day' => $row['day'], 'net' => 0, 'rows' => []];
        }
        $orders[$key]['day'] = min($orders[$key]['day'], $row['day']);
        $orders[$key]['net'] += $row['amount'];
        $orders[$key]['rows'][] = $row;
    }
    return array_values($orders);
}

function orders_by_customer(array $orders): array
{
    $groups = [];
    foreach ($orders as $order) $groups['#'.$order['customer']][] = $order;
    return $groups;
}
