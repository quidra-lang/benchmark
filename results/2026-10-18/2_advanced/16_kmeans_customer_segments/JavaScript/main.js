'use strict';

const { readTransactions, groupOrders } = require('./transactions');
const { FEATURES, SQUARE_ROOT, meanSD, customerFeatures, fitStandardization, standardize, correlation } = require('./features');
const { squaredDistance, meanPoint, clusterData, sumSquared, lloyd } = require('./kmeans');
const { distanceTable, clusterIndices, elbow, hartigan, adjustedRand } = require('./validation');
const { readRules, matchingRule, originalCenter } = require('./profiles');
const { real, rounded, amount, writeReport } = require('./report');

const compareText = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const yesNo = value => value ? 'yes' : 'no';
const numbers = values => values.map(real).join(' ');
const flattenBlocks = blocks => blocks.flatMap((block, index) => index === 0 ? block : ['', ...block]);
function sum(values) { let total = 0; for (const value of values) total += value; return total; }

class Minstd {
  constructor(seed) { this.state = seed; }
  next() { this.state = (48271 * this.state) % 2147483647; return this.state; }
}

function initialIndices(points, k, method, restart, random) {
  const chosen = [];
  if (method === 'forgy') {
    while (chosen.length < k) {
      const index = random.next() % points.length;
      if (!chosen.includes(index)) chosen.push(index);
    }
    return chosen;
  }
  if (method === 'maximin') {
    const center = meanPoint(points);
    const ranked = points.map((point, index) => ({ index, distance: squaredDistance(point, center) }))
      .sort((left, right) => left.distance - right.distance || left.index - right.index);
    chosen.push(ranked[restart - 1].index);
  } else chosen.push(random.next() % points.length);
  while (chosen.length < k) {
    const distances = points.map(point => {
      let best = squaredDistance(point, points[chosen[0]]);
      for (const index of chosen.slice(1)) best = Math.min(best, squaredDistance(point, points[index]));
      return best;
    });
    let selected = 0;
    if (method === 'maximin') {
      for (let index = 1; index < points.length; index++) if (distances[index] > distances[selected]) selected = index;
    } else {
      const total = sum(distances), threshold = (random.next() / 2147483647) * total;
      let cumulative = 0;
      selected = -1;
      for (let index = 0; index < points.length; index++) {
        cumulative += distances[index];
        if (cumulative > threshold) { selected = index; break; }
      }
      if (selected === -1) for (let index = 0; index < points.length; index++) if (distances[index] > 0) selected = index;
    }
    chosen.push(selected);
  }
  return chosen;
}

function refine(points, originalAssignment, k, limit) {
  const assignment = originalAssignment.slice();
  let { groups, centers } = clusterData(points, assignment, k);
  const counts = groups.map(group => group.length);
  let passes = 0, transfers = 0;
  while (passes < limit) {
    let changes = 0;
    for (let index = 0; index < points.length; index++) {
      const source = assignment[index], size = counts[source];
      if (size === 1) continue;
      const removal = (size / (size - 1)) * squaredDistance(points[index], centers[source]);
      let destination = -1, cost = 0;
      for (let target = 0; target < k; target++) {
        if (target === source) continue;
        const insertion = (counts[target] / (counts[target] + 1)) * squaredDistance(points[index], centers[target]);
        if (destination === -1 || insertion < cost) { destination = target; cost = insertion; }
      }
      if (cost < removal) {
        assignment[index] = destination;
        counts[source]--; counts[destination]++;
        centers[source] = meanPoint(points.filter((_, member) => assignment[member] === source));
        centers[destination] = meanPoint(points.filter((_, member) => assignment[member] === destination));
        changes++; transfers++;
      }
    }
    passes++;
    if (changes === 0) break;
  }
  ({ groups, centers } = clusterData(points, assignment, k));
  return { assignment, groups, centers, passes, transfers, sse: sumSquared(points, assignment, centers) };
}

function runClustering(points, k, method, restart, settings, random) {
  const seeds = initialIndices(points, k, method, restart, random);
  const result = lloyd(points, seeds.map(index => points[index]), settings.iterations);
  const refined = refine(points, result.assignment, k, settings.iterations);
  return { method, restart, seeds, result, refined, roundedSSE: rounded(refined.sse) };
}

function segmentOrder(points, refined) {
  const groups = refined.groups.slice().sort((left, right) => right.length - left.length || left[0] - right[0]);
  const assignment = Array(points.length), segments = groups.map((members, index) => {
    for (const member of members) assignment[member] = index;
    return { members, center: meanPoint(members.map(member => points[member])), number: index + 1 };
  });
  return { assignment, segments, sse: refined.sse };
}

function nameSegments(solution, rules) {
  const counts = new Map();
  for (const segment of solution.segments) {
    const rule = matchingRule(segment.center, rules), number = (counts.get(rule) || 0) + 1;
    counts.set(rule, number);
    segment.rule = rule + 1;
    segment.name = rules[rule].name + (number === 1 ? '' : '_' + number);
  }
}

function solveGrid(points, settings, rules, random) {
  const solutions = [];
  for (let k = settings.minK; k <= settings.maxK; k++) {
    const runs = [], bestMethods = new Map();
    let best = null;
    for (const method of settings.methods) {
      let methodBest = null;
      for (let restart = 1; restart <= settings.restarts; restart++) {
        const run = runClustering(points, k, method, restart, settings, random);
        runs.push(run);
        if (methodBest === null || run.roundedSSE < methodBest.roundedSSE) methodBest = run;
      }
      bestMethods.set(method, methodBest);
      if (best === null || methodBest.roundedSSE < best.roundedSSE) best = methodBest;
    }
    const solution = { k, ...segmentOrder(points, best.refined), runs, bestMethods, best };
    nameSegments(solution, rules);
    solutions.push(solution);
  }
  return solutions;
}

function chooseK(points, solutions, settings) {
  const distances = distanceTable(points);
  for (let index = 0; index < solutions.length; index++) {
    const solution = solutions[index];
    Object.assign(solution, clusterIndices(points, solution, distances));
    solution.elbow = elbow(solution.k, settings.minK, settings.maxK, solution.sse, solutions[0].sse, solutions.at(-1).sse);
    solution.hartigan = index + 1 < solutions.length ? hartigan(solution.sse, solutions[index + 1].sse, points.length, solution.k) : null;
    solution.votes = 0;
  }
  const votes = new Map();
  for (const [criterion, maximize] of [['elbow', true], ['silhouette', true], ['calinski_harabasz', true], ['davies_bouldin', false]]) {
    const candidates = criterion === 'elbow' ? solutions.slice(1, -1) : solutions;
    let best = candidates[0];
    for (const solution of candidates.slice(1)) {
      const value = rounded(solution[criterion]), current = rounded(best[criterion]);
      if (maximize ? value > current : value < current) best = solution;
    }
    votes.set(criterion, best.k);
  }
  votes.set('hartigan', (solutions.find(solution => solution.hartigan !== null && solution.hartigan <= 10) || solutions.at(-1)).k);
  for (const k of votes.values()) solutions[k - settings.minK].votes++;
  const chosen = [...solutions].sort((left, right) => right.votes - left.votes
    || rounded(right.silhouette) - rounded(left.silhouette) || left.k - right.k)[0];
  return { chosen, votes };
}

function customerResults(customers, solution) {
  for (let index = 0; index < customers.length; index++) {
    const customer = customers[index], own = solution.assignment[index];
    customer.number = index;
    customer.segment = own;
    customer.distance = Math.sqrt(squaredDistance(customer.point, solution.segments[own].center));
    customer.silhouette = solution.silhouettes[index];
    let other = -1, best = 0;
    for (let segment = 0; segment < solution.k; segment++) {
      if (segment === own) continue;
      const distance = squaredDistance(customer.point, solution.segments[segment].center);
      if (other === -1 || distance < best) { other = segment; best = distance; }
    }
    customer.other = other;
    customer.otherDistance = Math.sqrt(best);
    const ranks = [0, 0, 0];
    for (const candidate of customers) {
      if (candidate.raw[0] > customer.raw[0]) ranks[0]++;
      if (candidate.raw[1] < customer.raw[1]) ranks[1]++;
      if (candidate.spend < customer.spend) ranks[2]++;
    }
    customer.rfm = ranks.map(rank => 1 + Math.floor(5 * rank / customers.length));
    customer.code = customer.rfm.join('');
  }
}

function gini(customers) {
  const spends = customers.map(customer => customer.spend).sort((left, right) => left - right);
  let total = 0, weighted = 0;
  for (let index = 0; index < spends.length; index++) { total += spends[index]; weighted += (index + 1) * spends[index]; }
  return (2 * weighted - (spends.length + 1) * total) / (spends.length * total);
}

function categoryTotals(customers) {
  const totals = new Map();
  for (const customer of customers) for (const [category, spend] of customer.categorySpend) {
    totals.set(category, (totals.get(category) || 0) + spend);
  }
  return totals;
}

function buildProfiles(customers, solution, referenceOrders, settings) {
  return solution.segments.map(segment => {
    const members = segment.members.map(index => customers[index]), ids = new Set(members.map(customer => customer.id));
    const spend = sum(members.map(customer => customer.spend)), categories = categoryTotals(members);
    const categoryRanking = [...categories].filter(([, value]) => value > 0)
      .sort((left, right) => right[1] - left[1] || compareText(left[0], right[0]));
    let gaps = 0, gapTotal = 0, overdue = 0, sse = 0, gross = 0, returned = 0, cancelled = 0, silhouette = 0, negative = 0;
    const orderSizes = Array(settings.orderBins.length + 1).fill(0), rfm = [0, 0, 0], codes = new Map();
    for (const customer of members) {
      const [recency, frequency, , , , tenure] = customer.raw;
      if (frequency >= 2) {
        gaps++; gapTotal += (tenure - recency) / (frequency - 1);
        if (recency * (frequency - 1) > settings.overdueFactor * (tenure - recency)) overdue++;
      }
      for (const order of customer.purchases) orderSizes[settings.orderBins.filter(boundary => order.net >= boundary * 100).length]++;
      sse += squaredDistance(customer.point, segment.center);
      silhouette += customer.silhouette;
      if (customer.silhouette < 0) negative++;
      for (let component = 0; component < 3; component++) rfm[component] += customer.rfm[component];
      codes.set(customer.code, (codes.get(customer.code) || 0) + 1);
      customer.recommend = categoryRanking.find(([category]) => (customer.categorySpend.get(category) || 0) <= 0)?.[0] || '-';
    }
    for (const order of referenceOrders) if (ids.has(order.customer)) {
      if (order.net <= 0) cancelled++;
      for (const row of order.rows) {
        if (row.amount > 0) gross += row.amount;
        else returned -= row.amount;
      }
    }
    const mode = [...codes].sort((left, right) => right[1] - left[1] || compareText(left[0], right[0]))[0];
    let outliers = [];
    if (members.length >= 2) {
      const distances = meanSD(members.map(customer => customer.distance));
      outliers = members.filter(customer => customer.distance > distances.mean + settings.outlierSD * distances.sd);
    }
    const medians = FEATURES.map((_, feature) => {
      const values = members.map(customer => feature === 2 ? customer.spend : customer.raw[feature]).sort((left, right) => left - right);
      return values[Math.floor((members.length - 1) / 2)];
    });
    const traits = FEATURES.map((_, feature) => feature).sort((left, right) =>
      Math.abs(segment.center[right]) - Math.abs(segment.center[left]) || left - right).slice(0, 2)
      .map(feature => (segment.center[feature] > 0 ? 'high_' : 'low_') + FEATURES[feature]);
    return { segment, members, spend, categories, categoryRanking, gaps, meanGap: gaps === 0 ? null : gapTotal / gaps,
      overdue, orderSizes, sse, gross, returned, cancelled, silhouette: silhouette / members.length, negative,
      rfm: rfm.map(value => value / members.length), mode, outliers, medians, traits, gini: gini(members) };
  });
}

function relatedSegments(profile, solutions, k, settings) {
  const items = [];
  for (const neighbor of [k - 1, k + 1]) {
    if (neighbor < settings.minK || neighbor > settings.maxK) { items.push(`k=${neighbor} -`); continue; }
    const solution = solutions[neighbor - settings.minK], counts = Array(neighbor).fill(0);
    for (const customer of profile.members) counts[solution.assignment[customer.number]]++;
    let best = 0;
    for (let index = 1; index < counts.length; index++) if (counts[index] > counts[best]) best = index;
    items.push(`k=${neighbor} segment ${best + 1} shared ${counts[best]}`);
  }
  return items.join(' ');
}

function profileLines(customers, profiles, solutions, solution, scaling, totals, settings) {
  const totalSpend = sum(customers.map(customer => customer.spend));
  const blocks = [[`segments k=${solution.k} customers ${customers.length} revenue ${amount(totalSpend)} gini ${real(gini(customers))}`]];
  for (const profile of profiles) {
    const { segment, members, spend, medians } = profile;
    const original = originalCenter(segment.center, scaling);
    const top = [...members].sort((left, right) => right.spend - left.spend || left.number - right.number).slice(0, settings.topCustomers);
    const categories = profile.categoryRanking.slice(0, settings.topCategories).map(([category, value]) => {
      const share = value / spend, lift = share / (totals.get(category) / totalSpend);
      return `${category} ${real(share)} ${real(lift)}`;
    });
    blocks.push([
      `segment ${segment.number} ${segment.name} rule ${segment.rule} size ${members.length} share ${real(members.length / customers.length)}`
        + ` revenue ${amount(spend)} revenue_share ${real(spend / totalSpend)}`,
      '  center ' + numbers(segment.center),
      '  value ' + FEATURES.map((name, index) => `${name} ${real(original[index])}`).join(' '),
      '  traits ' + profile.traits.join(' '),
      `  median recency ${medians[0]} frequency ${medians[1]} monetary ${amount(medians[2])} basket ${real(medians[3])}`
        + ` categories ${medians[4]} tenure ${medians[5]}`,
      '  related ' + relatedSegments(profile, solutions, solution.k, settings),
      '  top_customers ' + top.map(customer => `${customer.id} ${amount(customer.spend)}`).join(' '),
      `  cadence customers ${profile.gaps} mean_gap ${real(profile.meanGap)} overdue ${profile.overdue}`,
      '  order_sizes ' + profile.orderSizes.join(' '),
      `  sse ${real(profile.sse)} share ${real(profile.sse / solution.sse)}`,
      `  gini ${real(profile.gini)}`,
      `  returns rate ${real(profile.returned / profile.gross)} returned ${amount(profile.returned)} cancelled ${profile.cancelled}`,
      `  silhouette ${real(profile.silhouette)} negative ${profile.negative}`,
      `  rfm r ${real(profile.rfm[0])} f ${real(profile.rfm[1])} m ${real(profile.rfm[2])} mode ${profile.mode[0]} ${profile.mode[1]}`,
      '  categories' + (categories.length === 0 ? '' : ' ' + categories.join(' ')),
      `  outliers ${profile.outliers.length}` + (profile.outliers.length === 0 ? '' : ' ' + profile.outliers.map(customer => customer.id).join(' ')),
    ]);
  }
  const segmentNumbers = solution.segments.map(segment => segment.number).join(' ');
  const mix = ['category_mix ' + segmentNumbers];
  for (const category of [...totals.keys()].sort(compareText)) {
    mix.push(category + ' ' + profiles.map(profile => real((profile.categories.get(category) || 0) / profile.spend)).join(' '));
  }
  blocks.push(mix);
  const recency = ['rfm_recency ' + segmentNumbers];
  for (const score of [5, 4, 3, 2, 1]) recency.push(`r=${score} ` + profiles.map(profile => profile.members.filter(customer => customer.rfm[0] === score).length).join(' '));
  recency.push('ari rfm_codes ' + real(adjustedRand(customers.map(customer => customer.code), solution.assignment)));
  blocks.push(recency);
  blocks.push(['center_distances', ...solution.segments.map(segment => `${segment.number} `
    + numbers(solution.segments.map(other => Math.sqrt(squaredDistance(segment.center, other.center)))))]);
  return flattenBlocks(blocks);
}

function subsampleLines(customers, solution, settings, random) {
  const n = customers.length, size = Math.floor(n * settings.percent / 100);
  const totals = Array(solution.k).fill(0), minima = Array(solution.k).fill(1);
  for (let sample = 0; sample < settings.subsamples; sample++) {
    const permutation = customers.map((_, index) => index);
    for (let position = 0; position < size; position++) {
      const other = position + random.next() % (n - position);
      [permutation[position], permutation[other]] = [permutation[other], permutation[position]];
    }
    const indices = permutation.slice(0, size).sort((left, right) => left - right);
    const result = lloyd(indices.map(index => customers[index].point), solution.segments.map(segment => segment.center), settings.iterations);
    const originalSizes = Array(solution.k).fill(0), trialSizes = Array(solution.k).fill(0);
    const intersections = solution.segments.map(() => Array(solution.k).fill(0));
    for (let position = 0; position < indices.length; position++) {
      const original = solution.assignment[indices[position]], trial = result.assignment[position];
      originalSizes[original]++; trialSizes[trial]++; intersections[original][trial]++;
    }
    for (let original = 0; original < solution.k; original++) {
      let best = 0;
      for (let trial = 0; trial < solution.k; trial++) {
        const common = intersections[original][trial], union = originalSizes[original] + trialSizes[trial] - common;
        const value = union === 0 ? 0 : common / union;
        best = Math.max(best, value);
      }
      totals[original] += best;
      minima[original] = Math.min(minima[original], best);
    }
  }
  return [`subsamples ${settings.subsamples} size ${size}`, ...solution.segments.map((segment, index) =>
    `segment ${segment.number} ${segment.name} mean_jaccard ${real(totals[index] / settings.subsamples)} min_jaccard ${real(minima[index])}`)];
}

function robustnessLines(customers, profiles, solution, settings, random) {
  const blocks = [subsampleLines(customers, solution, settings, random)], ablation = ['ablation'];
  for (let omitted = 0; omitted < FEATURES.length; omitted++) {
    const points = customers.map(customer => customer.point.filter((_, feature) => feature !== omitted));
    const run = runClustering(points, solution.k, 'maximin', 1, settings, random);
    ablation.push(`without ${FEATURES[omitted]} seeds ${run.seeds.map(index => customers[index].id).join(' ')}`
      + ` iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} transfers ${run.refined.transfers}`
      + ` sse ${real(run.refined.sse)} ari ${real(adjustedRand(run.refined.assignment, solution.assignment))}`);
  }
  blocks.push(ablation);
  const largest = profiles[0], points = largest.members.map(customer => customer.point);
  const run = runClustering(points, 2, 'maximin', 1, settings, random), split = segmentOrder(points, run.refined);
  blocks.push([
    `drilldown segment 1 ${largest.segment.name} size ${largest.members.length} seeds ${run.seeds.map(index => largest.members[index].id).join(' ')}`
      + ` iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} transfers ${run.refined.transfers}`,
    `sse before ${real(largest.sse)} after ${real(run.refined.sse)} gain ${real(largest.sse - run.refined.sse)}`,
    ...split.segments.map(part => `part ${part.number} size ${part.members.length} center ${numbers(part.center)}`),
  ]);
  return flattenBlocks(blocks);
}

function trackingLines(customers, profiles, solution, snapshot, outcomeOrders, settings) {
  const periods = [`periods ${settings.periods} days ${settings.periodDays}`];
  for (let period = 1; period <= settings.periods; period++) {
    const first = settings.reference - period * settings.periodDays + 1, last = settings.reference - (period - 1) * settings.periodDays;
    const revenue = [], active = [], acquired = [];
    for (const profile of profiles) {
      let spend = 0, buying = 0, firstTime = 0;
      for (const customer of profile.members) {
        const orders = customer.purchases.filter(order => order.day >= first && order.day <= last);
        spend += sum(orders.map(order => order.net));
        if (orders.length > 0) buying++;
        const initial = settings.reference - customer.raw[5];
        if (initial >= first && initial <= last) firstTime++;
      }
      revenue.push(amount(spend)); active.push(buying); acquired.push(firstTime);
    }
    periods.push(`period ${period} days ${first} ${last} revenue ${revenue.join(' ')} active ${active.join(' ')} acquired ${acquired.join(' ')}`);
  }
  const previous = new Map();
  for (const customer of snapshot) {
    let chosen = 0, best = squaredDistance(customer.point, solution.segments[0].center);
    for (let segment = 1; segment < solution.k; segment++) {
      const distance = squaredDistance(customer.point, solution.segments[segment].center);
      if (distance < best) { chosen = segment; best = distance; }
    }
    previous.set(customer.id, chosen);
  }
  const migration = Array.from({ length: solution.k + 1 }, () => Array(solution.k).fill(0)), movedLines = [];
  const ids = new Set(customers.map(customer => customer.id));
  let stayed = 0, moved = 0, newcomers = 0;
  for (const customer of customers) {
    const old = previous.has(customer.id) ? previous.get(customer.id) : solution.k;
    migration[old][customer.segment]++;
    if (old === solution.k) newcomers++;
    else if (old === customer.segment) stayed++;
    else { moved++; movedLines.push(`${customer.id} ${old + 1} ${customer.segment + 1}`); }
  }
  const migrationLines = [`migration day ${settings.snapshot} customers ${snapshot.length}`,
    'from\\to ' + solution.segments.map(segment => segment.number).join(' '),
    ...migration.map((row, index) => (index === solution.k ? 'none' : index + 1) + ' ' + row.join(' ')),
    'moved_customers', ...movedLines,
    `stayed ${stayed} moved ${moved} new ${newcomers} lost ${snapshot.filter(customer => !ids.has(customer.id)).length}`];
  const outcome = new Map();
  for (const order of outcomeOrders) if (order.net > 0) outcome.set(order.customer, (outcome.get(order.customer) || 0) + order.net);
  const outcomeLines = [`outcome days ${settings.reference + 1} ${settings.reference + settings.outcomeDays}`];
  for (const profile of profiles) {
    let buyers = 0, spend = 0;
    for (const customer of profile.members) if (outcome.has(customer.id)) { buyers++; spend += outcome.get(customer.id); }
    outcomeLines.push(`segment ${profile.segment.number} ${profile.segment.name} size ${profile.members.length} buyers ${buyers}`
      + ` rate ${real(buyers / profile.members.length)} revenue ${amount(spend)} per_customer ${real((spend / 100) / profile.members.length)}`);
  }
  const outside = [...outcome].filter(([id]) => !ids.has(id));
  outcomeLines.push(`unsegmented buyers ${outside.length} revenue ${amount(sum(outside.map(([, spend]) => spend)))}`);
  return flattenBlocks([periods, migrationLines, outcomeLines]);
}

function runLines(solutions, customers, settings) {
  return flattenBlocks(solutions.map(solution => {
    const lines = [`k ${solution.k}`];
    for (const run of solution.runs) lines.push(`run ${run.method} ${run.restart} seeds ${run.seeds.map(index => customers[index].id).join(' ')}`
      + ` iterations ${run.result.iterations} converged ${yesNo(run.result.converged)} reseeds ${run.result.reseeds} sse ${real(run.result.sse)}`
      + ` passes ${run.refined.passes} transfers ${run.refined.transfers} refined ${real(run.refined.sse)}`);
    for (const method of settings.methods) {
      const best = solution.bestMethods.get(method);
      lines.push(`best ${method} restart ${best.restart} sse ${real(best.refined.sse)}`);
    }
    lines.push(`chosen ${solution.best.method} restart ${solution.best.restart} sse ${real(solution.best.refined.sse)}`,
      'sizes ' + solution.segments.map(segment => segment.members.length).join(' '));
    return lines;
  }));
}

function selectionLines(solutions, chosen, votes, settings) {
  const indices = ['indices', ...solutions.map(solution => `k=${solution.k} sse ${real(solution.sse)} elbow ${real(solution.elbow)}`
    + ` silhouette ${real(solution.silhouette)} calinski_harabasz ${real(solution.calinski_harabasz)}`
    + ` davies_bouldin ${real(solution.davies_bouldin)} hartigan ${real(solution.hartigan)}`)];
  const voteLines = ['votes', ...[...votes].map(([name, k]) => `${name} k=${k}`), `chosen k=${chosen.k} votes ${chosen.votes}`];
  const names = ['segments', ...solutions.map(solution => `k=${solution.k} `
    + solution.segments.map(segment => `${segment.name}:${segment.members.length}`).join(' '))];
  const stability = ['stability'];
  for (let index = 0; index < solutions.length; index++) {
    const solution = solutions[index], values = [`k=${solution.k}`];
    for (let first = 0; first < settings.methods.length; first++) for (let second = first + 1; second < settings.methods.length; second++) {
      const left = settings.methods[first], right = settings.methods[second];
      values.push(`${left}:${right}`, real(adjustedRand(solution.bestMethods.get(left).refined.assignment, solution.bestMethods.get(right).refined.assignment)));
    }
    values.push('final');
    for (const method of settings.methods) values.push(method, real(adjustedRand(solution.bestMethods.get(method).refined.assignment, solution.assignment)));
    values.push('next', index + 1 === solutions.length ? '-' : real(adjustedRand(solution.assignment, solutions[index + 1].assignment)));
    stability.push(values.join(' '));
  }
  return flattenBlocks([indices, voteLines, names, stability]);
}

function summaryLines(data, customers, orders, totals, scaling) {
  const used = data.rows.filter(row => row.day <= data.settings.reference), eligible = new Set(customers.map(customer => customer.id));
  const excluded = [...data.customers].filter(id => !eligible.has(id)).sort(compareText), totalSpend = sum(customers.map(customer => customer.spend));
  const validOrders = orders.filter(order => order.net > 0).length;
  const rows = [
    `rows ${data.count} duplicates ${data.duplicates} zero ${data.zero} used ${used.length} returns ${used.filter(row => row.amount < 0).length}`
      + ` later ${data.rows.length - used.length}`,
    `orders ${orders.length} valid ${validOrders} cancelled ${orders.length - validOrders}`,
    `customers ${data.customers.size} clustered ${customers.length} excluded ${excluded.length}`,
    'excluded_ids ' + (excluded.length === 0 ? '-' : excluded.join(' ')),
  ];
  const categories = [...totals.keys()].sort(compareText).map(category => `category ${category} revenue ${amount(totals.get(category))}`
    + ` share ${real(totals.get(category) / totalSpend)} customers ${customers.filter(customer => (customer.categorySpend.get(category) || 0) > 0).length}`);
  const features = FEATURES.map((name, feature) => `feature ${name} transform ${SQUARE_ROOT.has(feature) ? 'sqrt' : 'none'}`
    + ` raw_mean ${real(scaling[feature].rawMean)} raw_sd ${real(scaling[feature].rawSD)}`
    + ` mean ${real(scaling[feature].mean)} sd ${real(scaling[feature].sd)}`);
  const correlations = correlation(customers);
  return flattenBlocks([rows, categories, features,
    ['correlation ' + FEATURES.join(' '), ...FEATURES.map((name, feature) => `${name} ${numbers(correlations[feature])}`)]]);
}

function main() {
  const data = readTransactions(), settings = data.settings, rules = readRules();
  const orders = groupOrders(data.rows, 1, settings.reference), customers = customerFeatures(orders, settings.reference);
  const scaling = fitStandardization(customers);
  standardize(customers, scaling);
  const snapshot = customerFeatures(groupOrders(data.rows, 1, settings.snapshot), settings.snapshot);
  standardize(snapshot, scaling);
  const outcomeOrders = groupOrders(data.rows, settings.reference + 1, settings.reference + settings.outcomeDays);
  const random = new Minstd(settings.seed), points = customers.map(customer => customer.point);
  const solutions = solveGrid(points, settings, rules, random), { chosen, votes } = chooseK(points, solutions, settings);
  customerResults(customers, chosen);
  const profiles = buildProfiles(customers, chosen, orders, settings), totals = categoryTotals(customers);
  const features = ['customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure'];
  const segments = ['customer,segment,name,distance,other,other_distance,silhouette,recommend'];
  for (const customer of customers) {
    const raw = customer.raw, segment = chosen.segments[customer.segment];
    features.push([customer.id, raw[0], raw[1], amount(customer.spend), real(raw[3]), raw[4], raw[5], ...customer.point.map(real)].join(','));
    segments.push([customer.id, segment.number, segment.name, real(customer.distance), customer.other + 1,
      real(customer.otherDistance), real(customer.silhouette), customer.recommend].join(','));
  }
  writeReport('features.csv', features);
  writeReport('runs.txt', runLines(solutions, customers, settings));
  writeReport('selection.txt', selectionLines(solutions, chosen, votes, settings));
  writeReport('segments.csv', segments);
  writeReport('profiles.txt', profileLines(customers, profiles, solutions, chosen, scaling, totals, settings));
  writeReport('robustness.txt', robustnessLines(customers, profiles, chosen, settings, random));
  writeReport('tracking.txt', trackingLines(customers, profiles, chosen, snapshot, outcomeOrders, settings));
  writeReport('summary.txt', summaryLines(data, customers, orders, totals, scaling));
}

main();
