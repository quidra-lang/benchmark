const fs = require('node:fs');
const { Product, Transaction, readCsv, buildBasket, extendBasket, contains,
  compareNames, compareItemsets, itemsetKey } = require('./baskets');
const { SupportCounter, candidates, countCandidates } = require('./apriori');
const fpgrowth = require('./fpgrowth');
const { Fraction, createRule, passes, compareRules, ruleKey } = require('./rules');
const { quotient, fraction, percentage, money, itemset, ruleLines, writeFiles } = require('./report');

function readParameters() {
  const parameters = {};
  for (const line of fs.readFileSync('input/params.txt', 'ascii').slice(0, -1).split('\n')) {
    const [name, value] = line.split(' ');
    parameters[name] = value.includes('/') ? new Fraction(...value.split('/')) : Number(value);
  }
  return parameters;
}

function readData() {
  const products = new Map();
  const errors = [];
  const itemRows = readCsv('input/items.csv');
  for (const row of itemRows) {
    const [name, category, priceText] = row.fields;
    const price = Number(priceText);
    let error = null;
    if (products.has(name)) error = `duplicate item ${name}`;
    else if (price === 0) error = `bad price ${price}`;
    if (error !== null) errors.push(`items.csv line ${row.line}: ${error}`);
    else products.set(name, new Product(name, category, price));
  }
  const transactionRows = readCsv('input/transactions.csv');
  const transactions = [];
  const byTid = new Map();
  let adopted = 0;
  let duplicates = 0;
  for (const row of transactionRows) {
    const [tid, customer, dayText, name] = row.fields;
    const day = Number(dayText);
    let previous = transactions.at(-1);
    if (previous !== undefined && previous.tid !== tid && byTid.has(tid)) {
      errors.push(`transactions.csv line ${row.line}: tid ${tid} not contiguous`);
      continue;
    }
    if (!byTid.has(tid)) {
      previous = new Transaction(tid, customer, day);
      transactions.push(previous);
      byTid.set(tid, previous);
    }
    let error = null;
    if (customer !== previous.customer) error = `tid ${tid} customer ${customer} differs from ${previous.customer}`;
    else if (day !== previous.day) error = `tid ${tid} day ${day} differs from ${previous.day}`;
    else if (!products.has(name)) error = `unknown item ${name}`;
    if (error !== null) {
      errors.push(`transactions.csv line ${row.line}: ${error}`);
    } else {
      if (previous.add(name)) duplicates += 1;
      adopted += 1;
    }
  }
  const baskets = transactions.filter(transaction => transaction.units.size > 0).map(buildBasket);
  const names = [...products.keys()].sort(compareNames);
  const categories = [...new Set([...products.values()].map(product => product.category))].sort(compareNames);
  const days = baskets.map(basket => basket.day);
  return { products, names, categories, transactions, baskets, errors, adopted, duplicates,
    itemRows: itemRows.length, transactionRows: transactionRows.length,
    firstDay: Math.min(...days), lastDay: Math.max(...days) };
}

function runApriori(baskets, universe, minimum, maximum, taxonomy = null) {
  const counter = new SupportCounter(baskets);
  const frequent = new Map();
  const levels = [];
  let previous = [];
  for (let size = 1; size <= maximum; size += 1) {
    if (size > 1 && previous.length === 0) break;
    const generated = size === 1
      ? { items: universe.map(name => [name]), candidates: universe.length, excluded: 0,
        pruned: 0, counted: universe.length }
      : candidates(previous, taxonomy);
    generated.items.sort(compareItemsets);
    const entries = countCandidates(generated.items, counter, minimum);
    levels.push({ number: size, candidates: generated.candidates, excluded: generated.excluded,
      pruned: generated.pruned, counted: generated.counted, entries });
    for (const entry of entries) frequent.set(itemsetKey(entry.items), entry);
    previous = entries.map(entry => entry.items);
  }
  return { count: baskets.length, counter, frequent, levels };
}

function sizeOrder(first, second) {
  return first.items.length - second.items.length || compareItemsets(first.items, second.items);
}

function support(run, items) {
  return items.length === 0 ? run.count : run.frequent.get(itemsetKey(items)).count;
}

function classifyItemsets(run) {
  const entries = [...run.frequent.values()].sort(sizeOrder);
  for (const entry of entries) {
    entry.closed = true;
    entry.maximal = true;
    entry.generator = entry.items.every((item, index) =>
      support(run, entry.items.filter((value, position) => position !== index)) > entry.count);
  }
  for (const entry of entries) {
    if (entry.items.length < 2) continue;
    for (let index = 0; index < entry.items.length; index += 1) {
      const subset = entry.items.filter((item, position) => position !== index);
      const smaller = run.frequent.get(itemsetKey(subset));
      smaller.maximal = false;
      if (smaller.count === entry.count) smaller.closed = false;
    }
  }
  return { closed: entries.filter(entry => entry.closed), maximal: entries.filter(entry => entry.maximal),
    generators: entries.filter(entry => entry.generator) };
}

function crossCheck(apriori, fp) {
  const difference = (first, second) => [...first.values()].filter(entry =>
    second.get(itemsetKey(entry.items))?.count !== entry.count).sort(sizeOrder);
  const onlyApriori = difference(apriori.frequent, fp.frequent);
  const onlyFp = difference(fp.frequent, apriori.frequent);
  return { onlyApriori, onlyFp, verdict: onlyApriori.length === 0 && onlyFp.length === 0 ? 'MATCH' : 'MISMATCH' };
}

function* subsets(items, index = 0, chosen = []) {
  if (index === items.length) {
    yield chosen;
    return;
  }
  yield* subsets(items, index + 1, chosen);
  yield* subsets(items, index + 1, [...chosen, items[index]]);
}

function makeRules(run, parameters, categories = null) {
  const rules = [];
  let generated = 0;
  for (const entry of run.frequent.values()) {
    if (entry.items.length < 2 || categories !== null && !entry.items.some(item => categories.has(item))) continue;
    for (const antecedent of subsets(entry.items)) {
      if (antecedent.length === 0 || antecedent.length === entry.items.length) continue;
      generated += 1;
      const first = new Set(antecedent);
      const consequent = entry.items.filter(item => !first.has(item));
      const rule = createRule(antecedent, consequent, support(run, antecedent), support(run, consequent), entry.count, run.count);
      if (!passes(rule, parameters.min_confidence, parameters.min_lift)) continue;
      let baseline = new Fraction(support(run, consequent), run.count);
      for (const subset of subsets(antecedent)) {
        if (subset.length === 0 || subset.length === antecedent.length) continue;
        const joined = [...subset, ...consequent].sort(compareNames);
        const confidence = new Fraction(support(run, joined), support(run, subset));
        if (confidence.compare(baseline) > 0) baseline = confidence;
      }
      rule.improvement = rule.confidence.subtract(baseline);
      rule.items = entry.items;
      rules.push(rule);
    }
  }
  rules.sort(compareRules);
  rules.forEach((rule, index) => { rule.rank = index + 1; });
  return { rules, generated, productive: rules.filter(rule => rule.improvement.numerator > 0n).length };
}

function collectCustomers(data) {
  const customers = new Map();
  const buyers = new Map(data.names.map(name => [name, 0]));
  for (const basket of data.baskets) {
    if (!customers.has(basket.customer)) {
      customers.set(basket.customer, { id: basket.customer, baskets: [], daySet: new Set(), purchases: new Map(),
        categoryUnits: new Map(), units: 0, revenue: 0 });
    }
    const customer = customers.get(basket.customer);
    customer.baskets.push(basket);
    customer.daySet.add(basket.day);
    for (const [name, units] of basket.units) {
      if (!customer.purchases.has(name)) customer.purchases.set(name, new Set());
      customer.purchases.get(name).add(basket.day);
      const product = data.products.get(name);
      customer.categoryUnits.set(product.category, (customer.categoryUnits.get(product.category) ?? 0) + units);
      customer.units += units;
      customer.revenue += units * product.price;
    }
  }
  for (const customer of customers.values()) {
    customer.days = [...customer.daySet].sort((first, second) => first - second);
    for (const [name, days] of customer.purchases) {
      customer.purchases.set(name, [...days].sort((first, second) => first - second));
      buyers.set(name, buyers.get(name) + 1);
    }
    customer.items = new Set(customer.purchases.keys());
  }
  return { customers, buyers };
}

function median(values) {
  const sorted = values.slice().sort((first, second) => first - second);
  const middle = quotient(sorted.length, 2);
  return sorted.length % 2 === 1 ? new Fraction(sorted[middle]) : new Fraction(sorted[middle - 1] + sorted[middle], 2);
}

function minimumGap(first, second) {
  let index = 0;
  let smallest = null;
  for (const day of second) {
    while (index < first.length && first[index] < day) index += 1;
    if (index > 0) {
      const gap = day - first[index - 1];
      if (smallest === null || gap < smallest) smallest = gap;
    }
  }
  return smallest;
}

function sequences(customerData, parameters) {
  const { customers, buyers } = customerData;
  const pairs = new Map();
  const intervals = new Map();
  for (const customer of customers.values()) {
    for (const [first, days] of customer.purchases) {
      if (days.length >= 2) {
        if (!intervals.has(first)) intervals.set(first, { name: first, customers: 0, gaps: [] });
        const repeat = intervals.get(first);
        repeat.customers += 1;
        for (let index = 1; index < days.length; index += 1) repeat.gaps.push(days[index] - days[index - 1]);
      }
      for (const [second, later] of customer.purchases) {
        if (days[0] >= later.at(-1)) continue;
        const key = `${first}->${second}`;
        if (!pairs.has(key)) pairs.set(key, { first, second, gaps: [] });
        pairs.get(key).gaps.push(minimumGap(days, later));
      }
    }
  }
  const frequent = [];
  for (const pair of pairs.values()) {
    const count = pair.gaps.length;
    if (count < parameters.sequence_min_support) continue;
    frequent.push({ ...pair, count, base: buyers.get(pair.first),
      confidence: new Fraction(count, buyers.get(pair.first)),
      lift: new Fraction(count * customers.size, buyers.get(pair.first) * buyers.get(pair.second)), gap: median(pair.gaps) });
  }
  frequent.sort((first, second) => second.count - first.count || second.confidence.compare(first.confidence)
    || compareNames(first.first, second.first) || compareNames(first.second, second.second));
  frequent.forEach((sequence, index) => { sequence.rank = index + 1; });
  const repeats = [...intervals.values()];
  for (const repeat of repeats) {
    repeat.mean = new Fraction(repeat.gaps.reduce((total, gap) => total + gap, 0), repeat.gaps.length);
    repeat.median = median(repeat.gaps);
    repeat.minimum = Math.min(...repeat.gaps);
    repeat.maximum = Math.max(...repeat.gaps);
  }
  repeats.sort((first, second) => first.mean.compare(second.mean) || compareNames(first.name, second.name));
  return { frequent, repeats, pairs: pairs.size,
    multiDay: [...customers.values()].filter(customer => customer.days.length >= 2).length };
}

function recommend(held, candidates_, maximum) {
  const selected = new Set();
  for (const name of candidates_) {
    if (!held.has(name)) selected.add(name);
    if (selected.size === maximum) break;
  }
  return [...selected];
}

function ruleRecommendation(held, rules, maximum) {
  function* candidates_() {
    for (const rule of rules) {
      if (rule.consequent.length === 1 && contains(held, rule.antecedent)) yield rule.consequent[0];
    }
  }
  return recommend(held, candidates_(), maximum);
}

function evaluationCounts() {
  return { cases: 0, covered: 0, hit1: 0, hit: 0, baseline: 0 };
}

function periodValidation(data, parameters) {
  const training = data.baskets.filter(basket => basket.day <= parameters.split_day);
  const testing = data.baskets.filter(basket => basket.day > parameters.split_day);
  const train = runApriori(training.map(basket => basket.items), data.names, parameters.train_min_support, parameters.max_size);
  const test = runApriori(testing.map(basket => basket.items), data.names, parameters.test_min_support, parameters.max_size);
  const trainingRules = makeRules(train, parameters).rules;
  const testRules = makeRules(test, parameters).rules;
  const verdicts = trainingRules.map(rule => {
    const a = test.counter.count(rule.antecedent);
    const b = test.counter.count(rule.consequent);
    const count = test.counter.count(rule.items);
    if (a === 0 || b === 0) return { rule, a, count, verdict: 'UNSEEN', confidence: null, lift: null };
    const confidence = new Fraction(count, a);
    const lift = new Fraction(test.count * count, a * b);
    const verdict = confidence.compare(parameters.min_confidence) >= 0 && lift.compare(parameters.min_lift) >= 0 ? 'HOLD' : 'FAIL';
    return { rule, a, count, verdict, confidence, lift };
  });
  const known = new Set(trainingRules.map(ruleKey));
  const emerging = testRules.filter(rule => !known.has(ruleKey(rule)));
  const popularity = data.names.slice().sort((first, second) => train.counter.count([second]) - train.counter.count([first])
    || compareNames(first, second));
  const sizes = new Map();
  const total = evaluationCounts();
  const heldout = new Map(data.names.map(name => [name, { count: 0, hits: 0 }]));
  for (const basket of testing) {
    if (basket.items.size < 2) continue;
    if (!sizes.has(basket.items.size)) sizes.set(basket.items.size, evaluationCounts());
    for (const hidden of basket.items) {
      const held = new Set(basket.items);
      held.delete(hidden);
      const suggested = ruleRecommendation(held, trainingRules, parameters.recommend_top);
      const baseline = recommend(held, popularity, parameters.recommend_top);
      const result = { cases: 1, covered: Number(suggested.length > 0), hit1: Number(suggested[0] === hidden),
        hit: Number(suggested.includes(hidden)), baseline: Number(baseline.includes(hidden)) };
      for (const counts of [total, sizes.get(basket.items.size)]) {
        for (const field of Object.keys(result)) counts[field] += result[field];
      }
      heldout.get(hidden).count += 1;
      heldout.get(hidden).hits += result.hit;
    }
  }
  return { train, test, trainingRules, verdicts, emerging, sizes, total, heldout };
}

function productSummary(data, main, categoryRun, mainRules, customerData, validation, parameters) {
  const products = new Map(data.names.map(name => [name, { product: data.products.get(name), units: 0, revenue: 0,
    count: main.counter.count([name]), buyers: customerData.buyers.get(name), itemsets: 0, partner: null, best: null,
    heldout: validation.heldout.get(name) }]));
  for (const basket of data.baskets) {
    for (const [name, units] of basket.units) products.get(name).units += units;
  }
  const pairs = [];
  for (const entry of main.frequent.values()) {
    for (const name of entry.items) products.get(name).itemsets += 1;
    if (entry.items.length === 2) {
      const [first, second] = entry.items;
      const lift = new Fraction(main.count * entry.count, products.get(first).count * products.get(second).count);
      pairs.push({ first, second, count: entry.count, lift });
      for (const [name, other] of [[first, second], [second, first]]) {
        const product = products.get(name);
        const old = product.partner;
        if (old === null || lift.compare(old.lift) > 0
            || lift.compare(old.lift) === 0 && (entry.count > old.count
              || entry.count === old.count && compareNames(other, old.name) < 0)) {
          product.partner = { name: other, count: entry.count, lift };
        }
      }
    }
  }
  for (const rule of mainRules.rules) {
    for (const name of rule.items) if (products.get(name).best === null) products.get(name).best = rule;
  }
  const categories = new Map(data.categories.map(name => [name, { name, items: 0, units: 0, revenue: 0,
    count: categoryRun.counter.count([name]) }]));
  let totalUnits = 0;
  let totalRevenue = 0;
  for (const row of products.values()) {
    row.revenue = row.units * row.product.price;
    const category = categories.get(row.product.category);
    category.items += 1;
    category.units += row.units;
    category.revenue += row.revenue;
    totalUnits += row.units;
    totalRevenue += row.revenue;
  }
  const adjacency = new Map(data.names.map(name => [name, new Set()]));
  for (const pair of pairs) {
    if (pair.lift.compare(parameters.group_min_lift) >= 0) {
      adjacency.get(pair.first).add(pair.second);
      adjacency.get(pair.second).add(pair.first);
    }
  }
  const seen = new Set();
  const groups = [];
  for (const name of data.names) {
    if (seen.has(name)) continue;
    const members = [];
    const pending = [name];
    while (pending.length > 0) {
      const item = pending.pop();
      if (seen.has(item)) continue;
      seen.add(item);
      members.push(item);
      pending.push(...adjacency.get(item));
    }
    if (members.length < 2) continue;
    members.sort(compareNames);
    const core = members.slice().sort((first, second) => adjacency.get(second).size - adjacency.get(first).size
      || products.get(second).count - products.get(first).count || compareNames(first, second))[0];
    groups.push({ members, core, edges: quotient(members.reduce((sum, item) => sum + adjacency.get(item).size, 0), 2),
      revenue: members.reduce((sum, item) => sum + products.get(item).revenue, 0) });
  }
  groups.sort((first, second) => second.members.length - first.members.length || compareNames(first.members[0], second.members[0]));
  const singles = main.levels[0].entries.map(entry => entry.items[0]);
  const substitutes = [];
  for (let first = 0; first < singles.length; first += 1) {
    for (let second = first + 1; second < singles.length; second += 1) {
      const a = singles[first];
      const b = singles[second];
      const expectedNumerator = products.get(a).count * products.get(b).count;
      if (expectedNumerator < parameters.negative_min_expected * main.count) continue;
      const count = main.counter.count([a, b]);
      const lift = new Fraction(main.count * count, expectedNumerator);
      if (lift.compare(parameters.negative_max_lift) <= 0) {
        substitutes.push({ a, b, count, lift, expected: new Fraction(expectedNumerator, main.count) });
      }
    }
  }
  substitutes.sort((first, second) => first.lift.compare(second.lift) || second.expected.compare(first.expected)
    || compareNames(first.a, second.a) || compareNames(first.b, second.b));
  return { products, categories, totalUnits, totalRevenue, groups, substitutes };
}

function weeklyTrends(data, parameters) {
  const weeks = quotient(data.lastDay - 1, 7) + 1;
  const basketCounts = Array(weeks).fill(0);
  const unitCounts = Array(weeks).fill(0);
  const customers = Array.from({ length: weeks }, () => new Set());
  const names = [...data.categories, ...data.names];
  const series = new Map(names.map(name => [name, Array(weeks).fill(0)]));
  for (const basket of data.baskets) {
    const week = quotient(basket.day - 1, 7);
    basketCounts[week] += 1;
    customers[week].add(basket.customer);
    for (const [name, units] of basket.units) {
      unitCounts[week] += units;
      series.get(name)[week] += units;
      series.get(data.products.get(name).category)[week] += units;
    }
  }
  let sumW = 0;
  let sumWW = 0;
  for (let week = 1; week <= weeks; week += 1) {
    sumW += week;
    sumWW += week * week;
  }
  const trends = [];
  for (const [name, values] of series) {
    let units = 0;
    let weighted = 0;
    values.forEach((value, index) => { units += value; weighted += (index + 1) * value; });
    const slope = new Fraction(weeks * weighted - sumW * units, weeks * sumWW - sumW * sumW);
    const relative = units > 0 ? slope.multiply(new Fraction(weeks, units)) : null;
    let verdict = 'NONE';
    if (relative !== null) {
      verdict = relative.compare(parameters.trend_threshold) >= 0 ? 'RISING'
        : relative.compare(parameters.trend_threshold.negate()) <= 0 ? 'FALLING' : 'FLAT';
    }
    trends.push({ name, units, slope, relative, verdict });
  }
  trends.sort((first, second) => {
    if (first.relative === null && second.relative !== null) return 1;
    if (first.relative !== null && second.relative === null) return -1;
    return (first.relative === null ? 0 : second.relative.compare(first.relative)) || compareNames(first.name, second.name);
  });
  const row = (label, values) => label.padEnd(17) + values.map(value => String(value).padStart(6)).join('');
  const lines = [row('WEEK', Array.from({ length: weeks }, (value, index) => index + 1)),
    row('BASKETS', basketCounts), row('UNITS', unitCounts), row('CUSTOMERS', customers.map(set => set.size))];
  for (const name of names) lines.push(row(name, series.get(name)));
  for (const trend of trends) {
    lines.push(`TREND ${trend.name} units ${trend.units} slope ${fraction(trend.slope)} `
      + `relative ${trend.relative === null ? '-' : fraction(trend.relative)} ${trend.verdict}`);
  }
  return lines;
}

function customerLines(data, customerData, mainRules, summary, parameters) {
  const segments = new Map(['NEW', 'LOYAL', 'AT_RISK', 'REGULAR'].map(name => [name, { customers: 0, revenue: 0 }]));
  const customers = [...customerData.customers.values()].sort((first, second) => compareNames(first.id, second.id));
  const lines = [];
  for (const customer of customers) {
    const first = customer.days[0];
    const last = customer.days.at(-1);
    let segment;
    if (first > data.lastDay - 28) segment = 'NEW';
    else if (customer.baskets.length >= 4 && data.lastDay - last <= 14) segment = 'LOYAL';
    else if (data.lastDay - last > 28) segment = 'AT_RISK';
    else segment = 'REGULAR';
    const favorite = [...customer.categoryUnits.keys()].sort((a, b) => customer.categoryUnits.get(b) - customer.categoryUnits.get(a)
      || compareNames(a, b))[0];
    const offer = ruleRecommendation(customer.items, mainRules.rules, parameters.recommend_top);
    lines.push(`CUSTOMER ${customer.id} baskets ${customer.baskets.length} days ${customer.days.length} first ${first} last ${last} `
      + `items ${customer.items.size} units ${customer.units} revenue ${money(customer.revenue)} `
      + `average ${money(quotient(customer.revenue, customer.baskets.length))} favorite ${favorite} segment ${segment} offer ${offer.join('+') || 'none'}`);
    segments.get(segment).customers += 1;
    segments.get(segment).revenue += customer.revenue;
  }
  for (const [name, counts] of segments) {
    lines.push(`SEGMENT ${name} customers ${counts.customers} revenue ${money(counts.revenue)} share ${percentage(counts.revenue, summary.totalRevenue)}`);
  }
  return lines;
}

function summaryLines(data, main, classified, fp, check, mainRules, categoryRun, categoryRules, customerData, sequential) {
  const total = data.baskets.length;
  const sizes = data.baskets.map(basket => basket.items.size);
  const largest = Math.max(...sizes);
  const lines = data.errors.map(error => `ERROR ${error}`);
  lines.push(`ITEMS rows ${data.itemRows} adopted ${data.products.size} categories ${data.categories.length}`);
  lines.push(`TRANSACTIONS lines ${data.transactionRows} adopted ${data.adopted} rejected ${data.transactionRows - data.adopted} `
    + `duplicates ${data.duplicates} transactions ${data.transactions.length} empty ${data.transactions.length - total}`);
  lines.push(`BASKETS count ${total} customers ${customerData.customers.size} first_day ${data.firstDay} last_day ${data.lastDay} `
    + `average_size ${fraction(new Fraction(sizes.reduce((sum, size) => sum + size, 0), total))} largest ${largest}`);
  for (let size = 1; size <= largest; size += 1) {
    const count = sizes.filter(value => value === size).length;
    lines.push(`SIZE ${size} baskets ${count} share ${percentage(count, total)}`);
  }
  lines.push(`FREQUENT itemsets ${main.frequent.size} closed ${classified.closed.length} maximal ${classified.maximal.length} `
    + `generators ${classified.generators.length} levels ${main.levels.length}`);
  lines.push(`FPGROWTH header ${fp.header} nodes ${fp.nodes} conditional_trees ${fp.conditionalTrees} `
    + `conditional_nodes ${fp.conditionalNodes} itemsets ${fp.frequent.size} ${check.verdict}`);
  for (const entry of check.onlyApriori) lines.push(`ONLY_APRIORI ${itemset(entry.items)} ${entry.count}`);
  for (const entry of check.onlyFp) lines.push(`ONLY_FPGROWTH ${itemset(entry.items)} ${entry.count}`);
  lines.push(`RULES generated ${mainRules.generated} passed ${mainRules.rules.length} productive ${mainRules.productive}`);
  for (const level of categoryRun.levels) {
    lines.push(`CATEGORY_LEVEL ${level.number} candidates ${level.candidates} taxonomy ${level.excluded} `
      + `pruned ${level.pruned} counted ${level.counted} frequent ${level.entries.length}`);
  }
  lines.push(`CATEGORY_RULES itemsets ${categoryRun.frequent.size} generated ${categoryRules.generated} `
    + `passed ${categoryRules.rules.length} productive ${categoryRules.productive}`);
  lines.push(`SEQUENCES customers ${customerData.customers.size} multi_day ${sequential.multiDay} pairs ${sequential.pairs} frequent ${sequential.frequent.length}`);
  return lines;
}

function itemsetLines(main) {
  const lines = [];
  for (const level of main.levels) {
    lines.push(`LEVEL ${level.number} candidates ${level.candidates} pruned ${level.pruned} counted ${level.counted} frequent ${level.entries.length}`);
    for (const entry of level.entries) lines.push(`${itemset(entry.items)} ${entry.count}`);
  }
  return lines;
}

function closedLines(classified) {
  const lines = [];
  for (const [label, entries] of [['CLOSED', classified.closed], ['MAXIMAL', classified.maximal], ['GENERATOR', classified.generators]]) {
    for (const entry of entries) lines.push(`${label} ${itemset(entry.items)} ${entry.count}`);
  }
  return lines;
}

function sequenceLines(sequential) {
  const lines = [];
  for (const sequence of sequential.frequent) {
    lines.push(`SEQ ${sequence.rank} ${sequence.first} -> ${sequence.second} customers ${sequence.count} base ${sequence.base} `
      + `confidence ${fraction(sequence.confidence)} lift ${fraction(sequence.lift)} gap ${fraction(sequence.gap)}`);
  }
  for (const repeat of sequential.repeats) {
    lines.push(`REPEAT ${repeat.name} customers ${repeat.customers} intervals ${repeat.gaps.length} min ${repeat.minimum} max ${repeat.maximum} `
      + `mean ${fraction(repeat.mean)} median ${fraction(repeat.median)}`);
  }
  return lines;
}

function recommendationLine(label, counts) {
  return `RECOMMEND ${label} cases ${counts.cases} covered ${counts.covered} hit1 ${counts.hit1} hit ${counts.hit} `
    + `rate ${fraction(new Fraction(counts.hit, counts.cases))} baseline ${counts.baseline} rate ${fraction(new Fraction(counts.baseline, counts.cases))}`;
}

function validationLines(validation) {
  const lines = [];
  const counts = { HOLD: 0, FAIL: 0, UNSEEN: 0 };
  for (const result of validation.verdicts) {
    const rule = result.rule;
    counts[result.verdict] += 1;
    lines.push(`RULE ${rule.rank} ${itemset(rule.antecedent)} -> ${itemset(rule.consequent)} train ${rule.count} `
      + `confidence ${fraction(rule.confidence)} lift ${fraction(rule.lift)} test ${result.count} of ${result.a} `
      + `confidence ${result.confidence === null ? '-' : fraction(result.confidence)} `
      + `lift ${result.lift === null ? '-' : fraction(result.lift)} ${result.verdict}`);
  }
  for (const rule of validation.emerging) {
    lines.push(`EMERGING ${rule.rank} ${itemset(rule.antecedent)} -> ${itemset(rule.consequent)} test ${rule.count} `
      + `confidence ${fraction(rule.confidence)} lift ${fraction(rule.lift)}`);
  }
  lines.push(`VALIDATION train ${validation.train.count} test ${validation.test.count} itemsets ${validation.train.frequent.size} `
    + `rules ${validation.trainingRules.length} hold ${counts.HOLD} fail ${counts.FAIL} unseen ${counts.UNSEEN} emerging ${validation.emerging.length}`);
  for (const size of [...validation.sizes.keys()].sort((first, second) => first - second)) {
    lines.push(recommendationLine(`size ${size}`, validation.sizes.get(size)));
  }
  lines.push(recommendationLine('total', validation.total));
  return lines;
}

function matrixLines(prefix, names, counter) {
  const counts = names.map(name => counter.count([name]));
  const lines = names.map((name, index) => `${prefix} ${index + 1} ${name} baskets ${counts[index]}`);
  lines.push('    ' + names.map((name, index) => String(index + 1).padStart(7)).join(''));
  for (let first = 0; first < names.length; first += 1) {
    const cells = names.map((name, second) => {
      if (first === second) return '-';
      const pair = [names[first], name].sort(compareNames);
      return String(quotient(100 * counter.size * counter.count(pair), counts[first] * counts[second]));
    });
    lines.push(String(first + 1).padStart(4) + cells.map(cell => cell.padStart(7)).join(''));
  }
  return lines;
}

function productLines(data, main, categoryRun, summary, customerData, parameters) {
  const rows = [...summary.products.values()].sort((first, second) => second.revenue - first.revenue
    || compareNames(first.product.name, second.product.name));
  const lines = [];
  rows.forEach((row, index) => {
    const product = row.product;
    const partner = row.partner === null ? 'none' : `${row.partner.name} ${fraction(row.partner.lift)}`;
    const best = row.best === null ? 'none' : `${row.best.rank} ${itemset(row.best.antecedent)} -> ${itemset(row.best.consequent)}`;
    lines.push(`ITEM ${index + 1} ${product.name} ${product.category} price ${money(product.price)} units ${row.units} revenue ${money(row.revenue)} `
      + `share ${percentage(row.revenue, summary.totalRevenue)} baskets ${row.count} support ${fraction(new Fraction(row.count, main.count))} `
      + `customers ${row.buyers} itemsets ${row.itemsets} heldout ${row.heldout.count} hits ${row.heldout.hits} partner ${partner} best ${best}`);
  });
  const categories = [...summary.categories.values()].sort((first, second) => second.revenue - first.revenue || compareNames(first.name, second.name));
  for (const category of categories) {
    lines.push(`CATEGORY ${category.name} items ${category.items} units ${category.units} revenue ${money(category.revenue)} `
      + `share ${percentage(category.revenue, summary.totalRevenue)} baskets ${category.count} support ${fraction(new Fraction(category.count, main.count))}`);
  }
  lines.push(`TOTAL items ${data.products.size} units ${summary.totalUnits} revenue ${money(summary.totalRevenue)} baskets ${main.count} customers ${customerData.customers.size}`);
  summary.groups.forEach((group, index) => {
    lines.push(`GROUP ${index + 1} items ${group.members.length} edges ${group.edges} core ${group.core} revenue ${money(group.revenue)} `
      + `share ${percentage(group.revenue, summary.totalRevenue)} members ${itemset(group.members)}`);
  });
  for (const pair of summary.substitutes) {
    lines.push(`SUBSTITUTE ${pair.a} ${pair.b} count ${pair.count} expected ${fraction(pair.expected)} lift ${fraction(pair.lift)}`);
  }
  const popular = (names, counter) => names.slice().sort((first, second) => counter.count([second]) - counter.count([first]) || compareNames(first, second));
  lines.push(...matrixLines('MATRIX', popular(data.names, main.counter).slice(0, parameters.matrix_size), main.counter));
  lines.push(...matrixLines('CATEGORY_MATRIX', popular(data.categories, categoryRun.counter), categoryRun.counter));
  return lines;
}

function main() {
  const parameters = readParameters();
  const data = readData();
  const baskets = data.baskets.map(basket => basket.items);
  const analysis = runApriori(baskets, data.names, parameters.min_support, parameters.max_size);
  const fp = fpgrowth.mine(baskets, parameters.min_support, parameters.max_size);
  const check = crossCheck(analysis, fp);
  const classified = classifyItemsets(analysis);
  const mainRules = makeRules(analysis, parameters);
  const taxonomy = new Map([...data.products.values()].map(product => [product.name, product.category]));
  const extended = data.baskets.map(basket => extendBasket(basket, data.products));
  const universe = [...data.names, ...data.categories].sort(compareNames);
  const categoryRun = runApriori(extended, universe, parameters.category_min_support, parameters.max_size, taxonomy);
  const categoryRules = makeRules(categoryRun, parameters, new Set(data.categories));
  const customerData = collectCustomers(data);
  const sequential = sequences(customerData, parameters);
  const validation = periodValidation(data, parameters);
  const summary = productSummary(data, analysis, categoryRun, mainRules, customerData, validation, parameters);
  writeFiles(new Map([
    ['summary.txt', summaryLines(data, analysis, classified, fp, check, mainRules, categoryRun, categoryRules, customerData, sequential)],
    ['itemsets.txt', itemsetLines(analysis)],
    ['closed_maximal.txt', closedLines(classified)],
    ['rules.csv', ruleLines(mainRules.rules)],
    ['category_rules.csv', ruleLines(categoryRules.rules)],
    ['sequences.txt', sequenceLines(sequential)],
    ['validation.txt', validationLines(validation)],
    ['items_report.txt', productLines(data, analysis, categoryRun, summary, customerData, parameters)],
    ['trends.txt', weeklyTrends(data, parameters)],
    ['customers.txt', customerLines(data, customerData, mainRules, summary, parameters)],
  ]));
}

if (require.main === module) main();
