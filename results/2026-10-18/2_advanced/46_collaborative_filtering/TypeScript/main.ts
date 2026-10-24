import { mkdirSync } from 'node:fs';
import { readData, type Data, type Rating, type Profile } from './ratings.ts';
import { buildNeighborhoods, select } from './neighborhood.ts';
import { trainSvd, trainAls, dot, type LogEntry } from './factorization.ts';
import { clip, errorMetrics, trainingRmse, rankingMetrics } from './evaluation.ts';
import { real, writeLines } from './report.ts';

const METHODS = ['GLOBAL', 'BASELINE', 'USER_KNN', 'ITEM_KNN', 'SLOPE_ONE', 'SVD', 'ALS'] as const;
const RANKINGS = [
  'POPULAR',
  'BASELINE',
  'USER_KNN',
  'ITEM_KNN',
  'SLOPE_ONE',
  'SVD',
  'ALS',
] as const;
type Method = (typeof METHODS)[number];
type Ranking = (typeof RANKINGS)[number];
interface Prediction {
  value: number;
  fallback: boolean;
  top: number | null;
  similarities: number[];
}
interface ListEntry {
  i: number;
  prediction: Prediction | null;
}
function sum(v: number[]): number {
  let total = 0;
  for (const x of v) total += x;
  return total;
}
function compareText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
function mapped<K extends string, V>(keys: readonly K[], fn: (key: K) => V): Record<K, V> {
  return Object.fromEntries(keys.map((k) => [k, fn(k)])) as Record<K, V>;
}
function sections(parts: string[][]): string[] {
  return parts.flatMap((p, i) => (i ? ['', ...p] : p));
}
function pairs<T>(items: readonly T[]): [T, T][] {
  return items.flatMap((a, i) => items.slice(i + 1).map((b) => [a, b] as [T, T]));
}
function group(count: number, bounds: number[]): number {
  return bounds.filter((b) => count >= b).length;
}
function trainBaseline(data: Data) {
  const userBias = data.users.map(() => 0);
  const itemBias = data.items.map(() => 0);
  const history: LogEntry[] = [];
  const predict = (u: number, i: number) => data.mean + userBias[u] + itemBias[i];
  for (let epoch = 1; epoch <= 10; epoch++) {
    data.items.forEach((item, i) => {
      let total = 0;
      for (const r of item.entries) total += r.rating - data.mean - userBias[r.u];
      itemBias[i] = total / (data.settings.itemReg + item.count);
    });
    data.users.forEach((user, u) => {
      let total = 0;
      for (const r of user.entries) total += r.rating - data.mean - itemBias[r.i];
      userBias[u] = total / (data.settings.userReg + user.count);
    });
    history.push({ method: 'BASELINE', epoch, rmse: trainingRmse(data.train, predict) });
  }
  return { userBias, itemBias, predict, history };
}
function train(data: Data) {
  const baseline = trainBaseline(data);
  const svd = trainSvd(data);
  const als = trainAls(data, baseline.predict);
  const neighborhood = buildNeighborhoods(data);
  const popularity = data.items
    .map((_, i) => i)
    .sort(
      (a, b) =>
        data.items[b].count - data.items[a].count ||
        data.items[b].mean - data.items[a].mean ||
        data.items[a].id - data.items[b].id,
    );
  return { data, baseline, svd, als, neighborhood, popularity };
}
type Trained = ReturnType<typeof train>;
function predict(
  model: Trained,
  method: Method,
  u: number,
  i: number,
  k = model.data.settings.neighbors,
): Prediction {
  const { data: d, baseline, neighborhood: n } = model;
  const plain = (value: number): Prediction => ({
    value,
    fallback: false,
    top: null,
    similarities: [],
  });
  if (method === 'GLOBAL') return plain(d.mean);
  if (method === 'BASELINE') return plain(baseline.predict(u, i));
  if (method === 'SVD') return plain(model.svd.predict(u, i));
  if (method === 'ALS') return plain(model.als.predict(u, i));
  const fallback = (): Prediction => ({ ...plain(baseline.predict(u, i)), fallback: true });
  if (method === 'SLOPE_ONE') {
    let num = 0;
    let den = 0;
    for (const r of d.users[u].entries) {
      const c = n.common[i][r.i];
      if (!c) continue;
      num += (n.difference[i][r.i] / (c + d.settings.shrinkage) + r.rating) * c;
      den += c;
    }
    return den ? plain(num / den) : fallback();
  }
  const candidates: { id: number; index: number; similarity: number; rating: number }[] = [];
  if (method === 'USER_KNN') {
    for (const r of d.items[i].entries) {
      const s = n.users[u][r.u];
      if (s !== null && s.similarity > d.settings.minSimilarity) {
        candidates.push({ id: r.user, index: r.u, similarity: s.similarity, rating: r.rating });
      }
    }
  } else {
    for (const r of d.users[u].entries) {
      const s = n.items[i][r.i];
      if (s !== null && s.similarity > d.settings.minSimilarity) {
        candidates.push({ id: r.item, index: r.i, similarity: s.similarity, rating: r.rating });
      }
    }
  }
  const selected = select(candidates, k);
  if (!selected.length) return fallback();
  let num = 0;
  let den = 0;
  for (const s of selected) {
    const mean = method === 'USER_KNN' ? d.users[s.index].mean : d.items[s.index].mean;
    num += s.similarity * (s.rating - mean);
    den += s.similarity;
  }
  return {
    value: (method === 'USER_KNN' ? d.users[u].mean : d.items[i].mean) + num / den,
    fallback: false,
    top: selected[0].id,
    similarities: selected.map((s) => s.similarity),
  };
}
function testPredictions(model: Trained) {
  return model.data.test.map((rating) => {
    const predictions = mapped(METHODS, (m) => predict(model, m, rating.u, rating.i));
    const clipped = mapped(METHODS, (m) => clip(predictions[m].value));
    return {
      rating,
      predictions,
      clipped,
      errors: mapped(METHODS, (m) => clipped[m] - rating.rating),
    };
  });
}
type TestRow = ReturnType<typeof testPredictions>[number];
function listBuilder(model: Trained) {
  const cache = new Map<string, ListEntry[]>();
  return (u: number, method: Ranking): ListEntry[] => {
    const key = `${u}:${method}`;
    const found = cache.get(key);
    if (found) return found;
    const indices = model.popularity.filter((i) => !model.data.users[u].ratings.has(i));
    const entries = indices.map((i) => ({
      i,
      prediction: method === 'POPULAR' ? null : predict(model, method, u, i),
    }));
    if (method !== 'POPULAR') {
      entries.sort(
        (a, b) =>
          b.prediction!.value - a.prediction!.value ||
          model.data.items[a.i].id - model.data.items[b.i].id,
      );
    }
    cache.set(key, entries);
    return entries;
  };
}
type Lists = ReturnType<typeof listBuilder>;
function summaryParts(model: Trained): string[][] {
  const { data: d, neighborhood: n } = model;
  const histogram = [1, 2, 3, 4, 5].map((v) => d.train.filter((r) => r.rating === v).length);
  const countSummary = (profiles: Profile[]) => {
    const counts = profiles.map((p) => p.count).sort((a, b) => a - b);
    const m = Math.floor(counts.length / 2);
    return `min ${counts[0]} median ${real(counts.length % 2 ? counts[m] : (counts[m - 1] + counts[m]) / 2)} max ${counts[counts.length - 1]}`;
  };
  const first = Math.min(...d.train.map((r) => r.time));
  const last = Math.max(...d.train.map((r) => r.time));
  const userPairs = pairs(d.users.map((_, i) => i))
    .map(([a, b]) => n.users[a][b])
    .filter((s) => s !== null);
  const itemPairs = pairs(d.items.map((_, i) => i))
    .map(([a, b]) => n.items[a][b])
    .filter((s) => s !== null);
  const data = [
    `data users ${d.users.length} items ${d.items.length} catalog ${d.catalog.size} ratings ${d.train.length} test ${d.test.length}`,
    `density ${real(d.train.length / (d.users.length * d.items.length))} global_mean ${real(d.mean)}`,
    `histogram ${histogram.join(' ')}`,
    `user_ratings ${countSummary(d.users)}`,
    `item_ratings ${countSummary(d.items)}`,
    `timestamps first ${first} last ${last}`,
    `cold_items ${d.catalog.size - d.items.length}`,
    `similarities user_pairs ${userPairs.length} usable ${userPairs.filter((s) => s.similarity > d.settings.minSimilarity).length} item_pairs ${itemPairs.length} usable ${itemPairs.filter((s) => s.similarity > d.settings.minSimilarity).length} slope_pairs ${pairs(d.items.map((_, i) => i)).filter(([a, b]) => n.common[a][b] > 0).length}`,
  ];
  const genres = [...new Set(d.items.flatMap((i) => i.genres))].sort(compareText);
  const genreStats = ['genre_stats'];
  for (const g of genres) {
    const items = d.items.filter((i) => i.genres.includes(g));
    genreStats.push(
      `genre ${g} items ${items.length} ratings ${sum(items.map((i) => i.count))} high ${sum(items.map((i) => i.entries.filter((r) => r.rating >= 4).length))}`,
    );
  }
  const buckets = Array.from({ length: d.settings.timeBuckets }, () => ({
    count: 0,
    users: new Set<number>(),
    sum: 0,
  }));
  for (const r of d.train) {
    const index = Number(
      (BigInt(r.time - first) * BigInt(d.settings.timeBuckets)) / BigInt(last - first + 1),
    );
    const b = buckets[index];
    b.count++;
    b.users.add(r.u);
    b.sum += r.rating;
  }
  return [
    data,
    genreStats,
    [
      `time_buckets ${d.settings.timeBuckets}`,
      ...buckets.map(
        (b, i) =>
          `bucket ${i + 1} ratings ${b.count} users ${b.users.size} mean ${real(b.count ? b.sum / b.count : null)}`,
      ),
    ],
  ];
}
function errorParts(model: Trained, rows: TestRow[]): string[][] {
  const d = model.data;
  const metrics = mapped(METHODS, (m) => errorMetrics(rows.map((r) => r.errors[m])));
  const rating = [
    'rating_metrics',
    ...METHODS.map(
      (m) =>
        `${m} rmse ${real(metrics[m].rmse)} mae ${real(metrics[m].mae)} clipped ${rows.filter((r) => r.predictions[m].value < 1 || r.predictions[m].value > 5).length} fallback ${rows.filter((r) => r.predictions[m].fallback).length}`,
    ),
  ];
  const trainRmse = {
    GLOBAL: trainingRmse(d.train, () => d.mean),
    BASELINE: model.baseline.history[9].rmse,
    SVD: model.svd.history[model.svd.history.length - 1].rmse,
    ALS: model.als.history[model.als.history.length - 1].rmse,
  };
  const generalization = [
    'generalization',
    ...(['GLOBAL', 'BASELINE', 'SVD', 'ALS'] as const).map(
      (m) =>
        `${m} train ${real(trainRmse[m])} test ${real(metrics[m].rmse)} gap ${real(metrics[m].rmse! - trainRmse[m])}`,
    ),
  ];
  const neighborhoods = [
    `neighborhoods k ${d.settings.neighbors}`,
    ...(['USER_KNN', 'ITEM_KNN'] as const).map((m) => {
      const used = rows.filter((r) => !r.predictions[m].fallback);
      const w = used.length;
      return `${m} predictions ${rows.length} with_neighbors ${w} mean_neighbors ${real(w ? sum(used.map((r) => r.predictions[m].similarities.length)) / w : null)} mean_similarity ${real(w ? sum(used.map((r) => sum(r.predictions[m].similarities) / r.predictions[m].similarities.length)) / w : null)}`;
    }),
  ];
  const actual = rows.map((r) => r.rating.rating);
  const ma = sum(actual) / rows.length;
  const actualCentered = actual.map((r) => r - ma);
  const sa = sum(actualCentered.map((v) => v * v));
  const stats = [
    `prediction_stats actual mean ${real(ma)} std ${real(Math.sqrt(sa / rows.length))}`,
    ...METHODS.map((m) => {
      const q = rows.map((r) => r.clipped[m]);
      const mean = sum(q) / q.length;
      const centered = q.map((v) => v - mean);
      const sq = sum(centered.map((v) => v * v));
      const correlation =
        q.every((v) => v === q[0]) || actual.every((v) => v === actual[0])
          ? null
          : sum(centered.map((v, i) => v * actualCentered[i])) / Math.sqrt(sq * sa);
      return `${m} mean ${real(mean)} std ${real(Math.sqrt(sq / q.length))} correlation ${real(correlation)}`;
    }),
  ];
  const bins = [
    'error_bins edges 0.5 1.0 1.5 2.0',
    ...METHODS.map((m) => {
      const counts = [0, 0, 0, 0, 0];
      for (const r of rows) counts[Math.min(4, Math.floor(Math.abs(r.errors[m]) / 0.5))]++;
      return `${m} ${counts.join(' ')}`;
    }),
  ];
  const comparisons = [
    'comparison',
    ...pairs(METHODS).map(([a, b]) => {
      let wins = 0;
      let ties = 0;
      let losses = 0;
      for (const r of rows) {
        const x = Math.abs(r.errors[a]);
        const y = Math.abs(r.errors[b]);
        if (x < y) wins++;
        else if (x === y) ties++;
        else losses++;
      }
      return `${a} ${b} wins ${wins} ties ${ties} losses ${losses}`;
    }),
  ];
  const groups = (name: string, bounds: number[], count: (r: Rating) => number) => [
    `${name}_groups bounds ${bounds.join(' ')}`,
    ...Array.from({ length: bounds.length + 1 }, (_, g) => {
      const selected = rows.filter((r) => group(count(r.rating), bounds) === g);
      return `group ${g + 1} from ${g ? bounds[g - 1] : 1} to ${g === bounds.length ? '-' : bounds[g] - 1} pairs ${selected.length} ${METHODS.map((m) => `${m} ${real(errorMetrics(selected.map((r) => r.errors[m])).rmse)}`).join(' ')}`;
    }),
  ];
  const byRating = [
    'by_rating',
    ...[1, 2, 3, 4, 5].map((v) => {
      const selected = rows.filter((r) => r.rating.rating === v);
      return `rating ${v} pairs ${selected.length} ${METHODS.map((m) => `${m} ${real(errorMetrics(selected.map((r) => r.errors[m])).mae)}`).join(' ')}`;
    }),
  ];
  const genres = [
    'genres',
    ...[...new Set(rows.flatMap((r) => d.items[r.rating.i].genres))].sort(compareText).map((g) => {
      const selected = rows.filter((r) => d.items[r.rating.i].genres.includes(g));
      return `genre ${g} pairs ${selected.length} ${METHODS.map((m) => `${m} ${real(errorMetrics(selected.map((r) => r.errors[m])).rmse)}`).join(' ')}`;
    }),
  ];
  return [
    rating,
    generalization,
    neighborhoods,
    stats,
    bins,
    comparisons,
    groups('user', d.settings.userGroups, (r) => d.users[r.u].count),
    groups('item', d.settings.itemGroups, (r) => d.items[r.i].count),
    byRating,
    genres,
  ];
}
function rankingParts(model: Trained, lists: Lists): string[][] {
  const d = model.data;
  const s = d.settings;
  const relevant = d.users.map(
    (_, u) => new Set(d.test.filter((r) => r.u === u && r.rating >= 4).map((r) => r.i)),
  );
  const evaluated = d.users.map((_, u) => u).filter((u) => relevant[u].size > 0);
  const e = evaluated.length;
  const metrics = (u: number, m: Ranking, cutoff: number) =>
    rankingMetrics(
      lists(u, m).map((v) => v.i),
      relevant[u],
      cutoff,
    );
  const ranking = [`ranking users ${e} relevant ${sum(evaluated.map((u) => relevant[u].size))}`];
  for (const cutoff of s.cutoffs) {
    ranking.push(`cutoff ${cutoff}`);
    for (const m of RANKINGS) {
      const values = evaluated.map((u) => metrics(u, m, cutoff));
      ranking.push(
        `  ${m} precision ${real(sum(values.map((v) => v.hits)) / (cutoff * e))} recall ${real(sum(values.map((v) => v.recall)) / e)} ndcg ${real(sum(values.map((v) => v.ndcg)) / e)} map ${real(sum(values.map((v) => v.ap)) / e)} mrr ${real(sum(values.map((v) => v.rr)) / e)} hit_rate ${real(values.filter((v) => v.hits > 0).length / e)}`,
      );
    }
  }
  const head = new Set(model.popularity.slice(0, Math.floor(d.items.length / 5)));
  const beyond = [`beyond_accuracy top_n ${s.topN} head ${head.size}`];
  for (const m of RANKINGS) {
    const union = new Set<number>();
    let diversity = 0;
    let novelty = 0;
    let popularity = 0;
    let tail = 0;
    let similarity = 0;
    for (const u of evaluated) {
      const items = lists(u, m)
        .slice(0, s.topN)
        .map((v) => v.i);
      const genres = new Set<string>();
      let nov = 0;
      let pop = 0;
      let ils = 0;
      for (const i of items) {
        union.add(i);
        for (const g of d.items[i].genres) genres.add(g);
        nov += Math.log2(d.users.length / d.items[i].count);
        pop += d.items[i].count;
        if (!head.has(i)) tail++;
      }
      for (let a = 0; a < items.length - 1; a++) {
        for (let b = a + 1; b < items.length; b++) {
          ils += model.neighborhood.items[items[a]][items[b]]?.similarity ?? 0;
        }
      }
      diversity += genres.size;
      novelty += nov / s.topN;
      popularity += pop;
      similarity += ils / ((s.topN * (s.topN - 1)) / 2);
    }
    beyond.push(
      `${m} coverage ${real(union.size / d.items.length)} diversity ${real(diversity / e)} novelty ${real(novelty / e)} popularity ${real(popularity / (s.topN * e))} long_tail ${real(tail / (s.topN * e))} similarity ${real(similarity / e)}`,
    );
  }
  const groups = [
    `ranking_groups top_n ${s.topN} bounds ${s.userGroups.join(' ')}`,
    ...Array.from({ length: s.userGroups.length + 1 }, (_, g) => {
      const users = evaluated.filter((u) => group(d.users[u].count, s.userGroups) === g);
      return `group ${g + 1} users ${users.length} ${RANKINGS.map((m) => `${m} ${real(users.length ? sum(users.map((u) => metrics(u, m, s.topN).ndcg)) / users.length : null)}`).join(' ')}`;
    }),
  ];
  const agreement = [
    `agreement top_n ${s.topN}`,
    ...pairs(RANKINGS).map(([a, b]) => {
      let total = 0;
      for (const u of evaluated) {
        const first = new Set(
          lists(u, a)
            .slice(0, s.topN)
            .map((v) => v.i),
        );
        const second = new Set(
          lists(u, b)
            .slice(0, s.topN)
            .map((v) => v.i),
        );
        const intersection = [...first].filter((i) => second.has(i)).length;
        total += intersection / (first.size + second.size - intersection);
      }
      return `${a} ${b} jaccard ${real(total / e)}`;
    }),
  ];
  return [ranking, beyond, groups, agreement];
}
function neighborGrid(model: Trained): string[] {
  const values = model.data.settings.neighborGrid.map((k) => ({
    k,
    user: errorMetrics(
      model.data.test.map((r) => clip(predict(model, 'USER_KNN', r.u, r.i, k).value) - r.rating),
    ).rmse!,
    item: errorMetrics(
      model.data.test.map((r) => clip(predict(model, 'ITEM_KNN', r.u, r.i, k).value) - r.rating),
    ).rmse!,
  }));
  let user = values[0];
  let item = values[0];
  for (const v of values) {
    if (v.user < user.user) user = v;
    if (v.item < item.item) item = v;
  }
  return [
    'neighbor_grid',
    ...values.map((v) => `k ${v.k} USER_KNN ${real(v.user)} ITEM_KNN ${real(v.item)}`),
    `best USER_KNN ${user.k} ITEM_KNN ${item.k}`,
  ];
}
function biasLines(model: Trained): string[] {
  const d = model.data;
  const lines = ['biases'];
  for (const kind of ['item', 'user'] as const) {
    for (const order of ['high', 'low'] as const) {
      const profiles = kind === 'item' ? d.items : d.users;
      const biases = kind === 'item' ? model.baseline.itemBias : model.baseline.userBias;
      const indices = profiles
        .map((_, i) => i)
        .sort(
          (a, b) =>
            (order === 'high' ? biases[b] - biases[a] : biases[a] - biases[b]) ||
            profiles[a].id - profiles[b].id,
        )
        .slice(0, d.settings.listSize);
      for (const i of indices) {
        const p = profiles[i];
        lines.push(
          `${kind}_${order} ${p.id} bias ${real(biases[i])} count ${p.count} mean ${real(p.mean)}` +
            (kind === 'item' ? ' ' + d.items[i].title : ''),
        );
      }
    }
  }
  return lines;
}
function recommendationParts(model: Trained, lists: Lists, rows: TestRow[]): string[][] {
  const d = model.data;
  const s = d.settings;
  const popularLine = (i: number, rank: number) => {
    const item = d.items[i];
    return `  ${rank + 1} ${item.id} count ${item.count} mean ${real(item.mean)} ${item.title}`;
  };
  return s.recommendUsers.map((id) => {
    const u = d.userIndex.get(id);
    if (u === undefined) {
      return [
        `user ${id} unknown`,
        'list POPULAR',
        ...model.popularity.slice(0, s.topN).map(popularLine),
      ];
    }
    const user = d.users[u];
    const genreCounts = (accept: (rating: number) => boolean) => {
      const counts = new Map<string, number>();
      for (const r of user.entries) {
        if (accept(r.rating)) {
          for (const g of d.items[r.i].genres) counts.set(g, (counts.get(g) ?? 0) + 1);
        }
      }
      return [...counts].sort((a, b) => b[1] - a[1] || compareText(a[0], b[0])).slice(0, 3);
    };
    const liked = genreCounts((r) => r >= 4);
    const disliked = genreCounts((r) => r <= 2);
    const likedNames = new Set(liked.map(([g]) => g));
    const genresText = (pairs: [string, number][]) =>
      pairs.length ? pairs.map(([g, n]) => `${g} ${n}`).join(' ') : '-';
    const recent = [...user.entries].sort((a, b) => b.time - a.time || a.item - b.item).slice(0, 3);
    const lines = [
      `user ${id} ratings ${user.count} mean ${real(user.mean)} bias ${real(model.baseline.userBias[u])}`,
      `liked_genres ${genresText(liked)}`,
      `disliked_genres ${genresText(disliked)}`,
      'recent ' + recent.map((r) => `${r.item} ${r.rating}`).join(' '),
    ];
    const neighbors = model.neighborhood.users[u].flatMap((v, index) =>
      v !== null && v.similarity > s.minSimilarity ? [{ ...v, id: d.users[index].id }] : [],
    );
    for (const v of select(neighbors, s.listSize)) {
      lines.push(`neighbor ${v.id} similarity ${real(v.similarity)} common ${v.common}`);
    }
    for (const r of rows.filter((r) => r.rating.u === u)) {
      lines.push(
        `heldout ${r.rating.item} actual ${r.rating.rating} ${METHODS.map((m) => real(r.clipped[m])).join(' ')}`,
      );
    }
    for (const m of RANKINGS) {
      const entries = lists(u, m).slice(0, s.topN);
      const matches = entries.filter((v) =>
        d.items[v.i].genres.some((g) => likedNames.has(g)),
      ).length;
      lines.push(`list ${m} genre_match ${matches}`);
      entries.forEach((v, rank) => {
        const item = d.items[v.i];
        if (m === 'POPULAR') lines.push(popularLine(v.i, rank));
        else {
          lines.push(
            `  ${rank + 1} ${item.id} ${real(v.prediction!.value)}` +
              (m === 'USER_KNN' || m === 'ITEM_KNN' ? ` via ${v.prediction!.top ?? '-'}` : '') +
              ' ' +
              item.title,
          );
        }
      });
    }
    return lines;
  });
}
function similarParts(model: Trained): string[][] {
  const d = model.data;
  const n = model.neighborhood;
  const s = d.settings;
  return s.similarItems.map((id) => {
    const i = d.itemIndex.get(id)!;
    const item = d.items[i];
    const others = d.items.map((_, j) => j).filter((j) => j !== i);
    const title = (j: number) => d.items[j].title;
    const lines = [
      `item ${id} ratings ${item.count} mean ${real(item.mean)} bias ${real(model.baseline.itemBias[i])} genres ${item.genreText} title ${item.title}`,
      'cosine',
    ];
    const similarities = others.flatMap((j) =>
      n.items[i][j] === null ? [] : [{ ...n.items[i][j]!, id: d.items[j].id, j }],
    );
    select(similarities, s.listSize).forEach((v, rank) =>
      lines.push(
        `  ${rank + 1} ${v.id} similarity ${real(v.similarity)} common ${v.common} ${title(v.j)}`,
      ),
    );
    lines.push('factors');
    const q = model.svd.itemFactors[i];
    const factors = others.map((j) => {
      const v = model.svd.itemFactors[j];
      return { j, id: d.items[j].id, similarity: dot(q, v) / Math.sqrt(dot(q, q) * dot(v, v)) };
    });
    select(factors, s.listSize).forEach((v, rank) =>
      lines.push(`  ${rank + 1} ${v.id} similarity ${real(v.similarity)} ${title(v.j)}`),
    );
    lines.push('co_rated');
    const common = others.filter((j) => n.common[i][j] >= 1);
    [...common]
      .sort((a, b) => n.common[i][b] - n.common[i][a] || d.items[a].id - d.items[b].id)
      .slice(0, s.listSize)
      .forEach((j, rank) =>
        lines.push(`  ${rank + 1} ${d.items[j].id} common ${n.common[i][j]} ${title(j)}`),
      );
    lines.push('slope_one');
    const deviation = (j: number) => n.difference[j][i] / (n.common[j][i] + s.shrinkage);
    [...common]
      .sort(
        (a, b) =>
          deviation(b) - deviation(a) ||
          n.common[i][b] - n.common[i][a] ||
          d.items[a].id - d.items[b].id,
      )
      .slice(0, s.listSize)
      .forEach((j, rank) =>
        lines.push(
          `  ${rank + 1} ${d.items[j].id} difference ${n.difference[j][i]} common ${n.common[j][i]} ${title(j)}`,
        ),
      );
    return lines;
  });
}
function main(): void {
  const model = train(readData());
  const rows = testPredictions(model);
  const lists = listBuilder(model);
  const predictions = [
    'user,item,actual,' + METHODS.join(','),
    ...rows.map((r) =>
      [
        r.rating.user,
        r.rating.item,
        r.rating.rating,
        ...METHODS.map((m) => real(r.clipped[m])),
      ].join(','),
    ),
  ];
  const evaluation = sections([
    ...summaryParts(model),
    ...errorParts(model, rows),
    ...rankingParts(model, lists),
    neighborGrid(model),
    biasLines(model),
  ]);
  const log = [
    'method,epoch,train_rmse',
    ...[...model.baseline.history, ...model.svd.history, ...model.als.history].map(
      (v) => `${v.method},${v.epoch},${real(v.rmse)}`,
    ),
  ];
  mkdirSync('output', { recursive: true });
  writeLines('predictions.csv', predictions);
  writeLines('evaluation.txt', evaluation);
  writeLines('recommendations.txt', sections(recommendationParts(model, lists, rows)));
  writeLines('similar_items.txt', sections(similarParts(model)));
  writeLines('training_log.csv', log);
}
main();
