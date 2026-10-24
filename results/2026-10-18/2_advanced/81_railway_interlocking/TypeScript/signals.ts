import type { Signal, Route, Section, SignalAspect } from './types.ts';

export function decideSignals(signals: Signal[], routes: Route[], occupied: (section: Section) => boolean): SignalAspect[] {
  const cleared = new Map<Signal, Route>();
  for (const route of routes) {
    if (route.state !== 'LOCKED') continue;
    if (route.requirements.some(({ point, position }) => point.moving || point.failed || point.position !== position)) continue;
    if (route.sections.some(occupied) || route.overlap.some(occupied)) continue;
    cleared.set(route.start, route);
  }
  return signals.map((signal): SignalAspect => {
    const route = cleared.get(signal);
    if (!route) return 'RED';
    if (route.finish.kind === 'boundary') return 'GREEN';
    if (route.finish.kind === 'buffer') return 'YELLOW';
    return cleared.has(route.finish) ? 'GREEN' : 'YELLOW';
  });
}

