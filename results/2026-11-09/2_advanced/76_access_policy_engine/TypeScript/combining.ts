import type { PolicyElement, TargetResult, EvalResult, ChildResult, CombineResult } from './types.ts';

export const indeterminate = (decision: string): boolean => decision.startsWith('INDETERMINATE');

export function combine(element: PolicyElement, evaluate: (child:PolicyElement)=>EvalResult, target: (child:PolicyElement)=>TargetResult): CombineResult {
  const children: ChildResult[] = element.children.map(child => ({state: 'skipped', element: child}));
  const finish = (decision: string, reason: string | null = null): CombineResult => ({decision, reason, children});
  if (element.algorithm === 'only-one-applicable') {
    let selected = null;
    for (let index = 0; index < children.length; index++) {
      const child = element.children[index];
      const checked = target(child);
      children[index] = {state: 'checked', element: child, target: checked};
      if (checked.status === 'INDETERMINATE') return finish('INDETERMINATE{DP}', checked.reason);
      if (checked.status === 'MATCH') {
        if (selected !== null) return finish('INDETERMINATE{DP}',
          `multiple applicable ${element.children[selected].id} ${child.id}`);
        selected = index;
      }
    }
    if (selected === null) return finish('NOT_APPLICABLE');
    const result = evaluate(element.children[selected]);
    children[selected] = {state: 'evaluated', element: element.children[selected], result};
    return finish(result.decision, result.reason);
  }
  const evaluated: EvalResult[] = [];
  for (let index = 0; index < children.length; index++) {
    const child = element.children[index];
    const result = evaluate(child);
    evaluated.push(result);
    children[index] = {state: 'evaluated', element: child, result};
    const algorithm = element.algorithm;
    if (algorithm === 'first-applicable' && result.decision !== 'NOT_APPLICABLE') return finish(result.decision, result.reason);
    if (['deny-overrides', 'permit-unless-deny'].includes(algorithm) && result.decision === 'DENY') return finish('DENY');
    if (['permit-overrides', 'deny-unless-permit'].includes(algorithm) && result.decision === 'PERMIT') return finish('PERMIT');
  }
  const decisions = new Set(evaluated.map(result => result.decision));
  const reason = evaluated.find(result => indeterminate(result.decision))?.reason || null;
  const has = (decision: string): boolean => decisions.has(decision);
  if (element.algorithm === 'deny-unless-permit') return finish('DENY');
  if (element.algorithm === 'permit-unless-deny') return finish('PERMIT');
  if (element.algorithm === 'first-applicable') return finish('NOT_APPLICABLE');
  if (element.algorithm === 'deny-overrides') {
    if (has('INDETERMINATE{DP}') || (has('INDETERMINATE{D}') && (has('INDETERMINATE{P}') || has('PERMIT')))) return finish('INDETERMINATE{DP}', reason);
    if (has('INDETERMINATE{D}')) return finish('INDETERMINATE{D}', reason);
    if (has('PERMIT')) return finish('PERMIT');
    if (has('INDETERMINATE{P}')) return finish('INDETERMINATE{P}', reason);
  } else {
    if (has('INDETERMINATE{DP}') || (has('INDETERMINATE{P}') && (has('INDETERMINATE{D}') || has('DENY')))) return finish('INDETERMINATE{DP}', reason);
    if (has('INDETERMINATE{P}')) return finish('INDETERMINATE{P}', reason);
    if (has('DENY')) return finish('DENY');
    if (has('INDETERMINATE{D}')) return finish('INDETERMINATE{D}', reason);
  }
  return finish('NOT_APPLICABLE');
}

