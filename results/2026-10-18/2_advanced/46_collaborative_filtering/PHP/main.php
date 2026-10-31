<?php

require_once __DIR__ . '/ratings.php';
require_once __DIR__ . '/neighborhood.php';
require_once __DIR__ . '/evaluation.php';
require_once __DIR__ . '/factorization.php';
require_once __DIR__ . '/report.php';

const METHODS = ['GLOBAL', 'BASELINE', 'USER_KNN', 'ITEM_KNN', 'SLOPE_ONE', 'SVD', 'ALS'];
const RANKINGS = ['POPULAR', 'BASELINE', 'USER_KNN', 'ITEM_KNN', 'SLOPE_ONE', 'SVD', 'ALS'];

function sections(array $parts): array
{
    $lines = [];
    foreach ($parts as $index => $part) {
        if ($index > 0) {
            $lines[] = '';
        }
        foreach ($part as $line) {
            $lines[] = $line;
        }
    }
    return $lines;
}

function valuePairs(array $names, array $values): string
{
    $pairs = [];
    foreach ($names as $index => $name) {
        $pairs[] = $name . ' ' . formatReal($values[$index]);
    }
    return implode(' ', $pairs);
}

function groupNumber(int $count, array $boundaries): int
{
    $group = 0;
    while ($group < count($boundaries) && $count >= $boundaries[$group]) {
        $group++;
    }
    return $group;
}

function trainBaseline(object $data): object
{
    $userBias = array_fill(0, count($data->users), 0.0);
    $itemBias = array_fill(0, count($data->items), 0.0);
    $predict = function ($user, $item) use ($data, &$userBias, &$itemBias) {
        return ($data->mean + $userBias[$user]) + $itemBias[$item];
    };
    $history = [];
    for ($sweep = 1; $sweep <= 10; $sweep++) {
        foreach ($data->items as $index => $item) {
            $total = 0.0;
            foreach ($item->entries as $row) {
                $total += $row->rating - $data->mean - $userBias[$row->u];
            }
            $itemBias[$index] = $total / ($data->settings->itemReg + $item->count);
        }
        foreach ($data->users as $index => $user) {
            $total = 0.0;
            foreach ($user->entries as $row) {
                $total += $row->rating - $data->mean - $itemBias[$row->i];
            }
            $userBias[$index] = $total / ($data->settings->userReg + $user->count);
        }
        $history[] = (object) ['method' => 'BASELINE', 'epoch' => $sweep, 'rmse' => trainingRmse($data->train, $predict)];
    }
    return (object) compact('userBias', 'itemBias', 'predict', 'history');
}

function neighborPrediction(object $data, int $user, int $item, int $method, int $count): object
{
    $userBased = $method === 2;
    $entries = $userBased ? $data->items[$item]->entries : $data->users[$user]->entries;
    $groups = $userBased ? $data->users : $data->items;
    $similarities = $userBased ? $data->neighborhoods->users[$user] : $data->neighborhoods->items[$item];
    $candidates = [];
    foreach ($entries as $row) {
        $source = $userBased ? $row->u : $row->i;
        $edge = $similarities[$source];
        if ($edge !== null && $edge->similarity > $data->settings->minSimilarity) {
            $candidates[] = (object) ['similarity' => $edge->similarity, 'common' => $edge->common,
                'index' => $source, 'id' => $groups[$source]->id, 'rating' => $row->rating];
        }
    }
    $neighbors = selectNeighbors($candidates, $count);
    if (count($neighbors) === 0) {
        return (object) ['raw' => ($data->baseline->predict)($user, $item), 'fallback' => true, 'neighbors' => [], 'similaritySum' => 0.0, 'top' => null];
    }
    $numerator = 0.0;
    $denominator = 0.0;
    foreach ($neighbors as $neighbor) {
        $numerator += $neighbor->similarity * ($neighbor->rating - $groups[$neighbor->index]->mean);
        $denominator += $neighbor->similarity;
    }
    $mean = $userBased ? $data->users[$user]->mean : $data->items[$item]->mean;
    return (object) ['raw' => $mean + $numerator / $denominator, 'fallback' => false, 'neighbors' => $neighbors,
        'similaritySum' => $denominator, 'top' => $neighbors[0]->id];
}

function predict(object $data, int $user, int $item, int $method, ?int $count = null): object
{
    $count = $count ?? $data->settings->neighbors;
    if ($method === 2 || $method === 3) {
        return neighborPrediction($data, $user, $item, $method, $count);
    }
    if ($method === 4) {
        $numerator = 0.0;
        $denominator = 0;
        foreach ($data->users[$user]->entries as $row) {
            $common = $data->neighborhoods->common[$item][$row->i];
            if ($common === 0) {
                continue;
            }
            $deviation = $data->neighborhoods->difference[$item][$row->i] / ($common + $data->settings->shrinkage);
            $numerator += ($deviation + $row->rating) * $common;
            $denominator += $common;
        }
        return $denominator === 0
            ? (object) ['raw' => ($data->baseline->predict)($user, $item), 'fallback' => true]
            : (object) ['raw' => $numerator / $denominator, 'fallback' => false];
    }
    if ($method === 0) {
        $raw = $data->mean;
    } elseif ($method === 1) {
        $raw = ($data->baseline->predict)($user, $item);
    } elseif ($method === 5) {
        $raw = ($data->svd->predict)($user, $item);
    } else {
        $raw = ($data->als->predict)($user, $item);
    }
    return (object) ['raw' => $raw, 'fallback' => false];
}

function predictTest(object $data): array
{
    $results = [];
    foreach ($data->test as $row) {
        $values = [];
        foreach (METHODS as $method => $name) {
            $result = predict($data, $row->u, $row->i, $method);
            $result->clipped = clip($result->raw);
            $result->error = $result->clipped - $row->rating;
            $values[] = $result;
        }
        $results[] = $values;
    }
    return $results;
}

function rankedLists(object $data, int $user): array
{
    if (isset($data->rankCache[$user])) {
        return $data->rankCache[$user];
    }
    $rated = $data->users[$user]->ratings;
    $limit = max(array_merge([$data->settings->topN], $data->settings->cutoffs));
    $candidates = [];
    foreach ($data->items as $index => $item) {
        if (!isset($rated[$index])) {
            $candidates[] = $index;
        }
    }
    $popular = [];
    foreach ($data->popularity as $item) {
        if (!isset($rated[$item])) {
            $popular[] = (object) ['item' => $item];
        }
    }
    $lists = [array_slice($popular, 0, $limit)];
    for ($method = 1; $method < count(METHODS); $method++) {
        $ranked = [];
        foreach ($candidates as $item) {
            $result = predict($data, $user, $item, $method);
            $ranked[] = (object) ['item' => $item, 'prediction' => (object) ['raw' => $result->raw, 'top' => $result->top ?? null]];
        }
        usort($ranked, fn($a, $b) => ($b->prediction->raw <=> $a->prediction->raw) ?: ($data->items[$a->item]->id <=> $data->items[$b->item]->id));
        $lists[] = array_slice($ranked, 0, $limit);
    }
    $data->rankCache[$user] = $lists;
    return $lists;
}

function testMetrics(object $data): array
{
    $all = [];
    foreach (METHODS as $method => $name) {
        $errors = [];
        $clipped = 0;
        $fallback = 0;
        foreach ($data->results as $row) {
            $value = $row[$method];
            $errors[] = $value->error;
            if ($value->raw < 1 || $value->raw > 5) {
                $clipped++;
            }
            if ($value->fallback) {
                $fallback++;
            }
        }
        $metrics = errorMetrics($errors);
        $metrics->clipped = $clipped;
        $metrics->fallback = $fallback;
        $all[] = $metrics;
    }
    return $all;
}

function countSummary(array $groups): string
{
    $counts = array_map(fn($group) => $group->count, $groups);
    sort($counts, SORT_NUMERIC);
    $middle = intdiv(count($counts), 2);
    $median = count($counts) % 2 === 1 ? $counts[$middle] : ($counts[$middle - 1] + $counts[$middle]) / 2;
    return 'min ' . $counts[0] . ' median ' . formatReal($median) . ' max ' . $counts[count($counts) - 1];
}

function summaryReport(object $data): array
{
    $histogram = array_fill(0, 5, 0);
    foreach ($data->train as $row) {
        $histogram[$row->rating - 1]++;
    }
    $userPairs = $userUsable = $itemPairs = $itemUsable = $slopePairs = 0;
    for ($first = 0; $first < count($data->users); $first++) {
        for ($second = $first + 1; $second < count($data->users); $second++) {
            $edge = $data->neighborhoods->users[$first][$second];
            if ($edge !== null) {
                $userPairs++;
                if ($edge->similarity > $data->settings->minSimilarity) {
                    $userUsable++;
                }
            }
        }
    }
    for ($first = 0; $first < count($data->items); $first++) {
        for ($second = $first + 1; $second < count($data->items); $second++) {
            $edge = $data->neighborhoods->items[$first][$second];
            if ($edge !== null) {
                $itemPairs++;
                if ($edge->similarity > $data->settings->minSimilarity) {
                    $itemUsable++;
                }
            }
            if ($data->neighborhoods->common[$first][$second] > 0) {
                $slopePairs++;
            }
        }
    }
    return [
        'data users ' . count($data->users) . ' items ' . count($data->items) . ' catalog ' . count($data->catalog) . ' ratings ' . count($data->train) . ' test ' . count($data->test),
        'density ' . formatReal(count($data->train) / (count($data->users) * count($data->items))) . ' global_mean ' . formatReal($data->mean),
        'histogram ' . implode(' ', $histogram), 'user_ratings ' . countSummary($data->users), 'item_ratings ' . countSummary($data->items),
        'timestamps first ' . $data->firstTime . ' last ' . $data->lastTime, 'cold_items ' . (count($data->catalog) - count($data->items)),
        'similarities user_pairs ' . $userPairs . ' usable ' . $userUsable . ' item_pairs ' . $itemPairs . ' usable ' . $itemUsable . ' slope_pairs ' . $slopePairs,
    ];
}

function genreReport(object $data): array
{
    $names = [];
    foreach ($data->items as $item) {
        foreach ($item->genres as $genre) {
            $names[$genre] = true;
        }
    }
    $names = array_keys($names);
    sort($names, SORT_STRING);
    $lines = ['genre_stats'];
    foreach ($names as $genre) {
        $items = $ratings = $high = 0;
        foreach ($data->items as $item) {
            if (!in_array($genre, $item->genres, true)) {
                continue;
            }
            $items++;
            $ratings += $item->count;
            foreach ($item->entries as $row) {
                if ($row->rating >= 4) {
                    $high++;
                }
            }
        }
        $lines[] = 'genre ' . $genre . ' items ' . $items . ' ratings ' . $ratings . ' high ' . $high;
    }
    return $lines;
}

function timeReport(object $data): array
{
    $count = $data->settings->timeBuckets;
    $buckets = array_fill(0, $count, null);
    foreach ($buckets as $index => $value) {
        $buckets[$index] = (object) ['count' => 0, 'users' => [], 'sum' => 0];
    }
    foreach ($data->train as $row) {
        $index = intdiv(($row->time - $data->firstTime) * $count, $data->lastTime - $data->firstTime + 1);
        $buckets[$index]->count++;
        $buckets[$index]->users[$row->u] = true;
        $buckets[$index]->sum += $row->rating;
    }
    $lines = ['time_buckets ' . $count];
    foreach ($buckets as $index => $bucket) {
        $lines[] = 'bucket ' . ($index + 1) . ' ratings ' . $bucket->count . ' users ' . count($bucket->users)
            . ' mean ' . formatReal($bucket->count ? $bucket->sum / $bucket->count : null);
    }
    return $lines;
}

function generalizationReport(object $data): array
{
    $methods = [0, 1, 5, 6];
    $training = [trainingRmse($data->train, fn($user, $item) => $data->mean),
        $data->baseline->history[count($data->baseline->history) - 1]->rmse,
        $data->svd->history[count($data->svd->history) - 1]->rmse,
        $data->als->history[count($data->als->history) - 1]->rmse];
    $lines = ['generalization'];
    foreach ($methods as $index => $method) {
        $test = $data->metrics[$method]->rmse;
        $lines[] = METHODS[$method] . ' train ' . formatReal($training[$index]) . ' test ' . formatReal($test) . ' gap ' . formatReal($test - $training[$index]);
    }
    return $lines;
}

function neighborhoodReport(object $data): array
{
    $lines = ['neighborhoods k ' . $data->settings->neighbors];
    foreach ([2, 3] as $method) {
        $count = $neighbors = 0;
        $similarity = 0.0;
        foreach ($data->results as $row) {
            $result = $row[$method];
            if ($result->fallback) {
                continue;
            }
            $count++;
            $neighbors += count($result->neighbors);
            $similarity += $result->similaritySum / count($result->neighbors);
        }
        $lines[] = METHODS[$method] . ' predictions ' . count($data->test) . ' with_neighbors ' . $count
            . ' mean_neighbors ' . formatReal($count ? $neighbors / $count : null)
            . ' mean_similarity ' . formatReal($count ? $similarity / $count : null);
    }
    return $lines;
}

function predictionStatistics(object $data): array
{
    $actualSum = 0;
    foreach ($data->test as $row) {
        $actualSum += $row->rating;
    }
    $actualMean = $actualSum / count($data->test);
    $actualSquared = 0.0;
    $actualConstant = true;
    foreach ($data->test as $row) {
        $actualSquared += ($row->rating - $actualMean) * ($row->rating - $actualMean);
        if ($row->rating !== $data->test[0]->rating) {
            $actualConstant = false;
        }
    }
    $lines = ['prediction_stats actual mean ' . formatReal($actualMean) . ' std ' . formatReal(sqrt($actualSquared / count($data->test)))];
    foreach (METHODS as $method => $name) {
        $total = 0.0;
        foreach ($data->results as $row) {
            $total += $row[$method]->clipped;
        }
        $mean = $total / count($data->test);
        $squared = $product = 0.0;
        $constant = true;
        foreach ($data->results as $index => $row) {
            $difference = $row[$method]->clipped - $mean;
            $squared += $difference * $difference;
            $product += $difference * ($data->test[$index]->rating - $actualMean);
            if ($row[$method]->clipped !== $data->results[0][$method]->clipped) {
                $constant = false;
            }
        }
        $correlation = $constant || $actualConstant ? null : $product / sqrt($squared * $actualSquared);
        $lines[] = $name . ' mean ' . formatReal($mean) . ' std ' . formatReal(sqrt($squared / count($data->test))) . ' correlation ' . formatReal($correlation);
    }
    return $lines;
}

function errorBinReport(object $data): array
{
    $lines = ['error_bins edges 0.5 1.0 1.5 2.0'];
    foreach (METHODS as $method => $name) {
        $counts = array_fill(0, 5, 0);
        foreach ($data->results as $row) {
            $error = abs($row[$method]->error);
            $bin = 4;
            foreach ([0.5, 1.0, 1.5, 2.0] as $index => $edge) {
                if ($error < $edge) {
                    $bin = $index;
                    break;
                }
            }
            $counts[$bin]++;
        }
        $lines[] = $name . ' ' . implode(' ', $counts);
    }
    return $lines;
}

function comparisonReport(object $data): array
{
    $lines = ['comparison'];
    for ($first = 0; $first < count(METHODS); $first++) {
        for ($second = $first + 1; $second < count(METHODS); $second++) {
            $wins = $ties = $losses = 0;
            foreach ($data->results as $row) {
                $a = abs($row[$first]->error);
                $b = abs($row[$second]->error);
                if ($a < $b) {
                    $wins++;
                } elseif ($a === $b) {
                    $ties++;
                } else {
                    $losses++;
                }
            }
            $lines[] = METHODS[$first] . ' ' . METHODS[$second] . ' wins ' . $wins . ' ties ' . $ties . ' losses ' . $losses;
        }
    }
    return $lines;
}

function errorsFor(object $data, array $indices, string $measure): array
{
    $values = [];
    foreach (METHODS as $method => $name) {
        $errors = [];
        foreach ($indices as $index) {
            $errors[] = $data->results[$index][$method]->error;
        }
        $metrics = errorMetrics($errors);
        $values[] = $metrics->$measure;
    }
    return $values;
}

function errorGroups(object $data, string $kind, array $boundaries): array
{
    $groups = array_fill(0, count($boundaries) + 1, []);
    foreach ($data->test as $index => $row) {
        $count = $kind === 'user' ? $data->users[$row->u]->count : $data->items[$row->i]->count;
        $groups[groupNumber($count, $boundaries)][] = $index;
    }
    $lines = [$kind . '_groups bounds ' . implode(' ', $boundaries)];
    foreach ($groups as $group => $indices) {
        $low = $group === 0 ? 1 : $boundaries[$group - 1];
        $high = $group === count($boundaries) ? '-' : $boundaries[$group] - 1;
        $lines[] = 'group ' . ($group + 1) . ' from ' . $low . ' to ' . $high . ' pairs ' . count($indices) . ' ' . valuePairs(METHODS, errorsFor($data, $indices, 'rmse'));
    }
    return $lines;
}

function ratingGroups(object $data): array
{
    $lines = ['by_rating'];
    for ($rating = 1; $rating <= 5; $rating++) {
        $indices = [];
        foreach ($data->test as $row) {
            if ($row->rating === $rating) {
                $indices[] = $row->index;
            }
        }
        $lines[] = 'rating ' . $rating . ' pairs ' . count($indices) . ' ' . valuePairs(METHODS, errorsFor($data, $indices, 'mae'));
    }
    return $lines;
}

function genreErrors(object $data): array
{
    $names = [];
    foreach ($data->test as $row) {
        foreach ($data->items[$row->i]->genres as $genre) {
            $names[$genre] = true;
        }
    }
    $names = array_keys($names);
    sort($names, SORT_STRING);
    $lines = ['genres'];
    foreach ($names as $genre) {
        $indices = [];
        foreach ($data->test as $row) {
            if (in_array($genre, $data->items[$row->i]->genres, true)) {
                $indices[] = $row->index;
            }
        }
        $lines[] = 'genre ' . $genre . ' pairs ' . count($indices) . ' ' . valuePairs(METHODS, errorsFor($data, $indices, 'rmse'));
    }
    return $lines;
}

function rankMetrics(object $data, int $user, int $method, int $cutoff): object
{
    $lists = rankedLists($data, $user);
    $items = array_map(fn($entry) => $entry->item, $lists[$method]);
    return rankingMetrics($items, $data->relevant[$user], $cutoff);
}

function rankingReport(object $data): array
{
    $relevant = 0;
    foreach ($data->evaluated as $user) {
        $relevant += count($data->relevant[$user]);
    }
    $users = count($data->evaluated);
    $lines = ['ranking users ' . $users . ' relevant ' . $relevant];
    foreach ($data->settings->cutoffs as $cutoff) {
        $lines[] = 'cutoff ' . $cutoff;
        foreach (RANKINGS as $method => $name) {
            $hits = $hitUsers = 0;
            $recall = $ndcg = $averagePrecision = $reciprocalRank = 0.0;
            foreach ($data->evaluated as $user) {
                $metrics = rankMetrics($data, $user, $method, $cutoff);
                $hits += $metrics->hits;
                $recall += $metrics->recall;
                $ndcg += $metrics->ndcg;
                $averagePrecision += $metrics->ap;
                $reciprocalRank += $metrics->rr;
                if ($metrics->hits > 0) {
                    $hitUsers++;
                }
            }
            $lines[] = '  ' . $name . ' precision ' . formatReal($hits / ($cutoff * $users)) . ' recall ' . formatReal($recall / $users)
                . ' ndcg ' . formatReal($ndcg / $users) . ' map ' . formatReal($averagePrecision / $users)
                . ' mrr ' . formatReal($reciprocalRank / $users) . ' hit_rate ' . formatReal($hitUsers / $users);
        }
    }
    return $lines;
}

function beyondAccuracyReport(object $data): array
{
    $count = $data->settings->topN;
    $users = count($data->evaluated);
    $lines = ['beyond_accuracy top_n ' . $count . ' head ' . count($data->popular)];
    foreach (RANKINGS as $method => $name) {
        $covered = [];
        $diversity = $popularity = $longTail = 0;
        $novelty = $similarity = 0.0;
        foreach ($data->evaluated as $user) {
            $lists = rankedLists($data, $user);
            $list = array_slice($lists[$method], 0, $count);
            $genres = [];
            $userNovelty = 0.0;
            foreach ($list as $entry) {
                $item = $data->items[$entry->item];
                $covered[$entry->item] = true;
                foreach ($item->genres as $genre) {
                    $genres[$genre] = true;
                }
                $userNovelty += log(count($data->users) / $item->count, 2);
                $popularity += $item->count;
                if (!isset($data->popular[$entry->item])) {
                    $longTail++;
                }
            }
            $diversity += count($genres);
            $novelty += $userNovelty / $count;
            $userSimilarity = 0.0;
            for ($first = 0; $first < $count - 1; $first++) {
                for ($second = $first + 1; $second < $count; $second++) {
                    $edge = $data->neighborhoods->items[$list[$first]->item][$list[$second]->item];
                    $userSimilarity += ($edge === null ? 0.0 : $edge->similarity);
                }
            }
            $similarity += $userSimilarity / intdiv($count * ($count - 1), 2);
        }
        $lines[] = $name . ' coverage ' . formatReal(count($covered) / count($data->items)) . ' diversity ' . formatReal($diversity / $users)
            . ' novelty ' . formatReal($novelty / $users) . ' popularity ' . formatReal($popularity / ($count * $users))
            . ' long_tail ' . formatReal($longTail / ($count * $users)) . ' similarity ' . formatReal($similarity / $users);
    }
    return $lines;
}

function rankingGroupReport(object $data): array
{
    $boundaries = $data->settings->userGroups;
    $lines = ['ranking_groups top_n ' . $data->settings->topN . ' bounds ' . implode(' ', $boundaries)];
    for ($group = 0; $group <= count($boundaries); $group++) {
        $users = [];
        foreach ($data->evaluated as $user) {
            if (groupNumber($data->users[$user]->count, $boundaries) === $group) {
                $users[] = $user;
            }
        }
        $values = [];
        foreach (RANKINGS as $method => $name) {
            $total = 0.0;
            foreach ($users as $user) {
                $total += rankMetrics($data, $user, $method, $data->settings->topN)->ndcg;
            }
            $values[] = count($users) ? $total / count($users) : null;
        }
        $lines[] = 'group ' . ($group + 1) . ' users ' . count($users) . ' ' . valuePairs(RANKINGS, $values);
    }
    return $lines;
}

function agreementReport(object $data): array
{
    $count = $data->settings->topN;
    $lines = ['agreement top_n ' . $count];
    for ($first = 0; $first < count(RANKINGS); $first++) {
        for ($second = $first + 1; $second < count(RANKINGS); $second++) {
            $total = 0.0;
            foreach ($data->evaluated as $user) {
                $lists = rankedLists($data, $user);
                $other = [];
                foreach (array_slice($lists[$second], 0, $count) as $entry) {
                    $other[$entry->item] = true;
                }
                $intersection = 0;
                foreach (array_slice($lists[$first], 0, $count) as $entry) {
                    if (isset($other[$entry->item])) {
                        $intersection++;
                    }
                }
                $total += $intersection / (2 * $count - $intersection);
            }
            $lines[] = RANKINGS[$first] . ' ' . RANKINGS[$second] . ' jaccard ' . formatReal($total / count($data->evaluated));
        }
    }
    return $lines;
}

function neighborGridReport(object $data): array
{
    $lines = ['neighbor_grid'];
    $best = [null, null];
    foreach ($data->settings->neighborGrid as $count) {
        $values = [];
        foreach ([2, 3] as $index => $method) {
            $errors = [];
            foreach ($data->test as $row) {
                $errors[] = clip(predict($data, $row->u, $row->i, $method, $count)->raw) - $row->rating;
            }
            $rmse = errorMetrics($errors)->rmse;
            if ($best[$index] === null || $rmse < $best[$index]->rmse) {
                $best[$index] = (object) ['count' => $count, 'rmse' => $rmse];
            }
            $values[] = $rmse;
        }
        $lines[] = 'k ' . $count . ' USER_KNN ' . formatReal($values[0]) . ' ITEM_KNN ' . formatReal($values[1]);
    }
    $lines[] = 'best USER_KNN ' . $best[0]->count . ' ITEM_KNN ' . $best[1]->count;
    return $lines;
}

function biasReport(object $data): array
{
    $lines = ['biases'];
    foreach (['item', 'user'] as $kind) {
        $groups = $kind === 'item' ? $data->items : $data->users;
        $biases = $kind === 'item' ? $data->baseline->itemBias : $data->baseline->userBias;
        foreach (['high', 'low'] as $direction) {
            $order = array_keys($groups);
            usort($order, function ($a, $b) use ($direction, $biases, $groups) {
                $comparison = $direction === 'high' ? $biases[$b] <=> $biases[$a] : $biases[$a] <=> $biases[$b];
                return $comparison ?: ($groups[$a]->id <=> $groups[$b]->id);
            });
            foreach (array_slice($order, 0, $data->settings->listSize) as $index) {
                $group = $groups[$index];
                $lines[] = $kind . '_' . $direction . ' ' . $group->id . ' bias ' . formatReal($biases[$index])
                    . ' count ' . $group->count . ' mean ' . formatReal($group->mean) . ($kind === 'item' ? ' ' . $group->title : '');
            }
        }
    }
    return $lines;
}

function evaluationReport(object $data): array
{
    $rating = ['rating_metrics'];
    foreach (METHODS as $method => $name) {
        $metrics = $data->metrics[$method];
        $rating[] = $name . ' rmse ' . formatReal($metrics->rmse) . ' mae ' . formatReal($metrics->mae)
            . ' clipped ' . $metrics->clipped . ' fallback ' . $metrics->fallback;
    }
    return sections([summaryReport($data), genreReport($data), timeReport($data), $rating, generalizationReport($data),
        neighborhoodReport($data), predictionStatistics($data), errorBinReport($data), comparisonReport($data),
        errorGroups($data, 'user', $data->settings->userGroups), errorGroups($data, 'item', $data->settings->itemGroups),
        ratingGroups($data), genreErrors($data), rankingReport($data), beyondAccuracyReport($data), rankingGroupReport($data),
        agreementReport($data), neighborGridReport($data), biasReport($data)]);
}

function favoriteGenres(object $data, int $user, callable $predicate): array
{
    $counts = [];
    foreach ($data->users[$user]->entries as $row) {
        if (!$predicate($row->rating)) {
            continue;
        }
        foreach ($data->items[$row->i]->genres as $genre) {
            $counts[$genre] = ($counts[$genre] ?? 0) + 1;
        }
    }
    $entries = [];
    foreach ($counts as $genre => $count) {
        $entries[] = [$genre, $count];
    }
    usort($entries, fn($a, $b) => ($b[1] <=> $a[1]) ?: strcmp($a[0], $b[0]));
    return array_slice($entries, 0, 3);
}

function popularityLine(object $data, int $item, int $rank): string
{
    $value = $data->items[$item];
    return '  ' . $rank . ' ' . $value->id . ' count ' . $value->count . ' mean ' . formatReal($value->mean) . ' ' . $value->title;
}

function recommendationReport(object $data): array
{
    $parts = [];
    foreach ($data->settings->recommendUsers as $id) {
        $user = $data->userIndex[$id] ?? null;
        if ($user === null) {
            $lines = ['user ' . $id . ' unknown', 'list POPULAR'];
            foreach (array_slice($data->popularity, 0, $data->settings->topN) as $rank => $item) {
                $lines[] = popularityLine($data, $item, $rank + 1);
            }
            $parts[] = $lines;
            continue;
        }
        $value = $data->users[$user];
        $liked = favoriteGenres($data, $user, fn($rating) => $rating >= 4);
        $disliked = favoriteGenres($data, $user, fn($rating) => $rating <= 2);
        $genreText = function ($entries) {
            if (count($entries) === 0) {
                return '-';
            }
            return implode(' ', array_map(fn($entry) => $entry[0] . ' ' . $entry[1], $entries));
        };
        $recent = $value->entries;
        usort($recent, fn($a, $b) => ($b->time <=> $a->time) ?: ($a->item <=> $b->item));
        $recent = array_slice($recent, 0, 3);
        $recentText = implode(' ', array_map(fn($row) => $row->item . ' ' . $row->rating, $recent));
        $lines = ['user ' . $id . ' ratings ' . $value->count . ' mean ' . formatReal($value->mean) . ' bias ' . formatReal($data->baseline->userBias[$user]),
            'liked_genres ' . $genreText($liked), 'disliked_genres ' . $genreText($disliked), 'recent ' . $recentText];
        $candidates = [];
        foreach ($data->neighborhoods->users[$user] as $index => $edge) {
            if ($edge !== null && $edge->similarity > $data->settings->minSimilarity) {
                $candidates[] = (object) ['similarity' => $edge->similarity, 'common' => $edge->common, 'id' => $data->users[$index]->id];
            }
        }
        foreach (selectNeighbors($candidates, $data->settings->listSize) as $neighbor) {
            $lines[] = 'neighbor ' . $neighbor->id . ' similarity ' . formatReal($neighbor->similarity) . ' common ' . $neighbor->common;
        }
        foreach ($data->test as $index => $row) {
            if ($row->u === $user) {
                $values = array_map(fn($result) => formatReal($result->clipped), $data->results[$index]);
                $lines[] = 'heldout ' . $row->item . ' actual ' . $row->rating . ' ' . implode(' ', $values);
            }
        }
        $likedNames = [];
        foreach ($liked as [$genre, $count]) {
            $likedNames[$genre] = true;
        }
        foreach (rankedLists($data, $user) as $method => $ranked) {
            $list = array_slice($ranked, 0, $data->settings->topN);
            $matches = 0;
            foreach ($list as $entry) {
                foreach ($data->items[$entry->item]->genres as $genre) {
                    if (isset($likedNames[$genre])) {
                        $matches++;
                        break;
                    }
                }
            }
            $lines[] = 'list ' . RANKINGS[$method] . ' genre_match ' . $matches;
            foreach ($list as $index => $entry) {
                $item = $data->items[$entry->item];
                if ($method === 0) {
                    $lines[] = popularityLine($data, $entry->item, $index + 1);
                } else {
                    $via = $method === 2 || $method === 3 ? ' via ' . ($entry->prediction->top ?? '-') : '';
                    $lines[] = '  ' . ($index + 1) . ' ' . $item->id . ' ' . formatReal($entry->prediction->raw) . $via . ' ' . $item->title;
                }
            }
        }
        $parts[] = $lines;
    }
    return sections($parts);
}

function similarItemReport(object $data): array
{
    $parts = [];
    $count = $data->settings->listSize;
    foreach ($data->settings->similarItems as $id) {
        $index = $data->itemIndex[$id];
        $item = $data->items[$index];
        $lines = ['item ' . $id . ' ratings ' . $item->count . ' mean ' . formatReal($item->mean) . ' bias ' . formatReal($data->baseline->itemBias[$index])
            . ' genres ' . $item->genreText . ' title ' . $item->title, 'cosine'];
        $cosine = $factors = $common = $deviations = [];
        foreach ($data->items as $second => $other) {
            if ($second === $index) {
                continue;
            }
            $edge = $data->neighborhoods->items[$index][$second];
            if ($edge !== null) {
                $cosine[] = (object) ['similarity' => $edge->similarity, 'common' => $edge->common, 'id' => $other->id, 'item' => $other];
            }
            $firstVector = $data->svd->itemFactors[$index];
            $secondVector = $data->svd->itemFactors[$second];
            $similarity = dot($firstVector, $secondVector) / sqrt(dot($firstVector, $firstVector) * dot($secondVector, $secondVector));
            $factors[] = (object) ['id' => $other->id, 'item' => $other, 'similarity' => $similarity];
            $shared = $data->neighborhoods->common[$index][$second];
            if ($shared > 0) {
                $common[] = (object) ['id' => $other->id, 'item' => $other, 'common' => $shared];
                $difference = $data->neighborhoods->difference[$second][$index];
                $deviations[] = (object) ['id' => $other->id, 'item' => $other, 'common' => $shared,
                    'difference' => $difference, 'deviation' => $difference / ($shared + $data->settings->shrinkage)];
            }
        }
        foreach (selectNeighbors($cosine, $count) as $rank => $entry) {
            $lines[] = '  ' . ($rank + 1) . ' ' . $entry->id . ' similarity ' . formatReal($entry->similarity) . ' common ' . $entry->common . ' ' . $entry->item->title;
        }
        $lines[] = 'factors';
        foreach (selectNeighbors($factors, $count) as $rank => $entry) {
            $lines[] = '  ' . ($rank + 1) . ' ' . $entry->id . ' similarity ' . formatReal($entry->similarity) . ' ' . $entry->item->title;
        }
        $lines[] = 'co_rated';
        usort($common, fn($a, $b) => ($b->common <=> $a->common) ?: ($a->id <=> $b->id));
        foreach (array_slice($common, 0, $count) as $rank => $entry) {
            $lines[] = '  ' . ($rank + 1) . ' ' . $entry->id . ' common ' . $entry->common . ' ' . $entry->item->title;
        }
        $lines[] = 'slope_one';
        usort($deviations, fn($a, $b) => ($b->deviation <=> $a->deviation) ?: (($b->common <=> $a->common) ?: ($a->id <=> $b->id)));
        foreach (array_slice($deviations, 0, $count) as $rank => $entry) {
            $lines[] = '  ' . ($rank + 1) . ' ' . $entry->id . ' difference ' . $entry->difference . ' common ' . $entry->common . ' ' . $entry->item->title;
        }
        $parts[] = $lines;
    }
    return sections($parts);
}

function main(): void
{
    $data = readData();
    $data->baseline = trainBaseline($data);
    $data->neighborhoods = buildNeighborhoods($data);
    $data->svd = trainSvd($data);
    $data->als = trainAls($data, $data->baseline->predict);
    $data->results = predictTest($data);
    $data->metrics = testMetrics($data);
    $times = array_map(fn($row) => $row->time, $data->train);
    $data->firstTime = min($times);
    $data->lastTime = max($times);
    $data->popularity = array_keys($data->items);
    usort($data->popularity, fn($a, $b) => ($data->items[$b]->count <=> $data->items[$a]->count)
        ?: (($data->items[$b]->mean <=> $data->items[$a]->mean) ?: ($data->items[$a]->id <=> $data->items[$b]->id)));
    $data->popular = [];
    foreach (array_slice($data->popularity, 0, intdiv(count($data->items), 5)) as $item) {
        $data->popular[$item] = true;
    }
    $data->rankCache = [];
    $data->relevant = [];
    foreach ($data->test as $row) {
        if ($row->rating >= 4) {
            $data->relevant[$row->u][$row->i] = true;
        }
    }
    $data->evaluated = [];
    foreach ($data->users as $index => $user) {
        if (isset($data->relevant[$index])) {
            $data->evaluated[] = $index;
        }
    }
    $predictions = ['user,item,actual,' . implode(',', METHODS)];
    foreach ($data->test as $index => $row) {
        $values = array_map(fn($result) => formatReal($result->clipped), $data->results[$index]);
        $predictions[] = implode(',', array_merge([$row->user, $row->item, $row->rating], $values));
    }
    $evaluation = evaluationReport($data);
    $recommendations = recommendationReport($data);
    $similar = similarItemReport($data);
    $history = array_merge($data->baseline->history, $data->svd->history, $data->als->history);
    $training = ['method,epoch,train_rmse'];
    foreach ($history as $entry) {
        $training[] = $entry->method . ',' . $entry->epoch . ',' . formatReal($entry->rmse);
    }
    writeLines('predictions.csv', $predictions);
    writeLines('evaluation.txt', $evaluation);
    writeLines('recommendations.txt', $recommendations);
    writeLines('similar_items.txt', $similar);
    writeLines('training_log.csv', $training);
}

main();
