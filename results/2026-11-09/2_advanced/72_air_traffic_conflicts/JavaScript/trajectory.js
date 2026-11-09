"use strict";

function buildTrajectory(plan, types) {
  const segments = [];
  let time = plan.departure + plan.delay;
  let flightLevel = plan.level + plan.offset;
  let routeLength = 0;
  const waypointTimes = [[time, flightLevel]];
  const rates = types[plan.type];

  function addSegment(leg, phase, ts, te, start, velocity, end) {
    segments.push({
      number: segments.length + 1, leg, phase, ts, te, start, velocity, end
    });
  }

  for (let leg = 1; leg < plan.waypoints.length; leg++) {
    const p = plan.waypoints[leg - 1], q = plan.waypoints[leg];
    const dx = q.x - p.x, dy = q.y - p.y;
    const length = Math.sqrt(dx * dx + dy * dy) / 10;
    const duration = length * 3600 / plan.speed;
    const vx = (dx / 10) / duration, vy = (dy / 10) / duration;
    const target = q.level === null ? flightLevel : q.level + plan.offset;
    const x = p.x / 10, y = p.y / 10;
    routeLength += length;
    if (target === flightLevel) {
      addSegment(
        leg, "LVL", time, time + duration,
        [x, y, flightLevel * 100], [vx, vy, 0],
        [q.x / 10, q.y / 10, target * 100]
      );
    } else {
      const climbing = target > flightLevel;
      const rate = climbing ? rates.climb : rates.descent;
      const changeTime = Math.abs(target - flightLevel) * 6000 / rate;
      const intermediate = [x + vx * changeTime, y + vy * changeTime, target * 100];
      addSegment(
        leg, climbing ? "CLB" : "DES", time, time + changeTime,
        [x, y, flightLevel * 100], [vx, vy, climbing ? rate / 60 : -rate / 60],
        intermediate
      );
      addSegment(
        leg, "LVL", time + changeTime, time + duration, intermediate,
        [vx, vy, 0], [q.x / 10, q.y / 10, target * 100]
      );
    }
    time += duration;
    flightLevel = target;
    waypointTimes.push([time, flightLevel]);
  }
  return {segments, arrival: time, length: routeLength, waypointTimes};
}

function position(segment, time) {
  const dt = time - segment.ts;
  return segment.start.map((value, i) => value + segment.velocity[i] * dt);
}

function activeSegment(trajectory, time) {
  const segments = trajectory.segments;
  if (!(segments[0].ts <= time && time < segments[segments.length - 1].te)) {
    return null;
  }
  return segments.find(s => s.ts <= time && time < s.te) || null;
}

function currentPosition(trajectory, time) {
  const segment = activeSegment(trajectory, time);
  return segment === null ? null : {point: position(segment, time), segment};
}

module.exports = {buildTrajectory, position, activeSegment, currentPosition};
