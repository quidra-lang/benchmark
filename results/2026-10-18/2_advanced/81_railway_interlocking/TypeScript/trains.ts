import { readFileSync } from 'node:fs';
import type { Layout, Train, Route, RouteRequest, Stop } from './types.ts';

export function readTrains(path: string, layout: Layout, routes: Map<string, Route>): {trains: Train[]; requests: Map<number, RouteRequest[]>} {
  const trains: Train[] = [];
  const byName = new Map<string, Train>();
  const requests = new Map<number, RouteRequest[]>();
  for (const line of readFileSync(path, 'ascii').split('\n').slice(0, -1)) {
    const [kind, name, ...fields] = line.split(' ');
    if (kind === 'TRAIN') {
      const [length, acceleration, deceleration, maximum, entry, scheduled, speed] = fields;
      const train: Train = { name, symbol: String.fromCharCode(97 + trains.length), length: Number(length),
        acceleration: Number(acceleration), deceleration: Number(deceleration), maximum: Number(maximum),
        entry: layout.boundaryByName.get(entry)!, scheduledEntry: Number(scheduled), entrySpeed: Number(speed),
        stops: [], exit: null, scheduledExit: null, actualEntry: null, actualExit: null, state: 'WAITING',
        direction: null, path: [], head: 0, speed: 0, nextStop: 0, dwelling: false, pendingDeparture: null,
        emergency: false, crossed: null, stats: { distance: 0, maxspeed: 0, standing: 0, passes: 0 } };
      trains.push(train); byName.set(name, train);
    } else {
      const train = byName.get(name)!;
      if (kind === 'REQUEST') {
        const time = Number(fields[1]);
        if (!requests.has(time)) requests.set(time, []);
        requests.get(time)!.push({ train, route: routes.get(fields[0])! });
      } else if (kind === 'EXIT') {
        train.exit = layout.boundaryByName.get(fields[0])!; train.scheduledExit = Number(fields[1]);
      } else {
        const [section, dwell, arrival, departure] = fields;
        train.stops.push({ section: layout.sectionByName.get(section)!, turn: kind === 'TURN', dwell: Number(dwell),
          scheduledArrival: Number(arrival), scheduledDeparture: Number(departure), arrival: null, departure: null });
      }
    }
  }
  return { trains, requests };
}

export function brakingDistance(speed: number, deceleration: number): number {
  const n = Math.floor(speed / deceleration);
  return n * speed - deceleration * n * (n + 1) / 2;
}

export function selectSpeed(train: Train, distance: number | null): number {
  const minimum = Math.max(train.speed - train.deceleration, 0);
  if (train.emergency) return minimum;
  for (let speed = Math.min(train.speed + train.acceleration, train.maximum); speed >= minimum; speed--) {
    if (distance === null || speed + brakingDistance(speed, train.deceleration) <= distance) return speed;
  }
  return minimum;
}

