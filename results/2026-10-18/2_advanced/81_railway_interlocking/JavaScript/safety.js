'use strict';

const PROPERTIES = ['OCCUPANCY', 'POINT_MOTION', 'CONFLICT', 'SIGNAL_PASSING'];

class Safety {
  constructor() {
    this.counts = new Map(PROPERTIES.map(property => [property, { checks: 0, violations: 0 }]));
    this.violations = [];
  }
  check(time, property, details = null) {
    const counts = this.counts.get(property); counts.checks++;
    if (details !== null) {
      counts.violations++;
      this.violations.push(`VIOLATION ${time} ${property} ${details}`);
    }
  }
  passing(time, train, signal) {
    this.check(time, 'SIGNAL_PASSING', signal.aspect === 'RED' ? train.name + ' ' + signal.name : null);
  }
  step(time, layout, routes) {
    for (const section of layout.sections) {
      const details = section.occupants.length >= 2 ? section.name + ' ' + section.occupants.map(train => train.name).join(',') : null;
      this.check(time, 'OCCUPANCY', details);
    }
    for (const point of layout.points) if (point.moving) {
      let details = null;
      if (point.common.occupants.length > 0) details = point.name + ' occupied';
      else if (point.locks.some(lock => lock.route.state === 'USED' || lock.route.state === 'APPROACH')) details = point.name + ' locked';
      this.check(time, 'POINT_MOTION', details);
    }
    const active = routes.filter(route => route.state === 'LOCKED' || route.state === 'APPROACH');
    for (let a = 0; a < active.length; a++) for (let b = a + 1; b < active.length; b++) {
      const first = active[a], second = active[b];
      const details = first.conflicts.includes(second) || second.conflicts.includes(first) ? first.name + ' ' + second.name : null;
      this.check(time, 'CONFLICT', details);
    }
  }
  report() {
    const lines = PROPERTIES.map(property => {
      const counts = this.counts.get(property);
      return `${property} ${counts.violations === 0 ? 'OK' : 'FAIL'} checks ${counts.checks} violations ${counts.violations}`;
    });
    const safe = Array.from(this.counts.values()).every(counts => counts.violations === 0);
    return lines.concat(this.violations, 'RESULT ' + (safe ? 'SAFE' : 'UNSAFE'));
  }
}

module.exports = { Safety };
