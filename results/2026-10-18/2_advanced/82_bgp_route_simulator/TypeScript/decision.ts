import type { Attribute, LocalRoute, LearnedRoute, Route, Origin, Link, AutonomousSystem } from './types.ts';

export const sameSequence = (a: number[], b: number[]): boolean => a.length === b.length && a.every((value, i) => value === b[i]);
export const originated = (origin: Origin, communities: number[]): LocalRoute => ({ local: true, path: [], origin, med: 0, communities });
export const learned = (attribute: Attribute, localPref: number, link: Link): LearnedRoute => ({ ...attribute, local: false, localPref, link });

export function attributesEqual(a: Attribute | null | undefined, b: Attribute | null | undefined): boolean {
  if (a == null || b == null) return a == null && b == null;
  return a.origin === b.origin && a.med === b.med && sameSequence(a.path, b.path) && sameSequence(a.communities, b.communities);
}

export function routesEqual(a: Route | null | undefined, b: Route | null | undefined): boolean {
  if (a == null || b == null) return a == null && b == null;
  return a.local === b.local && attributesEqual(a, b) && (a.local || (!b.local && a.localPref === b.localPref && a.link === b.link));
}

export function selectBest(routes: LearnedRoute[], ases: Map<number, AutonomousSystem>): {route: LearnedRoute; reason: string} {
  let remaining = routes.slice();
  if (remaining.length === 1) return { route: remaining[0], reason: 'ONLY' };
  const keepMinimum = (items: LearnedRoute[], value: (route: LearnedRoute) => number): LearnedRoute[] => {
    const minimum = Math.min(...items.map(value));
    return items.filter(item => value(item) === minimum);
  };
  const stages: [string, (routes: LearnedRoute[]) => LearnedRoute[]][] = [
    ['LOCALPREF', items => keepMinimum(items, item => -item.localPref)],
    ['ASPATH', items => keepMinimum(items, item => item.path.length)],
    ['ORIGIN', items => keepMinimum(items, item => ({ IGP: 0, EGP: 1, INCOMPLETE: 2 } as Record<Origin, number>)[item.origin])],
    ['MED', items => items.filter(item => !items.some(other => other.path[0] === item.path[0] && other.med < item.med))],
    ['ROUTERID', items => keepMinimum(items, item => ases.get(item.path[0])!.routerId)],
    ['LINK', items => keepMinimum(items, item => item.link.number)],
  ];
  for (const [reason, stage] of stages) {
    remaining = stage(remaining);
    if (remaining.length === 1) return { route: remaining[0], reason };
  }
  return {route: remaining[0], reason: 'LINK'};
}

