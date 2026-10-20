'use strict';

function* points(domains) {
  const indices = Array(domains.length).fill(0);
  for (;;) {
    yield new Map(domains.map((domain, index) => [domain.reference, domain.values[indices[index]]]));
    let position = domains.length - 1;
    while (position >= 0) {
      indices[position]++;
      if (indices[position] < domains[position].values.length) break;
      indices[position] = 0;
      position--;
    }
    if (position < 0) return;
  }
}

function dayNotation(days) {
  const ordered = [...days].sort((a, b) => a - b);
  const runs = [];
  let first = ordered[0];
  let last = first;
  for (const day of ordered.slice(1)) {
    if (day !== last + 1) {
      runs.push(`${first}-${last}`);
      first = day;
    }
    last = day;
  }
  runs.push(`${first}-${last}`);
  return runs.join(',');
}

function winner(policy, first, second) {
  if (policy.algorithm === 'first-applicable') return first;
  const effect = ['deny-overrides', 'permit-unless-deny'].includes(policy.algorithm) ? 'DENY' : 'PERMIT';
  return first.effect === effect ? first : second;
}

function blocker(rule, values) {
  for (const earlier of rule.parent.children) {
    if (earlier === rule) break;
    if (values.get(earlier.id) !== 'NOT_APPLICABLE') return earlier;
  }
  return null;
}

module.exports = {points, dayNotation, winner, blocker};
