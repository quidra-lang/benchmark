import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import type { HuffmanTable } from './entropy.ts';
export interface Image {
  width: number;
  height: number;
  pixels: number[];
}
export interface Plane {
  width: number;
  height: number;
  pixels: number[];
}
export interface Parameters {
  qualities: number[];
  sampling: number;
  restart: number;
  huffman: string;
  target: number;
  generations: number;
  truncate: number[];
}
export interface Tables {
  dct: number[][];
  quant: number[][];
  huffman: HuffmanTable[];
}
const lines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .trimEnd()
    .split('\n');
export function readImage(): Image {
  const rows = lines('image.ppm');
  const [width, height] = rows[1].split(' ').map(Number);
  return { width, height, pixels: rows.slice(3).flatMap((row) => row.split(' ').map(Number)) };
}
export function readParameters(): Parameters {
  const rows = lines('params.txt').map((row) => row.split(' ').slice(1));
  return {
    qualities: rows[0].map(Number),
    sampling: Number(rows[1][0]),
    restart: Number(rows[2][0]),
    huffman: rows[3][0],
    target: Number(rows[4][0]),
    generations: Number(rows[5][0]),
    truncate: rows[6].map(Number),
  };
}
export function readTables(): Tables {
  const rows = lines('tables.txt').map((row) => row.split(' '));
  const huffman: HuffmanTable[] = [];
  for (let i = 27; i < 39; i += 3) {
    huffman.push({
      class: Number(rows[i][1]),
      id: Number(rows[i][2]),
      counts: rows[i + 1].map(Number),
      values: rows[i + 2].map(Number),
    });
  }
  return {
    dct: rows.slice(1, 9).map((row) => row.map(Number)),
    quant: [
      rows.slice(10, 18).flatMap((row) => row.map(Number)),
      rows.slice(19, 27).flatMap((row) => row.map(Number)),
    ],
    huffman,
  };
}
export function readHex(): number[] {
  return (lines('stream.hex').join('').match(/../g) ?? []).map((pair) => parseInt(pair, 16));
}
export function writeLines(name: string, rows: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync('output/' + name, rows.join('\n') + '\n', 'ascii');
}
export function writeImage(name: string, image: Image): void {
  writeLines(name, [
    'P3',
    `${image.width} ${image.height}`,
    '255',
    ...Array.from({ length: image.height }, (_, y) =>
      image.pixels.slice(3 * y * image.width, 3 * (y + 1) * image.width).join(' '),
    ),
  ]);
}
export function writeHex(name: string, bytes: number[]): void {
  const rows: string[] = [];
  for (let i = 0; i < bytes.length; i += 32) {
    rows.push(
      bytes
        .slice(i, i + 32)
        .map((v) => v.toString(16).padStart(2, '0'))
        .join(''),
    );
  }
  writeLines(name, rows);
}
