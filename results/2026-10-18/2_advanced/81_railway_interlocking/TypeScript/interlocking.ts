import type { Layout, PointRequirement, Route, Section } from './types.ts';

import * as fs from 'node:fs';
const list = (text: string): string[] => text === '-' ? [] : text.split(',');

export class Interlocking {
  layout: Layout;
  routes: Route[];
  byName: Map<string, Route>;
  constructor(path: string, layout: Layout) {
    this.layout = layout; this.routes = []; this.byName = new Map();
    for (const section of layout.sections) { section.routeLock = null; section.overlapLocks = new Set(); }
    for (const point of layout.points) point.locks = [];
    const requirements = (text: string): PointRequirement[] => list(text).map(item => {
      const [name, position] = item.split(':');
      return { point: layout.pointByName.get(name)!, position };
    });
    for (const line of fs.readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
      const [, name, start, finish, points, sections, overlap, flank, conflicts, approach] = line.split(' ');
      const signal = layout.signalByName.get(start)!;
      const route: Route = { name, start: signal, finish: layout.features.get(finish)!, direction: signal.direction,
        points: requirements(points), flank: requirements(flank), sections: list(sections).map(value => layout.sectionByName.get(value)!),
        overlap: list(overlap).map(value => layout.sectionByName.get(value)!), conflictNames: list(conflicts), approach: Number(approach),
        state: null, passed: new Set(), overlapLocked: false, overlapCounter: 0, releaseTime: null, conflicts: [], requirements: [],
        stats: { requests: 0, grants: 0, uses: 0, cancels: 0, wait: 0, maxwait: 0, locked: 0 } };
      this.routes.push(route); this.byName.set(name, route);
    }
    for (const route of this.routes) {
      route.conflicts = route.conflictNames.map(name => this.byName.get(name)!);
      route.requirements = route.points.concat(route.flank);
    }
  }
  lock(route: Route): void {
    route.state = 'LOCKED'; route.passed.clear(); route.overlapLocked = true; route.overlapCounter = 0;
    for (const section of route.sections) section.routeLock = route;
    for (const section of route.overlap) section.overlapLocks.add(route);
    for (const { point, position } of route.requirements) {
      if (!point.locks.some(lock => lock.route === route && lock.position === position)) point.locks.push({ route, position });
    }
  }
  unlockSection(route: Route, section: Section): void {
    if (section.routeLock === route) section.routeLock = null;
    for (const point of this.layout.points) if (point.common === section) point.locks = point.locks.filter(lock => lock.route !== route);
  }
  unlockOverlap(route: Route): void {
    for (const section of route.overlap) section.overlapLocks.delete(route);
    for (const point of this.layout.points) {
      if (route.overlap.includes(point.common)) point.locks = point.locks.filter(lock => lock.route !== route);
    }
    route.overlapLocked = false;
  }
  release(route: Route): void {
    for (const section of route.sections) if (section.routeLock === route) section.routeLock = null;
    if (route.overlapLocked) this.unlockOverlap(route);
    for (const point of this.layout.points) point.locks = point.locks.filter(lock => lock.route !== route);
    route.state = null; route.releaseTime = null;
  }
}

