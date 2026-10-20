import { readFileSync } from 'node:fs';
import type { Packet } from './processes.ts';

export interface ChannelSpec { source: number; destination: number; type: string; low: number; high: number }
export function readTopology() {
    const rows = readFileSync('input/topology.txt', 'ascii').trimEnd().split('\n').map(line => line.split(' ')), names = rows[0].slice(1);
    const channels: ChannelSpec[] = rows.slice(1).map(w => ({ source: names.indexOf(w[1]), destination: names.indexOf(w[2]), type: w[3], low: Number(w[4]), high: Number(w[5] ?? w[4]) }));
    channels.sort((a, b) => a.source - b.source || a.destination - b.destination); return { names, channels };
}
export class Minstd {
    draws = 0;
    constructor(private state: number) {}
    next(): number { this.state = 48271 * this.state % 2147483647; this.draws++; return this.state; }
}
export class Channel implements ChannelSpec {
    source: number; destination: number; type: string; low: number; high: number;
    sequence = 0; lastArrival = 0; messages = 0; markers = 0; buffered = 0; maxDelay = 0; entries = 0; previousVector: number[];
    constructor(spec: ChannelSpec, size: number) { this.source = spec.source; this.destination = spec.destination; this.type = spec.type; this.low = spec.low; this.high = spec.high; this.previousVector = Array(size).fill(0); }
    dispatch(packet: Packet, time: number, generator: Minstd): void {
        packet.sequence = ++this.sequence; packet.dispatched = time;
        let delay = this.low; if (this.high !== this.low) delay += generator.next() % (this.high - this.low + 1);
        packet.arrival = time + delay; if (this.type === 'FIFO') packet.arrival = Math.max(packet.arrival, this.lastArrival);
        this.lastArrival = Math.max(this.lastArrival, packet.arrival); this.maxDelay = Math.max(this.maxDelay, packet.arrival - time);
        if (packet.kind === 'marker') this.markers++;
        else { this.messages++; const vector = packet.message.event!.V; for (let i = 0; i < vector.length; i++) if (vector[i] !== this.previousVector[i]) this.entries++; this.previousVector = vector.slice(); }
    }
}
