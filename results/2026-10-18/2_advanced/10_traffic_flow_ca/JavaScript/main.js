const fs = require('node:fs');
const { Minstd, select } = require('./minstd');
const { OBSTACLE, Segment, Incident } = require('./road');
const { VehicleClass, Vehicle, randomSlowdown } = require('./vehicles');
const { Junction } = require('./signals');
const { floorRatio, gcd, decimal, fraction, percentile, histogramLines } = require('./stats');

function readTokens(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n').map(line => line.split(' '));
}

function total(values, valueOf = value => value) {
  let result = 0;
  for (const value of values) result += valueOf(value);
  return result;
}

function time(step) {
  return String(step).padStart(4, '0');
}

function readInput() {
  const data = { segments: [], junctions: [], incidents: [], stops: [], classes: [], sources: [],
    sinks: [], detectors: [], diagrams: [], trackNumbers: [], rings: [] };
  const segments = new Map();
  const junctions = new Map();
  for (const [kind, ...fields] of readTokens('input/network.txt')) {
    if (kind === 'SEGMENT') {
      const [id, from, to, length, lanes, limit] = fields;
      const segment = new Segment(id, from, to, Number(length), Number(lanes), Number(limit));
      data.segments.push(segment);
      segments.set(id, segment);
    } else if (kind === 'JUNCTION') {
      const [node, offset, ...tokens] = fields;
      const phases = tokens.map(token => {
        const [duration, green] = token.split(':');
        return { duration: Number(duration), token: green, greens: new Set(green === '-' ? [] : green.split(',')) };
      });
      const junction = new Junction(node, Number(offset), phases);
      data.junctions.push(junction);
      junctions.set(node, junction);
    } else if (kind === 'INCIDENT') {
      const [id, lane, cell, start, end] = fields;
      data.incidents.push(new Incident(segments.get(id), Number(lane), Number(cell), Number(start), Number(end)));
    } else if (kind === 'STOP') {
      const [id, cell, dwell] = fields;
      const stop = { segment: segments.get(id), cell: Number(cell), dwell: Number(dwell), buses: 0 };
      data.stops.push(stop);
      stop.segment.stop = stop;
    }
  }
  for (const segment of data.segments) segment.junction = junctions.get(segment.to) ?? null;
  for (const [kind, ...fields] of readTokens('input/demand.txt')) {
    if (kind === 'CLASS') {
      const [name, maximum, weight, overtake, stops] = fields;
      data.classes.push(new VehicleClass(name, Number(maximum), Number(weight), overtake === 'Y', stops === 'Y'));
    } else if (kind === 'SOURCE') {
      const [node, ...tokens] = fields;
      const rates = tokens.map(token => {
        const [rate, end] = token.split(':').map(Number);
        return { rate, end };
      });
      data.sources.push({ node, rates, entry: data.segments.find(segment => segment.from === node),
        queue: [], head: 0, queueStart: 0, maximumQueue: 0 });
    } else if (kind === 'SINK') {
      data.sinks.push(fields[0]);
    } else if (kind === 'TURN') {
      const [from, to, weight] = fields;
      segments.get(from).turns.push({ to: segments.get(to), weight: Number(weight), vehicles: 0 });
    }
  }
  data.classWeights = data.classes.map(type => type.weight);
  for (const segment of data.segments) segment.turnWeights = segment.turns.map(turn => turn.weight);
  for (const [kind, ...fields] of readTokens('input/params.txt')) {
    if (kind === 'seed') data.seed = Number(fields[0]);
    else if (kind === 'steps') data.steps = Number(fields[0]);
    else if (kind === 'dawdle') [data.p, data.p0] = fields.map(Number);
    else if (kind === 'interval') data.interval = Number(fields[0]);
    else if (kind === 'bin') data.binWidth = Number(fields[0]);
    else if (kind === 'detector') {
      const [name, id, cell, width] = fields;
      data.detectors.push({ name, segment: segments.get(id), cell: Number(cell), width: Number(width) });
    } else if (kind === 'diagram') {
      const [id, lane, start, end] = fields;
      data.diagrams.push({ segment: segments.get(id), lane: Number(lane), start: Number(start), end: Number(end), lines: [] });
    } else if (kind === 'track') {
      data.trackNumbers = fields.map(Number);
    } else if (kind === 'ring') {
      const [length, maximum, warmup, measurement, seed, ...counts] = fields.map(Number);
      data.rings.push({ length, maximum, warmup, measurement, seed, counts });
    }
  }
  data.trackSet = new Set(data.trackNumbers);
  return data;
}

function enterSegment(vehicle, generator) {
  const segment = vehicle.segment;
  vehicle.route.push(segment.id);
  segment.entered += 1;
  vehicle.turn = segment.junction === null ? null
    : segment.turns[select(segment.turnWeights, generator.draw())];
}

function startInterval(data) {
  return { arrivals: 0, insertions: 0, exits: 0, vehicleSteps: 0, speedSum: 0,
    detectors: data.detectors.map(() => ({ passing: 0, occupancy: 0, occupancySpeed: 0 })) };
}

function arriveVehicles(data, state, interval, step) {
  for (const source of data.sources) {
    const random = state.generator.draw();
    const rate = source.rates.find(period => step <= period.end)?.rate ?? 0;
    if (random % 1000 >= rate) continue;
    const type = data.classes[select(data.classWeights, state.generator.draw())];
    const vehicle = new Vehicle(state.vehicles.length + 1, type, source, step);
    if (data.trackSet.has(vehicle.number)) vehicle.trajectory = [];
    state.vehicles.push(vehicle);
    source.queue.push(vehicle);
    interval.arrivals += 1;
  }
}

function insertVehicles(data, state, interval, step) {
  for (const source of data.sources) {
    const segment = source.entry;
    while (source.head < source.queue.length) {
      let chosen = 0;
      let largest = -1;
      for (let lane = 1; lane <= segment.lanes; lane += 1) {
        if (segment.get(lane, 0) !== null) continue;
        const first = segment.first(lane);
        if (first > largest) {
          chosen = lane;
          largest = first;
        }
      }
      if (chosen === 0) break;
      const vehicle = source.queue[source.head];
      source.head += 1;
      vehicle.place(segment, chosen, 0);
      vehicle.insertion = step;
      enterSegment(vehicle, state.generator);
      interval.insertions += 1;
    }
    const waiting = source.queue.length - source.head;
    if (waiting > 0 && source.queueStart === 0) {
      source.queueStart = step;
      source.maximumQueue = 0;
    }
    if (source.queueStart !== 0) {
      source.maximumQueue = Math.max(source.maximumQueue, waiting);
      if (waiting === 0) {
        state.events.push(`${time(step)} QUEUE ${source.node} from ${source.queueStart} max ${source.maximumQueue}`);
        source.queueStart = 0;
      }
    }
  }
}

function desiredLane(vehicle) {
  const segment = vehicle.segment;
  const lane = vehicle.lane;
  const cell = vehicle.cell;
  const maximum = vehicle.maximumSpeed();
  const here = segment.free(lane, cell, maximum + 1);
  const want = Math.min(vehicle.speed + 1, maximum);
  const obstacle = here < maximum + 1 && cell + here + 1 < segment.length
    && segment.get(lane, cell + here + 1) === OBSTACLE;
  if (obstacle) {
    for (const next of [lane + 1, lane - 1]) {
      if (next >= 1 && next <= segment.lanes && segment.free(next, cell, maximum + 1) > here
          && segment.safe(next, cell)) return { lane: next, kind: 'avoidance' };
    }
  }
  if (vehicle.headingForStop()) {
    return lane >= 2 && segment.safe(lane - 1, cell) ? { lane: lane - 1, kind: 'return' } : { lane };
  }
  if (vehicle.type.overtake && lane < segment.lanes && here < want
      && segment.free(lane + 1, cell, maximum + 1) > here && segment.safe(lane + 1, cell)) {
    return { lane: lane + 1, kind: 'overtaking' };
  }
  if (lane >= 2 && segment.free(lane - 1, cell, maximum + 1) > want && segment.safe(lane - 1, cell)) {
    return { lane: lane - 1, kind: 'return' };
  }
  return { lane };
}

function changeLanes(data) {
  const changes = [];
  for (const segment of data.segments) {
    if (segment.lanes < 2) continue;
    const reserved = new Set();
    for (let lane = 1; lane <= segment.lanes; lane += 1) {
      for (let cell = 0; cell < segment.length; cell += 1) {
        const vehicle = segment.get(lane, cell);
        if (vehicle === null || vehicle === OBSTACLE || vehicle.dwell > 0) continue;
        const desired = desiredLane(vehicle);
        if (desired.lane === lane) continue;
        const destination = desired.lane * segment.length + cell;
        if (reserved.has(destination)) continue;
        reserved.add(destination);
        changes.push({ vehicle, segment, lane: desired.lane, kind: desired.kind });
      }
    }
  }
  for (const change of changes) {
    change.vehicle.place(change.segment, change.lane, change.vehicle.cell);
    change.vehicle.laneChanges += 1;
    change.segment.changes[change.kind] += 1;
  }
}

function processingOrder(data) {
  const order = [];
  for (const segment of data.segments) {
    for (let lane = 1; lane <= segment.lanes; lane += 1) {
      for (let cell = segment.length - 1; cell >= 0; cell -= 1) {
        const vehicle = segment.get(lane, cell);
        if (vehicle !== null && vehicle !== OBSTACLE) order.push({ vehicle, previousSpeed: vehicle.speed });
      }
    }
  }
  return order;
}

function determineSpeeds(data, state, order, step) {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    const segment = vehicle.segment;
    const accelerated = Math.min(vehicle.speed + 1, vehicle.maximumSpeed());
    let gap = segment.free(vehicle.lane, vehicle.cell, accelerated);
    if (gap < accelerated && vehicle.cell + gap === segment.length - 1) {
      if (segment.junction === null) {
        gap = accelerated;
      } else if (segment.junction.green(segment.id, step)) {
        const target = vehicle.turn.to;
        const lane = Math.min(vehicle.lane, target.lanes);
        gap += target.free(lane, -1, accelerated - gap);
      }
    }
    if (vehicle.headingForStop()) gap = Math.min(gap, segment.stop.cell - vehicle.cell);
    let speed = randomSlowdown(Math.min(accelerated, gap), vehicle.speed, data.p, data.p0, state.generator);
    if (vehicle.dwell > 0) {
      speed = 0;
      vehicle.dwell -= 1;
    }
    movement.speed = speed;
  }
}

function moveVehicles(order, interval, step) {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    const segment = vehicle.segment;
    movement.beforeSegment = segment;
    movement.beforeCell = vehicle.cell;
    const destination = vehicle.cell + movement.speed;
    if (destination < segment.length) {
      vehicle.place(segment, vehicle.lane, destination);
    } else if (segment.junction === null) {
      vehicle.exit = step;
      vehicle.sink = segment.to;
      vehicle.remove();
      interval.exits += 1;
    } else {
      movement.crossing = true;
    }
  }
}

function passJunctions(state, order) {
  for (const movement of order) {
    if (!movement.crossing) continue;
    const vehicle = movement.vehicle;
    const segment = vehicle.segment;
    const cell = vehicle.cell;
    const turn = vehicle.turn;
    const target = turn.to;
    const lane = Math.min(vehicle.lane, target.lanes);
    const wanted = cell + movement.speed - segment.length;
    const position = Math.min(wanted, target.first(lane) - 1);
    if (position < wanted) segment.blocked += 1;
    if (position >= 0) {
      vehicle.place(target, lane, position);
      movement.speed = segment.length - cell + position;
      segment.passed += 1;
      turn.vehicles += 1;
      enterSegment(vehicle, state.generator);
    } else {
      vehicle.place(segment, vehicle.lane, segment.length - 1);
      movement.speed = segment.length - 1 - cell;
    }
  }
}

function aggregateVehicles(data, state, order, interval, step) {
  for (const movement of order) {
    const vehicle = movement.vehicle;
    vehicle.steps += 1;
    vehicle.distance += movement.speed;
    if (movement.speed === 0) {
      vehicle.stoppedSteps += 1;
      if (movement.previousSpeed > 0) vehicle.stopCount += 1;
    }
    vehicle.speed = movement.speed;
    interval.vehicleSteps += 1;
    interval.speedSum += movement.speed;
    if (vehicle.headingForStop() && vehicle.lane === 1 && vehicle.cell === vehicle.segment.stop.cell) {
      const stop = vehicle.segment.stop;
      vehicle.completedStops.add(vehicle.segment.id);
      vehicle.dwell = stop.dwell;
      stop.buses += 1;
      state.events.push(`${time(step)} BUS_STOP ${vehicle.number} ${vehicle.segment.id} cell ${vehicle.cell}`);
    }
    if (vehicle.trajectory !== null) {
      vehicle.trajectory.push(vehicle.segment === null ? `${time(step)} EXIT ${vehicle.speed}`
        : `${time(step)} ${vehicle.segment.id} ${vehicle.lane} ${vehicle.cell} ${vehicle.speed}`);
    }
    data.detectors.forEach((detector, index) => {
      if (movement.beforeSegment === detector.segment && movement.beforeCell < detector.cell
          && (vehicle.segment !== detector.segment || vehicle.cell >= detector.cell)) {
        interval.detectors[index].passing += 1;
      }
    });
  }
}

function aggregateState(data, interval, step) {
  data.detectors.forEach((detector, index) => {
    const statistics = interval.detectors[index];
    for (const row of detector.segment.cells) {
      for (let cell = detector.cell; cell < detector.cell + detector.width; cell += 1) {
        const vehicle = row[cell];
        if (vehicle !== null && vehicle !== OBSTACLE) {
          statistics.occupancy += 1;
          statistics.occupancySpeed += vehicle.speed;
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
        count += 1;
        speed += vehicle.speed;
        if (vehicle.speed === 0) queue += 1;
      }
    }
    segment.vehicleSum += count;
    segment.speedSum += speed;
    segment.maximumVehicles = Math.max(segment.maximumVehicles, count);
    if (segment.junction !== null) {
      const green = segment.junction.green(segment.id, step);
      if (green) segment.greenCount += 1;
      segment.queueSum += queue;
      segment.maximumQueue = Math.max(segment.maximumQueue, queue);
      if (step < data.steps && queue > 0 && green && !segment.junction.green(segment.id, step + 1)) segment.failures += 1;
    }
  }
  for (const diagram of data.diagrams) {
    if (step < diagram.start || step > diagram.end) continue;
    const segment = diagram.segment;
    const signal = segment.junction === null ? 'E' : segment.junction.green(segment.id, step) ? 'G' : 'R';
    diagram.lines.push(`${time(step)} ${segment.diagram(diagram.lane)} ${signal}`);
  }
}

function simulate(data) {
  const state = { generator: new Minstd(data.seed), vehicles: [], intervals: [], events: [] };
  for (let step = 1; step <= data.steps; step += 1) {
    for (const incident of data.incidents) {
      const event = incident.update(step);
      if (event !== null) state.events.push(`${time(step)} ${event} ${incident.segment.id} lane ${incident.lane} cell ${incident.cell}`);
    }
    if ((step - 1) % data.interval === 0) state.intervals.push(startInterval(data));
    const interval = state.intervals.at(-1);
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
      state.events.push(`${time(data.steps)} QUEUE ${source.node} from ${source.queueStart} max ${source.maximumQueue} open`);
    }
  }
  return state;
}

function reducedShare(numerator, denominator) {
  const divisor = gcd(numerator, denominator);
  return [numerator / divisor, denominator / divisor];
}

function addShares(first, second) {
  return reducedShare(first[0] * second[1] + second[0] * first[1], first[1] * second[1]);
}

function enumerateRoutes(segment, memo) {
  if (memo.has(segment)) return memo.get(segment);
  const routes = [];
  if (segment.junction === null) {
    routes.push({ ids: [segment.id], sink: segment.to, share: [1n, 1n] });
  } else {
    const weight = BigInt(total(segment.turnWeights));
    for (const turn of segment.turns) {
      for (const tail of enumerateRoutes(turn.to, memo)) {
        routes.push({ ids: [segment.id, ...tail.ids], sink: tail.sink,
          share: reducedShare(tail.share[0] * BigInt(turn.weight), tail.share[1] * weight) });
      }
    }
  }
  memo.set(segment, routes);
  return routes;
}

function travelTime(vehicle) {
  return vehicle.exit - vehicle.insertion + 1;
}

function travelBlock(heading, vehicles, width) {
  if (vehicles.length === 0) return [`${heading} exited 0`];
  const times = vehicles.map(travelTime).sort((first, second) => first - second);
  return [`${heading} exited ${times.length} min ${times[0]} p50 ${percentile(times, 50)} `
    + `p90 ${percentile(times, 90)} max ${times.at(-1)} mean ${decimal(total(times), times.length, 2)}`,
  ...histogramLines(times, width)];
}

function travelReport(data, state) {
  const exited = state.vehicles.filter(vehicle => vehicle.exit !== null);
  const lines = [];
  for (const type of data.classes) lines.push(...travelBlock(`CLASS ${type.name}`, exited.filter(vehicle => vehicle.type === type), data.binWidth));
  lines.push(...travelBlock('ALL', exited, data.binWidth));
  const memo = new Map();
  for (const source of data.sources) {
    const vehicles = exited.filter(vehicle => vehicle.source === source);
    const routes = enumerateRoutes(source.entry, memo);
    const byRoute = new Map();
    const bySink = new Map();
    for (const vehicle of vehicles) {
      for (const [counts, key] of [[byRoute, vehicle.route.join(',')], [bySink, vehicle.sink]]) {
        if (!counts.has(key)) counts.set(key, { count: 0, travel: 0 });
        counts.get(key).count += 1;
        counts.get(key).travel += travelTime(vehicle);
      }
    }
    const expected = new Map();
    lines.push(`SOURCE ${source.node} exited ${vehicles.length}`);
    for (const route of routes) {
      const key = route.ids.join(',');
      const counts = byRoute.get(key) ?? { count: 0, travel: 0 };
      lines.push(`  ROUTE ${key} expected ${fraction(...route.share)} vehicles ${counts.count} `
        + `share ${fraction(counts.count, vehicles.length)} mean ${decimal(counts.travel, counts.count, 2)}`);
      expected.set(route.sink, addShares(expected.get(route.sink) ?? [0n, 1n], route.share));
    }
    for (const sink of data.sinks) {
      if (!expected.has(sink)) continue;
      const counts = bySink.get(sink) ?? { count: 0, travel: 0 };
      lines.push(`  SINK ${sink} expected ${fraction(...expected.get(sink))} vehicles ${counts.count} `
        + `share ${fraction(counts.count, vehicles.length)} mean ${decimal(counts.travel, counts.count, 2)}`);
    }
  }
  return lines;
}

function classBlock(heading, vehicles) {
  const inserted = vehicles.filter(vehicle => vehicle.insertion !== null).length;
  const exited = vehicles.filter(vehicle => vehicle.exit !== null);
  const steps = total(vehicles, vehicle => vehicle.steps);
  const distance = total(vehicles, vehicle => vehicle.distance);
  const mean = valueOf => decimal(total(exited, valueOf), exited.length, 2);
  return [heading,
    `  generated ${vehicles.length} inserted ${inserted} exited ${exited.length} in_network ${inserted - exited.length} queued ${vehicles.length - inserted}`,
    `  vehicle_steps ${steps} distance ${distance} mean_speed ${fraction(distance, steps)} = ${decimal(distance, steps, 3)}`,
    `  travel ${mean(travelTime)} entry_delay ${mean(vehicle => vehicle.insertion - vehicle.arrival)} `
      + `stopped ${mean(vehicle => vehicle.stoppedSteps)} stops ${mean(vehicle => vehicle.stopCount)} lane_changes ${mean(vehicle => vehicle.laneChanges)}`];
}

function classReport(data, state) {
  const lines = [];
  for (const type of data.classes) {
    const heading = `CLASS ${type.name} vmax ${type.maximum} weight ${type.weight} overtake ${type.overtake ? 'Y' : 'N'} stops ${type.stops ? 'Y' : 'N'}`;
    lines.push(...classBlock(heading, state.vehicles.filter(vehicle => vehicle.type === type)));
  }
  lines.push(...classBlock('ALL', state.vehicles));
  return lines;
}

function networkReport(data) {
  const lines = [];
  for (const segment of data.segments) {
    lines.push(`SEGMENT ${segment.id} ${segment.from} ${segment.to} length ${segment.length} lanes ${segment.lanes} limit ${segment.limit} `
      + `entered ${segment.entered} mean_vehicles ${decimal(segment.vehicleSum, data.steps, 3)} `
      + `density ${decimal(segment.vehicleSum, data.steps * segment.length * segment.lanes, 4)} `
      + `mean_speed ${decimal(segment.speedSum, segment.vehicleSum, 2)} max_vehicles ${segment.maximumVehicles} `
      + `changes ${segment.changes.overtaking}/${segment.changes.return}/${segment.changes.avoidance}`);
  }
  for (const junction of data.junctions) {
    lines.push(...junction.lines());
    for (const segment of data.segments) {
      if (segment.junction !== junction) continue;
      lines.push(`  IN ${segment.id} green ${segment.greenCount} passed ${segment.passed} blocked ${segment.blocked} `
        + `max_queue ${segment.maximumQueue} mean_queue ${decimal(segment.queueSum, data.steps, 3)} failures ${segment.failures}`);
      for (const turn of segment.turns) lines.push(`    TURN ${turn.to.id} weight ${turn.weight} vehicles ${turn.vehicles}`);
    }
  }
  for (const stop of data.stops) lines.push(`STOP ${stop.segment.id} cell ${stop.cell} dwell ${stop.dwell} buses ${stop.buses}`);
  for (const incident of data.incidents) {
    const active = incident.activeStart === null ? 'none' : `${incident.activeStart}-${incident.activeEnd}`;
    lines.push(`INCIDENT ${incident.segment.id} lane ${incident.lane} cell ${incident.cell} planned ${incident.start}-${incident.end} active ${active}`);
  }
  return lines;
}

function spacetimeReport(data) {
  return data.diagrams.flatMap(diagram => [
    `DIAGRAM ${diagram.segment.id} lane ${diagram.lane} steps ${diagram.start}-${diagram.end}`, ...diagram.lines,
  ]);
}

function detectorReport(data, state) {
  const lines = ['detector,interval,flow,density,speed'];
  data.detectors.forEach((detector, index) => {
    state.intervals.forEach((interval, number) => {
      const counts = interval.detectors[index];
      lines.push(`${detector.name},${number + 1},${counts.passing},`
        + `${decimal(counts.occupancy, data.interval * detector.width * detector.segment.lanes, 4)},`
        + `${decimal(counts.occupancySpeed, counts.occupancy, 2)}`);
    });
  });
  return lines;
}

function timelineReport(state) {
  const lines = ['interval,arrived,inserted,exited,in_network,queued,mean_speed'];
  let arrived = 0;
  let inserted = 0;
  let exited = 0;
  state.intervals.forEach((interval, index) => {
    arrived += interval.arrivals;
    inserted += interval.insertions;
    exited += interval.exits;
    lines.push(`${index + 1},${interval.arrivals},${interval.insertions},${interval.exits},`
      + `${inserted - exited},${arrived - inserted},${decimal(interval.speedSum, interval.vehicleSteps, 2)}`);
  });
  return lines;
}

function tracksReport(data, state) {
  const lines = [];
  for (const number of data.trackNumbers) {
    const vehicle = state.vehicles[number - 1];
    if (vehicle === undefined) {
      lines.push(`VEHICLE ${number} none`);
      continue;
    }
    lines.push(`VEHICLE ${number} class ${vehicle.type.name} source ${vehicle.source.node} arrival ${vehicle.arrival} `
      + `inserted ${vehicle.insertion ?? '-'} exited ${vehicle.exit ?? '-'} sink ${vehicle.sink ?? '-'}`);
    lines.push(`ROUTE ${vehicle.route.length === 0 ? '-' : vehicle.route.join(' ')}`);
    lines.push(...vehicle.trajectory);
  }
  return lines;
}

function modulo(value, divisor) {
  const remainder = value % divisor;
  return remainder < 0 ? remainder + divisor : remainder;
}

function ringExperiment(ring, count, p, p0) {
  const generator = new Minstd(ring.seed);
  const vehicles = Array.from({ length: count }, (_, index) => ({ position: floorRatio(index * ring.length, count), speed: 0 }));
  let distance = 0;
  for (let step = 1; step <= ring.warmup + ring.measurement; step += 1) {
    vehicles.sort((first, second) => second.position - first.position);
    for (let index = 0; index < vehicles.length; index += 1) {
      const vehicle = vehicles[index];
      const ahead = vehicles[(index + vehicles.length - 1) % vehicles.length];
      const gap = modulo(ahead.position - vehicle.position - 1, ring.length);
      const speed = Math.min(vehicle.speed + 1, ring.maximum, gap);
      vehicle.nextSpeed = randomSlowdown(speed, vehicle.speed, p, p0, generator);
    }
    for (const vehicle of vehicles) {
      vehicle.position = modulo(vehicle.position + vehicle.nextSpeed, ring.length);
      vehicle.speed = vehicle.nextSpeed;
      if (step > ring.warmup) distance += vehicle.speed;
    }
  }
  return distance;
}

function fundamentalReport(data) {
  const lines = ['ring,vehicles,density,flow,speed'];
  data.rings.forEach((ring, index) => {
    for (const count of ring.counts) {
      const distance = ringExperiment(ring, count, data.p, data.p0);
      lines.push(`${index + 1},${count},${decimal(count, ring.length, 4)},`
        + `${decimal(distance, ring.length * ring.measurement, 4)},${decimal(distance, count * ring.measurement, 3)}`);
    }
  });
  return lines;
}

function main() {
  const data = readInput();
  const state = simulate(data);
  const reports = {
    'spacetime.txt': spacetimeReport(data),
    'detectors.csv': detectorReport(data, state),
    'travel_times.txt': travelReport(data, state),
    'class_stats.txt': classReport(data, state),
    'network_stats.txt': networkReport(data),
    'timeline.csv': timelineReport(state),
    'tracks.txt': tracksReport(data, state),
    'fundamental.csv': fundamentalReport(data),
    'events.txt': state.events,
  };
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    fs.writeFileSync(`output/${name}`, lines.length === 0 ? '' : `${lines.join('\n')}\n`, 'ascii');
  }
}

if (require.main === module) main();
