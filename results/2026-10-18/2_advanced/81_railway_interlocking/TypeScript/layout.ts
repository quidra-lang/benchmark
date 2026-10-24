import { readFileSync } from 'node:fs';
import type { Layout, Section, Point, Signal, BufferEnd, Boundary, Feature, NextConnection, Direction } from './types.ts';

export function readLayout(path: string): Layout {
  const sections: Section[] = [], points: Point[] = [], signals: Signal[] = [];
  const buffers: BufferEnd[] = [], boundaries: Boundary[] = [];
  const labels: Layout['labels'] = [];
  const sectionByName = new Map<string, Section>();
  const pointByName = new Map<string, Point>();
  const signalByName = new Map<string, Signal>();
  const boundaryByName = new Map<string, Boundary>();
  const features = new Map<string, Feature>();
  for (const line of readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const [kind, ...fields] = line.split(' ');
    if (kind === 'SECTION') {
      const [name, ...values] = fields, [length, row, col1, col2] = values.map(Number);
      const section: Section = { name, length, row, col1, col2,
        ends: {}, signals: {}, failed: false, occupants: [],
        stats: { occupied: 0, locked: 0, trains: new Set() },
        routeLock: null, overlapLocks: new Set() };
      sections.push(section); sectionByName.set(name, section);
    } else if (kind === 'JOINT') {
      const first = sectionByName.get(fields[0]), second = sectionByName.get(fields[1]);
      first!.ends.R = { kind: 'section', section: second! }; second!.ends.L = { kind: 'section', section: first! };
    } else if (kind === 'POINT') {
      const [name, side, common, normal, reverse, row, col] = fields;
      const point: Point = { name, side, common: sectionByName.get(common)!, normal: sectionByName.get(normal)!,
        reverse: sectionByName.get(reverse)!, row: Number(row), col: Number(col), position: 'N',
        moving: false, target: null, completion: null, failed: false, stats: { throws: 0, locked: 0, moving: 0 },
        locks: [] };
      points.push(point); pointByName.set(name, point);
      point.common.ends[side] = { kind: 'point', point };
      point.normal.ends[side === 'R' ? 'L' : 'R'] = { kind: 'point', point };
      point.reverse.ends[side === 'R' ? 'L' : 'R'] = { kind: 'point', point };
    } else if (kind === 'SIGNAL') {
      const [name, section, direction, row, col] = fields;
      const signal: Signal = { kind: 'signal', name, section: sectionByName.get(section)!,
        direction: direction as Direction, row: Number(row), col: Number(col),
        aspect: 'RED', stats: { RED: 0, YELLOW: 0, GREEN: 0, passes: 0 } };
      signals.push(signal); signalByName.set(name, signal); features.set(name, signal);
      signal.section.signals[signal.direction] = signal;
    } else if (kind === 'BUFFER' || kind === 'BOUNDARY') {
      const [name, section, end, row, col] = fields;
      const common = { name, section: sectionByName.get(section)!, end };
      if (kind === 'BUFFER') {
        const feature: BufferEnd = { kind: 'buffer', ...common, row: Number(row), col: Number(col) };
        buffers.push(feature);
        feature.section.ends[end] = feature;
        features.set(name, feature);
      } else {
        const feature: Boundary = { kind: 'boundary', ...common };
        boundaries.push(feature);
        boundaryByName.set(name, feature);
        feature.section.ends[end] = feature;
        features.set(name, feature);
      }
    } else labels.push({ row: Number(fields[0]), col: Number(fields[1]), text: fields[2] });
  }
  return { sections, points, signals, buffers, boundaries, labels, sectionByName, pointByName, signalByName, boundaryByName, features };
}

export function beyond(section: Section, direction: Direction): NextConnection {
  const connection = section.ends[direction === 'UP' ? 'R' : 'L'];
  if (connection.kind !== 'point') return connection;
  const point = connection.point;
  if (point.moving) return { kind: 'impassable' };
  const selected = point.position === 'N' ? point.normal : point.reverse;
  if (section === point.common) return { kind: 'section', section: selected };
  return section === selected ? { kind: 'section', section: point.common } : { kind: 'impassable' };
}

