<?php

function readLines(string $filename): array
{
    return file($filename, FILE_IGNORE_NEW_LINES);
}

function readData(): object
{
    $train = [];
    foreach (array_slice(readLines('input/ratings.csv'), 1) as $index => $line) {
        [$user, $item, $rating, $time] = array_map('intval', explode(',', $line));
        $train[] = (object) compact('user', 'item', 'rating', 'time', 'index');
    }
    $catalog = [];
    foreach (array_slice(readLines('input/items.csv'), 1) as $line) {
        [$id, $title, $genreText] = explode(',', $line);
        $id = (int) $id;
        $catalog[$id] = (object) ['id' => $id, 'title' => $title, 'genreText' => $genreText, 'genres' => explode('|', $genreText)];
    }
    $userIds = [];
    $itemIds = [];
    foreach ($train as $row) {
        $userIds[$row->user] = true;
        $itemIds[$row->item] = true;
    }
    $userIds = array_keys($userIds);
    $itemIds = array_keys($itemIds);
    sort($userIds, SORT_NUMERIC);
    sort($itemIds, SORT_NUMERIC);
    $users = [];
    $items = [];
    $userIndex = [];
    $itemIndex = [];
    foreach ($userIds as $index => $id) {
        $users[] = (object) ['id' => $id, 'entries' => []];
        $userIndex[$id] = $index;
    }
    foreach ($itemIds as $index => $id) {
        $item = clone $catalog[$id];
        $item->entries = [];
        $items[] = $item;
        $itemIndex[$id] = $index;
    }
    $total = 0;
    foreach ($train as $row) {
        $row->u = $userIndex[$row->user];
        $row->i = $itemIndex[$row->item];
        $users[$row->u]->entries[] = $row;
        $items[$row->i]->entries[] = $row;
        $total += $row->rating;
    }
    foreach ([[$users, 'i'], [$items, 'u']] as [$groups, $key]) {
        foreach ($groups as $group) {
            usort($group->entries, fn($a, $b) => $a->$key <=> $b->$key);
            $group->ratings = [];
            $group->sum = 0;
            foreach ($group->entries as $row) {
                $group->ratings[$row->$key] = $row->rating;
                $group->sum += $row->rating;
            }
            $group->count = count($group->entries);
            $group->mean = $group->sum / $group->count;
        }
    }
    $test = [];
    foreach (array_slice(readLines('input/test.csv'), 1) as $index => $line) {
        [$user, $item, $rating] = array_map('intval', explode(',', $line));
        $test[] = (object) ['user' => $user, 'item' => $item, 'rating' => $rating, 'index' => $index, 'u' => $userIndex[$user], 'i' => $itemIndex[$item]];
    }
    $names = [
        'NEIGHBORS' => 'neighbors', 'SHRINKAGE' => 'shrinkage', 'MIN_SIMILARITY' => 'minSimilarity', 'FACTORS' => 'factors',
        'LEARNING_RATE' => 'learningRate', 'REGULARIZATION' => 'regularization', 'EPOCHS' => 'epochs', 'ALS_REG' => 'alsReg',
        'ALS_ITERATIONS' => 'alsIterations', 'SEED' => 'seed', 'TOP_N' => 'topN', 'TIME_BUCKETS' => 'timeBuckets', 'LIST_SIZE' => 'listSize',
    ];
    $lists = ['CUTOFFS' => 'cutoffs', 'NEIGHBOR_GRID' => 'neighborGrid', 'USER_GROUPS' => 'userGroups', 'ITEM_GROUPS' => 'itemGroups',
        'RECOMMEND_USERS' => 'recommendUsers', 'SIMILAR_ITEMS' => 'similarItems'];
    $floats = ['MIN_SIMILARITY', 'LEARNING_RATE', 'REGULARIZATION', 'ALS_REG'];
    $settings = (object) [];
    foreach (readLines('input/params.txt') as $line) {
        $fields = explode(' ', $line);
        $keyword = array_shift($fields);
        if ($keyword === 'BIAS_REG') {
            $settings->itemReg = (float) $fields[0];
            $settings->userReg = (float) $fields[1];
        } elseif (isset($names[$keyword])) {
            $name = $names[$keyword];
            $settings->$name = in_array($keyword, $floats, true) ? (float) $fields[0] : (int) $fields[0];
        } else {
            $name = $lists[$keyword];
            $settings->$name = array_map('intval', $fields);
        }
    }
    return (object) ['train' => $train, 'test' => $test, 'catalog' => $catalog, 'users' => $users, 'items' => $items,
        'userIndex' => $userIndex, 'itemIndex' => $itemIndex, 'settings' => $settings, 'mean' => $total / count($train)];
}
