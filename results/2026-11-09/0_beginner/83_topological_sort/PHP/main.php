<?php

function topological(array $courses, array $edges): array
{
    $indegree = array_fill_keys($courses, 0);
    $adjacency = array_fill_keys($courses, []);
    foreach ($edges as [$source, $target]) {
        $adjacency[$source][] = $target;
        $indegree[$target]++;
    }
    sort($courses, SORT_STRING);
    $order = [];
    $taken = [];
    while (true) {
        $ready = array_find($courses, fn($course) => !isset($taken[$course]) && $indegree[$course] === 0);
        if ($ready === null) {
            break;
        }
        $order[] = $ready;
        $taken[$ready] = true;
        foreach ($adjacency[$ready] as $target) {
            $indegree[$target]--;
        }
    }
    return [$order, array_diff($courses, $order)];
}

$courses1 = ['physics', 'algebra', 'graphics', 'programming', 'statistics', 'calculus', 'databases', 'algorithms'];
$edges1 = [
    ['calculus', 'physics'], ['algebra', 'calculus'], ['programming', 'algorithms'],
    ['algebra', 'statistics'], ['algorithms', 'databases'], ['statistics', 'databases'],
    ['calculus', 'graphics'], ['algorithms', 'graphics'], ['physics', 'graphics'],
];
$courses2 = ['music', 'ecology', 'art', 'geology', 'biology', 'chemistry'];
$edges2 = [
    ['music', 'art'], ['art', 'ecology'], ['biology', 'chemistry'], ['chemistry', 'ecology'],
    ['ecology', 'geology'], ['geology', 'chemistry'],
];
[$first] = topological($courses1, $edges1);
[$second, $remaining] = topological($courses2, $edges2);
echo 'order: ', implode(' -> ', $first), "\norder: ", implode(' -> ', $second), "\n";
echo 'cycle: ', implode(' ', $remaining), "\n";
