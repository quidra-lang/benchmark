"use strict";

// Run from the task directory with: node JavaScript/main.js
// All calculations use IEEE 754 binary64 and follow the Task A specification.

const {loadAll, clonePlan} = require("./flight_plans");
const {buildTrajectory, position, activeSegment, currentPosition} = require("./trajectory");
const {lossInterval, pairConflicts, allConflicts} = require("./conflict");
const {priorityOrder, manoeuvres, propose} = require("./resolution");
const {decimal: d, named, chart, signed, writeLines} = require("./report");

const PI = 3.141592653589793;
const entries = object => Object.entries(object);
const names = object => Object.keys(object).sort();

function samples(params) {
  const result = [];
  for (let t = params.sampleStart; t < params.sampleEnd; t += 60) result.push(t);
  return result;
}

function pairKey(pair) {
  return pair[0] + "-" + pair[1];
}

function blockers(changed, candidate, partner, trajectories, ignored, start, params) {
  const blocked = [];
  for (const other of names(trajectories)) {
    if (other === changed) continue;
    const pair = [changed, other].sort();
    if (ignored.has(pairKey(pair))) continue;
    const first = pair[0] === changed ? candidate : trajectories[pair[0]];
    const second = pair[1] === changed ? candidate : trajectories[pair[1]];
    for (const conflict of pairConflicts(
      pair[0], first, pair[1], second, params.dh, params.dv
    )) {
      if (other === partner || conflict.start < start + params.lookahead) {
        blocked.push(conflict);
      }
    }
  }
  blocked.sort((a, b) =>
    a.start - b.start || a.name.localeCompare(b.name)
  );
  return blocked.length ? blocked[0] : null;
}

function resolve(initial, types, params) {
  const plans = Object.fromEntries(entries(initial).map(
    ([code, plan]) => [code, clonePlan(plan)]
  ));
  const trajectories = Object.fromEntries(entries(plans).map(
    ([code, plan]) => [code, buildTrajectory(plan, types)]
  ));
  const unresolved = new Set(), resolved = new Set();
  const rounds = [], unresolvedConflicts = [];
  while (true) {
    const target = allConflicts(trajectories, params.dh, params.dv)
      .find(c => !unresolved.has(pairKey(c.pair)));
    if (!target) break;
    const pair = target.pair;
    const [low, high] = priorityOrder(plans[pair[0]], plans[pair[1]]);
    const round = {number: rounds.length + 1, target, trials: [], accepted: null};
    for (const [flight, partner] of [[low, high], [high, low]]) {
      if (round.accepted) break;
      for (const [name, value] of manoeuvres(params.maxDelay)) {
        const next = propose(plans[flight], name, value, types, params);
        const attempt = {flight, name};
        if (!next) {
          attempt.status = "infeasible";
        } else {
          const path = buildTrajectory(next, types);
          const blocking = blockers(
            flight, path, partner, trajectories, unresolved, target.start, params
          );
          if (blocking) {
            attempt.status = "blocked";
            attempt.blocker = blocking;
          } else {
            attempt.status = "accepted";
            next.history.push(name);
            plans[flight] = next;
            trajectories[flight] = path;
            round.accepted = attempt;
          }
        }
        round.trials.push(attempt);
        if (round.accepted) break;
      }
    }
    const key = pairKey(pair);
    if (!round.accepted) {
      unresolved.add(key);
      unresolvedConflicts.push(target);
    } else {
      resolved.add(key);
    }
    rounds.push(round);
  }
  return {plans, trajectories, rounds, unresolved, resolved, unresolvedConflicts};
}

function track(segment) {
  let theta = Math.atan2(segment.velocity[0], segment.velocity[1]) * 180 / PI;
  if (theta < 0) theta += 360;
  return theta;
}

function contains(sector, p) {
  return sector.x1 / 10 <= p[0] && p[0] < sector.x2 / 10 &&
    sector.y1 / 10 <= p[1] && p[1] < sector.y2 / 10 &&
    sector.lower * 100 <= p[2] && p[2] < sector.upper * 100;
}

function classify(conflicts, sectors, remaining, resolved, dh, final = false) {
  for (const conflict of conflicts) {
    const piece = conflict.closest, a = piece.aSegment, b = piece.bSegment;
    const pa = position(a, piece.tc), pb = position(b, piece.tc);
    const trackA = track(a), trackB = track(b);
    const angle = Math.min(Math.abs(trackA - trackB), 360 - Math.abs(trackA - trackB));
    const dot = a.velocity[0] * b.velocity[0] +
      a.velocity[1] * b.velocity[1];
    const cross = a.velocity[0] * b.velocity[1] -
      a.velocity[1] * b.velocity[0];
    const geometry = dot * dot > cross * cross ?
      (dot < 0 ? "head_on" : "trailing") : "crossing";
    const severity = 10 * piece.distance < 4 * dh ? "HIGH" :
      10 * piece.distance < 7 * dh ? "MEDIUM" : "LOW";
    const mid = pa.map((v, i) => (v + pb[i]) / 2);
    const sector = sectors.find(s => contains(s, mid));
    const key = pairKey(conflict.pair);
    const outcome = final || remaining.has(key) ? "remaining" :
      resolved.has(key) ? "resolved" : "indirect";
    Object.assign(conflict, {
      levelA: pa[2] / 100, levelB: pb[2] / 100,
      trackA, trackB, angle, geometry, severity,
      sector: sector ? sector.name : "-", outcome
    });
  }
}

function activeConflicts(conflicts, time) {
  return conflicts.filter(c => c.start <= time && time < c.end);
}

function trajectoryRows(trajectories) {
  const lines = [
    "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end"
  ];
  for (const code of names(trajectories)) {
    for (const s of trajectories[code].segments) {
      lines.push([
        code, s.number, s.leg, s.phase, d(s.ts), d(s.te),
        d(s.start[0]), d(s.start[1]), Math.round(s.start[2] / 100),
        d(s.end[0]), d(s.end[1]), Math.round(s.end[2] / 100)
      ].join(","));
    }
  }
  return lines;
}

function perFlightConflicts(conflicts) {
  const result = {};
  for (const c of conflicts) {
    const [a, b] = c.pair;
    (result[a] ||= []).push([c, b]);
    (result[b] ||= []).push([c, a]);
  }
  return result;
}

function conflictReport(label, conflicts, trajectories, params) {
  const lines = ["CONFLICTS " + named({plan: label, count: conflicts.length})];
  const geometries = {head_on: 0, crossing: 0, trailing: 0};
  const severities = {HIGH: 0, MEDIUM: 0, LOW: 0};
  for (let index = 0; index < conflicts.length; index++) {
    const c = conflicts[index], p = c.closest;
    geometries[c.geometry]++;
    severities[c.severity]++;
    lines.push(
      "CONFLICT " + (index + 1) + " " + c.name + " " + named({
        start: d(c.start), end: d(c.end), duration: d(c.end - c.start),
        outcome: c.outcome
      })
    );
    lines.push(
      "  CPA " + named({
        t: d(p.tc), dist: d(p.distance), vert: d(p.vertical, 1),
        levels: d(c.levelA, 2) + "/" + d(c.levelB, 2),
        tracks: d(c.trackA, 1) + "/" + d(c.trackB, 1),
        angle: d(c.angle, 1)
      })
    );
    lines.push(
      "  TYPE " + named({
        geometry: c.geometry,
        phases: p.aSegment.phase + "/" + p.bSegment.phase,
        segments: p.aSegment.number + "/" + p.bSegment.number,
        sector: c.sector, severity: c.severity
      })
    );
    for (const piece of c.pieces) {
      lines.push(
        "  PIECE " + piece.aSegment.number + "/" + piece.bSegment.number +
        " " + d(piece.lo) + " " + d(piece.hi)
      );
    }
  }
  lines.push("SUMMARY " + named({
    count: conflicts.length,
    total: d(conflicts.reduce((s, c) => s + c.end - c.start, 0)),
    min_dist: conflicts.length ? d(Math.min(...conflicts.map(c => c.closest.distance))) : "-",
    head_on: geometries.head_on, crossing: geometries.crossing,
    trailing: geometries.trailing,
    high: severities.HIGH, medium: severities.MEDIUM, low: severities.LOW
  }));
  const grouped = perFlightConflicts(conflicts);
  for (const code of names(grouped)) {
    const involvement = grouped[code];
    lines.push("FLIGHT " + code + " " + named({
      conflicts: involvement.length,
      first: d(Math.min(...involvement.map(record => record[0].start))),
      partners: [...new Set(involvement.map(record => record[1]))].sort().join(",")
    }));
  }
  lines.push("TIMELINE " + named({
    from: params.sampleStart, to: params.sampleEnd, step: 60
  }));
  for (const code of names(grouped)) {
    let marks = "";
    for (const time of samples(params)) {
      if (!activeSegment(trajectories[code], time)) marks += ".";
      else if (grouped[code].some(([c]) => c.start <= time && time < c.end)) marks += "X";
      else marks += "-";
    }
    lines.push(code + " " + marks);
  }
  return lines;
}

function resolutionReport(initial, resolved, trajectoriesInitial, trajectoriesFinal,
  initialConflicts, finalConflicts, rounds, unresolvedConflicts) {
  const lines = [];
  for (const round of rounds) {
    const c = round.target;
    lines.push(
      "ROUND " + round.number + " " + c.name + " " + named({
        start: d(c.start), end: d(c.end), dist: d(c.closest.distance)
      })
    );
    for (const a of round.trials) {
      let line = "  TRY " + a.flight + " " + a.name + " " + a.status;
      if (a.blocker) line += " " + a.blocker.name + " start=" + d(a.blocker.start);
      lines.push(line);
    }
    lines.push(round.accepted ?
      "  RESULT resolved " + round.accepted.flight + " " + round.accepted.name :
      "  RESULT unresolved"
    );
  }
  const countInitial = {}, countFinal = {};
  for (const c of initialConflicts) for (const code of c.pair) {
    countInitial[code] = (countInitial[code] || 0) + 1;
  }
  for (const c of finalConflicts) for (const code of c.pair) {
    countFinal[code] = (countFinal[code] || 0) + 1;
  }
  let totalExtra = 0;
  for (const code of names(resolved)) {
    const original = initial[code], next = resolved[code];
    const prior = trajectoriesInitial[code], current = trajectoriesFinal[code];
    const extra = current.arrival - prior.arrival;
    totalExtra += extra;
    lines.push("FLIGHT " + code + " " + named({
      departure: next.departure + next.delay,
      delay: next.delay, level: signed(next.offset),
      speed: original.speed + "->" + next.speed,
      arrival: d(prior.arrival) + "->" + d(current.arrival),
      extra: d(extra), length: d(current.length),
      conflicts: (countInitial[code] || 0) + "->" + (countFinal[code] || 0),
      manoeuvres: next.history.join(",") || "-"
    }));
  }
  for (const conflict of unresolvedConflicts) {
    lines.push("UNRESOLVED " + conflict.name + " " + named({
      start: d(conflict.start), dist: d(conflict.closest.distance)
    }));
  }
  const attempts = rounds.flatMap(r => r.trials);
  const accepted = rounds.filter(r => r.accepted).map(r => r.accepted);
  lines.push("TOTAL " + named({
    rounds: rounds.length, resolved: accepted.length,
    unresolved: unresolvedConflicts.length,
    level: accepted.filter(r => r.name.startsWith("level_")).length,
    speed: accepted.filter(r => r.name === "speed_down").length,
    delay: accepted.filter(r => r.name.startsWith("delay_")).length,
    total_delay: entries(resolved).reduce((sum, [, p]) => sum + p.delay, 0),
    total_extra: d(totalExtra), trials: attempts.length,
    infeasible: attempts.filter(a => a.status === "infeasible").length,
    blocked: attempts.filter(a => a.status === "blocked").length
  }));
  return lines;
}

function inSector(segment, sector) {
  const limits = [
    [sector.x1 / 10, sector.x2 / 10],
    [sector.y1 / 10, sector.y2 / 10],
    [sector.lower * 100, sector.upper * 100]
  ];
  let lo = segment.ts, hi = segment.te;
  for (let axis = 0; axis < 3; axis++) {
    const p = segment.start[axis], v = segment.velocity[axis];
    const [lower, upper] = limits[axis];
    if (v === 0) {
      if (!(lower <= p && p < upper)) return null;
    } else {
      const r1 = (lower - p) / v, r2 = (upper - p) / v;
      lo = Math.max(lo, segment.ts + Math.min(r1, r2));
      hi = Math.min(hi, segment.ts + Math.max(r1, r2));
    }
  }
  return hi - lo > 1e-6 ? [lo, hi] : null;
}

function findTransits(trajectories, sectors) {
  const result = [];
  for (const code of names(trajectories)) {
    const trips = [];
    for (const sector of sectors) {
      const combined = [];
      for (const segment of trajectories[code].segments) {
        const range = inSector(segment, sector);
        if (!range) continue;
        if (combined.length && range[0] - combined[combined.length - 1][1] <= 1e-6) {
          combined[combined.length - 1][1] = range[1];
        } else {
          combined.push(range);
        }
      }
      for (const [entry, exit] of combined) {
        trips.push({
          code, sector: sector.name, sectorIndex: sector.index,
          entry, exit, from: "-", to: "-"
        });
      }
    }
    trips.sort((a, b) => a.entry - b.entry || a.sectorIndex - b.sectorIndex);
    for (let i = 1; i < trips.length; i++) {
      const before = trips[i - 1], after = trips[i];
      if (Math.abs(after.entry - before.exit) <= 1e-6) {
        before.to = after.sector;
        after.from = before.sector;
      }
    }
    result.push(...trips);
  }
  return result;
}

function transitsRows(transits) {
  return [
    "callsign,sector,entry,exit,duration,from,to",
    ...transits.map(t => [
      t.code, t.sector, d(t.entry), d(t.exit),
      d(t.exit - t.entry), t.from, t.to
    ].join(","))
  ];
}

function occupancy(trajectories, sectors, times) {
  const table = Object.fromEntries(sectors.map(s => [s.name, times.map(() => 0)]));
  for (let i = 0; i < times.length; i++) {
    for (const code of names(trajectories)) {
      const state = currentPosition(trajectories[code], times[i]);
      if (!state) continue;
      for (const sector of sectors) {
        if (contains(sector, state.point)) table[sector.name][i]++;
      }
    }
  }
  return table;
}

function periods(sectors, times, before, after, initialTransits, finalTransits) {
  const result = [];
  for (const sector of sectors) {
    const name = sector.name;
    for (let i = 0; i < times.length; i += 5) {
      const start = times[i], end = start + 300;
      const iValues = before[name].slice(i, i + 5);
      const fValues = after[name].slice(i, i + 5);
      const peakI = Math.max(...iValues), peakF = Math.max(...fValues);
      const entriesIn = initialTransits.filter(
        t => t.sector === name && start <= t.entry && t.entry < end
      ).length;
      const entriesOut = finalTransits.filter(
        t => t.sector === name && start <= t.entry && t.entry < end
      ).length;
      result.push({
        name, period: i / 5 + 1, start, end,
        entriesIn, entriesOut, peakI, peakF,
        meanF: fValues.reduce((s, n) => s + n, 0) / 5,
        capacity: sector.capacity,
        status: peakF > sector.capacity ? "OVER" :
          peakI > sector.capacity ? "RELIEVED" : "OK"
      });
    }
  }
  return result;
}

function periodRows(rows) {
  return [
    "sector,period,start,end,entries_initial,entries_final,peak_initial," +
    "peak_final,mean_final,capacity,status",
    ...rows.map(row => [
      row.name, row.period, row.start, row.end,
      row.entriesIn, row.entriesOut, row.peakI, row.peakF,
      d(row.meanF, 1), row.capacity, row.status
    ].join(","))
  ];
}

function levelUsage(trajectories) {
  const result = {};
  for (const code of names(trajectories)) {
    for (const s of trajectories[code].segments) {
      if (s.phase !== "LVL") continue;
      const level = Math.round(s.start[2] / 100);
      if (!result[level]) result[level] = {planes: new Set(), time: 0};
      result[level].planes.add(code);
      result[level].time += s.te - s.ts;
    }
  }
  return result;
}

function sectorReport(sectors, times, initialOcc, finalOcc,
  initialTransits, finalTransits, initialConflicts, finalConflicts,
  initialTrajectory, finalTrajectory) {
  const result = [];
  for (const sector of sectors) {
    result.push(
      "SECTOR " + sector.name + " x=" + sector.x1 + ".." + sector.x2 +
      " y=" + sector.y1 + ".." + sector.y2 +
      " fl=" + sector.lower + ".." + sector.upper +
      " capacity=" + sector.capacity
    );
    for (const [label, transits, occupation, conflicts] of [
      ["INITIAL", initialTransits, initialOcc, initialConflicts],
      ["FINAL", finalTransits, finalOcc, finalConflicts]
    ]) {
      const matches = transits.filter(t => t.sector === sector.name);
      const total = matches.reduce((sum, t) => sum + t.exit - t.entry, 0);
      let over = 0;
      for (let i = 0; i < times.length; i += 5) {
        if (Math.max(...occupation[sector.name].slice(i, i + 5)) > sector.capacity) over++;
      }
      result.push(label + " " + named({
        entries: matches.length, time: d(total),
        mean: matches.length ? d(total / matches.length) : "-",
        peak: Math.max(...occupation[sector.name]), over,
        conflicts: conflicts.filter(c => c.sector === sector.name).length
      }));
    }
    const values = finalOcc[sector.name];
    const highest = Math.max(sector.capacity + 1, ...values);
    const rows = [];
    for (let k = highest; k >= 1; k--) {
      rows.push(values.map(v => v >= k ? "#" : k === sector.capacity ? "-" : ".").join(""));
    }
    result.push(...chart(rows));
  }
  const before = levelUsage(initialTrajectory), after = levelUsage(finalTrajectory);
  result.push("LEVELS");
  for (const level of [...new Set([...names(before), ...names(after)].map(Number))]
    .sort((a, b) => b - a)) {
    const b = before[level] || {planes: new Set(), time: 0};
    const a = after[level] || {planes: new Set(), time: 0};
    result.push("LEVEL " + level + " " + named({
      flights: b.planes.size + "->" + a.planes.size,
      time: d(b.time) + "->" + d(a.time)
    }));
  }
  const counts = new Map();
  for (const t of finalTransits) {
    if (t.to === "-") continue;
    const key = t.sector + "/" + t.to;
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  result.push("HANDOFFS plan=final count=" +
    [...counts.values()].reduce((sum, n) => sum + n, 0));
  const sectorOrder = Object.fromEntries(sectors.map(s => [s.name, s.index]));
  for (const key of [...counts.keys()].sort((a, b) => {
    const [a1, a2] = a.split("/"), [b1, b2] = b.split("/");
    return sectorOrder[a1] - sectorOrder[b1] || sectorOrder[a2] - sectorOrder[b2];
  })) {
    const [first, second] = key.split("/");
    result.push("HANDOFF " + first + " " + second + " " + counts.get(key));
  }
  return result;
}

function alerts(trajectories, conflicts, params) {
  const observations = new Map();
  for (const time of samples(params)) {
    const current = {};
    for (const code of names(trajectories)) {
      const value = currentPosition(trajectories[code], time);
      if (value) current[code] = value;
    }
    const flying = names(current);
    for (let i = 0; i < flying.length; i++) {
      for (let j = i + 1; j < flying.length; j++) {
        const a = current[flying[i]], b = current[flying[j]];
        const relative = a.point.map((v, k) => v - b.point[k]);
        const velocity = a.segment.velocity.map((v, k) => v - b.segment.velocity[k]);
        const loss = lossInterval(relative, velocity, 0, params.alert, params.dh, params.dv);
        if (!loss) continue;
        const pair = flying[i] + "-" + flying[j];
        if (!observations.has(pair)) observations.set(pair, []);
        observations.get(pair).push({
          time, loss: time + loss.lo, distance: loss.distance
        });
      }
    }
  }
  const found = [];
  for (const [pair, records] of observations) {
    let grouped = [];
    for (const record of records) {
      const previous = grouped[grouped.length - 1];
      if (previous && record.time - previous[previous.length - 1].time === 60) {
        previous.push(record);
      } else {
        grouped.push([record]);
      }
    }
    for (const group of grouped) {
      found.push({
        pair, first: group[0].time, last: group[group.length - 1].time,
        samples: group.length, predicted: group[0].loss,
        minDist: Math.min(...group.map(item => item.distance))
      });
    }
  }
  found.sort((a, b) => a.first - b.first || a.pair.localeCompare(b.pair));
  const detected = new Set();
  for (const item of found) {
    const indices = [];
    for (let i = 0; i < conflicts.length; i++) {
      const c = conflicts[i];
      if (c.name === item.pair && c.start < item.last + params.alert && c.end > item.first) {
        indices.push(i);
        detected.add(i);
      }
    }
    item.lead = indices.length ? conflicts[indices[0]].start - item.first : null;
  }
  return {
    found, missed: conflicts.filter((c, i) => !detected.has(i))
  };
}

function alertReport(label, trajectories, conflicts, params) {
  const {found, missed} = alerts(trajectories, conflicts, params);
  const lines = ["ALERTS " + named({plan: label, horizon: params.alert, count: found.length})];
  const leads = [];
  for (let i = 0; i < found.length; i++) {
    const a = found[i];
    if (a.lead !== null) leads.push(a.lead);
    lines.push("ALERT " + (i + 1) + " " + a.pair + " " + named({
      first: a.first, last: a.last, samples: a.samples,
      predicted: d(a.predicted), min_dist: d(a.minDist),
      status: a.lead === null ? "false" : "true",
      lead: a.lead === null ? "-" : d(a.lead)
    }));
  }
  for (const c of missed) {
    lines.push("MISSED " + c.name + " " + named({start: d(c.start), end: d(c.end)}));
  }
  lines.push("SUMMARY " + named({
    alerts: found.length, true: leads.length, false: found.length - leads.length,
    missed: missed.length,
    mean_lead: leads.length ? d(leads.reduce((s, v) => s + v, 0) / leads.length) : "-"
  }));
  return lines;
}

function radarCell(point, params) {
  const [rx0, ry0, rx1, ry1, width, height] = params.radar;
  const col = Math.floor((10 * point[0] - rx0) * width / (rx1 - rx0));
  const bottom = Math.floor((10 * point[1] - ry0) * height / (ry1 - ry0));
  return 0 <= col && col < width && 0 <= bottom && bottom < height ?
    [col, height - 1 - bottom] : null;
}

function radarSnapshot(label, trajectories, conflicts, time, params) {
  const width = params.radar[4], height = params.radar[5];
  const grid = Array.from({length: height}, () => Array(width).fill("."));
  const current = {};
  const locations = new Map();
  for (const code of names(trajectories)) {
    const state = currentPosition(trajectories[code], time);
    if (!state) continue;
    const cell = radarCell(state.point, params);
    current[code] = {...state, cell};
    if (cell) {
      const key = cell.join(",");
      if (!locations.has(key)) locations.set(key, []);
      locations.get(key).push(code);
    }
  }
  const active = activeConflicts(conflicts, time);
  const conflicted = new Set(active.flatMap(c => c.pair));
  for (const [key, flightNames] of locations) {
    const [col, row] = key.split(",").map(Number);
    const one = flightNames[0];
    grid[row][col] = flightNames.length > 1 ?
      String(flightNames.length) :
      conflicted.has(one) ? one[0].toLowerCase() : one[0];
  }
  for (const code of names(current)) {
    const forecast = currentPosition(trajectories[code], time + params.leader);
    if (!forecast) continue;
    const cell = radarCell(forecast.point, params);
    if (cell && grid[cell[1]][cell[0]] === ".") grid[cell[1]][cell[0]] = "*";
  }
  const lines = [
    "RADAR " + named({
      plan: label, t: time, aircraft: names(current).length, conflicts: active.length
    }),
    ...chart(grid.map(row => row.join("")))
  ];
  for (const code of names(current)) {
    const record = current[code], [x, y, z] = record.point;
    lines.push(code + " " + named({
      x: d(x), y: d(y), fl: d(z / 100, 2),
      track: d(track(record.segment), 1), phase: record.segment.phase,
      cell: record.cell ? record.cell.join(",") : "outside"
    }));
  }
  for (const conflict of active) {
    const a = current[conflict.pair[0]].point;
    const b = current[conflict.pair[1]].point;
    const dx = a[0] - b[0], dy = a[1] - b[1];
    lines.push("CONFLICT " + conflict.name + " " + named({
      dist: d(Math.sqrt(dx * dx + dy * dy)), vert: d(Math.abs(a[2] - b[2]), 1)
    }));
  }
  return lines;
}

function densityReport(label, trajectories, params) {
  const width = params.radar[4], height = params.radar[5];
  const density = Array.from({length: height}, () => Array(width).fill(0));
  for (const time of samples(params)) {
    for (const code of names(trajectories)) {
      const state = currentPosition(trajectories[code], time);
      if (!state) continue;
      const cell = radarCell(state.point, params);
      if (cell) density[cell[1]][cell[0]]++;
    }
  }
  const biggest = Math.max(...density.flat());
  return [
    "DENSITY " + named({
      plan: label, from: params.sampleStart, to: params.sampleEnd,
      step: 60, max: biggest
    }),
    ...chart(density.map(row => row.map(value =>
      value === 0 ? "." : value <= 9 ? String(value) : "#"
    ).join("")))
  ];
}

function strips(initial, final, first, last, transits) {
  const lines = [];
  for (const code of names(final)) {
    const plan = final[code];
    const before = first[code], after = last[code];
    lines.push("STRIP " + code + " " + named({
      type: plan.type, waypoints: plan.waypoints.length,
      length: d(after.length), manoeuvres: plan.history.join(",") || "-"
    }));
    plan.waypoints.forEach((waypoint, index) => {
      const original = before.waypointTimes[index], current = after.waypointTimes[index];
      lines.push("WPT " + index + " " + named({
        at: waypoint.x + ":" + waypoint.y,
        eta: d(original[0]) + "->" + d(current[0]),
        fl: original[1] + "->" + current[1]
      }));
    });
    const order = transits.filter(t => t.code === code)
      .map(t => t.sector + "@" + d(t.entry));
    lines.push("SECTORS " + (order.join(",") || "-"));
  }
  return lines;
}

function main() {
  const {flights: initial, types, sectors, params} = loadAll();
  const trajectoriesInitial = Object.fromEntries(
    entries(initial).map(([code, plan]) => [code, buildTrajectory(plan, types)])
  );
  const initialConflicts = allConflicts(trajectoriesInitial, params.dh, params.dv);
  const solved = resolve(initial, types, params);
  const final = solved.plans, trajectoriesFinal = solved.trajectories;
  const finalConflicts = allConflicts(trajectoriesFinal, params.dh, params.dv);
  const finalPairs = new Set(finalConflicts.map(c => pairKey(c.pair)));
  classify(initialConflicts, sectors, finalPairs, solved.resolved, params.dh);
  classify(finalConflicts, sectors, finalPairs, solved.resolved, params.dh, true);
  const transitsInitial = findTransits(trajectoriesInitial, sectors);
  const transitsFinal = findTransits(trajectoriesFinal, sectors);
  const times = samples(params);
  const occupancyInitial = occupancy(trajectoriesInitial, sectors, times);
  const occupancyFinal = occupancy(trajectoriesFinal, sectors, times);
  const load = periods(
    sectors, times, occupancyInitial, occupancyFinal,
    transitsInitial, transitsFinal
  );

  writeLines("trajectories.csv", trajectoryRows(trajectoriesFinal));
  writeLines("conflicts.txt", [
    ...conflictReport("initial", initialConflicts, trajectoriesInitial, params),
    ...conflictReport("final", finalConflicts, trajectoriesFinal, params)
  ]);
  writeLines("resolutions.txt", resolutionReport(
    initial, final, trajectoriesInitial, trajectoriesFinal,
    initialConflicts, finalConflicts, solved.rounds, solved.unresolvedConflicts
  ));
  writeLines("sector_transits.csv", transitsRows(transitsFinal));
  writeLines("sector_load.csv", periodRows(load));
  writeLines("sector_report.txt", sectorReport(
    sectors, times, occupancyInitial, occupancyFinal,
    transitsInitial, transitsFinal, initialConflicts, finalConflicts,
    trajectoriesInitial, trajectoriesFinal
  ));
  writeLines("alerts.txt", [
    ...alertReport("initial", trajectoriesInitial, initialConflicts, params),
    ...alertReport("final", trajectoriesFinal, finalConflicts, params)
  ]);
  const radar = [];
  for (const time of params.snapshots) {
    radar.push(...radarSnapshot("initial", trajectoriesInitial, initialConflicts, time, params));
    radar.push(...radarSnapshot("final", trajectoriesFinal, finalConflicts, time, params));
  }
  radar.push(...densityReport("initial", trajectoriesInitial, params));
  radar.push(...densityReport("final", trajectoriesFinal, params));
  writeLines("radar.txt", radar);
  writeLines("strips.txt", strips(initial, final, trajectoriesInitial, trajectoriesFinal, transitsFinal));
}

main();
