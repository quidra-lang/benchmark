const OBSTACLE = Symbol('obstacle');

class Segment {
  constructor(id, from, to, length, lanes, limit) {
    this.id = id;
    this.from = from;
    this.to = to;
    this.length = length;
    this.lanes = lanes;
    this.limit = limit;
    this.cells = Array.from({ length: lanes }, () => Array(length).fill(null));
    this.junction = null;
    this.turns = [];
    this.stop = null;
    this.entered = 0;
    this.vehicleSum = 0;
    this.speedSum = 0;
    this.maximumVehicles = 0;
    this.changes = { overtaking: 0, return: 0, avoidance: 0 };
    this.greenCount = 0;
    this.passed = 0;
    this.blocked = 0;
    this.queueSum = 0;
    this.maximumQueue = 0;
    this.failures = 0;
  }

  get(lane, cell) {
    return this.cells[lane - 1][cell];
  }

  free(lane, cell, maximum) {
    const row = this.cells[lane - 1];
    let count = 0;
    while (count < maximum && cell + count + 1 < this.length && row[cell + count + 1] === null) count += 1;
    return count;
  }

  first(lane) {
    const row = this.cells[lane - 1];
    for (let cell = 0; cell < this.length; cell += 1) if (row[cell] !== null) return cell;
    return this.length;
  }

  safe(lane, cell) {
    const row = this.cells[lane - 1];
    for (let position = Math.max(0, cell - this.limit); position <= cell; position += 1) {
      if (row[position] !== null) return false;
    }
    return true;
  }

  diagram(lane) {
    return this.cells[lane - 1].map(cell => cell === null ? '.' : cell === OBSTACLE ? '#' : String(cell.speed)).join('');
  }
}

class Incident {
  constructor(segment, lane, cell, start, end) {
    this.segment = segment;
    this.lane = lane;
    this.cell = cell;
    this.start = start;
    this.end = end;
    this.state = 'planned';
    this.activeStart = null;
    this.activeEnd = null;
  }

  update(step) {
    const row = this.segment.cells[this.lane - 1];
    let event = null;
    if (this.state === 'active' && step > this.end) {
      this.state = 'cleared';
      row[this.cell] = null;
      event = 'INCIDENT_END';
    } else if (this.state === 'planned' && step > this.end) {
      this.state = 'cancelled';
    } else if (this.state === 'planned' && step >= this.start && row[this.cell] === null) {
      this.state = 'active';
      row[this.cell] = OBSTACLE;
      this.activeStart = step;
      event = 'INCIDENT_START';
    }
    if (this.state === 'active') this.activeEnd = step;
    return event;
  }
}

module.exports = { OBSTACLE, Segment, Incident };
