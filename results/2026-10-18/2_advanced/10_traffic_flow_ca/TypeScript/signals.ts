export interface Phase {
  duration: number;
  token: string;
  greens: Set<string>;
}

export class Junction {
  readonly cycle: number;

  constructor(
    readonly node: string,
    readonly offset: number,
    readonly phases: Phase[],
  ) {
    this.cycle = phases.reduce((sum, phase) => sum + phase.duration, 0);
  }

  green(segment: string, step: number): boolean {
    if (this.phases.length === 0) return true;
    let time = (step - 1 + this.offset) % this.cycle;
    for (const phase of this.phases) {
      if (time < phase.duration) return phase.greens.has(segment);
      time -= phase.duration;
    }
    return false;
  }

  lines(): string[] {
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
