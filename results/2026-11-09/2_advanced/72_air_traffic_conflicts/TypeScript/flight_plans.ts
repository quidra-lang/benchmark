import { readFileSync } from 'node:fs';
export interface AircraftType {
  climb: number;
  descent: number;
  minimum: number;
}
export interface Waypoint {
  x: number;
  y: number;
  level: number | null;
}
export interface Plan {
  callsign: string;
  type: string;
  departure: number;
  level: number;
  speedInitial: number;
  speed: number;
  delay: number;
  offset: number;
  history: string[];
  waypoints: Waypoint[];
}
export interface Sector {
  name: string;
  index: number;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  lower: number;
  upper: number;
  capacity: number;
}
export interface Parameters {
  dh: number;
  dv: number;
  lookahead: number;
  maxDelay: number;
  levelMin: number;
  levelMax: number;
  sampleStart: number;
  sampleEnd: number;
  radar: number[];
  snapshots: number[];
  leader: number;
  alert: number;
}
const lines = (file: string) => readFileSync(`input/${file}`, 'ascii').trimEnd().split('\n');
export function loadAll() {
  const types: Record<string, AircraftType> = {};
  for (const line of lines('aircraft.txt')) {
    const [name, climb, descent, minimum] = line.split(' ');
    types[name] = { climb: Number(climb), descent: Number(descent), minimum: Number(minimum) };
  }
  const sectors: Sector[] = lines('sectors.txt').map((line, index) => {
    const [name, ...raw] = line.split(' ');
    const [x1, y1, x2, y2, lower, upper, capacity] = raw.map(Number);
    return { name, index, x1, y1, x2, y2, lower, upper, capacity };
  });
  const p = lines('params.txt').map((line) => line.split(' ').slice(1).map(Number));
  const params: Parameters = {
    dh: p[0][0],
    dv: p[0][1],
    lookahead: p[1][0],
    maxDelay: p[2][0],
    levelMin: p[3][0],
    levelMax: p[3][1],
    sampleStart: p[4][0],
    sampleEnd: p[4][1],
    radar: p[5],
    snapshots: p[6],
    leader: p[7][0],
    alert: p[8][0],
  };
  const flights: Record<string, Plan> = {};
  for (const line of lines('flights.csv').slice(1)) {
    const [callsign, type, departure, level, speed, waypoints] = line.split(',');
    flights[callsign] = {
      callsign,
      type,
      departure: Number(departure),
      level: Number(level),
      speedInitial: Number(speed),
      speed: Number(speed),
      delay: 0,
      offset: 0,
      history: [],
      waypoints: waypoints.split(' ').map((word) => {
        const a = word.split(':').map(Number);
        return { x: a[0], y: a[1], level: a.length === 3 ? a[2] : null };
      }),
    };
  }
  return { types, sectors, params, flights };
}
export const clonePlan = (plan: Plan): Plan => ({ ...plan, history: plan.history.slice() });
export function levelList(plan: Plan) {
  const levels = [plan.level + plan.offset];
  for (const w of plan.waypoints) if (w.level !== null) levels.push(w.level + plan.offset);
  return levels;
}
