'use strict';

const sameSequence = (a, b) => a.length === b.length && a.every((value, i) => value === b[i]);
const originated = (origin, communities) => ({ local: true, path: [], origin, med: 0, communities });
const learned = (attribute, localPref, link) => ({ ...attribute, local: false, localPref, link });

function attributesEqual(a, b) {
  if (a == null || b == null) return a == null && b == null;
  return a.origin === b.origin && a.med === b.med && sameSequence(a.path, b.path) && sameSequence(a.communities, b.communities);
}

function routesEqual(a, b) {
  if (a == null || b == null) return a == null && b == null;
  return a.local === b.local && attributesEqual(a, b) && (a.local || (a.localPref === b.localPref && a.link === b.link));
}

function selectBest(routes, ases) {
  let remaining = routes.slice();
  if (remaining.length === 1) return { route: remaining[0], reason: 'ONLY' };
  const keepMinimum = (items, value) => {
    const minimum = Math.min(...items.map(value));
    return items.filter(item => value(item) === minimum);
  };
  const stages = [
    ['LOCALPREF', items => keepMinimum(items, item => -item.localPref)],
    ['ASPATH', items => keepMinimum(items, item => item.path.length)],
    ['ORIGIN', items => keepMinimum(items, item => ({ IGP: 0, EGP: 1, INCOMPLETE: 2 })[item.origin])],
    ['MED', items => items.filter(item => !items.some(other => other.path[0] === item.path[0] && other.med < item.med))],
    ['ROUTERID', items => keepMinimum(items, item => ases.get(item.path[0]).routerId)],
    ['LINK', items => keepMinimum(items, item => item.link.number)],
  ];
  for (const [reason, stage] of stages) {
    remaining = stage(remaining);
    if (remaining.length === 1) return { route: remaining[0], reason };
  }
}

module.exports = { sameSequence, originated, learned, attributesEqual, routesEqual, selectBest };
