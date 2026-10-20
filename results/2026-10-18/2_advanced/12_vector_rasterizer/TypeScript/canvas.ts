export type Point = [number, number];
export type Rectangle = [number, number, number, number];
export type Color = [number, number, number, number];
export type RGB = [number, number, number];
export type Segment = [Point, Point];
export type FillRule = 'evenodd' | 'nonzero';
export type BlendMode = 'normal' | 'multiply' | 'screen';
export interface Command {
  kind: 'command';
  keyword: string;
  args: string[];
  line: number;
}
export interface Repeat {
  kind: 'repeat';
  count: number;
  dx: number;
  dy: number;
  body: Node[];
}
export type Node = Command | Repeat;
export interface Block {
  name: string;
  body: Node[];
  end: number;
}
export interface LayerBlock extends Block {
  opacity: number;
  mode: BlendMode;
}
export interface Pixel {
  color: Color;
  line: number;
}

export const floorDiv = (n: number, d: number): number => Math.floor(n / d);
export function round(n: number, d: number): number {
  if (d < 0) {
    n = -n;
    d = -d;
  }
  return floorDiv(2 * n + d, 2 * d);
}

export class Layer {
  readonly pixels: (Pixel | null)[];
  commands = 0;
  errors = 0;
  constructor(
    readonly block: LayerBlock,
    width: number,
    height: number,
    readonly number: number,
  ) {
    this.pixels = Array<Pixel | null>(width * height).fill(null);
  }
  paint(index: number, color: Color, line: number): void {
    this.pixels[index] = { color, line };
  }
  erase(index: number): void {
    this.pixels[index] = null;
  }
  alpha(index: number): number {
    const pixel = this.pixels[index];
    return pixel === null ? 0 : round(pixel.color[3] * this.block.opacity, 255);
  }
}

export function composite(layers: Layer[], background: Color, size: number): RGB[] {
  const image = Array.from({ length: size }, (): RGB => [
    background[0],
    background[1],
    background[2],
  ]);
  for (const layer of layers) {
    for (let i = 0; i < size; i++) {
      const pixel = layer.pixels[i];
      if (pixel === null) continue;
      const alpha = layer.alpha(i);
      for (let c = 0; c < 3; c++) {
        const value = image[i][c];
        let source = pixel.color[c];
        if (layer.block.mode === 'multiply') source = round(source * value, 255);
        else if (layer.block.mode === 'screen') {
          source = 255 - round((255 - source) * (255 - value), 255);
        }
        image[i][c] = round(alpha * source + (255 - alpha) * value, 255);
      }
    }
  }
  return image;
}
