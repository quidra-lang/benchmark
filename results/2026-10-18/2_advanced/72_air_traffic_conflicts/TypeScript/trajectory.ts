import type { Plan, AircraftType } from './flight_plans.ts';
export type Vector = [number, number, number];
export interface Segment {
  number: number;
  leg: number;
  phase: 'CLB' | 'DES' | 'LVL';
  ts: number;
  te: number;
  start: Vector;
  velocity: Vector;
  end: Vector;
}
export interface Trajectory {
  segments: Segment[];
  arrival: number;
  length: number;
  waypointTimes: [number, number][];
}
export function buildTrajectory(plan: Plan, types: Record<string, AircraftType>): Trajectory {
  const segments: Segment[] = [];
  const rates = types[plan.type];
  let time = plan.departure + plan.delay;
  let level = plan.level + plan.offset;
  let routeLength = 0;
  const waypointTimes: [number, number][] = [[time, level]];
  const add = (
    leg: number,
    phase: Segment['phase'],
    ts: number,
    te: number,
    start: Vector,
    velocity: Vector,
    end: Vector,
  ) => segments.push({ number: segments.length + 1, leg, phase, ts, te, start, velocity, end });
  for (let leg = 1; leg < plan.waypoints.length; leg++) {
    const p = plan.waypoints[leg - 1];
    const q = plan.waypoints[leg];
    const dx = q.x - p.x;
    const dy = q.y - p.y;
    const length = Math.sqrt(dx * dx + dy * dy) / 10;
    const duration = (length * 3600) / plan.speed;
    const vx = dx / 10 / duration;
    const vy = dy / 10 / duration;
    const target = q.level === null ? level : q.level + plan.offset;
    const x = p.x / 10;
    const y = p.y / 10;
    routeLength += length;
    if (target === level) {
      add(
        leg,
        'LVL',
        time,
        time + duration,
        [x, y, level * 100],
        [vx, vy, 0],
        [q.x / 10, q.y / 10, target * 100],
      );
    } else {
      const climbing = target > level;
      const rate = climbing ? rates.climb : rates.descent;
      const change = (Math.abs(target - level) * 6000) / rate;
      const mid: Vector = [x + vx * change, y + vy * change, target * 100];
      add(
        leg,
        climbing ? 'CLB' : 'DES',
        time,
        time + change,
        [x, y, level * 100],
        [vx, vy, climbing ? rate / 60 : -(rate / 60)],
        mid,
      );
      add(
        leg,
        'LVL',
        time + change,
        time + duration,
        mid,
        [vx, vy, 0],
        [q.x / 10, q.y / 10, target * 100],
      );
    }
    time = time + duration;
    level = target;
    waypointTimes.push([time, level]);
  }
  return { segments, arrival: time, length: routeLength, waypointTimes };
}
export function position(s: Segment, time: number): Vector {
  const dt = time - s.ts;
  return [
    s.start[0] + s.velocity[0] * dt,
    s.start[1] + s.velocity[1] * dt,
    s.start[2] + s.velocity[2] * dt,
  ];
}
export function activeSegment(path: Trajectory, time: number) {
  return path.segments.find((s) => s.ts <= time && time < s.te) ?? null;
}
export function currentPosition(path: Trajectory, time: number) {
  const segment = activeSegment(path, time);
  return segment === null ? null : { point: position(segment, time), segment };
}
