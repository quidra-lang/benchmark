import { mkdirSync, writeFileSync } from 'node:fs';
import { floorDiv, type RGB } from './canvas.ts';

export function writeImages(image: RGB[], width: number, height: number): void {
  mkdirSync('output', { recursive: true });
  const ppm = ['P3', `${width} ${height}`, '255'];
  for (let y = 0; y < height; y++) {
    ppm.push(
      image
        .slice(y * width, (y + 1) * width)
        .flat()
        .join(' '),
    );
  }
  writeFileSync('output/image.ppm', ppm.join('\n') + '\n', 'ascii');
  const preview: string[] = [];
  const shades = '@%#*+=-:,.';
  for (let y = 0; y < height; y += 4) {
    let line = '';
    for (let x = 0; x < width; x += 2) {
      let total = 0;
      for (let j = 0; j < 4; j++) {
        for (let i = 0; i < 2; i++) {
          const [r, g, b] = image[(y + j) * width + x + i];
          total += 299 * r + 587 * g + 114 * b;
        }
      }
      line += shades[floorDiv(floorDiv(total, 8000) * 10, 256)];
    }
    preview.push(line);
  }
  writeFileSync('output/preview.txt', preview.join('\n') + '\n', 'ascii');
}
