export type Probability = readonly [number, number];

export class Minstd {
    constructor(private state: number) {}
    draw(): number {
        // The product is below 2^47, hence exactly representable as a Number.
        this.state = 48271 * this.state % 2147483647;
        return this.state;
    }
    below(limit: number): number { return this.draw() % limit; }
    chance([numerator, denominator]: Probability): boolean { return this.below(denominator) < numerator; }
    shuffle<T>(sequence: T[]): T[] {
        for (let i = sequence.length - 1; i >= 1; i--) {
            const j = this.below(i + 1);
            [sequence[i], sequence[j]] = [sequence[j], sequence[i]];
        }
        return sequence;
    }
}
