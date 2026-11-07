class VehicleClass {
  constructor(name, maximum, weight, overtake, stops) {
    this.name = name;
    this.maximum = maximum;
    this.weight = weight;
    this.overtake = overtake;
    this.stops = stops;
  }
}

class Vehicle {
  constructor(number, type, source, arrival) {
    this.number = number;
    this.type = type;
    this.source = source;
    this.arrival = arrival;
    this.insertion = null;
    this.exit = null;
    this.sink = null;
    this.segment = null;
    this.lane = null;
    this.cell = null;
    this.speed = 0;
    this.turn = null;
    this.route = [];
    this.steps = 0;
    this.distance = 0;
    this.stoppedSteps = 0;
    this.stopCount = 0;
    this.laneChanges = 0;
    this.dwell = 0;
    this.completedStops = new Set();
    this.trajectory = null;
  }

  maximumSpeed() {
    return Math.min(this.type.maximum, this.segment.limit);
  }

  headingForStop() {
    return this.segment !== null && this.type.stops && this.segment.stop !== null
      && !this.completedStops.has(this.segment.id) && this.cell <= this.segment.stop.cell;
  }

  place(segment, lane, cell) {
    if (this.segment !== null) this.segment.cells[this.lane - 1][this.cell] = null;
    this.segment = segment;
    this.lane = lane;
    this.cell = cell;
    segment.cells[lane - 1][cell] = this;
  }

  remove() {
    this.segment.cells[this.lane - 1][this.cell] = null;
    this.segment = null;
    this.lane = null;
    this.cell = null;
  }
}

function randomSlowdown(proposed, previous, p, p0, generator) {
  const random = generator.draw();
  const probability = previous === 0 ? p0 : p;
  return proposed > 0 && random % 1000 < probability ? proposed - 1 : proposed;
}

module.exports = { VehicleClass, Vehicle, randomSlowdown };
