export type ErrorKind = 'marker' | 'code' | 'index' | 'sync';
export class ScanError extends Error {
  constructor(public kind: ErrorKind) {
    super(kind);
  }
}
export class BitWriter {
  bytes: number[] = [];
  paddingBits = 0;
  stuffedBytes = 0;
  private buffer = 0;
  private used = 0;
  write(value: number, length: number): void {
    for (let i = length - 1; i >= 0; i--) {
      this.buffer = 2 * this.buffer + (Math.floor(value / 2 ** i) % 2);
      this.used++;
      if (this.used === 8) {
        this.bytes.push(this.buffer);
        if (this.buffer === 255) {
          this.bytes.push(0);
          this.stuffedBytes++;
        }
        this.buffer = 0;
        this.used = 0;
      }
    }
  }
  pad(): void {
    while (this.used > 0) {
      this.write(1, 1);
      this.paddingBits++;
    }
  }
  marker(value: number): void {
    this.pad();
    this.bytes.push(255, value);
  }
}
export class BitReader {
  private buffer = 0;
  private remaining = 0;
  constructor(
    private bytes: number[],
    public position: number,
  ) {}
  read(length: number): number {
    let value = 0;
    for (let i = 0; i < length; i++) {
      if (this.remaining === 0) {
        const byte = this.bytes[this.position];
        if (byte === 255) {
          if (this.bytes[this.position + 1] !== 0) throw new ScanError('marker');
          this.position += 2;
        } else this.position++;
        this.buffer = byte;
        this.remaining = 8;
      }
      this.remaining--;
      value = 2 * value + (Math.floor(this.buffer / 2 ** this.remaining) % 2);
    }
    return value;
  }
  clear(): void {
    this.buffer = 0;
    this.remaining = 0;
  }
}
export function resync(bytes: number[], position: number): number {
  for (let q = position; q + 1 < bytes.length; q++) {
    if (
      bytes[q] === 255 &&
      ((bytes[q + 1] >= 208 && bytes[q + 1] <= 215) || bytes[q + 1] === 217)
    ) {
      return q;
    }
  }
  return bytes.length - 2;
}
