import type { AttributeSet, Domain, PolicyElement } from './types.ts';

export function* points(domains: Domain[]): Generator<AttributeSet> {
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

export function dayNotation(days: Iterable<number>): string {
  const ordered = [...days].sort((a, b) => a - b);
  const runs: string[] = [];
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

export function winner(policy: PolicyElement, first: PolicyElement, second: PolicyElement): PolicyElement {
  if (policy.algorithm === 'first-applicable') return first;
  const effect = ['deny-overrides', 'permit-unless-deny'].includes(policy.algorithm) ? 'DENY' : 'PERMIT';
  return first.effect === effect ? first : second;
}

export function blocker(rule: PolicyElement, values: Map<string,string>): PolicyElement | null {
  for (const earlier of rule.parent!.children) {
    if (earlier === rule) break;
    if (values.get(earlier.id) !== 'NOT_APPLICABLE') return earlier;
  }
  return null;
}

