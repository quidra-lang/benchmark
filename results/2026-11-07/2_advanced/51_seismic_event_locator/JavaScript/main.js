'use strict';

const fs = require('node:fs');
const { readInput } = require('./waveform_io');
const { detectPicks } = require('./picker');
const { associate } = require('./associator');
const { distance, evaluate, geiger, locationRun, uncertainty } = require('./locator');
const { median, localMagnitude, durationMagnitude, magnitudeClass, frequencyStatistics } = require('./magnitude');

const sum = values => values.reduce((total, value) => total + value, 0);
const timeNotation = sample => Math.floor(sample / 100) + '.' + String(sample % 100).padStart(2, '0');
const classNotation = value => (value < 0 ? '-' : '') + Math.floor(Math.abs(value) / 10) + '.' + Math.abs(value) % 10;

function fixed(value, digits) {
  if (value === null) return '-';
  const absolute = Math.abs(value);
  const text = absolute >= 1e21 ? BigInt(absolute).toString() + '.' + '0'.repeat(digits) : absolute.toFixed(digits);
  return value < 0 && Number(text) !== 0 ? '-' + text : text;
}

const scaled = (value, digits) => Number(fixed(value, digits).replace('.', ''));
const rms = values => values.length ? Math.sqrt(sum(values.map(value => value * value)) / values.length) : null;
const observation = pick => ({ station: pick.station, time: pick.time, pick });

function processCandidates(candidates, params) {
  const events = [];
  for (const candidate of candidates) {
    candidate.picks.sort((a, b) => a.station.index - b.station.index);
    candidate.pass1 = locationRun(candidate.picks.map(observation), params);
    candidate.dropped = [];
    candidate.remaining = [];
    candidate.picks.forEach((pick, i) => {
      if (Math.abs(candidate.pass1.residuals[i]) > params.residualLimit) {
        candidate.dropped.push({ pick, residual: candidate.pass1.residuals[i] });
      } else candidate.remaining.push(pick);
    });
    candidate.rejected = candidate.dropped.length > 0 && candidate.remaining.length < params.minStations;
    if (candidate.rejected) {
      for (const pick of candidate.picks) pick.state = 'rejected';
      continue;
    }
    candidate.pass2 = candidate.dropped.length ? locationRun(candidate.remaining.map(observation), params) : null;
    const adopted = candidate.pass2 ?? candidate.pass1;
    const event = { number: events.length + 1, used: candidate.remaining, firstStage: adopted };
    candidate.event = event;
    event.used.forEach((pick, i) => {
      pick.state = 'used';
      pick.event = event.number;
      pick.firstResidual = adopted.residuals[i];
      pick.station.used.push(pick);
    });
    for (const { pick } of candidate.dropped) {
      pick.state = 'dropped';
      pick.event = event.number;
    }
    events.push(event);
  }
  return events;
}

function qualityAndStability(event, params) {
  const point = event.relocation.point;
  event.ellipse = uncertainty(point, event.corrected, params.velocity);
  const dx = point.x - event.firstStage.point.x;
  const dy = point.y - event.firstStage.point.y;
  event.shift = { dh: Math.sqrt(dx * dx + dy * dy), dz: point.z - event.firstStage.point.z };
  const azimuths = [];
  const horizontal = [];
  for (const pick of event.used) {
    const sx = pick.station.x - point.x;
    const sy = pick.station.y - point.y;
    let azimuth = Math.atan2(sx, sy) * 180 / 3.141592653589793;
    if (azimuth < 0) azimuth += 360;
    azimuths.push(azimuth);
    horizontal.push(Math.sqrt(sx * sx + sy * sy));
  }
  azimuths.sort((a, b) => a - b);
  event.gap = azimuths[0] + 360 - azimuths.at(-1);
  for (let i = 1; i < azimuths.length; i++) event.gap = Math.max(event.gap, azimuths[i] - azimuths[i - 1]);
  event.dmin = Math.min(...horizontal);
  const meets = limits => event.gap <= limits[0] && event.relocation.rms <= limits[1] && event.ellipse.smaj <= limits[2];
  event.quality = meets(params.qualityA) ? 'A' : meets(params.qualityB) ? 'B' : 'C';
  event.jackknife = event.used.map((pick, removed) => {
    const observations = event.corrected.filter((_, i) => i !== removed);
    const result = geiger(point, observations, params.velocity).point;
    const dx = result.x - point.x;
    const dy = result.y - point.y;
    return { station: pick.station, dx, dy, dz: result.z - point.z, shift: Math.sqrt(dx * dx + dy * dy) };
  });
  event.worstJackknife = event.jackknife[0];
  for (const jack of event.jackknife) if (jack.shift > event.worstJackknife.shift) event.worstJackknife = jack;
}

function relocateEvents(stations, events, params) {
  for (const station of stations) {
    station.correction = station.used.length ? sum(station.used.map(pick => pick.firstResidual)) / station.used.length : 0;
  }
  for (const event of events) {
    event.corrected = event.used.map(pick => ({ station: pick.station, time: pick.time - pick.station.correction, pick }));
    event.startRms = evaluate(event.firstStage.point, event.corrected, params.velocity).rms;
    event.relocation = geiger(event.firstStage.point, event.corrected, params.velocity);
    event.used.forEach((pick, i) => { pick.residual = event.relocation.residuals[i]; });
    qualityAndStability(event, params);
  }
}

function computeMagnitudes(stations, events, params) {
  for (const event of events) {
    event.used.forEach((pick, i) => {
      pick.distanceKm = event.relocation.distances[i] / 1000;
      pick.ml = pick.clipped ? null : localMagnitude(pick.amplitude, pick.distanceKm, params.localMagnitude);
      pick.md = durationMagnitude(pick.duration, pick.distanceKm, params.durationMagnitude);
    });
    event.unclipped = event.used.filter(pick => !pick.clipped);
    event.ml = median(event.unclipped.map(pick => pick.ml));
    event.md = median(event.used.map(pick => pick.md));
    for (const pick of event.unclipped) pick.mlResidual = pick.ml - event.ml;
    event.hundredths = event.ml === null ? null : scaled(event.ml, 2);
    event.magnitudeClass = event.ml === null ? null : magnitudeClass(event.hundredths);
  }
  for (const station of stations) {
    station.magnitudePicks = station.used.filter(pick => !pick.clipped);
    station.magnitudeCorrection = station.magnitudePicks.length
      ? sum(station.magnitudePicks.map(pick => pick.mlResidual)) / station.magnitudePicks.length : 0;
  }
  for (const event of events) event.mlc = median(event.unclipped.map(pick => pick.ml - pick.station.magnitudeCorrection));
}

function travelTimeFit(events) {
  const points = [];
  for (const event of events) {
    for (const pick of event.used) points.push({ d: pick.distanceKm, t: pick.time - event.relocation.point.t0 });
  }
  let sd = 0;
  let st = 0;
  let sdd = 0;
  let sdt = 0;
  for (const point of points) {
    sd += point.d;
    st += point.t;
    sdd += point.d * point.d;
    sdt += point.d * point.t;
  }
  const n = points.length;
  const slope = (n * sdt - sd * st) / (n * sdd - sd * sd);
  const intercept = (st - slope * sd) / n;
  let squares = 0;
  for (const point of points) {
    const residual = point.t - intercept - slope * point.d;
    squares += residual * residual;
  }
  return { n, velocity: 1000 / slope, intercept, rms: Math.sqrt(squares / n) };
}

function clusterEvents(events, params) {
  const [distanceLimit, timeLimit] = params.cluster;
  const neighbors = events.map(() => []);
  for (let i = 0; i < events.length; i++) {
    for (let j = i + 1; j < events.length; j++) {
      const first = events[i].relocation.point;
      const second = events[j].relocation.point;
      const dx = first.x - second.x;
      const dy = first.y - second.y;
      const dz = first.z - second.z;
      if (Math.abs(first.t0 - second.t0) <= timeLimit && Math.sqrt(dx * dx + dy * dy + dz * dz) <= distanceLimit) {
        neighbors[i].push(j);
        neighbors[j].push(i);
      }
    }
  }
  const clusters = [];
  for (let first = 0; first < events.length; first++) {
    if (events[first].cluster !== undefined) continue;
    const number = clusters.length + 1;
    const queue = [first];
    events[first].cluster = number;
    for (let position = 0; position < queue.length; position++) {
      for (const next of neighbors[queue[position]]) {
        if (events[next].cluster !== undefined) continue;
        events[next].cluster = number;
        queue.push(next);
      }
    }
    queue.sort((a, b) => a - b);
    const members = queue.map(i => events[i]);
    const points = members.map(event => event.relocation.point);
    clusters.push({ number, members, x: sum(points.map(point => point.x)) / points.length,
      y: sum(points.map(point => point.y)) / points.length, z: sum(points.map(point => point.z)) / points.length,
      span: Math.max(...points.map(point => point.t0)) - Math.min(...points.map(point => point.t0)) });
  }
  return clusters;
}

function reassociate(picks, events, params) {
  const stationSets = events.map(event => new Set(event.used.map(pick => pick.station.index)));
  const added = [];
  for (const pick of picks) {
    if (pick.state !== 'unassociated') continue;
    let best = null;
    for (let i = 0; i < events.length; i++) {
      if (stationSets[i].has(pick.station.index)) continue;
      const point = events[i].relocation.point;
      const residual = pick.time - point.t0 - distance(point, pick.station) / params.velocity - pick.station.correction;
      if (Math.abs(residual) <= params.residualLimit && (best === null || Math.abs(residual) < Math.abs(best.residual))) {
        best = { index: i, residual };
      }
    }
    if (best === null) continue;
    pick.state = 'added';
    pick.event = events[best.index].number;
    pick.residual = best.residual;
    stationSets[best.index].add(pick.station.index);
    added.push(pick);
  }
  return added;
}

function catalogStatistics(events) {
  const measured = events.filter(event => event.ml !== null);
  const frequency = frequencyStatistics(measured.map(event => event.magnitudeClass));
  const n = measured.length;
  const xbar = sum(measured.map(event => event.md)) / n;
  const ybar = sum(measured.map(event => event.ml)) / n;
  let xx = 0;
  let xy = 0;
  let yy = 0;
  for (const event of measured) {
    const x = event.md - xbar;
    const y = event.ml - ybar;
    xx += x * x;
    xy += x * y;
    yy += y * y;
  }
  const slope = xy / xx;
  return { frequency, measured: n, relation: { n, slope, intercept: ybar - slope * xbar,
    r: xy / Math.sqrt(xx * yy), meanDifference: ybar - xbar } };
}

function solutionLine(label, point, residualRms) {
  return `${label} x=${fixed(point.x, 1)} y=${fixed(point.y, 1)} z=${fixed(point.z, 1)} t0=${fixed(point.t0, 3)} rms=${fixed(residualRms, 4)}`;
}

function iterationLines(iterations) {
  return iterations.map((iteration, i) => solutionLine('ITER ' + (i + 1), iteration.point, iteration.rms));
}

function passLines(pass, number, velocity) {
  const lines = ['PASS ' + number + ' stations=' + pass.observations.map(item => item.station.code).join(','),
    solutionLine('GRID', pass.grid.point, pass.grid.rms), 'PROFILE ' + pass.grid.profile.map(value => fixed(value, 4)).join(' '),
    ...iterationLines(pass.iterations)];
  pass.observations.forEach((item, i) => {
    lines.push(`RES ${item.station.code} dist=${fixed(pass.distances[i], 1)} tt=${fixed(pass.distances[i] / velocity, 4)} obs=${timeNotation(item.pick.sample)} res=${fixed(pass.residuals[i], 4)}`);
  });
  return lines;
}

function locationsLines(stations, picks, candidates, events, fit, clusters, added, params) {
  const lines = [];
  for (const candidate of candidates) {
    lines.push(`CANDIDATE ${candidate.number} picks=${candidate.picks.length} first=${timeNotation(candidate.first.sample)}`,
      ...passLines(candidate.pass1, 1, params.velocity));
    for (const item of candidate.dropped) lines.push(`DROP ${item.pick.station.code} res=${fixed(item.residual, 4)}`);
    if (candidate.rejected) lines.push('RESULT REJECTED stations=' + candidate.remaining.length);
    else {
      if (candidate.pass2 !== null) lines.push(...passLines(candidate.pass2, 2, params.velocity));
      lines.push('RESULT EVENT ' + candidate.event.number);
    }
  }
  lines.push('CORRECTIONS');
  for (const station of stations) lines.push(`${station.code} n=${station.used.length} correction=${fixed(station.correction, 4)}`);
  for (const event of events) {
    lines.push('EVENT ' + event.number, solutionLine('START', event.firstStage.point, event.startRms),
      ...iterationLines(event.relocation.iterations));
    event.used.forEach((pick, i) => {
      const length = event.relocation.distances[i];
      lines.push(`RES ${pick.station.code} dist=${fixed(length, 1)} tt=${fixed(length / params.velocity, 4)} obs=${timeNotation(pick.sample)} corr=${fixed(pick.station.correction, 4)} res=${fixed(pick.residual, 4)}`);
    });
    const ellipse = event.ellipse;
    lines.push(`ELLIPSE smaj=${fixed(ellipse.smaj, 1)} smin=${fixed(ellipse.smin, 1)} az=${fixed(ellipse.az, 1)} erz=${fixed(ellipse.erz, 1)} ert=${fixed(ellipse.ert, 4)}`,
      `SHIFT dh=${fixed(event.shift.dh, 1)} dz=${fixed(event.shift.dz, 1)}`,
      `GAP ${fixed(event.gap, 1)} DMIN ${fixed(event.dmin, 1)} QUALITY ${event.quality}`);
    for (const jack of event.jackknife) {
      lines.push(`JACK ${jack.station.code} dx=${fixed(jack.dx, 1)} dy=${fixed(jack.dy, 1)} dz=${fixed(jack.dz, 1)} shift=${fixed(jack.shift, 1)}`);
    }
    lines.push(`JACKKNIFE max=${fixed(event.worstJackknife.shift, 1)} station=${event.worstJackknife.station.code}`);
  }
  lines.push(`FIT n=${fit.n} velocity=${fixed(fit.velocity, 1)} intercept=${fixed(fit.intercept, 4)} rms=${fixed(fit.rms, 4)}`);
  for (const cluster of clusters) {
    if (cluster.members.length < 2) continue;
    lines.push(`CLUSTER ${cluster.number} events=${cluster.members.map(event => event.number).join(',')} x=${fixed(cluster.x, 1)} y=${fixed(cluster.y, 1)} z=${fixed(cluster.z, 1)} span=${fixed(cluster.span, 3)}`);
  }
  lines.push('ADDED');
  for (const pick of added) lines.push(`${pick.station.code} sample=${pick.sample} event=${pick.event} res=${fixed(pick.residual, 4)}`);
  const depths = events.map(event => event.relocation.point.z);
  const quality = code => events.filter(event => event.quality === code).length;
  const meanRms = sum(events.map(event => event.relocation.rms)) / events.length;
  lines.push(`SUMMARY picks=${picks.length} candidates=${candidates.length} events=${events.length} rejected=${candidates.filter(candidate => candidate.rejected).length} unassociated=${picks.filter(pick => pick.state === 'unassociated').length}`,
    `DEPTH min=${fixed(Math.min(...depths), 1)} median=${fixed(median(depths), 1)} max=${fixed(Math.max(...depths), 1)}`,
    `QUALITY A=${quality('A')} B=${quality('B')} C=${quality('C')} mean_rms=${fixed(meanRms, 4)}`);
  return lines;
}

function picksLines(picks) {
  return ['station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual', ...picks.map(pick =>
    [pick.station.code, pick.sample, timeNotation(pick.sample), pick.duration, fixed(pick.snr, 2), pick.amplitude,
      pick.clipped ? 'yes' : 'no', pick.event ?? 0, pick.state,
      pick.state === 'used' || pick.state === 'added' ? fixed(pick.residual, 4) : '-'].join(','))];
}

function catalogLines(events) {
  return ['event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster', ...events.map(event => {
    const point = event.relocation.point;
    const ellipse = event.ellipse;
    return [event.number, fixed(point.t0, 3), fixed(point.x, 1), fixed(point.y, 1), fixed(point.z, 1), fixed(event.relocation.rms, 4),
      event.used.length, fixed(event.gap, 1), fixed(event.dmin, 1), fixed(ellipse.smaj, 1), fixed(ellipse.smin, 1),
      fixed(ellipse.az, 1), fixed(ellipse.erz, 1), fixed(event.ml, 2), fixed(event.md, 2), event.quality, event.cluster].join(',');
  })];
}

function chartGrid(width, height) {
  return Array.from({ length: height }, () => Array(width).fill(' '));
}

function framed(grid) {
  const border = '+' + '-'.repeat(grid[0].length) + '+';
  return [border, ...grid.map(row => '|' + row.join('') + '|'), border];
}

function timelineLines(events, params) {
  const [duration, width, low, high, height] = params.timeline;
  const grid = chartGrid(width, height);
  for (const event of events) {
    if (event.ml === null) continue;
    const time = scaled(event.relocation.point.t0, 3);
    const h = event.hundredths;
    if (time < 0 || time >= 1000 * duration || h < 100 * low) continue;
    const column = Math.floor(time * width / (1000 * duration));
    const level = Math.min(Math.floor((h - 100 * low) * height / (100 * (high - low))), height - 1);
    for (let k = 0; k <= level; k++) {
      const row = height - 1 - k;
      if (k === level) grid[row][column] = 'o';
      else if (grid[row][column] === ' ') grid[row][column] = '|';
    }
  }
  return [`TIMELINE t=0..${duration} ML=${low}..${high}`, ...framed(grid)];
}

function magnitudesLines(events, statistics, params) {
  const lines = [];
  for (const event of events) {
    lines.push(`EVENT ${event.number} ML=${fixed(event.ml, 2)} n=${event.unclipped.length} MD=${fixed(event.md, 2)}`);
    for (const pick of event.used) {
      const prefix = `${pick.station.code} r=${fixed(pick.distanceKm, 3)} amp=${pick.amplitude}`;
      const local = pick.clipped ? ' clipped' : ` ml=${fixed(pick.ml, 2)} res=${fixed(pick.mlResidual, 2)}`;
      lines.push(prefix + local + ` dur=${pick.duration} md=${fixed(pick.md, 2)}`);
    }
  }
  lines.push('CORRECTED');
  for (const event of events) lines.push(`EVENT ${event.number} MLC=${fixed(event.mlc, 2)}`);
  lines.push('FMD');
  const frequency = statistics.frequency;
  let cumulative = statistics.measured;
  for (let value = frequency.minimum; value <= frequency.maximum; value++) {
    const count = frequency.frequencies.get(value) ?? 0;
    lines.push(`M=${classNotation(value)} N=${count} CUM=${cumulative}`);
    cumulative -= count;
  }
  const relation = statistics.relation;
  lines.push('MC ' + classNotation(frequency.completeness),
    `BVALUE ${fixed(frequency.b, 3)} SIGMA ${fixed(frequency.sigma, 3)} N ${frequency.count}`,
    'AVALUE ' + fixed(frequency.a, 3),
    `MLMD n=${relation.n} slope=${fixed(relation.slope, 3)} intercept=${fixed(relation.intercept, 3)} r=${fixed(relation.r, 3)} mean_diff=${fixed(relation.meanDifference, 3)}`,
    ...timelineLines(events, params));
  return lines;
}

function stationsLines(stations) {
  const lines = [];
  for (const station of stations) {
    const stats = station.stats;
    const count = state => stats.picks.filter(pick => pick.state === state).length;
    lines.push(`STATION ${station.code} x=${station.x} y=${station.y} elevation=${station.elevation}`,
      `SAMPLES start=${station.start} count=${station.samples.length} mean=${stats.mean} noise=${fixed(stats.noise, 1)} peak=${stats.peak} clipped=${stats.clippedSamples}`,
      `TRIGGERS total=${stats.triggers} short=${stats.shortTriggers} picks=${stats.picks.length}`,
      `PICKS used=${count('used')} dropped=${count('dropped')} added=${count('added')} rejected=${count('rejected')} unassociated=${count('unassociated')}`,
      `RESIDUALS n=${station.used.length} rms=${fixed(rms(station.used.map(pick => pick.firstResidual)), 4)} correction=${fixed(station.correction, 4)} after=${fixed(rms(station.used.map(pick => pick.residual)), 4)}`,
      `MAGNITUDES n=${station.magnitudePicks.length} correction=${fixed(station.magnitudeCorrection, 2)}`);
  }
  return lines;
}

function mapLines(stations, events, params) {
  const [xmin, xmax, ymin, ymax] = params.mapArea;
  const [width, mapHeight] = params.mapSize;
  const [zmax, sectionHeight] = params.section;
  const map = chartGrid(width, mapHeight);
  const eastWest = chartGrid(width, sectionHeight);
  const northSouth = chartGrid(width, sectionHeight);
  const withinX = x => 10 * xmin <= x && x < 10 * xmax;
  const withinY = y => 10 * ymin <= y && y < 10 * ymax;
  const xColumn = x => Math.floor((x - 10 * xmin) * width / (10 * (xmax - xmin)));
  const yColumn = y => Math.floor((y - 10 * ymin) * width / (10 * (ymax - ymin)));
  const mapPosition = (x, y) => withinX(x) && withinY(y)
    ? [xColumn(x), mapHeight - 1 - Math.floor((y - 10 * ymin) * mapHeight / (10 * (ymax - ymin)))] : null;
  const priorities = { '?': 0, '.': 1, o: 2, O: 3, '@': 4, '^': 5 };
  function place(grid, position, symbol) {
    if (position === null) return;
    const [column, row] = position;
    const previous = grid[row][column];
    if (previous === ' ' || priorities[symbol] > priorities[previous]) grid[row][column] = symbol;
  }
  const eventPositions = events.map(event => {
    const point = event.relocation.point;
    const x = scaled(point.x, 1);
    const y = scaled(point.y, 1);
    const z = scaled(point.z, 1);
    const h = event.hundredths;
    const symbol = h === null ? '?' : h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
    const positions = { event, symbol, map: mapPosition(x, y),
      ew: withinX(x) && z < 10 * zmax ? [xColumn(x), Math.floor(z * sectionHeight / (10 * zmax))] : null,
      ns: withinY(y) && z < 10 * zmax ? [yColumn(y), Math.floor(z * sectionHeight / (10 * zmax))] : null };
    place(map, positions.map, symbol);
    place(eastWest, positions.ew, symbol);
    place(northSouth, positions.ns, symbol);
    return positions;
  });
  const stationPositions = stations.map(station => {
    const position = mapPosition(10 * station.x, 10 * station.y);
    place(map, position, '^');
    return { station, position };
  });
  const lines = [`MAP x=${xmin}..${xmax} y=${ymin}..${ymax}`, ...framed(map),
    `SECTION EW x=${xmin}..${xmax} z=0..${zmax}`, ...framed(eastWest),
    `SECTION NS y=${ymin}..${ymax} z=0..${zmax}`, ...framed(northSouth),
    'LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML'];
  const positionText = position => position === null ? 'outside' : position.join(',');
  for (const item of stationPositions) lines.push(`STATION ${item.station.code} map=${positionText(item.position)}`);
  for (const item of eventPositions) {
    lines.push(`EVENT ${item.event.number} ${item.symbol} map=${positionText(item.map)} ew=${positionText(item.ew)} ns=${positionText(item.ns)}`);
  }
  return lines;
}

function main() {
  const { stations, params } = readInput();
  for (const station of stations) {
    station.used = [];
    station.stats = detectPicks(station, params);
  }
  const picks = stations.flatMap(station => station.stats.picks).sort((a, b) => a.sample - b.sample || a.station.index - b.station.index);
  const candidates = associate(picks, params.associationWindow, params.minStations);
  const events = processCandidates(candidates, params);
  relocateEvents(stations, events, params);
  computeMagnitudes(stations, events, params);
  const fit = travelTimeFit(events);
  const clusters = clusterEvents(events, params);
  const added = reassociate(picks, events, params);
  const statistics = catalogStatistics(events);
  const outputs = [
    ['picks.csv', picksLines(picks)],
    ['locations.txt', locationsLines(stations, picks, candidates, events, fit, clusters, added, params)],
    ['catalog.csv', catalogLines(events)],
    ['magnitudes.txt', magnitudesLines(events, statistics, params)],
    ['stations.txt', stationsLines(stations)],
    ['map.txt', mapLines(stations, events, params)]
  ];
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of outputs) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
