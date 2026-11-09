import { readFileSync } from "node:fs";


class Invalid extends Error {}

function requireValid(condition) {
  if (!condition) throw new Invalid();
}

function floorBig(n, d) {
  let quotient = n / d;
  if (n < 0n && n % d !== 0n) quotient--;
  return quotient;
}

function floorRatio(n, d) {
  return Number(floorBig(BigInt(n), BigInt(d)));
}

function roundRatio(n, d) {
  const denominator = BigInt(d);
  return Number(floorBig(2n * BigInt(n) + denominator, 2n * denominator));
}

function awayRatio(n, d) {
  return n < 0 ? -roundRatio(-n, d) : roundRatio(n, d);
}

function mod(n, denominator) {
  return ((n % denominator) + denominator) % denominator;
}

function clamp(value) {
  return Math.max(0, Math.min(255, value));
}

function integer(token, low, high) {
  requireValid(/^-?\d{1,9}$/.test(token));
  const value = Number(token);
  requireValid(value >= low && value <= high);
  return value;
}

function integers(tokens, ranges) {
  return tokens.map((token, i) => integer(token, ranges[i][0], ranges[i][1]));
}

function keyword(token, choices) {
  requireValid(choices.includes(token));
  return token;
}

function nameArgument(token) {
  requireValid(/^[a-z]{1,12}$/.test(token));
  return token;
}

function parseHex(token) {
  return [1, 3, 5].map(start => parseInt(token.slice(start, start + 2), 16));
}

const builtinRows = [
  ["black", "#000000"], ["maroon", "#800000"], ["green", "#008000"], ["olive", "#808000"],
  ["navy", "#000080"], ["purple", "#800080"], ["teal", "#008080"], ["silver", "#C0C0C0"],
  ["gray", "#808080"], ["red", "#FF0000"], ["lime", "#00FF00"], ["yellow", "#FFFF00"],
  ["blue", "#0000FF"], ["magenta", "#FF00FF"], ["cyan", "#00FFFF"], ["white", "#FFFFFF"],
  ["orange", "#FFA500"], ["pink", "#FFC0CB"], ["brown", "#A52A2A"], ["gold", "#FFD700"],
  ["coral", "#FF7F50"], ["salmon", "#FA8072"], ["violet", "#EE82EE"], ["indigo", "#4B0082"]
];
const builtins = builtinRows.map(([name, value]) => ({name, color: parseHex(value)}));
const builtinMap = new Map(builtins.map(entry => [entry.name, entry.color]));
const registered = new Map();

function table() {
  return [...builtins, ...[...registered].map(([name, color]) => ({name, color}))];
}

function colorArgument(token) {
  if (/^#[0-9a-fA-F]{6}$/.test(token)) return parseHex(token);
  if (/^#[0-9a-fA-F]{3}$/.test(token)) {
    return [...token.slice(1)].map(digit => parseInt(digit + digit, 16));
  }
  const match = token.match(/^rgb\((\d{1,3}),(\d{1,3}),(\d{1,3})\)$/);
  if (match) {
    const color = match.slice(1).map(Number);
    requireValid(color.every(component => component <= 255));
    return color;
  }
  const color = builtinMap.get(token) ?? registered.get(token);
  requireValid(color !== undefined);
  return [...color];
}

function hex(color) {
  return "#" + color.map(component => component.toString(16).toUpperCase().padStart(2, "0")).join("");
}

function same(a, b) {
  return a.every((value, i) => value === b[i]);
}

function distance(a, b) {
  return a.reduce((sum, value, i) => sum + (value - b[i]) * (value - b[i]), 0);
}

function hue(color) {
  const [r, g, b] = color;
  const maximum = Math.max(...color), difference = maximum - Math.min(...color);
  if (difference === 0) return 0;
  let numerator;
  if (maximum === r) {
    numerator = 60 * (g - b);
    if (numerator < 0) numerator += 360 * difference;
  } else if (maximum === g) numerator = 60 * (b - r) + 120 * difference;
  else numerator = 60 * (r - g) + 240 * difference;
  return roundRatio(numerator, difference) % 360;
}

function hsl(color) {
  const maximum = Math.max(...color), minimum = Math.min(...color);
  const difference = maximum - minimum;
  const saturation = difference === 0 ? 0 : roundRatio(100 * difference, 255 - Math.abs(maximum + minimum - 255));
  return [hue(color), saturation, roundRatio(100 * (maximum + minimum), 510)];
}

function base60(h) {
  const sector = floorRatio(h, 60), fraction = h % 60;
  const x = sector % 2 === 0 ? fraction : 60 - fraction;
  const bases = [[60, x, 0], [x, 60, 0], [0, 60, x], [0, x, 60], [x, 0, 60], [60, 0, x]];
  return bases[sector];
}

function fromHsl(h, s, l) {
  const chroma = (100 - Math.abs(2 * l - 100)) * s;
  return base60(h).map(component => roundRatio(255 * (chroma * component + 30 * (200 * l - chroma)), 600000));
}

function fromHsv(h, s, v) {
  const chroma = v * s;
  return base60(h).map(component => roundRatio(255 * (chroma * component + 60 * (100 * v - chroma)), 600000));
}

function fromHwb(h, w, k) {
  if (w + k >= 100) return Array(3).fill(roundRatio(255 * w, w + k));
  return base60(h).map(component => roundRatio(255 * (component * (100 - w - k) + 60 * w), 6000));
}

function modelValues(command, color) {
  const [r, g, b] = color;
  const maximum = Math.max(...color), minimum = Math.min(...color);
  switch (command) {
    case "HSL": return hsl(color);
    case "HSV":
      return [hue(color), maximum === 0 ? 0 : roundRatio(100 * (maximum - minimum), maximum), roundRatio(100 * maximum, 255)];
    case "HWB":
      return [hue(color), roundRatio(100 * minimum, 255), roundRatio(100 * (255 - maximum), 255)];
    case "CMYK":
      if (maximum === 0) return [0, 0, 0, 100];
      return [...color.map(component => roundRatio(100 * (maximum - component), maximum)), roundRatio(100 * (255 - maximum), 255)];
    case "YCBCR":
      return [
        clamp(roundRatio(299 * r + 587 * g + 114 * b, 1000)),
        clamp(roundRatio(128000 - 169 * r - 331 * g + 500 * b, 1000)),
        clamp(roundRatio(128000 + 500 * r - 419 * g - 81 * b, 1000))
      ];
    case "YIQ":
      return [
        roundRatio(299 * r + 587 * g + 114 * b, 1000),
        roundRatio(596 * r - 274 * g - 322 * b, 1000),
        roundRatio(211 * r - 523 * g + 312 * b, 1000)
      ];
    default: throw new Invalid();
  }
}

function modelText(command, color) {
  const values = modelValues(command, color);
  let body;
  if (["HSL", "HSV", "HWB"].includes(command)) body = values[0] + "," + values[1] + "%," + values[2] + "%";
  else if (command === "CMYK") body = values.map(value => value + "%").join(",");
  else body = values.join(",");
  return command.toLowerCase() + "(" + body + ")";
}

function ansiColor(code) {
  if (code <= 15) return [...builtins[code].color];
  if (code >= 232) return Array(3).fill(8 + 10 * (code - 232));
  const levels = [0, 95, 135, 175, 215, 255], value = code - 16;
  return [levels[floorRatio(value, 36)], levels[floorRatio(value, 6) % 6], levels[value % 6]];
}

function rootScaled(value, scale) {
  const target = BigInt(value), factor = BigInt(scale);
  let low = 0n, high = 1n;
  while (factor * high * high <= target) high *= 2n;
  while (low + 1n < high) {
    const middle = (low + high) / 2n;
    if (factor * middle * middle <= target) low = middle;
    else high = middle;
  }
  return Number(low);
}

function gradient(a, b, count) {
  return Array.from({length: count}, (_, i) => a.map((value, c) => value + awayRatio((b[c] - value) * i, count - 1)));
}

function rotate(color, degrees) {
  const [h, s, l] = hsl(color);
  return fromHsl(mod(h + degrees, 360), s, l);
}

const blendModes = [
  "MULTIPLY", "SCREEN", "OVERLAY", "HARDLIGHT", "SOFTLIGHT", "DARKEN", "LIGHTEN",
  "DIFFERENCE", "EXCLUSION", "ADD", "SUBTRACT", "COLORDODGE", "COLORBURN",
  "HUE", "SATURATION", "COLOR", "LUMINOSITY"
];

function blendChannel(mode, x, y) {
  switch (mode) {
    case "MULTIPLY": return floorRatio(x * y, 255);
    case "SCREEN": return 255 - floorRatio((255 - x) * (255 - y), 255);
    case "OVERLAY":
    case "HARDLIGHT":
      if ((mode === "OVERLAY" ? x : y) < 128) return floorRatio(2 * x * y, 255);
      return 255 - floorRatio(2 * (255 - x) * (255 - y), 255);
    case "SOFTLIGHT": {
      const multiply = floorRatio(x * y, 255);
      const screen = 255 - floorRatio((255 - x) * (255 - y), 255);
      return floorRatio((255 - x) * multiply + x * screen, 255);
    }
    case "DARKEN": return Math.min(x, y);
    case "LIGHTEN": return Math.max(x, y);
    case "DIFFERENCE": return Math.abs(x - y);
    case "EXCLUSION": return x + y - floorRatio(2 * x * y, 255);
    case "ADD": return Math.min(255, x + y);
    case "SUBTRACT": return Math.max(0, x - y);
    case "COLORDODGE": return y === 255 ? 255 : Math.min(255, floorRatio(255 * x, 255 - y));
    case "COLORBURN": return y === 0 ? 0 : Math.max(0, 255 - floorRatio(255 * (255 - x), y));
    default: throw new Invalid();
  }
}

function blend(mode, base, top) {
  const [h1, s1, l1] = hsl(base), [h2, s2, l2] = hsl(top);
  switch (mode) {
    case "HUE": return fromHsl(h2, s1, l1);
    case "SATURATION": return fromHsl(h1, s2, l1);
    case "COLOR": return fromHsl(h2, s2, l1);
    case "LUMINOSITY": return fromHsl(h1, s1, l2);
    default: return base.map((value, i) => blendChannel(mode, value, top[i]));
  }
}

const simulations = new Map([
  ["PROTANOPIA", [[567, 433, 0], [558, 442, 0], [0, 242, 758]]],
  ["DEUTERANOPIA", [[625, 375, 0], [700, 300, 0], [0, 300, 700]]],
  ["TRITANOPIA", [[950, 50, 0], [0, 433, 567], [0, 475, 525]]],
  ["ACHROMATOPSIA", [[299, 587, 114], [299, 587, 114], [299, 587, 114]]]
]);

function contrast(a, b) {
  const luminance = (c) => 2126 * c[0] * c[0] + 7152 * c[1] * c[1] + 722 * c[2] * c[2];
  const first = luminance(a), second = luminance(b);
  const high = Math.max(first, second) + 32512500;
  const low = Math.min(first, second) + 32512500;
  const verdict = high >= 7 * low ? "AAA" : 2 * high >= 9 * low ? "AA" : "FAIL";
  return {ratio: roundRatio(100 * high, low), verdict};
}

function contrastText(info) {
  return floorRatio(info.ratio, 100) + "." + String(info.ratio % 100).padStart(2, "0") + " " + info.verdict;
}

function accessible(foreground, background) {
  if (contrast(foreground, background).verdict !== "FAIL") return foreground;
  const [h, s, l] = hsl(foreground);
  for (let step = 1; step <= 100; step++) {
    for (const lightness of [l - step, l + step]) {
      if (lightness < 0 || lightness > 100) continue;
      const candidate = fromHsl(h, s, lightness);
      if (contrast(candidate, background).verdict !== "FAIL") return candidate;
    }
  }
  throw new Error("Accessible color must exist");
}

function describe(color) {
  const [h, s, l] = hsl(color);
  if (l <= 5) return "black";
  if (l >= 95) return "white";
  const lightness = l <= 20 ? "very dark" : l <= 40 ? "dark" : l <= 60 ? "medium" : l <= 80 ? "light" : "very light";
  if (s < 10) return lightness + " gray";
  const saturation = s < 40 ? "muted" : s < 80 ? "moderate" : "vivid";
  const names = ["red", "orange", "yellow", "chartreuse", "green", "spring-green", "cyan", "azure", "blue", "violet", "magenta", "rose"];
  return lightness + " " + saturation + " " + names[floorRatio((h + 15) % 360, 30)];
}

function mean(colors) {
  return [0, 1, 2].map(component => roundRatio(colors.reduce((sum, c) => sum + c[component], 0), colors.length));
}

function palette(colors, count) {
  const boxes = [colors.slice()];
  while (boxes.length < count) {
    let chosen = -1, chosenWidth = -1, component = 0;
    boxes.forEach((box, index) => {
      if (box.length < 2) return;
      const widths = [0, 1, 2].map(c => Math.max(...box.map(color => color[c])) - Math.min(...box.map(color => color[c])));
      const width = Math.max(...widths);
      if (width > chosenWidth) {
        chosen = index;
        chosenWidth = width;
        component = widths.indexOf(width);
      }
    });
    const colorsInOrder = boxes[chosen].toSorted((a, b) => a[component] - b[component]);
    const middle = floorRatio(colorsInOrder.length, 2);
    boxes.splice(chosen, 1, colorsInOrder.slice(0, middle), colorsInOrder.slice(middle));
  }
  return boxes;
}

function kmeans(colors, count) {
  let representatives = palette(colors, count).map(mean);
  let counts = [], iterations = 0;
  for (let iteration = 0; iteration < 20; iteration++) {
    const groups = Array.from({length: count}, () => []);
    for (const color of colors) {
      let selected = 0, best = distance(color, representatives[0]);
      for (let j = 1; j < count; j++) {
        const value = distance(color, representatives[j]);
        if (value < best) {
          selected = j;
          best = value;
        }
      }
      groups[selected].push(color);
    }
    const next = groups.map((group, j) => group.length > 0 ? mean(group) : representatives[j]);
    counts = groups.map(group => group.length);
    iterations++;
    const unchanged = next.every((color, j) => same(color, representatives[j]));
    representatives = next;
    if (unchanged) break;
  }
  return iterations + " " + representatives.map((color, j) => hex(color) + ":" + counts[j]).join(" ");
}

function dither(colors) {
  let error = [0, 0, 0];
  const names = [];
  for (const color of colors) {
    const adjusted = color.map((value, c) => clamp(value + error[c]));
    let selected = 0, best = distance(adjusted, builtins[0].color);
    for (let j = 1; j < 16; j++) {
      const value = distance(adjusted, builtins[j].color);
      if (value < best) {
        selected = j;
        best = value;
      }
    }
    names.push(builtins[selected].name);
    error = adjusted.map((value, c) => value - builtins[selected].color[c]);
  }
  return names.join(" ");
}

const arities = new Map();
const fixedGroups = [
  ["LIST", 0],
  ["PARSE UNDEFINE HSL HSV HWB CMYK YCBCR YIQ RGB565 FROM565 ANSI FROMANSI WEBSAFE INVERT COMPLEMENT TRIADIC TETRADIC SPLITCOMP NEAREST DESCRIBE", 1],
  ["DEFINE GRAY TINTS SHADES TONES SIMULATE ROTATE LIGHTEN DARKEN SATURATE DESATURATE DISTANCE CONTRAST ACCESSIBLE RANDOM", 2],
  ["FROMHSL FROMHSV FROMHWB FROMYCBCR FROMYIQ MIX MIXHSL GRADIENT BLEND ANALOGOUS", 3],
  ["FROMCMYK ALPHA", 4]
];
for (const [names, count] of fixedGroups) {
  for (const name of names.split(" ")) arities.set(name, [count, count]);
}
for (const command of ["BEST", "PALETTE", "KMEANS"]) arities.set(command, [2, 33]);
for (const command of ["SORT", "DITHER"]) arities.set(command, [1, 32]);

function execute(line) {
  const [command, ...args] = line.split(" ");
  const arity = arities.get(command);
  requireValid(arity !== undefined);
  requireValid(args.length >= arity[0] && args.length <= arity[1]);
  if (command === "DEFINE") {
    const name = nameArgument(args[0]);
    requireValid(!builtinMap.has(name));
    const color = colorArgument(args[1]);
    registered.set(name, color);
    return name + " " + hex(color);
  }
  if (command === "UNDEFINE") {
    const name = nameArgument(args[0]);
    requireValid(registered.has(name));
    registered.delete(name);
    return name + " removed";
  }
  if (command === "LIST") {
    const names = [...registered.keys()].sort();
    return names.length === 0 ? "NONE" : names.map(name => name + "=" + hex(registered.get(name))).join(" ");
  }
  if (command === "PARSE") {
    const color = colorArgument(args[0]);
    const first = table().find(entry => same(entry.color, color));
    const models = ["HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ"].map(model => modelText(model, color));
    return [hex(color), "rgb(" + color.join(",") + ")", ...models, first ? first.name : "-"].join(" ");
  }
  if (["HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ"].includes(command)) {
    return modelText(command, colorArgument(args[0]));
  }
  if (["FROMHSL", "FROMHSV", "FROMHWB"].includes(command)) {
    const [h, second, third] = integers(args, [[0, 359], [0, 100], [0, 100]]);
    if (command === "FROMHSL") return hex(fromHsl(h, second, third));
    if (command === "FROMHSV") return hex(fromHsv(h, second, third));
    return hex(fromHwb(h, second, third));
  }
  if (command === "FROMCMYK") {
    const [c, m, y, k] = integers(args, Array.from({length: 4}, () => [0, 100]));
    return hex([c, m, y].map(value => roundRatio(255 * (100 - value) * (100 - k), 10000)));
  }
  if (command === "FROMYCBCR") {
    const [y, cb, cr] = integers(args, [[0, 255], [0, 255], [0, 255]]);
    return hex([
      clamp(roundRatio(1000 * y + 1402 * (cr - 128), 1000)),
      clamp(roundRatio(1000 * y - 344 * (cb - 128) - 714 * (cr - 128), 1000)),
      clamp(roundRatio(1000 * y + 1772 * (cb - 128), 1000))
    ]);
  }
  if (command === "FROMYIQ") {
    const [y, i, q] = integers(args, [[0, 255], [-255, 255], [-255, 255]]);
    return hex([
      clamp(roundRatio(1000 * y + 956 * i + 619 * q, 1000)),
      clamp(roundRatio(1000 * y - 272 * i - 647 * q, 1000)),
      clamp(roundRatio(1000 * y - 1106 * i + 1703 * q, 1000))
    ]);
  }
  if (command === "FROM565") {
    requireValid(/^0x[0-9a-fA-F]{4}$/.test(args[0]));
    const value = parseInt(args[0].slice(2), 16);
    return hex([
      roundRatio(255 * floorRatio(value, 2048), 31),
      roundRatio(255 * (floorRatio(value, 32) % 64), 63),
      roundRatio(255 * (value % 32), 31)
    ]);
  }
  if (command === "FROMANSI") return hex(ansiColor(integer(args[0], 0, 255)));
  if (command === "RGB565") {
    const [r, g, b] = colorArgument(args[0]);
    const value = 2048 * roundRatio(31 * r, 255) + 32 * roundRatio(63 * g, 255) + roundRatio(31 * b, 255);
    return "0x" + value.toString(16).toUpperCase().padStart(4, "0");
  }
  if (command === "ANSI") {
    const color = colorArgument(args[0]);
    let selected = 16, best = distance(color, ansiColor(16));
    for (let code = 17; code <= 255; code++) {
      const value = distance(color, ansiColor(code));
      if (value < best) {
        selected = code;
        best = value;
      }
    }
    return selected + " " + hex(ansiColor(selected)) + " " + best;
  }
  if (command === "WEBSAFE") return hex(colorArgument(args[0]).map(value => 51 * roundRatio(value, 51)));
  if (command === "INVERT") return hex(colorArgument(args[0]).map(value => 255 - value));
  if (command === "GRAY") {
    const color = colorArgument(args[0]), [r, g, b] = color;
    const method = keyword(args[1], ["LUMA", "AVERAGE", "LIGHTNESS", "HSP"]);
    let value;
    if (method === "LUMA") value = roundRatio(299 * r + 587 * g + 114 * b, 1000);
    else if (method === "AVERAGE") value = roundRatio(r + g + b, 3);
    else if (method === "LIGHTNESS") value = roundRatio(Math.max(...color) + Math.min(...color), 2);
    else value = rootScaled(299 * r * r + 587 * g * g + 114 * b * b, 1000);
    return hex([value, value, value]);
  }
  if (command === "MIX" || command === "MIXHSL") {
    const a = colorArgument(args[0]), b = colorArgument(args[1]), p = integer(args[2], 0, 100);
    if (command === "MIX") return hex(a.map((value, i) => roundRatio(value * (100 - p) + b[i] * p, 100)));
    const [h1, s1, l1] = hsl(a), [h2, s2, l2] = hsl(b);
    let delta = mod(h2 - h1, 360);
    if (delta > 180) delta -= 360;
    return hex(fromHsl(
      mod(h1 + awayRatio(delta * p, 100), 360),
      s1 + awayRatio((s2 - s1) * p, 100),
      l1 + awayRatio((l2 - l1) * p, 100)
    ));
  }
  if (command === "GRADIENT") {
    const a = colorArgument(args[0]), b = colorArgument(args[1]), count = integer(args[2], 2, 16);
    return gradient(a, b, count).map(hex).join(" ");
  }
  if (["TINTS", "SHADES", "TONES"].includes(command)) {
    const color = colorArgument(args[0]), count = integer(args[1], 1, 10);
    const target = command === "TINTS" ? [255, 255, 255] : command === "SHADES" ? [0, 0, 0] : [128, 128, 128];
    return gradient(color, target, count + 2).slice(1, -1).map(hex).join(" ");
  }
  if (command === "BLEND") {
    const mode = keyword(args[0], blendModes), base = colorArgument(args[1]), top = colorArgument(args[2]);
    return hex(blend(mode, base, top));
  }
  if (command === "ALPHA") {
    const foreground = colorArgument(args[0]), p = integer(args[1], 0, 100);
    const background = colorArgument(args[2]), q = integer(args[3], 0, 100);
    const opacity = 100 * p + q * (100 - p);
    const color = opacity === 0 ? [0, 0, 0] : foreground.map((value, i) => {
      const numerator = 100 * p * value + q * (100 - p) * background[i];
      return roundRatio(numerator, opacity);
    });
    return hex(color) + " " + roundRatio(opacity, 100) + "%";
  }
  if (command === "SIMULATE") {
    const color = colorArgument(args[0]), type = keyword(args[1], [...simulations.keys()]);
    const result = simulations.get(type).map(row => roundRatio(row.reduce((sum, value, i) => sum + value * color[i], 0), 1000));
    return hex(result);
  }
  if (command === "ROTATE") return hex(rotate(colorArgument(args[0]), integer(args[1], -720, 720)));
  const rotations = new Map([
    ["COMPLEMENT", [180]], ["TRIADIC", [120, 240]], ["TETRADIC", [90, 180, 270]], ["SPLITCOMP", [150, 210]]
  ]);
  if (rotations.has(command)) {
    const color = colorArgument(args[0]);
    return rotations.get(command).map(degrees => hex(rotate(color, degrees))).join(" ");
  }
  if (command === "ANALOGOUS") {
    const color = colorArgument(args[0]), k = integer(args[1], 1, 6), step = integer(args[2], 1, 60);
    const result = [];
    for (let i = -k; i <= k; i++) {
      if (i !== 0) result.push(rotate(color, i * step));
    }
    return result.map(hex).join(" ");
  }
  if (["LIGHTEN", "DARKEN", "SATURATE", "DESATURATE"].includes(command)) {
    const color = colorArgument(args[0]), p = integer(args[1], 0, 100);
    let [h, s, l] = hsl(color);
    if (command === "LIGHTEN") l = Math.min(100, l + p);
    if (command === "DARKEN") l = Math.max(0, l - p);
    if (command === "SATURATE") s = Math.min(100, s + p);
    if (command === "DESATURATE") s = Math.max(0, s - p);
    return hex(fromHsl(h, s, l));
  }
  if (command === "NEAREST") {
    const color = colorArgument(args[0]), entries = table();
    let selected = entries[0], best = distance(color, selected.color);
    for (const entry of entries.slice(1)) {
      const value = distance(color, entry.color);
      if (value < best) {
        selected = entry;
        best = value;
      }
    }
    return selected.name + " " + hex(selected.color) + " " + best;
  }
  if (command === "DISTANCE") {
    const a = colorArgument(args[0]), b = colorArgument(args[1]);
    const [dr, dg, db] = a.map((value, i) => value - b[i]);
    const weighted = (1024 + a[0] + b[0]) * dr * dr + 2048 * dg * dg + (1534 - a[0] - b[0]) * db * db;
    return distance(a, b) + " " + rootScaled(weighted, 512);
  }
  if (command === "CONTRAST") {
    return contrastText(contrast(colorArgument(args[0]), colorArgument(args[1])));
  }
  if (command === "ACCESSIBLE") {
    const foreground = colorArgument(args[0]), background = colorArgument(args[1]);
    const result = accessible(foreground, background);
    return hex(result) + " " + contrastText(contrast(result, background));
  }
  if (command === "BEST") {
    const [background, ...colors] = args.map(colorArgument);
    let chosen = colors[0], info = contrast(chosen, background);
    for (const color of colors.slice(1)) {
      const candidate = contrast(color, background);
      if (candidate.ratio > info.ratio) {
        chosen = color;
        info = candidate;
      }
    }
    return hex(chosen) + " " + contrastText(info);
  }
  if (command === "DESCRIBE") return describe(colorArgument(args[0]));
  if (command === "PALETTE" || command === "KMEANS") {
    const count = integer(args[0], 1, args.length - 1), colors = args.slice(1).map(colorArgument);
    if (command === "KMEANS") return kmeans(colors, count);
    return palette(colors, count).map(box => hex(mean(box)) + ":" + box.length).join(" ");
  }
  if (command === "SORT") {
    const colors = args.map(colorArgument);
    colors.sort((a, b) => {
      const first = hsl(a), second = hsl(b);
      return first[0] - second[0] || first[1] - second[1] || first[2] - second[2];
    });
    return colors.map(hex).join(" ");
  }
  if (command === "DITHER") return dither(args.map(colorArgument));
  if (command === "RANDOM") {
    let state = BigInt(integer(args[0], 1, 999999999));
    const count = integer(args[1], 1, 16), colors = [];
    for (let i = 0; i < count; i++) {
      state = state * 48271n % 2147483647n;
      const h = Number(state % 360n);
      state = state * 48271n % 2147483647n;
      const s = 40 + Number(state % 61n);
      state = state * 48271n % 2147483647n;
      const l = 25 + Number(state % 51n);
      colors.push(fromHsl(h, s, l));
    }
    return colors.map(hex).join(" ");
  }
  throw new Invalid();
}

const input = readFileSync(0, "utf8").split("\n");
const count = Number(input[0]), output = [];
for (let index = 1; index <= count; index++) {
  try {
    output.push(execute(input[index]));
  } catch (error) {
    if (!(error instanceof Invalid)) throw error;
    output.push("INVALID");
  }
}
process.stdout.write(output.join("\n") + "\n");
