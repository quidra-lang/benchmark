import { readFileSync } from "node:fs";

const INTEGER_WORD = /^(?:0|-?[1-9][0-9]{0,6})$/;
const NAME_WORD = /^[a-z]{1,8}$/;
const DIGITS = /^[0-9]+$/;
const SHADES = "@#*+=~-:,.";
const NEIGHBORS4: Point[] = [[0, -1], [-1, 0], [1, 0], [0, 1]];
const NEIGHBORS8: Point[] = [
  [-1, -1], [0, -1], [1, -1], [-1, 0],
  [1, 0], [-1, 1], [0, 1], [1, 1]
];
const KERNELS: Record<string, [number[], number]> = {
  BLUR: [[1, 1, 1, 1, 1, 1, 1, 1, 1], 9],
  GAUSS: [[1, 2, 1, 2, 4, 2, 1, 2, 1], 16],
  SHARPEN: [[0, -1, 0, -1, 5, -1, 0, -1, 0], 1]
};
const PATTERNS: Record<string, string> = {
  NEW: "iiii", OUTPUT: "", INVERT: "", BRIGHTNESS: "i",
  CONTRAST: "ii", THRESHOLD: "i", LEVELS: "ii", POSTERIZE: "i",
  MAXVAL: "i", FLIPH: "", FLIPV: "", ROTATE: "i",
  CROP: "iiii", PAD: "ii", SCALE: "ii", SHIFT: "iii",
  TILE: "ii", BLUR: "", GAUSS: "", SHARPEN: "", CONVOLVE: "iiiiiiiiii",
  SOBEL: "", MEDIAN: "", ERODE: "", DILATE: "",
  OPEN: "", CLOSE: "", GRADIENT: "", LINE: "iiiii",
  RECT: "iiiii", CIRCLE: "iiii", FLOOD: "iii",
  HISTOGRAM: "", EQUALIZE: "", LABEL: "i", DISTANCE: "i",
  STATS: "", REGION: "iiii", DITHER: "", ASCIIART: "",
  STORE: "n", RECALL: "n", DROP: "n", BLEND: "nii",
  DIFF: "n", PASTE: "nii", SLOTS: "", INFO: "", UNDO: "", REDO: ""
};
const IMAGELESS = new Set(["NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO"]);
const NEED_SLOT = new Set(["RECALL", "DROP", "BLEND", "DIFF", "PASTE"]);

type Point = [number, number];
type Rectangle = [number, number, number, number];
type ParsedCommand = { name: string; numbers: number[]; slot: string; fill: boolean };

class CommandError extends Error {}

function requireValue(condition: boolean, reason = "bad value"): asserts condition {
  if (!condition) throw new CommandError(reason);
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

function withinLimit(...numbers: number[]): boolean {
  return numbers.every(n => -1000 <= n && n <= 1000);
}

function sum(numbers: number[]): number {
  return numbers.reduce((result, n) => result + n, 0);
}

class Image {
  constructor(
    readonly width: number,
    readonly height: number,
    readonly maxval: number,
    readonly pixels: number[]
  ) {}

  get(x: number, y: number): number {
    return this.pixels[y * this.width + x];
  }

  contains(x: number, y: number): boolean {
    return x >= 0 && y >= 0 && x < this.width && y < this.height;
  }

  row(y: number): number[] {
    return this.pixels.slice(y * this.width, (y + 1) * this.width);
  }

  withPixels(pixels: number[]): Image {
    return new Image(this.width, this.height, this.maxval, pixels);
  }

  clamp(value: number): number {
    return clamp(value, 0, this.maxval);
  }

  neighborhood(x: number, y: number): number[] {
    const values = [];
    for (let dy = -1; dy <= 1; ++dy) {
      for (let dx = -1; dx <= 1; ++dx) {
        values.push(this.get(
          clamp(x + dx, 0, this.width - 1),
          clamp(y + dy, 0, this.height - 1)
        ));
      }
    }
    return values;
  }

  summary(): string {
    const checksum = this.pixels.reduce((total, value, index) => total + (index + 1) * value, 0);
    return this.width + "x" + this.height + " maxval " + this.maxval + " checksum " + checksum;
  }
}

function readPGM(lines: string[]): Image {
  const words = lines.flatMap(line => line.split("#", 1)[0].trim().split(/\s+/).filter(Boolean));
  requireValue(words.length > 0 && words[0] === "P2", "bad magic");
  const header = (position: number, limit: number, reason: string): number => {
    requireValue(position < words.length, "truncated header");
    requireValue(DIGITS.test(words[position]), "bad number");
    const value = Number(words[position]);
    requireValue(value >= 1 && value <= limit, reason);
    return value;
  };
  const width = header(1, 64, "bad size");
  const height = header(2, 64, "bad size");
  const maxval = header(3, 255, "bad maxval");
  const values = words.slice(4);
  const pixels = [];
  const needed = width * height;
  for (let i = 0; i < needed; ++i) {
    const x = i % width;
    const y = Math.floor(i / width);
    requireValue(i < values.length,
      "too few pixels (" + values.length + " of " + needed + ")");
    requireValue(DIGITS.test(values[i]), "bad pixel at " + x + "," + y);
    const pixel = Number(values[i]);
    requireValue(pixel <= maxval, "pixel out of range at " + x + "," + y);
    pixels.push(pixel);
  }
  requireValue(values.length <= needed,
    "too many pixels (" + values.length + " of " + needed + ")");
  return new Image(width, height, maxval, pixels);
}

function transformed(image: Image, width: number, height: number, pixelAt: (x: number, y: number) => number): Image {
  const pixels = [];
  for (let y = 0; y < height; ++y) {
    for (let x = 0; x < width; ++x) pixels.push(pixelAt(x, y));
  }
  return new Image(width, height, image.maxval, pixels);
}

function rotated(image: Image, angle: number): Image {
  const w = image.width, h = image.height;
  if (angle === 180) {
    return transformed(image, w, h, (x, y) => image.get(w - 1 - x, h - 1 - y));
  }
  if (angle === 90) {
    return transformed(image, h, w, (x, y) => image.get(y, h - 1 - x));
  }
  return transformed(image, h, w, (x, y) => image.get(w - 1 - y, x));
}

function cropped(image: Image, left: number, top: number, width: number, height: number): Image {
  return transformed(image, width, height, (x, y) => image.get(left + x, top + y));
}

function translated(image: Image, width: number, height: number, dx: number, dy: number, fill: number): Image {
  return transformed(image, width, height, (x, y) => image.contains(x - dx, y - dy)
    ? image.get(x - dx, y - dy) : fill);
}

function scaled(image: Image, width: number, height: number, numerator: number, denominator: number): Image {
  return transformed(image, width, height, (x, y) =>
    image.get(
      Math.floor((2 * x + 1) * denominator / (2 * numerator)),
      Math.floor((2 * y + 1) * denominator / (2 * numerator))
    ));
}

function convolution(image: Image, kernel: number[], divisor: number): Image {
  return transformed(image, image.width, image.height, (x, y) => {
    const q = image.neighborhood(x, y);
    return image.clamp(Math.floor(sum(kernel.map((v, i) => v * q[i])) / divisor));
  });
}

function rankFiltered(image: Image, rank: number): Image {
  return transformed(image, image.width, image.height, (x, y) =>
    image.neighborhood(x, y).sort((a, b) => a - b)[rank]);
}

function sobel(image: Image): Image {
  return transformed(image, image.width, image.height, (x, y) => {
    const q = image.neighborhood(x, y);
    const gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
    const gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
    return image.clamp(Math.abs(gx) + Math.abs(gy));
  });
}

function linePoints(x0: number, y0: number, x1: number, y1: number): Point[] {
  const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  let error = dx + dy, x = x0, y = y0;
  const points: Point[] = [];
  while (true) {
    points.push([x, y]);
    if (x === x1 && y === y1) return points;
    const twice = 2 * error;
    if (twice >= dy) { error += dy; x += sx; }
    if (twice <= dx) { error += dx; y += sy; }
  }
}

function rectanglePoints(image: Image, left: number, top: number, width: number, height: number, fill: boolean): Point[] {
  const right = left + width - 1, bottom = top + height - 1;
  const points: Point[] = [];
  for (let y = Math.max(0, top); y <= Math.min(bottom, image.height - 1); ++y) {
    for (let x = Math.max(0, left); x <= Math.min(right, image.width - 1); ++x) {
      if (fill || x === left || x === right || y === top || y === bottom) points.push([x, y]);
    }
  }
  return points;
}

function circlePoints(cx: number, cy: number, radius: number): Point[] {
  let a = radius, b = 0, error = 1 - radius;
  const points: Point[] = [];
  while (a >= b) {
    points.push(
      [cx + a, cy + b], [cx + b, cy + a], [cx - b, cy + a], [cx - a, cy + b],
      [cx - a, cy - b], [cx - b, cy - a], [cx + b, cy - a], [cx + a, cy - b]
    );
    ++b;
    if (error < 0) error += 2 * b + 1;
    else { --a; error += 2 * (b - a) + 1; }
  }
  return points;
}

function discPoints(image: Image, outline: Point[]): Point[] {
  const rows = new Map<number, Point>();
  for (const [x, y] of outline) {
    if (rows.has(y)) {
      const [left, right] = rows.get(y)!;
      rows.set(y, [Math.min(left, x), Math.max(right, x)]);
    } else rows.set(y, [x, x]);
  }
  const result: Point[] = [];
  for (const [y, [left, right]] of rows) {
    if (y < 0 || y >= image.height) continue;
    for (let x = Math.max(0, left); x <= Math.min(image.width - 1, right); ++x) {
      result.push([x, y]);
    }
  }
  return result;
}

function floodPoints(image: Image, x: number, y: number): Point[] {
  const target = image.get(x, y);
  const stack: Point[] = [[x, y]];
  const seen = new Set<number>([y * image.width + x]);
  const result: Point[] = [];
  while (stack.length > 0) {
    const [cx, cy] = stack.pop()!;
    result.push([cx, cy]);
    for (const [dx, dy] of NEIGHBORS4) {
      const nx = cx + dx, ny = cy + dy;
      if (!image.contains(nx, ny) || image.get(nx, ny) !== target) continue;
      const index = ny * image.width + nx;
      if (!seen.has(index)) {
        seen.add(index);
        stack.push([nx, ny]);
      }
    }
  }
  return result;
}

function equalized(image: Image): Image {
  const n = image.pixels.length;
  const counts = Array(image.maxval + 1).fill(0);
  for (const value of image.pixels) ++counts[value];
  const cdf = [];
  let accumulated = 0;
  for (const count of counts) {
    accumulated += count;
    cdf.push(accumulated);
  }
  const minimumCDF = cdf[Math.min(...image.pixels)];
  if (minimumCDF === n) return image.withPixels([...image.pixels]);
  const span = n - minimumCDF;
  return image.withPixels(image.pixels.map(pixel =>
    Math.floor((2 * (cdf[pixel] - minimumCDF) * image.maxval + span) / (2 * span))));
}

function components(image: Image, threshold: number): Point[][] {
  const visited = new Set<number>(), groups: Point[][] = [];
  for (let start = 0; start < image.pixels.length; ++start) {
    if (visited.has(start) || image.pixels[start] < threshold) continue;
    visited.add(start);
    const stack: Point[] = [[start % image.width, Math.floor(start / image.width)]];
    const group: Point[] = [];
    while (stack.length > 0) {
      const [x, y] = stack.pop()!;
      group.push([x, y]);
      for (const [dx, dy] of NEIGHBORS8) {
        const nx = x + dx, ny = y + dy;
        if (!image.contains(nx, ny)) continue;
        const index = ny * image.width + nx;
        if (image.pixels[index] >= threshold && !visited.has(index)) {
          visited.add(index);
          stack.push([nx, ny]);
        }
      }
    }
    groups.push(group);
  }
  return groups;
}

function componentText(image: Image, threshold: number, group: Point[]): string {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  let sumX = 0, sumY = 0, perimeter = 0;
  for (const [x, y] of group) {
    minX = Math.min(minX, x); minY = Math.min(minY, y);
    maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
    sumX += x; sumY += y;
    if (NEIGHBORS4.some(([dx, dy]) => !image.contains(x + dx, y + dy) ||
        image.get(x + dx, y + dy) < threshold)) ++perimeter;
  }
  const area = group.length;
  return "area " + area + " perimeter " + perimeter + " box " +
    [minX, minY, maxX, maxY].join(" ") + " center " +
    Math.floor(sumX / area) + " " + Math.floor(sumY / area);
}

function distanceMap(image: Image, threshold: number): Image {
  const w = image.width, h = image.height;
  const far = w + h;
  const distances = image.pixels.map(pixel => pixel < threshold ? 0 : far);
  for (let y = 0; y < h; ++y) {
    for (let x = 0; x < w; ++x) {
      const index = y * w + x;
      if (x > 0) distances[index] = Math.min(distances[index], distances[index - 1] + 1);
      if (y > 0) distances[index] = Math.min(distances[index], distances[index - w] + 1);
    }
  }
  for (let y = h - 1; y >= 0; --y) {
    for (let x = w - 1; x >= 0; --x) {
      const index = y * w + x;
      if (x < w - 1) distances[index] = Math.min(distances[index], distances[index + 1] + 1);
      if (y < h - 1) distances[index] = Math.min(distances[index], distances[index + w] + 1);
    }
  }
  return image.withPixels(distances.map(value => Math.min(value, image.maxval)));
}

function statistics(values: number[], maxval: number): string {
  const sorted = [...values].sort((a, b) => a - b);
  const counts = Array(maxval + 1).fill(0);
  for (const value of values) ++counts[value];
  let mode = 0;
  for (let value = 1; value <= maxval; ++value) {
    if (counts[value] > counts[mode]) mode = value;
  }
  const n = sorted.length;
  return "min " + sorted[0] + " max " + sorted[n - 1] +
    " mean " + Math.floor(sum(values) / n) +
    " median " + sorted[Math.floor((n - 1) / 2)] + " mode " + mode;
}

function dithered(image: Image): Image {
  const errors = [...image.pixels];
  const pixels = Array(errors.length).fill(0);
  const diffusion = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]];
  for (let y = 0; y < image.height; ++y) {
    for (let x = 0; x < image.width; ++x) {
      const index = y * image.width + x;
      const old = errors[index];
      const next = 2 * old >= image.maxval ? image.maxval : 0;
      pixels[index] = next;
      const error = old - next;
      for (const [dx, dy, weight] of diffusion) {
        if (image.contains(x + dx, y + dy)) {
          errors[(y + dy) * image.width + x + dx] += Math.floor(error * weight / 16);
        }
      }
    }
  }
  return image.withPixels(pixels);
}

class ImageEditor {
  current: Image | null = null;
  undoHistory: Image[] = [];
  redoHistory: Image[] = [];
  slots = new Map<string, Image>();
  output: string[] = [];

  emit(text: string): void {
    this.output.push(text);
  }

  parse(words: string[]): ParsedCommand {
    const name = words[0], given = words.slice(1);
    requireValue(Object.hasOwn(PATTERNS, name), "unknown command " + name);
    const pattern = PATTERNS[name];
    const fill = (name === "RECT" || name === "CIRCLE") &&
      given.length === pattern.length + 1 && given.at(-1) === "FILL";
    const args = fill ? given.slice(0, -1) : given;
    requireValue(args.length === pattern.length, "bad arguments");
    const numbers: number[] = [];
    let slot = "";
    for (let i = 0; i < args.length; ++i) {
      if (pattern[i] === "i") {
        requireValue(INTEGER_WORD.test(args[i]), "bad arguments");
        numbers.push(Number(args[i]));
      } else {
        requireValue(NAME_WORD.test(args[i]), "bad arguments");
        slot = args[i];
      }
    }
    return { name, numbers, slot, fill };
  }

  execute(words: string[]): void {
    try {
      const command = this.parse(words);
      if (!IMAGELESS.has(command.name)) requireValue(this.current !== null, "no image");
      if (NEED_SLOT.has(command.name)) {
        requireValue(this.slots.has(command.slot), "no slot " + command.slot);
      }
      this.run(command);
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("error: " + error.message);
    }
  }

  load(lines: string[]): void {
    try {
      this.replace(readPGM(lines), "loaded");
    } catch (error) {
      if (!(error instanceof CommandError)) throw error;
      this.emit("error: load: " + error.message);
    }
  }

  replace(image: Image, label: string): void {
    this.current = image;
    this.undoHistory = [];
    this.redoHistory = [];
    this.emit(label + " " + image.summary());
  }

  commit(image: Image, painted: number | null = null): void {
    this.undoHistory.push(this.current!);
    this.redoHistory = [];
    this.current = image;
    this.emit("ok " + image.summary() + (painted === null ? "" : " painted " + painted));
  }

  paint(points: Point[], value: number): void {
    const image = this.current!;
    const marked = new Set<number>();
    for (const [x, y] of points) {
      if (image.contains(x, y)) marked.add(y * image.width + x);
    }
    this.commit(image.withPixels(image.pixels.map((p, i) => marked.has(i) ? value : p)), marked.size);
  }

  cropArea([x, y, w, h]: number[]): Rectangle {
    const image = this.current!;
    requireValue(x >= 0 && y >= 0 && w >= 1 && h >= 1);
    requireValue(x + w <= image.width && y + h <= image.height);
    return [x, y, w, h];
  }

  matchingSlot(name: string): Image {
    const other = this.slots.get(name)!, image = this.current!;
    requireValue(other.width === image.width && other.height === image.height, "size mismatch");
    requireValue(other.maxval === image.maxval, "maxval mismatch");
    return other;
  }

  run({ name, numbers: a, slot, fill }: ParsedCommand): void {
    const image = this.current!;
    const m = image?.maxval ?? 0;
    switch (name) {
      case "NEW": {
        const [w, h, maxval, value] = a;
        requireValue(w >= 1 && w <= 64 && h >= 1 && h <= 64);
        requireValue(maxval >= 1 && maxval <= 255 && value >= 0 && value <= maxval);
        this.replace(new Image(w, h, maxval, Array(w * h).fill(value)), "created");
        break;
      }
      case "OUTPUT":
        this.emit("P2");
        this.emit(image.width + " " + image.height);
        this.emit(String(m));
        for (let y = 0; y < image.height; ++y) this.emit(image.row(y).join(" "));
        break;
      case "INVERT":
        this.commit(image.withPixels(image.pixels.map(p => m - p)));
        break;
      case "BRIGHTNESS":
        requireValue(a[0] >= -255 && a[0] <= 255);
        this.commit(image.withPixels(image.pixels.map(p => image.clamp(p + a[0]))));
        break;
      case "CONTRAST": {
        const [num, den] = a;
        requireValue(num >= 0 && num <= 100 && den >= 1 && den <= 100);
        const center = Math.floor((m + 1) / 2);
        this.commit(image.withPixels(image.pixels.map(p =>
          image.clamp(center + Math.floor((p - center) * num / den)))));
        break;
      }
      case "THRESHOLD":
        requireValue(a[0] >= 0 && a[0] <= m);
        this.commit(image.withPixels(image.pixels.map(p => p >= a[0] ? m : 0)));
        break;
      case "LEVELS": {
        const [low, high] = a;
        requireValue(low >= 0 && low < high && high <= m);
        this.commit(image.withPixels(image.pixels.map(p =>
          image.clamp(Math.floor((p - low) * m / (high - low))))));
        break;
      }
      case "POSTERIZE": {
        const count = a[0];
        requireValue(count >= 2 && count <= m + 1);
        this.commit(image.withPixels(image.pixels.map(p =>
          Math.floor(Math.floor(p * count / (m + 1)) * m / (count - 1)))));
        break;
      }
      case "MAXVAL": {
        const maxval = a[0];
        requireValue(maxval >= 1 && maxval <= 255);
        const pixels = image.pixels.map(p => Math.floor((2 * p * maxval + m) / (2 * m)));
        this.commit(new Image(image.width, image.height, maxval, pixels));
        break;
      }
      case "FLIPH":
        this.commit(transformed(image, image.width, image.height, (x, y) =>
          image.get(image.width - 1 - x, y)));
        break;
      case "FLIPV":
        this.commit(transformed(image, image.width, image.height, (x, y) =>
          image.get(x, image.height - 1 - y)));
        break;
      case "ROTATE":
        requireValue([90, 180, 270].includes(a[0]));
        this.commit(rotated(image, a[0]));
        break;
      case "CROP":
        this.commit(cropped(image, ...this.cropArea(a)));
        break;
      case "PAD": {
        const [n, value] = a;
        requireValue(n >= 1 && value >= 0 && value <= m);
        const w = image.width + 2 * n, h = image.height + 2 * n;
        requireValue(w <= 64 && h <= 64, "too large");
        this.commit(translated(image, w, h, n, n, value));
        break;
      }
      case "SCALE": {
        const [num, den] = a;
        requireValue(num >= 1 && num <= 16 && den >= 1 && den <= 16);
        const w = Math.floor(image.width * num / den);
        const h = Math.floor(image.height * num / den);
        requireValue(w > 0 && h > 0, "too small");
        requireValue(w <= 64 && h <= 64, "too large");
        this.commit(scaled(image, w, h, num, den));
        break;
      }
      case "SHIFT":
        requireValue(withinLimit(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
        this.commit(translated(image, image.width, image.height, ...a));
        break;
      case "TILE": {
        const [nx, ny] = a;
        requireValue(nx >= 1 && ny >= 1);
        const w = image.width * nx, h = image.height * ny;
        requireValue(w <= 64 && h <= 64, "too large");
        this.commit(transformed(image, w, h, (x, y) =>
          image.get(x % image.width, y % image.height)));
        break;
      }
      case "BLUR":
      case "GAUSS":
      case "SHARPEN":
        this.commit(convolution(image, ...KERNELS[name]));
        break;
      case "CONVOLVE":
        requireValue(a.slice(0, 9).every(k => k >= -16 && k <= 16) &&
          a[9] >= 1 && a[9] <= 256);
        this.commit(convolution(image, a.slice(0, 9), a[9]));
        break;
      case "SOBEL":
        this.commit(sobel(image));
        break;
      case "MEDIAN":
      case "ERODE":
      case "DILATE":
        this.commit(rankFiltered(image, { MEDIAN: 4, ERODE: 0, DILATE: 8 }[name]));
        break;
      case "OPEN":
        this.commit(rankFiltered(rankFiltered(image, 0), 8));
        break;
      case "CLOSE":
        this.commit(rankFiltered(rankFiltered(image, 8), 0));
        break;
      case "GRADIENT": {
        const high = rankFiltered(image, 8).pixels;
        const low = rankFiltered(image, 0).pixels;
        this.commit(image.withPixels(high.map((p, i) => p - low[i])));
        break;
      }
      case "LINE":
        requireValue(withinLimit(...a.slice(0, 4)) && a[4] >= 0 && a[4] <= m);
        this.paint(linePoints(...a.slice(0, 4)), a[4]);
        break;
      case "RECT":
        requireValue(withinLimit(a[0], a[1]) && a[2] >= 1 && a[2] <= 1000 &&
          a[3] >= 1 && a[3] <= 1000 && a[4] >= 0 && a[4] <= m);
        this.paint(rectanglePoints(image, ...a.slice(0, 4), fill), a[4]);
        break;
      case "CIRCLE": {
        const [cx, cy, radius, value] = a;
        requireValue(withinLimit(cx, cy) && radius >= 0 && radius <= 1000 &&
          value >= 0 && value <= m);
        const outline = circlePoints(cx, cy, radius);
        this.paint(fill ? discPoints(image, outline) : outline, value);
        break;
      }
      case "FLOOD": {
        const [x, y, value] = a;
        requireValue(image.contains(x, y) && value >= 0 && value <= m);
        this.paint(floodPoints(image, x, y), value);
        break;
      }
      case "HISTOGRAM": {
        const lows = Array(16).fill(null), highs = Array(16).fill(0);
        const counts = Array(16).fill(0);
        for (let v = 0; v <= m; ++v) {
          const bin = Math.floor(v * 16 / (m + 1));
          if (lows[bin] === null) lows[bin] = v;
          highs[bin] = v;
        }
        for (const p of image.pixels) ++counts[Math.floor(p * 16 / (m + 1))];
        const top = Math.max(...counts);
        for (let bin = 0; bin < 16; ++bin) {
          if (lows[bin] === null) continue;
          this.emit(String(lows[bin]).padStart(3) + "-" +
            String(highs[bin]).padStart(3) + " " +
            String(counts[bin]).padStart(4) + " |" +
            "#".repeat(Math.floor(counts[bin] * 32 / top)));
        }
        break;
      }
      case "EQUALIZE":
        this.commit(equalized(image));
        break;
      case "LABEL": {
        requireValue(a[0] >= 0 && a[0] <= m);
        const groups = components(image, a[0]);
        this.emit("labels " + groups.length);
        groups.forEach((group, index) =>
          this.emit("label " + (index + 1) + " " + componentText(image, a[0], group)));
        break;
      }
      case "DISTANCE":
        requireValue(a[0] >= 0 && a[0] <= m);
        this.commit(distanceMap(image, a[0]));
        break;
      case "STATS":
        this.emit(statistics(image.pixels, m));
        break;
      case "REGION":
        this.emit(statistics(cropped(image, ...this.cropArea(a)).pixels, m));
        break;
      case "DITHER":
        this.commit(dithered(image));
        break;
      case "ASCIIART":
        for (let y = 0; y < image.height; ++y) {
          this.emit(image.row(y).map(p =>
            SHADES[Math.floor(p * SHADES.length / (m + 1))]).join(""));
        }
        break;
      case "STORE":
        this.slots.set(slot, image);
        this.emit("stored " + slot + " " + image.summary());
        break;
      case "RECALL":
        this.replace(this.slots.get(slot)!, "recalled " + slot);
        break;
      case "DROP":
        this.slots.delete(slot);
        this.emit("dropped " + slot);
        break;
      case "BLEND": {
        const [num, den] = a;
        requireValue(num >= 0 && num <= den && den >= 1 && den <= 100);
        const other = this.matchingSlot(slot);
        this.commit(image.withPixels(image.pixels.map((p, i) =>
          Math.floor((p * (den - num) + other.pixels[i] * num) / den))));
        break;
      }
      case "DIFF": {
        const other = this.matchingSlot(slot);
        this.commit(image.withPixels(image.pixels.map((p, i) =>
          Math.abs(p - other.pixels[i]))));
        break;
      }
      case "PASTE": {
        const [x, y] = a;
        requireValue(withinLimit(x, y));
        const other = this.slots.get(slot)!;
        requireValue(other.maxval === m, "maxval mismatch");
        const pixels = [...image.pixels];
        let painted = 0;
        for (let j = 0; j < other.height; ++j) {
          for (let i = 0; i < other.width; ++i) {
            if (image.contains(x + i, y + j)) {
              pixels[(y + j) * image.width + x + i] = other.get(i, j);
              ++painted;
            }
          }
        }
        this.commit(image.withPixels(pixels), painted);
        break;
      }
      case "SLOTS":
        if (this.slots.size === 0) this.emit("no slots");
        for (const name of [...this.slots.keys()].sort()) {
          this.emit(name + " " + this.slots.get(name)!.summary());
        }
        break;
      case "INFO":
        this.emit("image " + (image === null ? "none" : image.summary()) +
          " undo " + this.undoHistory.length +
          " redo " + this.redoHistory.length + " slots " + this.slots.size);
        break;
      case "UNDO":
        requireValue(this.undoHistory.length > 0, "nothing to undo");
        this.redoHistory.push(image);
        this.current = this.undoHistory.pop()!;
        this.emit("undo " + this.current.summary());
        break;
      case "REDO":
        requireValue(this.redoHistory.length > 0, "nothing to redo");
        this.undoHistory.push(image);
        this.current = this.redoHistory.pop()!;
        this.emit("redo " + this.current.summary());
        break;
    }
  }
}

function main(): void {
  const lines = readFileSync(0, "utf8").split(/\r?\n/);
  let position = 0;
  const commands = Number(lines[position++]);
  const editor = new ImageEditor();
  for (let i = 0; i < commands; ++i) {
    const words = lines[position++].split(" ");
    if (words[0] === "LOAD") {
      const count = Number(words[1]);
      editor.load(lines.slice(position, position + count));
      position += count;
    } else {
      editor.execute(words);
    }
  }
  process.stdout.write(editor.output.join("\n") + "\n");
}

main();
