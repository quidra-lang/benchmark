import { readFileSync } from 'node:fs';
export interface Rating {
  user: number;
  item: number;
  rating: number;
  u: number;
  i: number;
  index: number;
}
export interface TrainingRating extends Rating {
  time: number;
}
export interface CatalogItem {
  id: number;
  title: string;
  genreText: string;
  genres: string[];
}
export interface Profile {
  id: number;
  entries: TrainingRating[];
  ratings: Map<number, number>;
  count: number;
  sum: number;
  mean: number;
}
export interface Item extends Profile, CatalogItem {}
export interface Settings {
  neighbors: number;
  shrinkage: number;
  minSimilarity: number;
  itemReg: number;
  userReg: number;
  factors: number;
  learningRate: number;
  regularization: number;
  epochs: number;
  alsReg: number;
  alsIterations: number;
  seed: number;
  topN: number;
  cutoffs: number[];
  neighborGrid: number[];
  userGroups: number[];
  itemGroups: number[];
  timeBuckets: number;
  listSize: number;
  recommendUsers: number[];
  similarItems: number[];
}
export function readData() {
  const lines = (name: string) =>
    readFileSync('input/' + name, 'ascii')
      .slice(0, -1)
      .split('\n');
  const raw = lines('ratings.csv')
    .slice(1)
    .map((line) => {
      const [user, item, rating, time] = line.split(',').map(Number);
      return { user, item, rating, time };
    });
  const catalog = new Map<number, CatalogItem>();
  for (const line of lines('items.csv').slice(1)) {
    const [id, title, genreText] = line.split(',');
    catalog.set(+id, { id: +id, title, genreText, genres: genreText.split('|') });
  }
  const ids = (key: 'user' | 'item') => [...new Set(raw.map((r) => r[key]))].sort((a, b) => a - b);
  const userIds = ids('user');
  const itemIds = ids('item');
  const userIndex = new Map(userIds.map((id, i) => [id, i]));
  const itemIndex = new Map(itemIds.map((id, i) => [id, i]));
  const train: TrainingRating[] = raw.map((r, index) => ({
    ...r,
    index,
    u: userIndex.get(r.user)!,
    i: itemIndex.get(r.item)!,
  }));
  function profile(id: number, entries: TrainingRating[], key: 'u' | 'i'): Profile {
    entries.sort((a, b) => a[key] - b[key]);
    let sum = 0;
    for (const r of entries) sum += r.rating;
    return {
      id,
      entries,
      ratings: new Map(entries.map((r) => [r[key], r.rating])),
      count: entries.length,
      sum,
      mean: sum / entries.length,
    };
  }
  const users = userIds.map((id, u) =>
    profile(
      id,
      train.filter((r) => r.u === u),
      'i',
    ),
  );
  const items: Item[] = itemIds.map((id, i) => ({
    ...catalog.get(id)!,
    ...profile(
      id,
      train.filter((r) => r.i === i),
      'u',
    ),
  }));
  const test: Rating[] = lines('test.csv')
    .slice(1)
    .map((line, index) => {
      const [user, item, rating] = line.split(',').map(Number);
      return { user, item, rating, index, u: userIndex.get(user)!, i: itemIndex.get(item)! };
    });
  const fields = new Map(
    lines('params.txt').map((line) => {
      const [name, ...v] = line.split(' ');
      return [name, v.map(Number)];
    }),
  );
  const p = (k: string) => fields.get(k)!;
  const n = (k: string) => p(k)[0];
  const settings: Settings = {
    neighbors: n('NEIGHBORS'),
    shrinkage: n('SHRINKAGE'),
    minSimilarity: n('MIN_SIMILARITY'),
    itemReg: p('BIAS_REG')[0],
    userReg: p('BIAS_REG')[1],
    factors: n('FACTORS'),
    learningRate: n('LEARNING_RATE'),
    regularization: n('REGULARIZATION'),
    epochs: n('EPOCHS'),
    alsReg: n('ALS_REG'),
    alsIterations: n('ALS_ITERATIONS'),
    seed: n('SEED'),
    topN: n('TOP_N'),
    cutoffs: p('CUTOFFS'),
    neighborGrid: p('NEIGHBOR_GRID'),
    userGroups: p('USER_GROUPS'),
    itemGroups: p('ITEM_GROUPS'),
    timeBuckets: n('TIME_BUCKETS'),
    listSize: n('LIST_SIZE'),
    recommendUsers: p('RECOMMEND_USERS'),
    similarItems: p('SIMILAR_ITEMS'),
  };
  let total = 0;
  for (const r of train) total += r.rating;
  return {
    train,
    test,
    catalog,
    users,
    items,
    userIndex,
    itemIndex,
    settings,
    mean: total / train.length,
  };
}
export type Data = ReturnType<typeof readData>;
