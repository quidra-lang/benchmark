import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { Minstd, select } from './minstd';
import { OBSTACLE, Segment, Incident } from './road';
import type { BusStop, ChangeKind } from './road';
import { VehicleClass, Vehicle, randomSlowdown } from './vehicles';
import type { Source } from './vehicles';
import { Junction } from './signals';
import { floorRatio, gcd, decimal, fraction, percentile, histogramLines } from './stats';

interface Detector {
  name: string;
  segment: Segment;
  cell: number;
  width: number;
}
interface Diagram {
  segment: Segment;
  lane: number;
  start: number;
  end: number;
  lines: string[];
}
interface Ring {
  length: number;
  maximum: number;
  warmup: number;
  measurement: number;
  seed: number;
  counts: number[];
}
interface Input {
  segments: Segment[];
  junctions: Junction[];
  incidents: Incident[];
  stops: BusStop[];
  classes: VehicleClass[];
  classWeights: number[];
  sources: Source[];
  sinks: string[];
  detectors: Detector[];
  diagrams: Diagram[];
  trackNumbers: number[];
  trackSet: Set<number>;
  rings: Ring[];
  seed: number;
  steps: number;
  p: number;
  p0: number;
  interval: number;
  binWidth: number;
}
interface DetectorCounts {
  passing: number;
  occupancy: number;
  occupancySpeed: number;
}
interface Interval {
  arrivals: number;
  insertions: number;
  exits: number;
  vehicleSteps: number;
  speedSum: number;
  detectors: DetectorCounts[];
}
interface State {
  generator: Minstd;
  vehicles: Vehicle[];
  intervals: Interval[];
  events: string[];
}
interface Movement {
  vehicle: Vehicle;
  previousSpeed: number;
  speed: number;
  beforeSegment: Segment;
  beforeCell: number;
  crossing: boolean;
}
interface LaneChoice {
  lane: number;
  kind: ChangeKind;
}
type Share = [bigint, bigint];
interface Route {
  ids: string[];
  sink: string;
  share: Share;
}
interface TravelCounts {
  count: number;
  travel: number;
}

function readTokens(path: string): string[][] {
  return readFileSync(path, 'ascii')
    .slice(0, -1)
    .split('\n')
    .map((line) => line.split(' '));
}
function total<T>(values: readonly T[], valueOf: (value: T) => number): number {
  let result = 0;
  for (const value of values) result += valueOf(value);
  return result;
}
const time = (step: number): string => String(step).padStart(4, '0');

function readInput(): Input {
  const data: Input = {
    segments: [],
    junctions: [],
    incidents: [],
    stops: [],
    classes: [],
    classWeights: [],
    sources: [],
    sinks: [],
    detectors: [],
    diagrams: [],
    trackNumbers: [],
    trackSet: new Set(),
    rings: [],
    seed: 0,
    steps: 0,
    p: 0,
    p0: 0,
    interval: 0,
    binWidth: 0,
  };
  const segments = new Map<string, Segment>();
  const junctions = new Map<string, Junction>();
  function segment(id: string): Segment {
    const found = segments.get(id);
    if (found === undefined) throw new Error(`Unknown segment ${id}`);
    return found;
  }
  for (const [kind, ...fields] of readTokens('input/network.txt')) {
    if (kind === 'SEGMENT') {
      const [id, from, to, length, lanes, limit] = fields;
      const road = new Segment(id, from, to, Number(length), Number(lanes), Number(limit));
      data.segments.push(road);
      segments.set(id, road);
    } else if (kind === 'JUNCTION') {
      const [node, offset, ...tokens] = fields;
      const phases = tokens.map((token) => {
        const [duration, green] = token.split(':');
        return {
          duration: Number(duration),
          token: green,
          greens: new Set(green === '-' ? [] : green.split(',')),
        };
      });
      const junction = new Junction(node, Number(offset), phases);
      data.junctions.push(junction);
      junctions.set(node, junction);
    } else if (kind === 'INCIDENT') {
      const [id, lane, cell, start, end] = fields;
      data.incidents.push(
        new Incident(segment(id), Number(lane), Number(cell), Number(start), Number(end)),
      );
    } else if (kind === 'STOP') {
      const [id, cell, dwell] = fields;
      const stop = { segment: segment(id), cell: Number(cell), dwell: Number(dwell), buses: 0 };
      data.stops.push(stop);
      stop.segment.stop = stop;
    }
  }
  for (const road of data.segments) road.junction = junctions.get(road.to) ?? null;
  for (const [kind, ...fields] of readTokens('input/demand.txt')) {
    if (kind === 'CLASS') {
      const [name, maximum, weight, overtake, stops] = fields;
      data.classes.push(
        new VehicleClass(name, Number(maximum), Number(weight), overtake === 'Y', stops === 'Y'),
      );
    } else if (kind === 'SOURCE') {
      const [node, ...tokens] = fields;
      const rates = tokens.map((token) => {
        const [rate, end] = token.split(':').map(Number);
        return { rate, end };
      });
      const entry = data.segments.find((road) => road.from === node);
      if (entry === undefined) throw new Error(`No entry for ${node}`);
      data.sources.push({ node, rates, entry, queue: [], head: 0, queueStart: 0, maximumQueue: 0 });
    } else if (kind === 'SINK') {
      data.sinks.push(fields[0]);
    } else if (kind === 'TURN') {
      const [from, to, weight] = fields;
      segment(from).turns.push({ to: segment(to), weight: Number(weight), vehicles: 0 });
    }
  }
  data.classWeights = data.classes.map((type) => type.weight);
  for (const road of data.segments) road.turnWeights = road.turns.map((turn) => turn.weight);
  for (const [kind, ...fields] of readTokens('input/params.txt')) {
    if (kind === 'seed') data.seed = Number(fields[0]);
    else if (kind === 'steps') data.steps = Number(fields[0]);
    else if (kind === 'dawdle') [data.p, data.p0] = fields.map(Number);
    else if (kind === 'interval') data.interval = Number(fields[0]);
    else if (kind === 'bin') data.binWidth = Number(fields[0]);
    else if (kind === 'detector') {
      const [name, id, cell, width] = fields;
      data.detectors.push({ name, segment: segment(id), cell: Number(cell), width: Number(width) });
    } else if (kind === 'diagram') {
      const [id, lane, start, end] = fields;
      data.diagrams.push({
        segment: segment(id),
        lane: Number(lane),
        start: Number(start),
        end: Number(end),
        lines: [],
      });
    } else if (kind === 'track') data.trackNumbers = fields.map(Number);
    else if (kind === 'ring') {
      const [length, maximum, warmup, measurement, seed, ...counts] = fields.map(Number);
      data.rings.push({ length, maximum, warmup, measurement, seed, counts });
    }
  }
  data.trackSet = new Set(data.trackNumbers);
  return data;
}

function enterSegment(vehicle: Vehicle, generator: Minstd): void {
  const segment = vehicle.road();
  vehicle.route.push(segment.id);
  segment.entered++;
  vehicle.turn =
    segment.junction === null ? null : segment.turns[select(segment.turnWeights, generator.draw())];
}

function startInterval(data: Input): Interval {
  return {
    arrivals: 0,
    insertions: 0,
    exits: 0,
    vehicleSteps: 0,
    speedSum: 0,
    detectors: data.detectors.map(() => ({ passing: 0, occupancy: 0, occupancySpeed: 0 })),
  };
}

function arriveVehicles(data: Input, state: State, interval: Interval, step: number): void {
  for (const source of data.sources) {
    const random = state.generator.draw();
    const rate = source.rates.find((period) => step <= period.end)?.rate ?? 0;
    if (random % 1000 >= rate) continue;
    const type = data.classes[select(data.classWeights, state.generator.draw())];
    const vehicle = new Vehicle(state.vehicles.length + 1, type, source, step);
    if (data.trackSet.has(vehicle.number)) vehicle.trajectory = [];
    state.vehicles.push(vehicle);
    source.queue.push(vehicle);
    interval.arrivals++;
  }
}

function insertVehicles(data: Input, state: State, interval: Interval, step: number): void {
  for (const source of data.sources) {
    const segment = source.entry;
    while (source.head < source.queue.length) {
      let chosen = 0;
      let largest = -1;
      for (let lane = 1; lane <= segment.lanes; lane++) {
        if (segment.get(lane, 0) !== null) continue;
        const first = segment.first(lane);
        if (first > largest) {
          chosen = lane;
          largest = first;
        }
      }
      if (chosen === 0) break;
      const vehicle = source.queue[source.head++];
      vehicle.place(segment, chosen, 0);
      vehicle.insertion = step;
      enterSegment(vehicle, state.generator);
      interval.insertions++;
    }
    const waiting = source.queue.length - source.head;
    if (waiting > 0 && source.queueStart === 0) {
      source.queueStart = step;
      source.maximumQueue = 0;
    }
    if (source.queueStart !== 0) {
      source.maximumQueue = Math.max(source.maximumQueue, waiting);
      if (waiting === 0) {
        state.events.push(
          `${time(step)} QUEUE ${source.node} from ${source.queueStart} max ${source.maximumQueue}`,
        );
        source.queueStart = 0;
      }
    }
  }
}

function desiredLane(vehicle: Vehicle): LaneChoice | null {
  const segment = vehicle.road();
  const lane = vehicle.lane;
  const cell = vehicle.cell;
  const maximum = vehicle.maximumSpeed();
  const here = segment.free(lane, cell, maximum + 1);
  const want = Math.min(vehicle.speed + 1, maximum);
  const obstacle =
    here < maximum + 1 &&
    cell + here + 1 < segment.length &&
    segment.get(lane, cell + here + 1) === OBSTACLE;
  if (obstacle) {
    for (const next of [lane + 1, lane - 1]) {
      if (
        next >= 1 &&
        next <= segment.lanes &&
        segment.free(next, cell, maximum + 1) > here &&
        segment.safe(next, cell)
      ) {
        return { lane: next, kind: 'avoidance' };
      }
    }
  }
  if (vehicle.headingForStop()) {
    return lane >= 2 && segment.safe(lane - 1, cell) ? { lane: lane - 1, kind: 'return' } : null;
  }
  if (
    vehicle.type.overtake &&
    lane < segment.lanes &&
    here < want &&
    segment.free(lane + 1, cell, maximum + 1) > here &&
    segment.safe(lane + 1, cell)
  ) {
    return { lane: lane + 1, kind: 'overtaking' };
  }
  if (
    lane >= 2 &&
    segment.free(lane - 1, cell, maximum + 1) > want &&
    segment.safe(lane - 1, cell)
  ) {
    return { lane: lane - 1, kind: 'return' };
  }
  return null;
}

function changeLanes(data: Input): void {
  const changes: { vehicle: Vehicle; segment: Segment; choice: LaneChoice }[] = [];
  for (const segment of data.segments) {
    if (segment.lanes < 2) continue;
    const reserved = new Set<number>();
    for (let lane = 1; lane <= segment.lanes; lane++) {
      for (let cell = 0; cell < segment.length; cell++) {
        const vehicle = segment.get(lane, cell);
        if (vehicle === null || vehicle === OBSTACLE || vehicle.dwell > 0) continue;
        const choice = desiredLane(vehicle);
        if (choice === null) continue;
        const destination = choice.lane * segment.length + cell;
        if (reserved.has(destination)) continue;
        reserved.add(destination);
        changes.push({ vehicle, segment, choice });
      }
    }
  }
  for (const { vehicle, segment, choice } of changes) {
    vehicle.place(segment, choice.lane, vehicle.cell);
    vehicle.laneChanges++;
    segment.changes[choice.kind]++;
  }
}

function processingOrder(data: Input): Movement[] {
  const order: Movement[] = [];
  for (const segment of data.segments) {
    for (let lane = 1; lane <= segment.lanes; lane++) {
      for (let cell = segment.length - 1; cell >= 0; cell--) {
        const vehicle = segment.get(lane, cell);
        if (vehicle !== null && vehicle !== OBSTACLE) {
          order.push({
            vehicle,
            previousSpeed: vehicle.speed,
            speed: 0,
            beforeSegment: segment,
            beforeCell: cell,
            crossing: false,
          });
        }
      }
    }
  }
  return order;
}

function determineSpeeds(data: Input, state: State, order: Movement[], step: number): void {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    const segment = vehicle.road();
    const accelerated = Math.min(vehicle.speed + 1, vehicle.maximumSpeed());
    let gap = segment.free(vehicle.lane, vehicle.cell, accelerated);
    if (gap < accelerated && vehicle.cell + gap === segment.length - 1) {
      if (segment.junction === null) gap = accelerated;
      else if (segment.junction.green(segment.id, step)) {
        const turn = vehicle.turn;
        if (turn === null) throw new Error('Missing turn');
        gap += turn.to.free(Math.min(vehicle.lane, turn.to.lanes), -1, accelerated - gap);
      }
    }
    if (vehicle.headingForStop() && segment.stop !== null) {
      gap = Math.min(gap, segment.stop.cell - vehicle.cell);
    }
    let speed = randomSlowdown(
      Math.min(accelerated, gap),
      vehicle.speed,
      data.p,
      data.p0,
      state.generator,
    );
    if (vehicle.dwell > 0) {
      speed = 0;
      vehicle.dwell--;
    }
    movement.speed = speed;
  }
}

function moveVehicles(order: Movement[], interval: Interval, step: number): void {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    const segment = vehicle.road();
    const destination = vehicle.cell + movement.speed;
    if (destination < segment.length) vehicle.place(segment, vehicle.lane, destination);
    else if (segment.junction === null) {
      vehicle.exit = step;
      vehicle.sink = segment.to;
      vehicle.remove();
      interval.exits++;
    } else movement.crossing = true;
  }
}

function passJunctions(state: State, order: Movement[]): void {
  for (const movement of order) {
    if (!movement.crossing) continue;
    const vehicle = movement.vehicle;
    const segment = vehicle.road();
    const cell = vehicle.cell;
    const turn = vehicle.turn;
    if (turn === null) throw new Error('Missing turn');
    const target = turn.to;
    const lane = Math.min(vehicle.lane, target.lanes);
    const wanted = cell + movement.speed - segment.length;
    const position = Math.min(wanted, target.first(lane) - 1);
    if (position < wanted) segment.blocked++;
    if (position >= 0) {
      vehicle.place(target, lane, position);
      movement.speed = segment.length - cell + position;
      segment.passed++;
      turn.vehicles++;
      enterSegment(vehicle, state.generator);
    } else {
      vehicle.place(segment, vehicle.lane, segment.length - 1);
      movement.speed = segment.length - 1 - cell;
    }
  }
}

function aggregateVehicles(
  data: Input,
  state: State,
  order: Movement[],
  interval: Interval,
  step: number,
): void {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    vehicle.steps++;
    vehicle.distance += movement.speed;
    if (movement.speed === 0) {
      vehicle.stoppedSteps++;
      if (movement.previousSpeed > 0) vehicle.stopCount++;
    }
    vehicle.speed = movement.speed;
    interval.vehicleSteps++;
    interval.speedSum += movement.speed;
    const segment = vehicle.segment;
    if (
      segment !== null &&
      segment.stop !== null &&
      vehicle.headingForStop() &&
      vehicle.lane === 1 &&
      vehicle.cell === segment.stop.cell
    ) {
      vehicle.completedStops.add(segment.id);
      vehicle.dwell = segment.stop.dwell;
      segment.stop.buses++;
      state.events.push(
        `${time(step)} BUS_STOP ${vehicle.number} ${segment.id} cell ${vehicle.cell}`,
      );
    }
    if (vehicle.trajectory !== null) {
      vehicle.trajectory.push(
        segment === null
          ? `${time(step)} EXIT ${vehicle.speed}`
          : `${time(step)} ${segment.id} ${vehicle.lane} ${vehicle.cell} ${vehicle.speed}`,
      );
    }
    data.detectors.forEach((detector, index) => {
      if (
        movement.beforeSegment === detector.segment &&
        movement.beforeCell < detector.cell &&
        (segment !== detector.segment || vehicle.cell >= detector.cell)
      ) {
        interval.detectors[index].passing++;
      }
    });
  }
}

function aggregateState(data: Input, interval: Interval, step: number): void {
  data.detectors.forEach((detector, index) => {
    const counts = interval.detectors[index];
    for (const row of detector.segment.cells) {
      for (let cell = detector.cell; cell < detector.cell + detector.width; cell++) {
        const vehicle = row[cell];
        if (vehicle !== null && vehicle !== OBSTACLE) {
          counts.occupancy++;
          counts.occupancySpeed += vehicle.speed;
        }
      }
    }
  });
  for (const segment of data.segments) {
    let count = 0;
    let speed = 0;
    let queue = 0;
    for (const row of segment.cells) {
      for (const vehicle of row) {
        if (vehicle === null || vehicle === OBSTACLE) continue;
        count++;
        speed += vehicle.speed;
        if (vehicle.speed === 0) queue++;
      }
    }
    segment.vehicleSum += count;
    segment.speedSum += speed;
    segment.maximumVehicles = Math.max(segment.maximumVehicles, count);
    if (segment.junction !== null) {
      const green = segment.junction.green(segment.id, step);
      if (green) segment.greenCount++;
      segment.queueSum += queue;
      segment.maximumQueue = Math.max(segment.maximumQueue, queue);
      if (
        step < data.steps &&
        queue > 0 &&
        green &&
        !segment.junction.green(segment.id, step + 1)
      ) {
        segment.failures++;
      }
    }
  }
  for (const diagram of data.diagrams) {
    if (step < diagram.start || step > diagram.end) continue;
    const segment = diagram.segment;
    const signal =
      segment.junction === null ? 'E' : segment.junction.green(segment.id, step) ? 'G' : 'R';
    diagram.lines.push(`${time(step)} ${segment.diagram(diagram.lane)} ${signal}`);
  }
}

function simulate(data: Input): State {
  const state: State = {
    generator: new Minstd(data.seed),
    vehicles: [],
    intervals: [],
    events: [],
  };
  for (let step = 1; step <= data.steps; step++) {
    for (const incident of data.incidents) {
      const event = incident.update(step);
      if (event !== null) {
        state.events.push(
          `${time(step)} ${event} ${incident.segment.id} lane ${incident.lane} cell ${incident.cell}`,
        );
      }
    }
    if ((step - 1) % data.interval === 0) state.intervals.push(startInterval(data));
    const interval = state.intervals[state.intervals.length - 1];
    arriveVehicles(data, state, interval, step);
    insertVehicles(data, state, interval, step);
    changeLanes(data);
    const order = processingOrder(data);
    determineSpeeds(data, state, order, step);
    moveVehicles(order, interval, step);
    passJunctions(state, order);
    aggregateVehicles(data, state, order, interval, step);
    aggregateState(data, interval, step);
  }
  for (const source of data.sources) {
    if (source.queueStart !== 0) {
      state.events.push(
        `${time(data.steps)} QUEUE ${source.node} from ${source.queueStart} max ${source.maximumQueue} open`,
      );
    }
  }
  return state;
}

function reducedShare(numerator: bigint, denominator: bigint): Share {
  const divisor = gcd(numerator, denominator);
  return [numerator / divisor, denominator / divisor];
}
function addShares(first: Share, second: Share): Share {
  return reducedShare(first[0] * second[1] + second[0] * first[1], first[1] * second[1]);
}
function enumerateRoutes(segment: Segment, memo: Map<Segment, Route[]>): Route[] {
  const known = memo.get(segment);
  if (known !== undefined) return known;
  const routes: Route[] = [];
  if (segment.junction === null) {
    routes.push({ ids: [segment.id], sink: segment.to, share: [1n, 1n] });
  } else {
    const weight = BigInt(total(segment.turnWeights, (value) => value));
    for (const turn of segment.turns) {
      for (const tail of enumerateRoutes(turn.to, memo)) {
        routes.push({
          ids: [segment.id, ...tail.ids],
          sink: tail.sink,
          share: reducedShare(tail.share[0] * BigInt(turn.weight), tail.share[1] * weight),
        });
      }
    }
  }
  memo.set(segment, routes);
  return routes;
}

const travelTime = (vehicle: Vehicle): number => vehicle.steps;
function travelBlock(heading: string, vehicles: Vehicle[], width: number): string[] {
  if (vehicles.length === 0) return [`${heading} exited 0`];
  const times = vehicles.map(travelTime).sort((a, b) => a - b);
  return [
    `${heading} exited ${times.length} min ${times[0]} p50 ${percentile(times, 50)} ` +
      `p90 ${percentile(times, 90)} max ${times[times.length - 1]} mean ${decimal(
        total(times, (value) => value),
        times.length,
        2,
      )}`,
    ...histogramLines(times, width),
  ];
}

function travelReport(data: Input, state: State): string[] {
  const exited = state.vehicles.filter((vehicle) => vehicle.exit !== null);
  const lines: string[] = [];
  for (const type of data.classes) {
    lines.push(
      ...travelBlock(
        `CLASS ${type.name}`,
        exited.filter((v) => v.type === type),
        data.binWidth,
      ),
    );
  }
  lines.push(...travelBlock('ALL', exited, data.binWidth));
  const memo = new Map<Segment, Route[]>();
  for (const source of data.sources) {
    const vehicles = exited.filter((vehicle) => vehicle.source === source);
    const routes = enumerateRoutes(source.entry, memo);
    const byRoute = new Map<string, TravelCounts>();
    const bySink = new Map<string, TravelCounts>();
    const record = (counts: Map<string, TravelCounts>, key: string, vehicle: Vehicle): void => {
      const value = counts.get(key) ?? { count: 0, travel: 0 };
      value.count++;
      value.travel += travelTime(vehicle);
      counts.set(key, value);
    };
    for (const vehicle of vehicles) {
      record(byRoute, vehicle.route.join(','), vehicle);
      if (vehicle.sink !== null) record(bySink, vehicle.sink, vehicle);
    }
    const expected = new Map<string, Share>();
    lines.push(`SOURCE ${source.node} exited ${vehicles.length}`);
    for (const route of routes) {
      const key = route.ids.join(',');
      const counts = byRoute.get(key) ?? { count: 0, travel: 0 };
      lines.push(
        `  ROUTE ${key} expected ${fraction(...route.share)} vehicles ${counts.count} ` +
          `share ${fraction(counts.count, vehicles.length)} mean ${decimal(counts.travel, counts.count, 2)}`,
      );
      expected.set(route.sink, addShares(expected.get(route.sink) ?? [0n, 1n], route.share));
    }
    for (const sink of data.sinks) {
      const share = expected.get(sink);
      if (share === undefined) continue;
      const counts = bySink.get(sink) ?? { count: 0, travel: 0 };
      lines.push(
        `  SINK ${sink} expected ${fraction(...share)} vehicles ${counts.count} ` +
          `share ${fraction(counts.count, vehicles.length)} mean ${decimal(counts.travel, counts.count, 2)}`,
      );
    }
  }
  return lines;
}

function classBlock(heading: string, vehicles: Vehicle[]): string[] {
  const inserted = vehicles.filter((vehicle) => vehicle.insertion !== null).length;
  const exited = vehicles.filter((vehicle) => vehicle.exit !== null);
  const steps = total(vehicles, (vehicle) => vehicle.steps);
  const distance = total(vehicles, (vehicle) => vehicle.distance);
  const mean = (valueOf: (vehicle: Vehicle) => number): string =>
    decimal(total(exited, valueOf), exited.length, 2);
  return [
    heading,
    `  generated ${vehicles.length} inserted ${inserted} exited ${exited.length} in_network ${inserted - exited.length} queued ${vehicles.length - inserted}`,
    `  vehicle_steps ${steps} distance ${distance} mean_speed ${fraction(distance, steps)} = ${decimal(distance, steps, 3)}`,
    `  travel ${mean(travelTime)} entry_delay ${mean((vehicle) => (vehicle.insertion ?? 0) - vehicle.arrival)} ` +
      `stopped ${mean((vehicle) => vehicle.stoppedSteps)} stops ${mean((vehicle) => vehicle.stopCount)} lane_changes ${mean((vehicle) => vehicle.laneChanges)}`,
  ];
}

function classReport(data: Input, state: State): string[] {
  const lines: string[] = [];
  for (const type of data.classes) {
    const heading = `CLASS ${type.name} vmax ${type.maximum} weight ${type.weight} overtake ${type.overtake ? 'Y' : 'N'} stops ${type.stops ? 'Y' : 'N'}`;
    lines.push(
      ...classBlock(
        heading,
        state.vehicles.filter((vehicle) => vehicle.type === type),
      ),
    );
  }
  return [...lines, ...classBlock('ALL', state.vehicles)];
}

function networkReport(data: Input): string[] {
  const lines: string[] = [];
  for (const segment of data.segments) {
    lines.push(
      `SEGMENT ${segment.id} ${segment.from} ${segment.to} length ${segment.length} lanes ${segment.lanes} limit ${segment.limit} ` +
        `entered ${segment.entered} mean_vehicles ${decimal(segment.vehicleSum, data.steps, 3)} ` +
        `density ${decimal(segment.vehicleSum, data.steps * segment.length * segment.lanes, 4)} ` +
        `mean_speed ${decimal(segment.speedSum, segment.vehicleSum, 2)} max_vehicles ${segment.maximumVehicles} ` +
        `changes ${segment.changes.overtaking}/${segment.changes.return}/${segment.changes.avoidance}`,
    );
  }
  for (const junction of data.junctions) {
    lines.push(...junction.lines());
    for (const segment of data.segments) {
      if (segment.junction !== junction) continue;
      lines.push(
        `  IN ${segment.id} green ${segment.greenCount} passed ${segment.passed} blocked ${segment.blocked} ` +
          `max_queue ${segment.maximumQueue} mean_queue ${decimal(segment.queueSum, data.steps, 3)} failures ${segment.failures}`,
      );
      for (const turn of segment.turns) {
        lines.push(`    TURN ${turn.to.id} weight ${turn.weight} vehicles ${turn.vehicles}`);
      }
    }
  }
  for (const stop of data.stops) {
    lines.push(`STOP ${stop.segment.id} cell ${stop.cell} dwell ${stop.dwell} buses ${stop.buses}`);
  }
  for (const incident of data.incidents) {
    const active =
      incident.activeStart === null ? 'none' : `${incident.activeStart}-${incident.activeEnd}`;
    lines.push(
      `INCIDENT ${incident.segment.id} lane ${incident.lane} cell ${incident.cell} planned ${incident.start}-${incident.end} active ${active}`,
    );
  }
  return lines;
}

function detectorReport(data: Input, state: State): string[] {
  const lines = ['detector,interval,flow,density,speed'];
  data.detectors.forEach((detector, index) => {
    state.intervals.forEach((interval, number) => {
      const counts = interval.detectors[index];
      lines.push(
        `${detector.name},${number + 1},${counts.passing},` +
          `${decimal(counts.occupancy, data.interval * detector.width * detector.segment.lanes, 4)},` +
          `${decimal(counts.occupancySpeed, counts.occupancy, 2)}`,
      );
    });
  });
  return lines;
}

function timelineReport(state: State): string[] {
  const lines = ['interval,arrived,inserted,exited,in_network,queued,mean_speed'];
  let arrived = 0;
  let inserted = 0;
  let exited = 0;
  state.intervals.forEach((interval, index) => {
    arrived += interval.arrivals;
    inserted += interval.insertions;
    exited += interval.exits;
    lines.push(
      `${index + 1},${interval.arrivals},${interval.insertions},${interval.exits},` +
        `${inserted - exited},${arrived - inserted},${decimal(interval.speedSum, interval.vehicleSteps, 2)}`,
    );
  });
  return lines;
}

function tracksReport(data: Input, state: State): string[] {
  const lines: string[] = [];
  for (const number of data.trackNumbers) {
    const vehicle = state.vehicles[number - 1];
    if (vehicle === undefined) {
      lines.push(`VEHICLE ${number} none`);
      continue;
    }
    lines.push(
      `VEHICLE ${number} class ${vehicle.type.name} source ${vehicle.source.node} arrival ${vehicle.arrival} ` +
        `inserted ${vehicle.insertion ?? '-'} exited ${vehicle.exit ?? '-'} sink ${vehicle.sink ?? '-'}`,
    );
    lines.push(`ROUTE ${vehicle.route.length === 0 ? '-' : vehicle.route.join(' ')}`);
    if (vehicle.trajectory !== null) lines.push(...vehicle.trajectory);
  }
  return lines;
}

function modulo(value: number, divisor: number): number {
  const remainder = value % divisor;
  return remainder < 0 ? remainder + divisor : remainder;
}
function ringExperiment(ring: Ring, count: number, p: number, p0: number): number {
  const generator = new Minstd(ring.seed);
  const vehicles = Array.from({ length: count }, (_, index) => ({
    position: floorRatio(index * ring.length, count),
    speed: 0,
    nextSpeed: 0,
  }));
  let distance = 0;
  for (let step = 1; step <= ring.warmup + ring.measurement; step++) {
    vehicles.sort((a, b) => b.position - a.position);
    for (let index = 0; index < vehicles.length; index++) {
      const vehicle = vehicles[index];
      const ahead = vehicles[(index + vehicles.length - 1) % vehicles.length];
      const gap = modulo(ahead.position - vehicle.position - 1, ring.length);
      vehicle.nextSpeed = randomSlowdown(
        Math.min(vehicle.speed + 1, ring.maximum, gap),
        vehicle.speed,
        p,
        p0,
        generator,
      );
    }
    for (const vehicle of vehicles) {
      vehicle.position = modulo(vehicle.position + vehicle.nextSpeed, ring.length);
      vehicle.speed = vehicle.nextSpeed;
      if (step > ring.warmup) distance += vehicle.speed;
    }
  }
  return distance;
}
function fundamentalReport(data: Input): string[] {
  const lines = ['ring,vehicles,density,flow,speed'];
  data.rings.forEach((ring, index) => {
    for (const count of ring.counts) {
      const distance = ringExperiment(ring, count, data.p, data.p0);
      lines.push(
        `${index + 1},${count},${decimal(count, ring.length, 4)},` +
          `${decimal(distance, ring.length * ring.measurement, 4)},${decimal(distance, count * ring.measurement, 3)}`,
      );
    }
  });
  return lines;
}

function main(): void {
  const data = readInput();
  const state = simulate(data);
  const reports: Record<string, string[]> = {
    'spacetime.txt': data.diagrams.flatMap((diagram) => [
      `DIAGRAM ${diagram.segment.id} lane ${diagram.lane} steps ${diagram.start}-${diagram.end}`,
      ...diagram.lines,
    ]),
    'detectors.csv': detectorReport(data, state),
    'travel_times.txt': travelReport(data, state),
    'class_stats.txt': classReport(data, state),
    'network_stats.txt': networkReport(data),
    'timeline.csv': timelineReport(state),
    'tracks.txt': tracksReport(data, state),
    'fundamental.csv': fundamentalReport(data),
    'events.txt': state.events,
  };
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync(`output/${name}`, lines.length ? `${lines.join('\n')}\n` : '', 'ascii');
  }
}

main();
