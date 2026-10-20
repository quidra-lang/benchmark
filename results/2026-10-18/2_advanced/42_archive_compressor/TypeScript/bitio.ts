export type ErrorKind = 'end_of_data' | 'bad_code' | 'bad_offset' | 'bad_table' | 'overrun' | 'early_end';
export class DecodingError extends Error { constructor(public kind: ErrorKind) { super(kind); } }
export function bits(value: number) { let width = 0; while (value > 0) { width++; value = Math.floor(value / 2); } return width; }
export class BitWriter {
    bytes: number[] = [];
    current = 0;
    used = 0;
    length = 0;
    write(value: number, width: number) {
        for (let shift = width - 1; shift >= 0; shift--) { this.current = this.current * 2 + Math.floor(value / 2 ** shift) % 2; this.used++; this.length++; if (this.used === 8) { this.bytes.push(this.current); this.current = 0; this.used = 0; } }
    }
    finish() { if (this.used) { this.bytes.push(this.current * 2 ** (8 - this.used)); this.current = 0; this.used = 0; } return Buffer.from(this.bytes); }
}
export class BitReader {
    position = 0;
    constructor(public data: Uint8Array, public zeroFill = false) {}
    read(width: number) {
        if (!this.zeroFill && this.position + width > this.data.length * 8) throw new DecodingError('end_of_data');
        let value = 0;
        for (let i = 0; i < width; i++) { const byte = this.position < this.data.length * 8 ? this.data[Math.floor(this.position / 8)] : 0; value = value * 2 + Math.floor(byte / 2 ** (7 - this.position % 8)) % 2; this.position++; }
        return value;
    }
}
