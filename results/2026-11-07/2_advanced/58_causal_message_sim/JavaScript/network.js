'use strict';

const fs = require('node:fs');

function readTopology() {
    const rows = fs.readFileSync('input/topology.txt', 'ascii').slice(0, -1)
        .split('\n').map(line => line.split(' '));
    const names = rows[0].slice(1);
    const channels = rows.slice(1).map(row => ({
        source: names.indexOf(row[1]), destination: names.indexOf(row[2]), type: row[3],
        low: Number(row[4]), high: row.length === 6 ? Number(row[5]) : Number(row[4]),
    }));
    channels.sort((a, b) => a.source - b.source || a.destination - b.destination);
    return { names, channels };
}

class Minstd {
    constructor(seed) {
        this.state = seed;
        this.draws = 0;
    }

    next() {
        this.state = (48271 * this.state) % 2147483647;
        this.draws++;
        return this.state;
    }
}

class Channel {
    constructor(specification, size) {
        Object.assign(this, specification);
        this.sequence = 0;
        this.lastArrival = 0;
        this.messages = 0;
        this.markers = 0;
        this.buffered = 0;
        this.maxDelay = 0;
        this.entries = 0;
        this.previousVector = Array(size).fill(0);
    }

    dispatch(packet, time, generator) {
        packet.sequence = ++this.sequence;
        packet.dispatched = time;
        let delay = this.low;
        if (this.high !== this.low) delay += generator.next() % (this.high - this.low + 1);
        packet.arrival = time + delay;
        if (this.type === 'FIFO') packet.arrival = Math.max(packet.arrival, this.lastArrival);
        this.lastArrival = Math.max(this.lastArrival, packet.arrival);
        this.maxDelay = Math.max(this.maxDelay, packet.arrival - time);
        if (packet.marker) this.markers++;
        else {
            this.messages++;
            const vector = packet.message.event.V;
            for (let i = 0; i < vector.length; i++) {
                if (vector[i] !== this.previousVector[i]) this.entries++;
            }
            this.previousVector = vector.slice();
        }
    }
}

module.exports = { readTopology, Minstd, Channel };
