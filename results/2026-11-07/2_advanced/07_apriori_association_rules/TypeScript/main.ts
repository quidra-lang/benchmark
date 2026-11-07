import { readFileSync } from 'node:fs';
import {
  readCsv,
  buildBasket,
  extendBasket,
  contains,
  compareNames,
  compareItemsets,
  itemsetKey as key,
  type Product,
  type Transaction,
  type Basket,
  type Itemset,
} from './baskets.ts';
import { SupportCounter, candidates, countCandidates } from './apriori.ts';
import { mine } from './fpgrowth.ts';
import { Fraction, createRule, passes, compareRules, ruleKey, type Rule } from './rules.ts';
import {
  quotient,
  fraction as f,
  percentage as pct,
  money,
  ruleLines,
  writeFiles,
} from './report.ts';

interface Parameters {
  min_support: number;
  min_confidence: Fraction;
  min_lift: Fraction;
  max_size: number;
  category_min_support: number;
  sequence_min_support: number;
  split_day: number;
  train_min_support: number;
  test_min_support: number;
  recommend_top: number;
  matrix_size: number;
  group_min_lift: Fraction;
  negative_max_lift: Fraction;
  negative_min_expected: number;
  trend_threshold: Fraction;
}
interface Level {
  number: number;
  candidates: number;
  excluded: number;
  pruned: number;
  counted: number;
  entries: Itemset[];
}
interface Run {
  count: number;
  counter: SupportCounter;
  frequent: Map<string, Itemset>;
  levels: Level[];
}
interface Customer {
  id: string;
  baskets: Basket[];
  days: Set<number>;
  purchases: Map<string, Set<number>>;
  categoryUnits: Map<string, number>;
  units: number;
  revenue: number;
}
interface Evaluation {
  cases: number;
  covered: number;
  hit1: number;
  hit: number;
  baseline: number;
}
const sum = (values: Iterable<number>) => {
  let total = 0;
  for (const value of values) total += value;
  return total;
};
const sizeOrder = (a: Itemset, b: Itemset) =>
  a.items.length - b.items.length || compareItemsets(a.items, b.items);
function readParameters(): Parameters {
  const rows = new Map(
    readFileSync('input/params.txt', 'ascii')
      .slice(0, -1)
      .split('\n')
      .map((line) => {
        const [name, value] = line.split(' ');
        return [name, value];
      }),
  );
  const n = (name: string) => Number(rows.get(name));
  const r = (name: string) => {
    const [a, b] = rows.get(name)!.split('/');
    return new Fraction(a, b);
  };
  return {
    min_support: n('min_support'),
    min_confidence: r('min_confidence'),
    min_lift: r('min_lift'),
    max_size: n('max_size'),
    category_min_support: n('category_min_support'),
    sequence_min_support: n('sequence_min_support'),
    split_day: n('split_day'),
    train_min_support: n('train_min_support'),
    test_min_support: n('test_min_support'),
    recommend_top: n('recommend_top'),
    matrix_size: n('matrix_size'),
    group_min_lift: r('group_min_lift'),
    negative_max_lift: r('negative_max_lift'),
    negative_min_expected: n('negative_min_expected'),
    trend_threshold: r('trend_threshold'),
  };
}
function readData() {
  const products = new Map<string, Product>();
  const errors: string[] = [];
  const itemRows = readCsv('input/items.csv');
  for (const row of itemRows) {
    const [name, category, priceText] = row.fields;
    const price = Number(priceText);
    const error = products.has(name)
      ? `duplicate item ${name}`
      : price === 0
        ? `bad price ${price}`
        : null;
    if (error) errors.push(`items.csv line ${row.line}: ${error}`);
    else products.set(name, { name, category, price });
  }
  const transactionRows = readCsv('input/transactions.csv');
  const transactions: Transaction[] = [];
  const byTid = new Map<string, Transaction>();
  let adopted = 0;
  let duplicates = 0;
  for (const row of transactionRows) {
    const [tid, customer, dayText, name] = row.fields;
    const day = Number(dayText);
    let previous = transactions.at(-1);
    if (previous && previous.tid !== tid && byTid.has(tid)) {
      errors.push(`transactions.csv line ${row.line}: tid ${tid} not contiguous`);
      continue;
    }
    if (!byTid.has(tid)) {
      previous = { tid, customer, day, units: new Map() };
      transactions.push(previous);
      byTid.set(tid, previous);
    }
    const transaction = previous!;
    const error =
      customer !== transaction.customer
        ? `tid ${tid} customer ${customer} differs from ${transaction.customer}`
        : day !== transaction.day
          ? `tid ${tid} day ${day} differs from ${transaction.day}`
          : !products.has(name)
            ? `unknown item ${name}`
            : null;
    if (error) errors.push(`transactions.csv line ${row.line}: ${error}`);
    else {
      const count = transaction.units.get(name) ?? 0;
      if (count) duplicates++;
      transaction.units.set(name, count + 1);
      adopted++;
    }
  }
  const baskets = transactions.filter((t) => t.units.size).map(buildBasket);
  const names = [...products.keys()].sort(compareNames);
  const categories = [...new Set([...products.values()].map((p) => p.category))].sort(compareNames);
  const days = baskets.map((b) => b.day);
  return {
    products,
    names,
    categories,
    transactions,
    baskets,
    errors,
    adopted,
    duplicates,
    itemRows: itemRows.length,
    transactionRows: transactionRows.length,
    firstDay: Math.min(...days),
    lastDay: Math.max(...days),
  };
}
type Data = ReturnType<typeof readData>;
function runApriori(
  baskets: ReadonlySet<string>[],
  universe: string[],
  minimum: number,
  maximum: number,
  taxonomy?: Map<string, string>,
): Run {
  const counter = new SupportCounter(baskets);
  const frequent = new Map<string, Itemset>();
  const levels: Level[] = [];
  let previous: string[][] = [];
  for (let size = 1; size <= maximum; size++) {
    if (size > 1 && !previous.length) break;
    const generated =
      size === 1
        ? {
            items: universe.map((name) => [name]),
            candidates: universe.length,
            excluded: 0,
            pruned: 0,
            counted: universe.length,
          }
        : candidates(previous, taxonomy);
    generated.items.sort(compareItemsets);
    const entries = countCandidates(generated.items, counter, minimum);
    levels.push({
      number: size,
      candidates: generated.candidates,
      excluded: generated.excluded,
      pruned: generated.pruned,
      counted: generated.counted,
      entries,
    });
    for (const entry of entries) frequent.set(key(entry.items), entry);
    previous = entries.map((e) => e.items);
  }
  return { count: baskets.length, counter, frequent, levels };
}
const support = (run: Run, items: string[]) =>
  items.length ? run.frequent.get(key(items))!.count : run.count;
function classify(run: Run) {
  const entries = [...run.frequent.values()].sort(sizeOrder);
  const closed = new Set(entries);
  const maximal = new Set(entries);
  const generators = entries.filter((e) =>
    e.items.every(
      (_, i) =>
        support(
          run,
          e.items.filter((_, j) => i !== j),
        ) > e.count,
    ),
  );
  for (const e of entries) {
    if (e.items.length >= 2) {
      for (let i = 0; i < e.items.length; i++) {
        const smaller = run.frequent.get(key(e.items.filter((_, j) => i !== j)))!;
        maximal.delete(smaller);
        if (smaller.count === e.count) closed.delete(smaller);
      }
    }
  }
  return { closed: [...closed], maximal: [...maximal], generators };
}
function* subsets(items: string[], i = 0, chosen: string[] = []): Generator<string[]> {
  if (i === items.length) {
    yield chosen;
    return;
  }
  yield* subsets(items, i + 1, chosen);
  yield* subsets(items, i + 1, [...chosen, items[i]]);
}
function makeRules(run: Run, p: Parameters, categories?: Set<string>) {
  const rules: Rule[] = [];
  let generated = 0;
  for (const entry of run.frequent.values()) {
    if (
      entry.items.length < 2 ||
      (categories && !entry.items.some((item) => categories.has(item)))
    ) {
      continue;
    }
    for (const antecedent of subsets(entry.items)) {
      if (!antecedent.length || antecedent.length === entry.items.length) continue;
      generated++;
      const consequent = entry.items.filter((item) => !antecedent.includes(item));
      const metrics = createRule(
        antecedent,
        consequent,
        support(run, antecedent),
        support(run, consequent),
        entry.count,
        run.count,
      );
      if (!passes(metrics, p.min_confidence, p.min_lift)) continue;
      let baseline = new Fraction(support(run, consequent), run.count);
      for (const subset of subsets(antecedent)) {
        if (!subset.length || subset.length === antecedent.length) continue;
        const confidence = new Fraction(
          support(run, [...subset, ...consequent].sort(compareNames)),
          support(run, subset),
        );
        if (confidence.compare(baseline) > 0) baseline = confidence;
      }
      rules.push({
        ...metrics,
        items: entry.items,
        improvement: metrics.confidence.subtract(baseline),
        rank: 0,
      });
    }
  }
  rules.sort(compareRules);
  rules.forEach((rule, i) => (rule.rank = i + 1));
  return { rules, generated, productive: rules.filter((r) => r.improvement.numerator > 0n).length };
}
function collectCustomers(data: Data) {
  const customers = new Map<string, Customer>();
  const buyers = new Map(data.names.map((name) => [name, 0]));
  for (const basket of data.baskets) {
    let c = customers.get(basket.customer);
    if (!c) {
      c = {
        id: basket.customer,
        baskets: [],
        days: new Set(),
        purchases: new Map(),
        categoryUnits: new Map(),
        units: 0,
        revenue: 0,
      };
      customers.set(c.id, c);
    }
    c.baskets.push(basket);
    c.days.add(basket.day);
    for (const [name, units] of basket.units) {
      let days = c.purchases.get(name);
      if (!days) {
        days = new Set();
        c.purchases.set(name, days);
      }
      days.add(basket.day);
      const product = data.products.get(name)!;
      c.categoryUnits.set(product.category, (c.categoryUnits.get(product.category) ?? 0) + units);
      c.units += units;
      c.revenue += units * product.price;
    }
  }
  for (const c of customers.values()) {
    for (const name of c.purchases.keys()) buyers.set(name, buyers.get(name)! + 1);
  }
  return { customers, buyers };
}
type CustomerData = ReturnType<typeof collectCustomers>;
function median(values: number[]): Fraction {
  const sorted = values.slice().sort((a, b) => a - b);
  const i = quotient(sorted.length, 2);
  return sorted.length % 2 ? new Fraction(sorted[i]) : new Fraction(sorted[i - 1] + sorted[i], 2);
}
function sequenceAnalysis(customerData: CustomerData, p: Parameters) {
  const { customers, buyers } = customerData;
  const pairs = new Map<string, { a: string; b: string; gaps: number[] }>();
  const intervals = new Map<string, { name: string; customers: number; gaps: number[] }>();
  for (const c of customers.values()) {
    const purchased = new Map(
      [...c.purchases].map(([name, days]) => [name, [...days].sort((a, b) => a - b)]),
    );
    for (const [a, days] of purchased) {
      if (days.length >= 2) {
        let repeat = intervals.get(a);
        if (!repeat) {
          repeat = { name: a, customers: 0, gaps: [] };
          intervals.set(a, repeat);
        }
        repeat.customers++;
        for (let i = 1; i < days.length; i++) repeat.gaps.push(days[i] - days[i - 1]);
      }
      for (const [b, later] of purchased) {
        if (days[0] >= later[later.length - 1]) continue;
        let smallest = Infinity;
        let index = 0;
        for (const day of later) {
          while (index < days.length && days[index] < day) index++;
          if (index) smallest = Math.min(smallest, day - days[index - 1]);
        }
        const id = `${a}->${b}`;
        let pair = pairs.get(id);
        if (!pair) {
          pair = { a, b, gaps: [] };
          pairs.set(id, pair);
        }
        pair.gaps.push(smallest);
      }
    }
  }
  const frequent = [...pairs.values()]
    .filter((pair) => pair.gaps.length >= p.sequence_min_support)
    .map((pair) => ({
      ...pair,
      count: pair.gaps.length,
      base: buyers.get(pair.a)!,
      confidence: new Fraction(pair.gaps.length, buyers.get(pair.a)!),
      lift: new Fraction(
        pair.gaps.length * customers.size,
        buyers.get(pair.a)! * buyers.get(pair.b)!,
      ),
      gap: median(pair.gaps),
    }));
  frequent.sort(
    (a, b) =>
      b.count - a.count ||
      b.confidence.compare(a.confidence) ||
      compareNames(a.a, b.a) ||
      compareNames(a.b, b.b),
  );
  const repeats = [...intervals.values()].map((r) => ({
    ...r,
    mean: new Fraction(sum(r.gaps), r.gaps.length),
    median: median(r.gaps),
  }));
  repeats.sort((a, b) => a.mean.compare(b.mean) || compareNames(a.name, b.name));
  const lines = frequent.map(
    (r, i) =>
      `SEQ ${i + 1} ${r.a} -> ${r.b} customers ${r.count} base ${r.base} confidence ${f(r.confidence)} lift ${f(r.lift)} gap ${f(r.gap)}`,
  );
  for (const r of repeats) {
    lines.push(
      `REPEAT ${r.name} customers ${r.customers} intervals ${r.gaps.length} min ${Math.min(...r.gaps)} max ${Math.max(...r.gaps)} mean ${f(r.mean)} median ${f(r.median)}`,
    );
  }
  return {
    lines,
    count: frequent.length,
    pairs: pairs.size,
    multiDay: [...customers.values()].filter((c) => c.days.size >= 2).length,
  };
}
function recommend(
  held: ReadonlySet<string>,
  candidates: Iterable<string>,
  maximum: number,
): string[] {
  const selected = new Set<string>();
  for (const name of candidates) {
    if (!held.has(name)) selected.add(name);
    if (selected.size === maximum) break;
  }
  return [...selected];
}
function ruleRecommendation(held: ReadonlySet<string>, rules: Rule[], maximum: number): string[] {
  return recommend(
    held,
    rules
      .filter((r) => r.consequent.length === 1 && contains(held, r.antecedent))
      .map((r) => r.consequent[0]),
    maximum,
  );
}
const evaluationCounts = (): Evaluation => ({ cases: 0, covered: 0, hit1: 0, hit: 0, baseline: 0 });
function periodValidation(data: Data, p: Parameters) {
  const training = data.baskets.filter((b) => b.day <= p.split_day);
  const testing = data.baskets.filter((b) => b.day > p.split_day);
  const train = runApriori(
    training.map((b) => b.items),
    data.names,
    p.train_min_support,
    p.max_size,
  );
  const test = runApriori(
    testing.map((b) => b.items),
    data.names,
    p.test_min_support,
    p.max_size,
  );
  const trainingRules = makeRules(train, p).rules;
  const testRules = makeRules(test, p).rules;
  const known = new Set(trainingRules.map(ruleKey));
  const verdictCounts = { HOLD: 0, FAIL: 0, UNSEEN: 0 };
  const lines: string[] = [];
  for (const r of trainingRules) {
    const a = test.counter.count(r.antecedent);
    const b = test.counter.count(r.consequent);
    const c = test.counter.count(r.items);
    const confidence = a && b ? new Fraction(c, a) : null;
    const lift = a && b ? new Fraction(test.count * c, a * b) : null;
    const verdict =
      confidence === null || lift === null
        ? 'UNSEEN'
        : confidence.compare(p.min_confidence) >= 0 && lift.compare(p.min_lift) >= 0
          ? 'HOLD'
          : 'FAIL';
    verdictCounts[verdict]++;
    lines.push(
      `RULE ${r.rank} ${key(r.antecedent)} -> ${key(r.consequent)} train ${r.count} confidence ${f(r.confidence)} lift ${f(r.lift)} test ${c} of ${a} confidence ${confidence === null ? '-' : f(confidence)} lift ${lift === null ? '-' : f(lift)} ${verdict}`,
    );
  }
  const emerging = testRules.filter((r) => !known.has(ruleKey(r)));
  for (const r of emerging) {
    lines.push(
      `EMERGING ${r.rank} ${key(r.antecedent)} -> ${key(r.consequent)} test ${r.count} confidence ${f(r.confidence)} lift ${f(r.lift)}`,
    );
  }
  lines.push(
    `VALIDATION train ${train.count} test ${test.count} itemsets ${train.frequent.size} rules ${trainingRules.length} hold ${verdictCounts.HOLD} fail ${verdictCounts.FAIL} unseen ${verdictCounts.UNSEEN} emerging ${emerging.length}`,
  );
  const popularity = data.names
    .slice()
    .sort((a, b) => train.counter.count([b]) - train.counter.count([a]) || compareNames(a, b));
  const sizes = new Map<number, Evaluation>();
  const total = evaluationCounts();
  const heldout = new Map(data.names.map((name) => [name, { count: 0, hits: 0 }]));
  for (const basket of testing) {
    if (basket.items.size >= 2) {
      if (!sizes.has(basket.items.size)) sizes.set(basket.items.size, evaluationCounts());
      for (const hidden of basket.items) {
        const held = new Set(basket.items);
        held.delete(hidden);
        const suggested = ruleRecommendation(held, trainingRules, p.recommend_top);
        const baseline = recommend(held, popularity, p.recommend_top);
        const result: Evaluation = {
          cases: 1,
          covered: Number(suggested.length > 0),
          hit1: Number(suggested[0] === hidden),
          hit: Number(suggested.includes(hidden)),
          baseline: Number(baseline.includes(hidden)),
        };
        for (const counts of [total, sizes.get(basket.items.size)!]) {
          counts.cases += result.cases;
          counts.covered += result.covered;
          counts.hit1 += result.hit1;
          counts.hit += result.hit;
          counts.baseline += result.baseline;
        }
        const item = heldout.get(hidden)!;
        item.count++;
        item.hits += result.hit;
      }
    }
  }
  const recommendationLine = (label: string, c: Evaluation) =>
    `RECOMMEND ${label} cases ${c.cases} covered ${c.covered} hit1 ${c.hit1} hit ${c.hit} rate ${f(new Fraction(c.hit, c.cases))} baseline ${c.baseline} rate ${f(new Fraction(c.baseline, c.cases))}`;
  for (const size of [...sizes.keys()].sort((a, b) => a - b)) {
    lines.push(recommendationLine(`size ${size}`, sizes.get(size)!));
  }
  lines.push(recommendationLine('total', total));
  return { lines, heldout };
}
interface ProductSummary {
  product: Product;
  units: number;
  revenue: number;
  count: number;
  buyers: number;
  itemsets: number;
  partner: { name: string; count: number; lift: Fraction } | null;
  best: Rule | null;
  heldout: { count: number; hits: number };
}
function matrixLines(prefix: string, names: string[], counter: SupportCounter): string[] {
  const counts = names.map((name) => counter.count([name]));
  const lines = names.map((name, i) => `${prefix} ${i + 1} ${name} baskets ${counts[i]}`);
  lines.push('    ' + names.map((_, i) => String(i + 1).padStart(7)).join(''));
  names.forEach((name, i) =>
    lines.push(
      String(i + 1).padStart(4) +
        names
          .map((other, j) =>
            (i === j
              ? '-'
              : String(
                  quotient(
                    100n *
                      BigInt(counter.size) *
                      BigInt(counter.count([name, other].sort(compareNames))),
                    BigInt(counts[i]) * BigInt(counts[j]),
                  ),
                )
            ).padStart(7),
          )
          .join(''),
    ),
  );
  return lines;
}
function productAnalysis(
  data: Data,
  main: Run,
  categoryRun: Run,
  rules: Rule[],
  customers: CustomerData,
  validation: ReturnType<typeof periodValidation>,
  p: Parameters,
) {
  const products = new Map<string, ProductSummary>(
    data.names.map((name) => [
      name,
      {
        product: data.products.get(name)!,
        units: 0,
        revenue: 0,
        count: main.counter.count([name]),
        buyers: customers.buyers.get(name)!,
        itemsets: 0,
        partner: null,
        best: null,
        heldout: validation.heldout.get(name)!,
      },
    ]),
  );
  for (const basket of data.baskets) {
    for (const [name, units] of basket.units) products.get(name)!.units += units;
  }
  const pairs: { a: string; b: string; count: number; lift: Fraction }[] = [];
  for (const entry of main.frequent.values()) {
    for (const name of entry.items) products.get(name)!.itemsets++;
    if (entry.items.length !== 2) continue;
    const [a, b] = entry.items;
    const lift = new Fraction(
      main.count * entry.count,
      products.get(a)!.count * products.get(b)!.count,
    );
    pairs.push({ a, b, count: entry.count, lift });
    for (const [name, other] of [
      [a, b],
      [b, a],
    ]) {
      const row = products.get(name)!;
      const old = row.partner;
      if (
        !old ||
        lift.compare(old.lift) > 0 ||
        (lift.compare(old.lift) === 0 &&
          (entry.count > old.count ||
            (entry.count === old.count && compareNames(other, old.name) < 0)))
      ) {
        row.partner = { name: other, count: entry.count, lift };
      }
    }
  }
  for (const rule of rules) {
    for (const name of rule.items) {
      const row = products.get(name)!;
      if (!row.best) row.best = rule;
    }
  }
  const categories = new Map(
    data.categories.map((name) => [
      name,
      { name, items: 0, units: 0, revenue: 0, count: categoryRun.counter.count([name]) },
    ]),
  );
  let totalUnits = 0;
  let totalRevenue = 0;
  for (const row of products.values()) {
    row.revenue = row.units * row.product.price;
    const category = categories.get(row.product.category)!;
    category.items++;
    category.units += row.units;
    category.revenue += row.revenue;
    totalUnits += row.units;
    totalRevenue += row.revenue;
  }
  const adjacency = new Map<string, Set<string>>(data.names.map((name) => [name, new Set()]));
  for (const pair of pairs) {
    if (pair.lift.compare(p.group_min_lift) >= 0) {
      adjacency.get(pair.a)!.add(pair.b);
      adjacency.get(pair.b)!.add(pair.a);
    }
  }
  const seen = new Set<string>();
  const groups: { members: string[]; core: string; edges: number; revenue: number }[] = [];
  for (const name of data.names) {
    if (seen.has(name)) continue;
    const pending = [name];
    const members: string[] = [];
    while (pending.length) {
      const item = pending.pop()!;
      if (seen.has(item)) continue;
      seen.add(item);
      members.push(item);
      pending.push(...adjacency.get(item)!);
    }
    if (members.length < 2) continue;
    members.sort(compareNames);
    const core = members
      .slice()
      .sort(
        (a, b) =>
          adjacency.get(b)!.size - adjacency.get(a)!.size ||
          products.get(b)!.count - products.get(a)!.count ||
          compareNames(a, b),
      )[0];
    groups.push({
      members,
      core,
      edges: quotient(sum(members.map((item) => adjacency.get(item)!.size)), 2),
      revenue: sum(members.map((item) => products.get(item)!.revenue)),
    });
  }
  groups.sort(
    (a, b) => b.members.length - a.members.length || compareNames(a.members[0], b.members[0]),
  );
  const singles = main.levels[0].entries.map((e) => e.items[0]);
  const substitutes: { a: string; b: string; count: number; expected: Fraction; lift: Fraction }[] =
    [];
  for (let i = 0; i < singles.length; i++) {
    for (let j = i + 1; j < singles.length; j++) {
      const a = singles[i];
      const b = singles[j];
      const expected = products.get(a)!.count * products.get(b)!.count;
      if (expected < p.negative_min_expected * main.count) continue;
      const count = main.counter.count([a, b]);
      const lift = new Fraction(main.count * count, expected);
      if (lift.compare(p.negative_max_lift) <= 0) {
        substitutes.push({ a, b, count, expected: new Fraction(expected, main.count), lift });
      }
    }
  }
  substitutes.sort(
    (a, b) =>
      a.lift.compare(b.lift) ||
      b.expected.compare(a.expected) ||
      compareNames(a.a, b.a) ||
      compareNames(a.b, b.b),
  );
  const lines: string[] = [];
  [...products.values()]
    .sort((a, b) => b.revenue - a.revenue || compareNames(a.product.name, b.product.name))
    .forEach((row, i) => {
      const product = row.product;
      const partner = row.partner ? `${row.partner.name} ${f(row.partner.lift)}` : 'none';
      const best = row.best
        ? `${row.best.rank} ${key(row.best.antecedent)} -> ${key(row.best.consequent)}`
        : 'none';
      lines.push(
        `ITEM ${i + 1} ${product.name} ${product.category} price ${money(product.price)} units ${row.units} revenue ${money(row.revenue)} share ${pct(row.revenue, totalRevenue)}` +
          ` baskets ${row.count} support ${f(new Fraction(row.count, main.count))} customers ${row.buyers} itemsets ${row.itemsets} heldout ${row.heldout.count} hits ${row.heldout.hits} partner ${partner} best ${best}`,
      );
    });
  for (const c of [...categories.values()].sort(
    (a, b) => b.revenue - a.revenue || compareNames(a.name, b.name),
  )) {
    lines.push(
      `CATEGORY ${c.name} items ${c.items} units ${c.units} revenue ${money(c.revenue)} share ${pct(c.revenue, totalRevenue)} baskets ${c.count} support ${f(new Fraction(c.count, main.count))}`,
    );
  }
  lines.push(
    `TOTAL items ${data.products.size} units ${totalUnits} revenue ${money(totalRevenue)} baskets ${main.count} customers ${customers.customers.size}`,
  );
  groups.forEach((g, i) =>
    lines.push(
      `GROUP ${i + 1} items ${g.members.length} edges ${g.edges} core ${g.core} revenue ${money(g.revenue)} share ${pct(g.revenue, totalRevenue)} members ${key(g.members)}`,
    ),
  );
  for (const pair of substitutes) {
    lines.push(
      `SUBSTITUTE ${pair.a} ${pair.b} count ${pair.count} expected ${f(pair.expected)} lift ${f(pair.lift)}`,
    );
  }
  const popular = (names: string[], counter: SupportCounter) =>
    names.slice().sort((a, b) => counter.count([b]) - counter.count([a]) || compareNames(a, b));
  lines.push(
    ...matrixLines(
      'MATRIX',
      popular(data.names, main.counter).slice(0, p.matrix_size),
      main.counter,
    ),
    ...matrixLines(
      'CATEGORY_MATRIX',
      popular(data.categories, categoryRun.counter),
      categoryRun.counter,
    ),
  );
  return { lines, totalRevenue };
}
function weeklyTrends(data: Data, p: Parameters): string[] {
  const weeks = quotient(data.lastDay - 1, 7) + 1;
  const names = [...data.categories, ...data.names];
  const basketCounts: number[] = Array(weeks).fill(0);
  const unitCounts: number[] = Array(weeks).fill(0);
  const customers = Array.from({ length: weeks }, () => new Set<string>());
  const series = new Map<string, number[]>(names.map((name) => [name, Array(weeks).fill(0)]));
  for (const basket of data.baskets) {
    const week = quotient(basket.day - 1, 7);
    basketCounts[week]++;
    customers[week].add(basket.customer);
    for (const [name, units] of basket.units) {
      unitCounts[week] += units;
      series.get(name)![week] += units;
      series.get(data.products.get(name)!.category)![week] += units;
    }
  }
  let sumW = 0;
  let sumWW = 0;
  for (let w = 1; w <= weeks; w++) {
    sumW += w;
    sumWW += w * w;
  }
  const trends = [...series].map(([name, values]) => {
    const units = sum(values);
    const weighted = sum(values.map((v, i) => (i + 1) * v));
    const slope = new Fraction(weeks * weighted - sumW * units, weeks * sumWW - sumW * sumW);
    const relative = units ? slope.multiply(new Fraction(weeks, units)) : null;
    const verdict =
      relative === null
        ? 'NONE'
        : relative.compare(p.trend_threshold) >= 0
          ? 'RISING'
          : relative.compare(p.trend_threshold.negate()) <= 0
            ? 'FALLING'
            : 'FLAT';
    return { name, units, slope, relative, verdict };
  });
  trends.sort((a, b) =>
    a.relative === null && b.relative !== null
      ? 1
      : a.relative !== null && b.relative === null
        ? -1
        : (a.relative !== null && b.relative !== null ? b.relative.compare(a.relative) : 0) ||
          compareNames(a.name, b.name),
  );
  const row = (name: string, values: number[]) =>
    name.padEnd(17) + values.map((v) => String(v).padStart(6)).join('');
  const lines = [
    row(
      'WEEK',
      Array.from({ length: weeks }, (_, i) => i + 1),
    ),
    row('BASKETS', basketCounts),
    row('UNITS', unitCounts),
    row(
      'CUSTOMERS',
      customers.map((c) => c.size),
    ),
  ];
  for (const name of names) lines.push(row(name, series.get(name)!));
  for (const t of trends) {
    lines.push(
      `TREND ${t.name} units ${t.units} slope ${f(t.slope)} relative ${t.relative === null ? '-' : f(t.relative)} ${t.verdict}`,
    );
  }
  return lines;
}
function customerLines(
  data: Data,
  customers: CustomerData,
  rules: Rule[],
  totalRevenue: number,
  p: Parameters,
): string[] {
  type Segment = 'NEW' | 'LOYAL' | 'AT_RISK' | 'REGULAR';
  const segments: Record<Segment, { customers: number; revenue: number }> = {
    NEW: { customers: 0, revenue: 0 },
    LOYAL: { customers: 0, revenue: 0 },
    AT_RISK: { customers: 0, revenue: 0 },
    REGULAR: { customers: 0, revenue: 0 },
  };
  const lines: string[] = [];
  for (const c of [...customers.customers.values()].sort((a, b) => compareNames(a.id, b.id))) {
    const first = Math.min(...c.days);
    const last = Math.max(...c.days);
    const segment: Segment =
      first > data.lastDay - 28
        ? 'NEW'
        : c.baskets.length >= 4 && data.lastDay - last <= 14
          ? 'LOYAL'
          : data.lastDay - last > 28
            ? 'AT_RISK'
            : 'REGULAR';
    const favorite = [...c.categoryUnits.keys()].sort(
      (a, b) => c.categoryUnits.get(b)! - c.categoryUnits.get(a)! || compareNames(a, b),
    )[0];
    const held = new Set(c.purchases.keys());
    const offer = ruleRecommendation(held, rules, p.recommend_top);
    lines.push(
      `CUSTOMER ${c.id} baskets ${c.baskets.length} days ${c.days.size} first ${first} last ${last} items ${held.size} units ${c.units}` +
        ` revenue ${money(c.revenue)} average ${money(quotient(c.revenue, c.baskets.length))} favorite ${favorite} segment ${segment} offer ${offer.join('+') || 'none'}`,
    );
    segments[segment].customers++;
    segments[segment].revenue += c.revenue;
  }
  for (const name of ['NEW', 'LOYAL', 'AT_RISK', 'REGULAR'] satisfies Segment[]) {
    const counts = segments[name];
    lines.push(
      `SEGMENT ${name} customers ${counts.customers} revenue ${money(counts.revenue)} share ${pct(counts.revenue, totalRevenue)}`,
    );
  }
  return lines;
}
function main() {
  const p = readParameters();
  const data = readData();
  const baskets = data.baskets.map((b) => b.items);
  const analysis = runApriori(baskets, data.names, p.min_support, p.max_size);
  const fp = mine(baskets, p.min_support, p.max_size);
  const classified = classify(analysis);
  const mainRules = makeRules(analysis, p);
  const taxonomy = new Map(
    [...data.products.values()].map((product) => [product.name, product.category]),
  );
  const extended = data.baskets.map((b) => extendBasket(b, data.products));
  const categoryRun = runApriori(
    extended,
    [...data.names, ...data.categories].sort(compareNames),
    p.category_min_support,
    p.max_size,
    taxonomy,
  );
  const categoryRules = makeRules(categoryRun, p, new Set(data.categories));
  const customers = collectCustomers(data);
  const sequential = sequenceAnalysis(customers, p);
  const validation = periodValidation(data, p);
  const products = productAnalysis(
    data,
    analysis,
    categoryRun,
    mainRules.rules,
    customers,
    validation,
    p,
  );
  const difference = (a: Map<string, Itemset>, b: Map<string, Itemset>) =>
    [...a.values()].filter((e) => b.get(key(e.items))?.count !== e.count).sort(sizeOrder);
  const onlyApriori = difference(analysis.frequent, fp.frequent);
  const onlyFp = difference(fp.frequent, analysis.frequent);
  const match = !onlyApriori.length && !onlyFp.length;
  const sizes = data.baskets.map((b) => b.items.size);
  const largest = Math.max(...sizes);
  const total = baskets.length;
  const summary = data.errors.map((error) => `ERROR ${error}`);
  summary.push(
    `ITEMS rows ${data.itemRows} adopted ${data.products.size} categories ${data.categories.length}`,
    `TRANSACTIONS lines ${data.transactionRows} adopted ${data.adopted} rejected ${data.transactionRows - data.adopted} duplicates ${data.duplicates} transactions ${data.transactions.length} empty ${data.transactions.length - total}`,
    `BASKETS count ${total} customers ${customers.customers.size} first_day ${data.firstDay} last_day ${data.lastDay} average_size ${f(new Fraction(sum(sizes), total))} largest ${largest}`,
  );
  for (let size = 1; size <= largest; size++) {
    const count = sizes.filter((v) => v === size).length;
    summary.push(`SIZE ${size} baskets ${count} share ${pct(count, total)}`);
  }
  summary.push(
    `FREQUENT itemsets ${analysis.frequent.size} closed ${classified.closed.length} maximal ${classified.maximal.length} generators ${classified.generators.length} levels ${analysis.levels.length}`,
    `FPGROWTH header ${fp.header} nodes ${fp.nodes} conditional_trees ${fp.conditionalTrees} conditional_nodes ${fp.conditionalNodes} itemsets ${fp.frequent.size} ${match ? 'MATCH' : 'MISMATCH'}`,
  );
  for (const e of onlyApriori) summary.push(`ONLY_APRIORI ${key(e.items)} ${e.count}`);
  for (const e of onlyFp) summary.push(`ONLY_FPGROWTH ${key(e.items)} ${e.count}`);
  summary.push(
    `RULES generated ${mainRules.generated} passed ${mainRules.rules.length} productive ${mainRules.productive}`,
  );
  for (const l of categoryRun.levels) {
    summary.push(
      `CATEGORY_LEVEL ${l.number} candidates ${l.candidates} taxonomy ${l.excluded} pruned ${l.pruned} counted ${l.counted} frequent ${l.entries.length}`,
    );
  }
  summary.push(
    `CATEGORY_RULES itemsets ${categoryRun.frequent.size} generated ${categoryRules.generated} passed ${categoryRules.rules.length} productive ${categoryRules.productive}`,
    `SEQUENCES customers ${customers.customers.size} multi_day ${sequential.multiDay} pairs ${sequential.pairs} frequent ${sequential.count}`,
  );
  const itemsetLines: string[] = [];
  const closedLines: string[] = [];
  for (const l of analysis.levels) {
    itemsetLines.push(
      `LEVEL ${l.number} candidates ${l.candidates} pruned ${l.pruned} counted ${l.counted} frequent ${l.entries.length}`,
    );
    for (const e of l.entries) itemsetLines.push(`${key(e.items)} ${e.count}`);
  }
  for (const [label, entries] of [
    ['CLOSED', classified.closed],
    ['MAXIMAL', classified.maximal],
    ['GENERATOR', classified.generators],
  ] satisfies [string, Itemset[]][]) {
    for (const e of entries) closedLines.push(`${label} ${key(e.items)} ${e.count}`);
  }
  writeFiles({
    'summary.txt': summary,
    'itemsets.txt': itemsetLines,
    'closed_maximal.txt': closedLines,
    'rules.csv': ruleLines(mainRules.rules),
    'category_rules.csv': ruleLines(categoryRules.rules),
    'sequences.txt': sequential.lines,
    'validation.txt': validation.lines,
    'items_report.txt': products.lines,
    'trends.txt': weeklyTrends(data, p),
    'customers.txt': customerLines(data, customers, mainRules.rules, products.totalRevenue, p),
  });
}
main();
