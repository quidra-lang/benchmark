import { readFileSync } from 'node:fs';

export interface Image {
  name: string;
  width: number;
  height: number;
  maxval: number;
  pixels: number[];
}

export function readImages(): Image[] {
  const words = readFileSync('input/images.txt', 'ascii')
    .replace(/#[^\n]*/g, '')
    .trim()
    .split(/\s+/);
  const images: Image[] = [];
  let position = 0;
  while (position < words.length) {
    position++;
    const name = words[position++];
    position++;
    const width = Number(words[position++]);
    const height = Number(words[position++]);
    const maxval = Number(words[position++]);
    const pixels = words.slice(position, position + width * height).map(Number);
    position += pixels.length;
    images.push({ name, width, height, maxval, pixels });
  }
  return images;
}
