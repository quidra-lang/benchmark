"use strict";

const fs = require("fs");

function readLines(path) {
  return fs.readFileSync(path, "ascii").trimEnd().split("\n");
}

function loadAll() {
  const types = {};
  for (const line of readLines("input/aircraft.txt")) {
    const [name, climb, descent, minimum] = line.split(" ");
    types[name] = {
      climb: Number(climb), descent: Number(descent), minimum: Number(minimum)
    };
  }
  const sectors = readLines("input/sectors.txt").map((line, index) => {
    const [name, ...raw] = line.split(" ");
    const [x1, y1, x2, y2, lower, upper, capacity] = raw.map(Number);
    return {name, index, x1, y1, x2, y2, lower, upper, capacity};
  });
  const rows = readLines("input/params.txt").map(line => line.split(" "));
  const keys = ["separation", "lookahead", "max_delay", "levels",
    "sampling", "radar", "snapshots", "leader", "alert"];
  if (rows.length !== keys.length || rows.some((r, i) => r[0] !== keys[i])) {
    throw new Error("unexpected parameter lines");
  }
  const p = rows.map(row => row.slice(1).map(Number));
  const params = {
    dh: p[0][0], dv: p[0][1], lookahead: p[1][0],
    maxDelay: p[2][0], levelMin: p[3][0], levelMax: p[3][1],
    sampleStart: p[4][0], sampleEnd: p[4][1],
    radar: p[5], snapshots: p[6], leader: p[7][0], alert: p[8][0]
  };
  const flights = {};
  for (const line of readLines("input/flights.csv").slice(1)) {
    const [callsign, type, departure, level, speed, waypoints] = line.split(",");
    flights[callsign] = {
      callsign, type, departure: Number(departure), level: Number(level),
      speedInitial: Number(speed), speed: Number(speed),
      delay: 0, offset: 0, history: [],
      waypoints: waypoints.split(" ").map(word => {
        const coords = word.split(":").map(Number);
        return {x: coords[0], y: coords[1], level: coords.length === 3 ? coords[2] : null};
      })
    };
  }
  return {flights, types, sectors, params};
}

function clonePlan(plan) {
  return {...plan, history: [...plan.history]};
}

function levelList(plan) {
  return [
    plan.level + plan.offset,
    ...plan.waypoints.slice(1).filter(w => w.level !== null)
      .map(w => w.level + plan.offset)
  ];
}

module.exports = {loadAll, clonePlan, levelList};
