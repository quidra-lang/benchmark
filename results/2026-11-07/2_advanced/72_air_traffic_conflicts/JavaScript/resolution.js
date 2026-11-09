"use strict";

const {clonePlan, levelList} = require("./flight_plans");

function priorityOrder(a, b) {
  const da = a.departure + a.delay, db = b.departure + b.delay;
  if (da > db || (da === db && a.callsign > b.callsign)) {
    return [a.callsign, b.callsign];
  }
  return [b.callsign, a.callsign];
}

function manoeuvres(maxDelay) {
  const choices = [
    ["level_up", 10], ["level_down", -10], ["speed_down", null]
  ];
  for (let delay = 60; delay <= maxDelay; delay += 60) {
    choices.push(["delay_" + delay, delay]);
  }
  return choices;
}

function propose(plan, name, amount, types, params) {
  const next = clonePlan(plan);
  if (name === "level_up" || name === "level_down") {
    next.offset += amount;
    if (levelList(next).some(v => v < params.levelMin || v > params.levelMax)) {
      return null;
    }
  } else if (name === "speed_down") {
    next.speed = Math.floor(next.speed * 9 / 10);
    if (next.speed < types[next.type].minimum) return null;
  } else {
    next.delay += amount;
  }
  return next;
}

module.exports = {priorityOrder, manoeuvres, propose};
