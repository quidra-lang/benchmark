'use strict';

const fs = require('node:fs');
const { readData } = require('./ratings');
const { buildNeighborhoods, select } = require('./neighborhood');
const { dot, trainSvd, trainAls } = require('./factorization');
const { clip, errorMetrics, trainingRmse, rankingMetrics } = require('./evaluation');
const { real, writeLines } = require('./report');

const METHODS = ['GLOBAL', 'BASELINE', 'USER_KNN', 'ITEM_KNN', 'SLOPE_ONE', 'SVD', 'ALS'];
const RANKINGS = ['POPULAR', ...METHODS.slice(1)];

function compareText(first, second) {
  return first < second ? -1 : first > second ? 1 : 0;
}

function sections(parts) {
  const lines = [];
  parts.forEach((part, index) => {
    if (index > 0) lines.push('');
    for (const line of part) lines.push(line);
  });
  return lines;
}

function valuePairs(names, values) {
  return names.map((name, index) => name + ' ' + real(values[index])).join(' ');
}

function groupNumber(count, boundaries) {
  let group = 0;
  while (group < boundaries.length && count >= boundaries[group]) group++;
  return group;
}

function trainBaseline(data) {
  const userBias = data.users.map(() => 0);
  const itemBias = data.items.map(() => 0);
  const predict = (user, item) => (data.mean + userBias[user]) + itemBias[item];
  const history = [];
  for (let sweep = 1; sweep <= 10; sweep++) {
    data.items.forEach((item, index) => {
      let total = 0;
      for (const row of item.entries) total += row.rating - data.mean - userBias[row.u];
      itemBias[index] = total / (data.settings.itemReg + item.count);
    });
    data.users.forEach((user, index) => {
      let total = 0;
      for (const row of user.entries) total += row.rating - data.mean - itemBias[row.i];
      userBias[index] = total / (data.settings.userReg + user.count);
    });
    history.push({ method: 'BASELINE', epoch: sweep, rmse: trainingRmse(data.train, predict) });
  }
  return { userBias, itemBias, predict, history };
}

function neighborPrediction(data, user, item, method, count) {
  const userBased = method === 2;
  const entries = userBased ? data.items[item].entries : data.users[user].entries;
  const groups = userBased ? data.users : data.items;
  const similarities = userBased ? data.neighborhoods.users[user] : data.neighborhoods.items[item];
  const candidates = [];
  for (const row of entries) {
    const source = userBased ? row.u : row.i;
    const edge = similarities[source];
    if (edge !== null && edge.similarity > data.settings.minSimilarity) {
      candidates.push({ ...edge, index: source, id: groups[source].id, rating: row.rating });
    }
  }
  const neighbors = select(candidates, count);
  if (neighbors.length === 0) {
    return { raw: data.baseline.predict(user, item), fallback: true, neighbors, similaritySum: 0, top: null };
  }
  let numerator = 0;
  let denominator = 0;
  for (const neighbor of neighbors) {
    numerator += neighbor.similarity * (neighbor.rating - groups[neighbor.index].mean);
    denominator += neighbor.similarity;
  }
  const mean = userBased ? data.users[user].mean : data.items[item].mean;
  return { raw: mean + numerator / denominator, fallback: false, neighbors, similaritySum: denominator, top: neighbors[0].id };
}

function predict(data, user, item, method, count = data.settings.neighbors) {
  if (method === 2 || method === 3) return neighborPrediction(data, user, item, method, count);
  if (method === 4) {
    let numerator = 0;
    let denominator = 0;
    for (const row of data.users[user].entries) {
      const common = data.neighborhoods.common[item][row.i];
      if (common === 0) continue;
      const deviation = data.neighborhoods.difference[item][row.i] / (common + data.settings.shrinkage);
      numerator += (deviation + row.rating) * common;
      denominator += common;
    }
    return denominator === 0 ? { raw: data.baseline.predict(user, item), fallback: true }
      : { raw: numerator / denominator, fallback: false };
  }
  let raw;
  if (method === 0) raw = data.mean;
  else if (method === 1) raw = data.baseline.predict(user, item);
  else if (method === 5) raw = data.svd.predict(user, item);
  else raw = data.als.predict(user, item);
  return { raw, fallback: false };
}

function predictTest(data) {
  return data.test.map(row => METHODS.map((name, method) => {
    const result = predict(data, row.u, row.i, method);
    const clipped = clip(result.raw);
    return { ...result, clipped, error: clipped - row.rating };
  }));
}

function rankedLists(data, user) {
  if (data.rankCache.has(user)) return data.rankCache.get(user);
  const rated = data.users[user].ratings;
  const candidates = data.items.map((item, index) => index).filter(item => !rated.has(item));
  const lists = [data.popularity.filter(item => !rated.has(item)).map(item => ({ item }))];
  for (let method = 1; method < METHODS.length; method++) {
    const ranked = candidates.map(item => ({ item, prediction: predict(data, user, item, method) }));
    ranked.sort((a, b) => b.prediction.raw - a.prediction.raw || data.items[a.item].id - data.items[b.item].id);
    lists.push(ranked);
  }
  data.rankCache.set(user, lists);
  return lists;
}

function testMetrics(data) {
  return METHODS.map((name, method) => {
    const values = data.results.map(row => row[method]);
    const metrics = errorMetrics(values.map(value => value.error));
    return { ...metrics, clipped: values.filter(value => value.raw < 1 || value.raw > 5).length,
      fallback: values.filter(value => value.fallback).length };
  });
}

function countSummary(groups) {
  const counts = groups.map(group => group.count).sort((a, b) => a - b);
  const middle = Math.floor(counts.length / 2);
  const median = counts.length % 2 === 1 ? counts[middle] : (counts[middle - 1] + counts[middle]) / 2;
  return `min ${counts[0]} median ${real(median)} max ${counts.at(-1)}`;
}

function summaryReport(data) {
  const histogram = Array(5).fill(0);
  for (const row of data.train) histogram[row.rating - 1]++;
  let userPairs = 0;
  let userUsable = 0;
  for (let first = 0; first < data.users.length; first++) {
    for (let second = first + 1; second < data.users.length; second++) {
      const edge = data.neighborhoods.users[first][second];
      if (edge !== null) {
        userPairs++;
        if (edge.similarity > data.settings.minSimilarity) userUsable++;
      }
    }
  }
  let itemPairs = 0;
  let itemUsable = 0;
  let slopePairs = 0;
  for (let first = 0; first < data.items.length; first++) {
    for (let second = first + 1; second < data.items.length; second++) {
      const edge = data.neighborhoods.items[first][second];
      if (edge !== null) {
        itemPairs++;
        if (edge.similarity > data.settings.minSimilarity) itemUsable++;
      }
      if (data.neighborhoods.common[first][second] > 0) slopePairs++;
    }
  }
  return [
    `data users ${data.users.length} items ${data.items.length} catalog ${data.catalog.size} ratings ${data.train.length} test ${data.test.length}`,
    `density ${real(data.train.length / (data.users.length * data.items.length))} global_mean ${real(data.mean)}`,
    `histogram ${histogram.join(' ')}`, `user_ratings ${countSummary(data.users)}`, `item_ratings ${countSummary(data.items)}`,
    `timestamps first ${data.firstTime} last ${data.lastTime}`, `cold_items ${data.catalog.size - data.items.length}`,
    `similarities user_pairs ${userPairs} usable ${userUsable} item_pairs ${itemPairs} usable ${itemUsable} slope_pairs ${slopePairs}`
  ];
}

function genreReport(data) {
  const names = [...new Set(data.items.flatMap(item => item.genres))].sort(compareText);
  const lines = ['genre_stats'];
  for (const genre of names) {
    let items = 0;
    let ratings = 0;
    let high = 0;
    for (const item of data.items) {
      if (!item.genres.includes(genre)) continue;
      items++;
      ratings += item.count;
      for (const row of item.entries) if (row.rating >= 4) high++;
    }
    lines.push(`genre ${genre} items ${items} ratings ${ratings} high ${high}`);
  }
  return lines;
}

function timeReport(data) {
  const count = data.settings.timeBuckets;
  const buckets = Array.from({ length: count }, () => ({ count: 0, users: new Set(), sum: 0 }));
  for (const row of data.train) {
    const index = Number(BigInt(row.time - data.firstTime) * BigInt(count) / BigInt(data.lastTime - data.firstTime + 1));
    const bucket = buckets[index];
    bucket.count++;
    bucket.users.add(row.u);
    bucket.sum += row.rating;
  }
  return [`time_buckets ${count}`, ...buckets.map((bucket, index) =>
    `bucket ${index + 1} ratings ${bucket.count} users ${bucket.users.size} mean ${real(bucket.count ? bucket.sum / bucket.count : null)}`)];
}

function generalizationReport(data) {
  const methods = [0, 1, 5, 6];
  const training = [trainingRmse(data.train, () => data.mean), data.baseline.history.at(-1).rmse,
    data.svd.history.at(-1).rmse, data.als.history.at(-1).rmse];
  return ['generalization', ...methods.map((method, index) =>
    `${METHODS[method]} train ${real(training[index])} test ${real(data.metrics[method].rmse)} gap ${real(data.metrics[method].rmse - training[index])}`)];
}

function neighborhoodReport(data) {
  const lines = [`neighborhoods k ${data.settings.neighbors}`];
  for (const method of [2, 3]) {
    let count = 0;
    let neighbors = 0;
    let similarity = 0;
    for (const row of data.results) {
      const result = row[method];
      if (result.fallback) continue;
      count++;
      neighbors += result.neighbors.length;
      similarity += result.similaritySum / result.neighbors.length;
    }
    lines.push(`${METHODS[method]} predictions ${data.test.length} with_neighbors ${count} mean_neighbors ${real(count ? neighbors / count : null)} mean_similarity ${real(count ? similarity / count : null)}`);
  }
  return lines;
}

function predictionStatistics(data) {
  let actualSum = 0;
  for (const row of data.test) actualSum += row.rating;
  const actualMean = actualSum / data.test.length;
  let actualSquared = 0;
  for (const row of data.test) actualSquared += (row.rating - actualMean) * (row.rating - actualMean);
  const actualConstant = data.test.every(row => row.rating === data.test[0].rating);
  const lines = [`prediction_stats actual mean ${real(actualMean)} std ${real(Math.sqrt(actualSquared / data.test.length))}`];
  for (let method = 0; method < METHODS.length; method++) {
    let total = 0;
    for (const row of data.results) total += row[method].clipped;
    const mean = total / data.test.length;
    let squared = 0;
    let product = 0;
    data.results.forEach((row, index) => {
      const difference = row[method].clipped - mean;
      squared += difference * difference;
      product += difference * (data.test[index].rating - actualMean);
    });
    const constant = data.results.every(row => row[method].clipped === data.results[0][method].clipped);
    const correlation = constant || actualConstant ? null : product / Math.sqrt(squared * actualSquared);
    lines.push(`${METHODS[method]} mean ${real(mean)} std ${real(Math.sqrt(squared / data.test.length))} correlation ${real(correlation)}`);
  }
  return lines;
}

function errorBinReport(data) {
  const lines = ['error_bins edges 0.5 1.0 1.5 2.0'];
  for (let method = 0; method < METHODS.length; method++) {
    const counts = Array(5).fill(0);
    for (const row of data.results) {
      const error = Math.abs(row[method].error);
      const bin = [0.5, 1, 1.5, 2].findIndex(edge => error < edge);
      counts[bin < 0 ? 4 : bin]++;
    }
    lines.push(`${METHODS[method]} ${counts.join(' ')}`);
  }
  return lines;
}

function comparisonReport(data) {
  const lines = ['comparison'];
  for (let first = 0; first < METHODS.length; first++) {
    for (let second = first + 1; second < METHODS.length; second++) {
      let wins = 0;
      let ties = 0;
      let losses = 0;
      for (const row of data.results) {
        const a = Math.abs(row[first].error);
        const b = Math.abs(row[second].error);
        if (a < b) wins++;
        else if (a === b) ties++;
        else losses++;
      }
      lines.push(`${METHODS[first]} ${METHODS[second]} wins ${wins} ties ${ties} losses ${losses}`);
    }
  }
  return lines;
}

function errorsFor(data, indices, measure) {
  return METHODS.map((name, method) => errorMetrics(indices.map(index => data.results[index][method].error))[measure]);
}

function errorGroups(data, kind, boundaries) {
  const groups = Array.from({ length: boundaries.length + 1 }, () => []);
  data.test.forEach((row, index) => {
    const count = kind === 'user' ? data.users[row.u].count : data.items[row.i].count;
    groups[groupNumber(count, boundaries)].push(index);
  });
  const lines = [`${kind}_groups bounds ${boundaries.join(' ')}`];
  groups.forEach((indices, group) => {
    const low = group === 0 ? 1 : boundaries[group - 1];
    const high = group === boundaries.length ? '-' : boundaries[group] - 1;
    lines.push(`group ${group + 1} from ${low} to ${high} pairs ${indices.length} ${valuePairs(METHODS, errorsFor(data, indices, 'rmse'))}`);
  });
  return lines;
}

function ratingGroups(data) {
  const lines = ['by_rating'];
  for (let rating = 1; rating <= 5; rating++) {
    const indices = data.test.filter(row => row.rating === rating).map(row => row.index);
    lines.push(`rating ${rating} pairs ${indices.length} ${valuePairs(METHODS, errorsFor(data, indices, 'mae'))}`);
  }
  return lines;
}

function genreErrors(data) {
  const names = [...new Set(data.test.flatMap(row => data.items[row.i].genres))].sort(compareText);
  const lines = ['genres'];
  for (const genre of names) {
    const indices = data.test.filter(row => data.items[row.i].genres.includes(genre)).map(row => row.index);
    lines.push(`genre ${genre} pairs ${indices.length} ${valuePairs(METHODS, errorsFor(data, indices, 'rmse'))}`);
  }
  return lines;
}

function rankMetrics(data, user, method, cutoff) {
  return rankingMetrics(rankedLists(data, user)[method].map(entry => entry.item), data.relevant.get(user), cutoff);
}

function rankingReport(data) {
  let relevant = 0;
  for (const user of data.evaluated) relevant += data.relevant.get(user).size;
  const users = data.evaluated.length;
  const lines = [`ranking users ${users} relevant ${relevant}`];
  for (const cutoff of data.settings.cutoffs) {
    lines.push(`cutoff ${cutoff}`);
    for (let method = 0; method < RANKINGS.length; method++) {
      let hits = 0;
      let recall = 0;
      let ndcg = 0;
      let averagePrecision = 0;
      let reciprocalRank = 0;
      let hitUsers = 0;
      for (const user of data.evaluated) {
        const metrics = rankMetrics(data, user, method, cutoff);
        hits += metrics.hits;
        recall += metrics.recall;
        ndcg += metrics.ndcg;
        averagePrecision += metrics.ap;
        reciprocalRank += metrics.rr;
        if (metrics.hits > 0) hitUsers++;
      }
      lines.push(`  ${RANKINGS[method]} precision ${real(hits / (cutoff * users))} recall ${real(recall / users)} ndcg ${real(ndcg / users)} map ${real(averagePrecision / users)} mrr ${real(reciprocalRank / users)} hit_rate ${real(hitUsers / users)}`);
    }
  }
  return lines;
}

function beyondAccuracyReport(data) {
  const count = data.settings.topN;
  const users = data.evaluated.length;
  const lines = [`beyond_accuracy top_n ${count} head ${data.popular.size}`];
  for (let method = 0; method < RANKINGS.length; method++) {
    const covered = new Set();
    let diversity = 0;
    let novelty = 0;
    let popularity = 0;
    let longTail = 0;
    let similarity = 0;
    for (const user of data.evaluated) {
      const list = rankedLists(data, user)[method].slice(0, count);
      const genres = new Set();
      let userNovelty = 0;
      for (const entry of list) {
        const item = data.items[entry.item];
        covered.add(entry.item);
        for (const genre of item.genres) genres.add(genre);
        userNovelty += Math.log2(data.users.length / item.count);
        popularity += item.count;
        if (!data.popular.has(entry.item)) longTail++;
      }
      diversity += genres.size;
      novelty += userNovelty / count;
      let userSimilarity = 0;
      for (let first = 0; first < count - 1; first++) {
        for (let second = first + 1; second < count; second++) {
          userSimilarity += data.neighborhoods.items[list[first].item][list[second].item]?.similarity ?? 0;
        }
      }
      similarity += userSimilarity / (count * (count - 1) / 2);
    }
    lines.push(`${RANKINGS[method]} coverage ${real(covered.size / data.items.length)} diversity ${real(diversity / users)} novelty ${real(novelty / users)} popularity ${real(popularity / (count * users))} long_tail ${real(longTail / (count * users))} similarity ${real(similarity / users)}`);
  }
  return lines;
}

function rankingGroupReport(data) {
  const boundaries = data.settings.userGroups;
  const lines = [`ranking_groups top_n ${data.settings.topN} bounds ${boundaries.join(' ')}`];
  for (let group = 0; group <= boundaries.length; group++) {
    const users = data.evaluated.filter(user => groupNumber(data.users[user].count, boundaries) === group);
    const values = RANKINGS.map((name, method) => {
      let total = 0;
      for (const user of users) total += rankMetrics(data, user, method, data.settings.topN).ndcg;
      return users.length ? total / users.length : null;
    });
    lines.push(`group ${group + 1} users ${users.length} ${valuePairs(RANKINGS, values)}`);
  }
  return lines;
}

function agreementReport(data) {
  const count = data.settings.topN;
  const lines = [`agreement top_n ${count}`];
  for (let first = 0; first < RANKINGS.length; first++) {
    for (let second = first + 1; second < RANKINGS.length; second++) {
      let total = 0;
      for (const user of data.evaluated) {
        const lists = rankedLists(data, user);
        const other = new Set(lists[second].slice(0, count).map(entry => entry.item));
        let intersection = 0;
        for (const entry of lists[first].slice(0, count)) if (other.has(entry.item)) intersection++;
        total += intersection / (2 * count - intersection);
      }
      lines.push(`${RANKINGS[first]} ${RANKINGS[second]} jaccard ${real(total / data.evaluated.length)}`);
    }
  }
  return lines;
}

function neighborGridReport(data) {
  const lines = ['neighbor_grid'];
  const best = [null, null];
  for (const count of data.settings.neighborGrid) {
    const values = [2, 3].map((method, index) => {
      const errors = data.test.map(row => clip(predict(data, row.u, row.i, method, count).raw) - row.rating);
      const rmse = errorMetrics(errors).rmse;
      if (best[index] === null || rmse < best[index].rmse) best[index] = { count, rmse };
      return rmse;
    });
    lines.push(`k ${count} USER_KNN ${real(values[0])} ITEM_KNN ${real(values[1])}`);
  }
  lines.push(`best USER_KNN ${best[0].count} ITEM_KNN ${best[1].count}`);
  return lines;
}

function biasReport(data) {
  const lines = ['biases'];
  for (const kind of ['item', 'user']) {
    const groups = kind === 'item' ? data.items : data.users;
    const biases = kind === 'item' ? data.baseline.itemBias : data.baseline.userBias;
    for (const direction of ['high', 'low']) {
      const order = groups.map((group, index) => index).sort((a, b) =>
        (direction === 'high' ? biases[b] - biases[a] : biases[a] - biases[b]) || groups[a].id - groups[b].id);
      for (const index of order.slice(0, data.settings.listSize)) {
        const group = groups[index];
        lines.push(`${kind}_${direction} ${group.id} bias ${real(biases[index])} count ${group.count} mean ${real(group.mean)}${kind === 'item' ? ' ' + group.title : ''}`);
      }
    }
  }
  return lines;
}

function evaluationReport(data) {
  const rating = ['rating_metrics', ...METHODS.map((name, method) => {
    const metrics = data.metrics[method];
    return `${name} rmse ${real(metrics.rmse)} mae ${real(metrics.mae)} clipped ${metrics.clipped} fallback ${metrics.fallback}`;
  })];
  return sections([summaryReport(data), genreReport(data), timeReport(data), rating, generalizationReport(data),
    neighborhoodReport(data), predictionStatistics(data), errorBinReport(data), comparisonReport(data),
    errorGroups(data, 'user', data.settings.userGroups), errorGroups(data, 'item', data.settings.itemGroups),
    ratingGroups(data), genreErrors(data), rankingReport(data), beyondAccuracyReport(data), rankingGroupReport(data),
    agreementReport(data), neighborGridReport(data), biasReport(data)]);
}

function favoriteGenres(data, user, predicate) {
  const counts = new Map();
  for (const row of data.users[user].entries) {
    if (!predicate(row.rating)) continue;
    for (const genre of data.items[row.i].genres) counts.set(genre, (counts.get(genre) ?? 0) + 1);
  }
  return [...counts].sort((a, b) => b[1] - a[1] || compareText(a[0], b[0])).slice(0, 3);
}

function popularityLine(data, item, rank) {
  const value = data.items[item];
  return `  ${rank} ${value.id} count ${value.count} mean ${real(value.mean)} ${value.title}`;
}

function recommendationReport(data) {
  const parts = [];
  for (const id of data.settings.recommendUsers) {
    const user = data.userIndex.get(id);
    if (user === undefined) {
      parts.push([`user ${id} unknown`, 'list POPULAR',
        ...data.popularity.slice(0, data.settings.topN).map((item, index) => popularityLine(data, item, index + 1))]);
      continue;
    }
    const value = data.users[user];
    const liked = favoriteGenres(data, user, rating => rating >= 4);
    const disliked = favoriteGenres(data, user, rating => rating <= 2);
    const genreText = entries => entries.length ? entries.map(entry => entry.join(' ')).join(' ') : '-';
    const recent = value.entries.slice().sort((a, b) => b.time - a.time || a.item - b.item).slice(0, 3);
    const lines = [`user ${id} ratings ${value.count} mean ${real(value.mean)} bias ${real(data.baseline.userBias[user])}`,
      `liked_genres ${genreText(liked)}`, `disliked_genres ${genreText(disliked)}`,
      `recent ${recent.map(row => `${row.item} ${row.rating}`).join(' ')}`];
    const candidates = [];
    data.neighborhoods.users[user].forEach((edge, index) => {
      if (edge !== null && edge.similarity > data.settings.minSimilarity) candidates.push({ ...edge, id: data.users[index].id });
    });
    for (const neighbor of select(candidates, data.settings.listSize)) {
      lines.push(`neighbor ${neighbor.id} similarity ${real(neighbor.similarity)} common ${neighbor.common}`);
    }
    data.test.forEach((row, index) => {
      if (row.u === user) lines.push(`heldout ${row.item} actual ${row.rating} ${data.results[index].map(result => real(result.clipped)).join(' ')}`);
    });
    const likedNames = new Set(liked.map(entry => entry[0]));
    rankedLists(data, user).forEach((ranked, method) => {
      const list = ranked.slice(0, data.settings.topN);
      const matches = list.filter(entry => data.items[entry.item].genres.some(genre => likedNames.has(genre))).length;
      lines.push(`list ${RANKINGS[method]} genre_match ${matches}`);
      list.forEach((entry, index) => {
        const item = data.items[entry.item];
        if (method === 0) lines.push(popularityLine(data, entry.item, index + 1));
        else {
          const via = method === 2 || method === 3 ? ` via ${entry.prediction.top ?? '-'}` : '';
          lines.push(`  ${index + 1} ${item.id} ${real(entry.prediction.raw)}${via} ${item.title}`);
        }
      });
    });
    parts.push(lines);
  }
  return sections(parts);
}

function similarItemReport(data) {
  const parts = [];
  const count = data.settings.listSize;
  for (const id of data.settings.similarItems) {
    const index = data.itemIndex.get(id);
    const item = data.items[index];
    const lines = [`item ${id} ratings ${item.count} mean ${real(item.mean)} bias ${real(data.baseline.itemBias[index])} genres ${item.genreText} title ${item.title}`, 'cosine'];
    const cosine = [];
    const factors = [];
    const common = [];
    const deviations = [];
    data.items.forEach((other, second) => {
      if (second === index) return;
      const edge = data.neighborhoods.items[index][second];
      if (edge !== null) cosine.push({ ...edge, id: other.id, item: other });
      const firstVector = data.svd.itemFactors[index];
      const secondVector = data.svd.itemFactors[second];
      const similarity = dot(firstVector, secondVector) / Math.sqrt(dot(firstVector, firstVector) * dot(secondVector, secondVector));
      factors.push({ id: other.id, item: other, similarity });
      const shared = data.neighborhoods.common[index][second];
      if (shared > 0) {
        common.push({ id: other.id, item: other, common: shared });
        const difference = data.neighborhoods.difference[second][index];
        deviations.push({ id: other.id, item: other, common: shared, difference, deviation: difference / (shared + data.settings.shrinkage) });
      }
    });
    select(cosine, count).forEach((entry, rank) => lines.push(`  ${rank + 1} ${entry.id} similarity ${real(entry.similarity)} common ${entry.common} ${entry.item.title}`));
    lines.push('factors');
    select(factors, count).forEach((entry, rank) => lines.push(`  ${rank + 1} ${entry.id} similarity ${real(entry.similarity)} ${entry.item.title}`));
    lines.push('co_rated');
    common.sort((a, b) => b.common - a.common || a.id - b.id).slice(0, count)
      .forEach((entry, rank) => lines.push(`  ${rank + 1} ${entry.id} common ${entry.common} ${entry.item.title}`));
    lines.push('slope_one');
    deviations.sort((a, b) => b.deviation - a.deviation || b.common - a.common || a.id - b.id).slice(0, count)
      .forEach((entry, rank) => lines.push(`  ${rank + 1} ${entry.id} difference ${entry.difference} common ${entry.common} ${entry.item.title}`));
    parts.push(lines);
  }
  return sections(parts);
}

function main() {
  const data = readData();
  data.baseline = trainBaseline(data);
  data.neighborhoods = buildNeighborhoods(data);
  data.svd = trainSvd(data);
  data.als = trainAls(data, data.baseline.predict);
  data.results = predictTest(data);
  data.metrics = testMetrics(data);
  data.firstTime = Math.min(...data.train.map(row => row.time));
  data.lastTime = Math.max(...data.train.map(row => row.time));
  data.popularity = data.items.map((item, index) => index).sort((a, b) =>
    data.items[b].count - data.items[a].count || data.items[b].mean - data.items[a].mean || data.items[a].id - data.items[b].id);
  data.popular = new Set(data.popularity.slice(0, Math.floor(data.items.length / 5)));
  data.rankCache = new Map();
  data.relevant = new Map();
  for (const row of data.test) {
    if (row.rating < 4) continue;
    if (!data.relevant.has(row.u)) data.relevant.set(row.u, new Set());
    data.relevant.get(row.u).add(row.i);
  }
  data.evaluated = data.users.map((user, index) => index).filter(user => data.relevant.has(user));
  const predictions = ['user,item,actual,' + METHODS.join(',')];
  data.test.forEach((row, index) => predictions.push([row.user, row.item, row.rating,
    ...data.results[index].map(result => real(result.clipped))].join(',')));
  const evaluation = evaluationReport(data);
  const recommendations = recommendationReport(data);
  const similar = similarItemReport(data);
  const history = [...data.baseline.history, ...data.svd.history, ...data.als.history];
  const training = ['method,epoch,train_rmse', ...history.map(entry => `${entry.method},${entry.epoch},${real(entry.rmse)}`)];
  fs.mkdirSync('output', { recursive: true });
  writeLines('predictions.csv', predictions);
  writeLines('evaluation.txt', evaluation);
  writeLines('recommendations.txt', recommendations);
  writeLines('similar_items.txt', similar);
  writeLines('training_log.csv', training);
}

if (require.main === module) main();
