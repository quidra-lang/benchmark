class Junction {
  constructor(node, offset, phases) {
    this.node = node;
    this.offset = offset;
    this.phases = phases;
    this.cycle = 0;
    for (const phase of phases) this.cycle += phase.duration;
  }

  green(segment, step) {
    if (this.phases.length === 0) return true;
    let time = (step - 1 + this.offset) % this.cycle;
    for (const phase of this.phases) {
      if (time < phase.duration) return phase.greens.has(segment);
      time -= phase.duration;
    }
    return false;
  }

  lines() {
    if (this.phases.length === 0) return [`JUNCTION ${this.node} unsignalized`];
    const lines = [`JUNCTION ${this.node} signal cycle ${this.cycle} offset ${this.offset}`];
    let start = 0;
    this.phases.forEach((phase, index) => {
      lines.push(`  PHASE ${index + 1} ${start}-${start + phase.duration - 1} ${phase.token}`);
      start += phase.duration;
    });
    return lines;
  }
}

module.exports = { Junction };
