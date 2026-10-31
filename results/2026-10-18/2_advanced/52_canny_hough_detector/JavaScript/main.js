'use strict';

const fs = require('fs');
const io = require('./pgm_io');
const filters = require('./filters');
const canny = require('./canny');
const hough = require('./hough');
const harris = require('./corners');

const cross = (a, b) => a.x * b.y - a.y * b.x;
const subtract = (a, b) => ({ x: a.x - b.x, y: a.y - b.y });
const distance = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const angle = (a, b) => Math.min(Math.abs(a - b), 180 - Math.abs(a - b));
const insideImage = (p, width, height) => p.x >= 0 && p.x < width && p.y >= 0 && p.y < height;
const count = values => values.reduce((sum, value) => sum + value, 0);
const shapeReference = shape => shape ? `${shape.type} ${shape.number}` : 'none';

function rounded(numerator, denominator) {
  if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
  return Math.floor((2 * numerator + denominator) / (2 * denominator));
}

function bresenham(start, end) {
  const dx = Math.abs(end.x - start.x), dy = -Math.abs(end.y - start.y);
  const sx = start.x < end.x ? 1 : -1, sy = start.y < end.y ? 1 : -1;
  let x = start.x, y = start.y, error = dx + dy;
  const points = [];
  while (true) {
    points.push({ x, y });
    if (x === end.x && y === end.y) return points;
    const twice = 2 * error;
    if (twice >= dy) { error += dy; x += sx; }
    if (twice <= dx) { error += dx; y += sy; }
  }
}

function circumference(circle, point) {
  const dx = point.x - circle.x, dy = point.y - circle.y, squared = dx * dx + dy * dy;
  return (circle.radius - 1) * (circle.radius - 1) <= squared &&
    squared <= (circle.radius + 1) * (circle.radius + 1);
}

function circleGaps(circle, edges, width, height) {
  const half = p => p.y > 0 || (p.y === 0 && p.x > 0) ? 0 : 1;
  const offsets = circle.offsets.slice().sort((a, b) => half(a) - half(b) || -cross(a, b));
  const hits = offsets.map(o => {
    const p = { x: circle.x + o.x, y: circle.y + o.y };
    return insideImage(p, width, height) && edges[p.y * width + p.x] ? 1 : 0;
  });
  const total = count(hits), n = hits.length;
  if (total === 0) return { gap: n, arcs: 0 };
  if (total === n) return { gap: 0, arcs: 1 };
  let arcs = 0, gap = 0, run = 0;
  for (let i = 0; i < n; i++) if (hits[i] && !hits[(i + n - 1) % n]) arcs++;
  const first = hits.indexOf(1);
  for (let step = 1; step <= n; step++) {
    if (hits[(first + step) % n]) run = 0;
    else { run++; gap = Math.max(gap, run); }
  }
  return { gap, arcs };
}

function selectCircles(detection, edges, width, height, maximum) {
  detection.peaks.sort((a, b) => b.votes * a.points - a.votes * b.points ||
    a.radius - b.radius || a.y - b.y || a.x - b.x);
  return detection.peaks.slice(0, maximum).map((peak, i) => ({
    ...peak, type: 'circle', number: i + 1, ...circleGaps(peak, edges, width, height),
    explained: new Uint8Array(edges.length)
  }));
}

function removeCirclePixels(edges, circles, width) {
  const pixels = [], removed = new Uint8Array(edges.length);
  for (let index = 0; index < edges.length; index++) {
    if (!edges[index]) continue;
    const point = { x: index % width, y: Math.floor(index / width), index };
    for (const circle of circles) {
      if (circumference(circle, point)) { removed[index] = 1; circle.explained[index] = 1; }
    }
    if (!removed[index]) pixels.push(point);
  }
  return { pixels, removed };
}

function extractSegments(peaks, pixels, trig, params, size) {
  peaks.sort((a, b) => b.votes - a.votes || a.theta - b.theta || a.rho - b.rho);
  const used = new Uint8Array(size), lines = [], segments = [];
  for (const peak of peaks) {
    if (lines.length === params.hough_max_lines) break;
    const selected = pixels.filter(p => !used[p.index] &&
      Math.abs(hough.rho(p, peak.theta, trig, params.hough_rho_step) - peak.rho) <= params.segment_tolerance)
      .map(p => ({ ...p, u: p.y * trig.cos[peak.theta] - p.x * trig.sin[peak.theta] }));
    selected.sort((a, b) => a.u - b.u || a.x - b.x || a.y - b.y);
    const groups = [];
    for (let i = 0; i < selected.length; i++) {
      if (i === 0 || selected[i].u - selected[i - 1].u > params.segment_max_gap * 16384) groups.push([]);
      groups[groups.length - 1].push(selected[i]);
    }
    const accepted = groups.filter(group => distance(group[0], group[group.length - 1]) + 1 >= params.segment_min_length);
    if (accepted.length === 0) continue;
    const line = { ...peak, number: lines.length + 1, segments: [] };
    for (const group of accepted) {
      const start = group[0], end = group[group.length - 1];
      const segment = { number: segments.length + 1, line: line.number, theta: peak.theta,
        start, end, length: distance(start, end) + 1, pixels: group.map(p => p.index) };
      for (const index of segment.pixels) used[index] = 1;
      segments.push(segment);
      line.segments.push(segment);
    }
    lines.push(line);
  }
  return { lines, segments, used };
}

function findJunctions(segments, params) {
  const adjacency = segments.map(() => new Map());
  let count = 0;
  for (let a = 0; a < segments.length; a++) {
    for (let b = a + 1; b < segments.length; b++) {
      const first = segments[a], second = segments[b];
      if (angle(first.theta, second.theta) < params.junction_min_angle) continue;
      const da = subtract(first.end, first.start), db = subtract(second.end, second.start);
      const denominator = cross(da, db);
      if (denominator === 0) continue;
      const lambda = cross(subtract(second.start, first.start), db);
      const point = {
        x: rounded(first.start.x * denominator + lambda * da.x, denominator),
        y: rounded(first.start.y * denominator + lambda * da.y, denominator)
      };
      const endA = distance(first.start, point) <= distance(first.end, point) ? 0 : 1;
      const endB = distance(second.start, point) <= distance(second.end, point) ? 0 : 1;
      if (distance(endA ? first.end : first.start, point) > params.junction_distance ||
          distance(endB ? second.end : second.start, point) > params.junction_distance) continue;
      adjacency[a].set(b, { point, end: endA });
      adjacency[b].set(a, { point, end: endB });
      count++;
    }
  }
  return { adjacency, count };
}

function findPolygons(segments, adjacency) {
  const polygons = [], neighbors = adjacency.map(map => Array.from(map.keys()).sort((a, b) => a - b));
  for (const size of [3, 4]) {
    for (let first = 0; first < segments.length; first++) {
      const path = [first];
      function visit() {
        const last = path[path.length - 1];
        if (path.length === size) {
          if (path[1] >= last || !adjacency[last].has(first)) return;
          if (adjacency[last].get(path[size - 2]).end === adjacency[last].get(first).end ||
              adjacency[first].get(last).end === adjacency[first].get(path[1]).end) return;
          const vertices = path.map((current, i) => adjacency[current].get(path[(i + size - 1) % size]).point);
          const turns = vertices.map((v, i) => cross(subtract(vertices[(i + 1) % size], v),
            subtract(vertices[(i + 2) % size], vertices[(i + 1) % size])));
          if (!turns.every(turn => turn > 0) && !turns.every(turn => turn < 0)) return;
          polygons.push({ type: 'polygon', segments: path.map(i => segments[i]), vertices });
          return;
        }
        for (const next of neighbors[last]) {
          if (next <= first || path.includes(next)) continue;
          if (path.length > 1 && adjacency[last].get(path[path.length - 2]).end === adjacency[last].get(next).end) continue;
          path.push(next);
          visit();
          path.pop();
        }
      }
      visit();
    }
  }
  polygons.sort((a, b) => {
    if (a.segments.length !== b.segments.length) return a.segments.length - b.segments.length;
    for (let i = 0; i < a.segments.length; i++) {
      if (a.segments[i].number !== b.segments[i].number) return a.segments[i].number - b.segments[i].number;
    }
    return 0;
  });
  polygons.forEach((polygon, i) => { polygon.number = i + 1; });
  return polygons;
}

function polygonAttributes(polygon, edges, width, height, params) {
  const vertices = polygon.vertices, size = vertices.length;
  polygon.angles = [];
  polygon.length2 = [];
  polygon.support = [];
  polygon.sigma = 0;
  polygon.explained = new Uint8Array(edges.length);
  for (let i = 0; i < size; i++) {
    const before = vertices[(i + size - 1) % size], here = vertices[i], next = vertices[(i + 1) % size];
    const left = subtract(before, here), right = subtract(next, here);
    const phi = angle(polygon.segments[(i + size - 1) % size].theta, polygon.segments[i].theta);
    polygon.angles.push(left.x * right.x + left.y * right.y < 0 ? 180 - phi : phi);
    polygon.length2.push(right.x * right.x + right.y * right.y);
    polygon.sigma += cross(here, next);
    const points = bresenham(here, next);
    let supported = 0;
    for (const point of points) {
      let hit = false;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const p = { x: point.x + dx, y: point.y + dy };
          if (!insideImage(p, width, height)) continue;
          const index = p.y * width + p.x;
          polygon.explained[index] = 1;
          if (edges[index]) hit = true;
        }
      }
      if (hit) supported++;
    }
    polygon.support.push(Math.floor(100 * supported / points.length));
  }
  const absolute = Math.abs(polygon.sigma);
  polygon.area = `${Math.floor(absolute / 2)}.${absolute % 2 ? 5 : 0}`;
  const tolerance = params.angle_tolerance;
  if (size === 3) {
    polygon.kind = polygon.angles.every(a => Math.abs(a - 60) <= tolerance) ? 'equilateral_triangle' :
      polygon.angles.some(a => Math.abs(a - 90) <= tolerance) ? 'right_triangle' : 'triangle';
    return;
  }
  const parallelA = angle(polygon.segments[0].theta, polygon.segments[2].theta) <= tolerance;
  const parallelB = angle(polygon.segments[1].theta, polygon.segments[3].theta) <= tolerance;
  if (!parallelA && !parallelB) polygon.kind = 'quadrilateral';
  else if (parallelA !== parallelB) polygon.kind = 'trapezoid';
  else if (polygon.angles.some(a => Math.abs(a - 90) > tolerance)) polygon.kind = 'parallelogram';
  else {
    const maximum = Math.max(...polygon.length2), minimum = Math.min(...polygon.length2);
    polygon.kind = 100 * (maximum - minimum) <= params.square_tolerance * maximum ? 'square' : 'rectangle';
  }
}

function representatives(shape) {
  if (shape.type === 'polygon') return shape.vertices;
  const { x, y, radius: r } = shape;
  return [{ x: x + r, y }, { x, y: y + r }, { x: x - r, y }, { x, y: y - r }];
}

function contains(shape, point) {
  if (shape.type === 'circle') {
    const dx = point.x - shape.x, dy = point.y - shape.y;
    return dx * dx + dy * dy <= shape.radius * shape.radius;
  }
  return shape.vertices.every((v, i) => {
    const z = cross(subtract(shape.vertices[(i + 1) % shape.vertices.length], v), subtract(point, v));
    return z === 0 || (z > 0) === (shape.sigma > 0);
  });
}

function measureShapes(shapes, image, margin) {
  const { width, height, pixels } = image;
  for (const shape of shapes) {
    const points = representatives(shape);
    const x0 = Math.max(0, Math.min(...points.map(p => p.x)) - margin);
    const x1 = Math.min(width - 1, Math.max(...points.map(p => p.x)) + margin);
    const y0 = Math.max(0, Math.min(...points.map(p => p.y)) - margin);
    const y1 = Math.min(height - 1, Math.max(...points.map(p => p.y)) + margin);
    let inner = 0, innerSum = 0, outer = 0, outerSum = 0;
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        if (contains(shape, { x, y })) { inner++; innerSum += pixels[y * width + x]; }
        else { outer++; outerSum += pixels[y * width + x]; }
      }
    }
    shape.pixelCount = inner;
    shape.mean = inner ? Math.floor(innerSum / inner) : 0;
    shape.contrast = shape.mean - (outer ? Math.floor(outerSum / outer) : 0);
  }
  for (const shape of shapes) {
    shape.enclosing = null;
    for (const other of shapes) {
      if (other.pixelCount <= shape.pixelCount ||
          (shape.enclosing && other.pixelCount >= shape.enclosing.pixelCount)) continue;
      if (representatives(shape).every(point => contains(other, point))) shape.enclosing = other;
    }
  }
}

function matchCorners(corners, polygons, segments, maximum) {
  for (const corner of corners) {
    corner.match = 'none';
    corner.matchKind = 'none';
    let best = Infinity;
    for (const polygon of polygons) {
      polygon.vertices.forEach((vertex, i) => {
        const delta = distance(corner, vertex);
        if (delta <= maximum && delta < best) {
          best = delta;
          corner.match = `polygon ${polygon.number} vertex ${i + 1}`;
          corner.matchKind = 'polygon';
        }
      });
    }
    if (corner.matchKind === 'polygon') continue;
    for (const segment of segments) {
      for (const end of ['start', 'end']) {
        const delta = distance(corner, segment[end]);
        if (delta <= maximum && delta < best) {
          best = delta;
          corner.match = `segment ${segment.number} ${end}`;
          corner.matchKind = 'segment';
        }
      }
    }
  }
  for (const polygon of polygons) {
    polygon.vertexCorners = polygon.vertices.map(vertex => {
      let best = Infinity, selected = null;
      for (const corner of corners) {
        const delta = distance(vertex, corner);
        if (delta <= maximum && delta < best) { best = delta; selected = corner; }
      }
      return selected;
    });
  }
}

function describeComponents(groups, edges, magnitude, direction, shapes, width, height) {
  return groups.map((pixels, i) => {
    let minX = width, minY = height, maxX = -1, maxY = -1, ends = 0, sum = 0;
    const directions = { 0: 0, 45: 0, 90: 0, 135: 0 };
    for (const index of pixels) {
      const x = index % width, y = Math.floor(index / width);
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      sum += magnitude[index];
      directions[direction[index]]++;
      if (canny.neighbors(index, width, height).filter(next => edges[next]).length === 1) ends++;
    }
    let mainDirection = 0;
    for (const d of [45, 90, 135]) if (directions[d] > directions[mainDirection]) mainDirection = d;
    let matching = null, explained = 0;
    for (const shape of shapes) {
      const matched = pixels.reduce((sum, index) => sum + shape.explained[index], 0);
      if (matched > explained) { matching = shape; explained = matched; }
    }
    return { number: i + 1, pixels: pixels.length, box: [minX, minY, maxX, maxY], ends,
      strength: Math.floor(sum / pixels.length), direction: mainDirection, matching, explained };
  });
}

function voteImage(votes, width, height, trig, step) {
  const points = [{ x: 0, y: 0 }, { x: width - 1, y: 0 },
    { x: 0, y: height - 1 }, { x: width - 1, y: height - 1 }];
  let low = Infinity, high = -Infinity, maximum = 0;
  for (let theta = 0; theta < 180; theta++) {
    for (const point of points) {
      const r = hough.rho(point, theta, trig, step);
      low = Math.min(low, r); high = Math.max(high, r);
    }
    for (const value of votes[theta].values()) maximum = Math.max(maximum, value);
  }
  const pixels = new Int32Array(180 * (high - low + 1));
  if (maximum) {
    for (let r = low; r <= high; r++) {
      for (let theta = 0; theta < 180; theta++) {
        pixels[(r - low) * 180 + theta] = Math.floor(255 * (votes[theta].get(r) || 0) / maximum);
      }
    }
  }
  return { pixels, height: high - low + 1, maximum };
}

function overlayImage(image, segments, circles, corners, divisor) {
  const { width, height } = image, pixels = image.pixels.map(value => Math.floor(value / divisor));
  const mark = point => { if (insideImage(point, width, height)) pixels[point.y * width + point.x] = 255; };
  for (const segment of segments) for (const point of bresenham(segment.start, segment.end)) mark(point);
  for (const circle of circles) {
    for (const offset of circle.offsets) mark({ x: circle.x + offset.x, y: circle.y + offset.y });
  }
  for (const corner of corners) {
    for (let e = -2; e <= 2; e++) {
      mark({ x: corner.x + e, y: corner.y });
      mark({ x: corner.x, y: corner.y + e });
    }
  }
  return pixels;
}

function writeText(name, lines) {
  fs.writeFileSync(`output/${name}.txt`, lines.join('\n') + '\n', 'ascii');
}

function writeLists(lines, circles, polygons, corners, components) {
  const lineText = [`lines ${lines.length}`];
  for (const line of lines) {
    lineText.push(`line ${line.number} theta ${line.theta} rho ${line.rho} votes ${line.votes} segments ${line.segments.length}`);
    for (const s of line.segments) {
      lineText.push(`segment ${s.number} start ${s.start.x} ${s.start.y} end ${s.end.x} ${s.end.y} length ${s.length} pixels ${s.pixels.length}`);
    }
  }
  writeText('lines', lineText);
  writeText('circles', [`circles ${circles.length}`, ...circles.map(c =>
    `circle ${c.number} center ${c.x} ${c.y} radius ${c.radius} votes ${c.votes} points ${c.points} gap ${c.gap} arcs ${c.arcs} pixels ${c.pixelCount} mean ${c.mean} contrast ${c.contrast} inside ${shapeReference(c.enclosing)}`)]);
  const polygonText = [`polygons ${polygons.length}`];
  for (const p of polygons) {
    polygonText.push(`polygon ${p.number} ${p.kind} segments ${p.segments.map(s => s.number).join(' ')} area ${p.area} pixels ${p.pixelCount} mean ${p.mean} contrast ${p.contrast} inside ${shapeReference(p.enclosing)}`);
    p.vertices.forEach((v, i) => polygonText.push(`vertex ${i + 1} ${v.x} ${v.y} angle ${p.angles[i]} corner ${p.vertexCorners[i] ? p.vertexCorners[i].number : 'none'}`));
    p.segments.forEach((s, i) => polygonText.push(`side ${i + 1} segment ${s.number} length2 ${p.length2[i]} support ${p.support[i]}`));
  }
  writeText('polygons', polygonText);
  writeText('corners', [`corners ${corners.length}`, ...corners.map(c =>
    `corner ${c.number} ${c.x} ${c.y} response ${c.response} match ${c.match}`)]);
  writeText('components', [`components ${components.length}`, ...components.map(c =>
    `component ${c.number} pixels ${c.pixels} box ${c.box.join(' ')} ends ${c.ends} strength ${c.strength} direction ${c.direction} shape ${shapeReference(c.matching)} explained ${c.explained}`)]);
}

function writeCounts(image, gradient, nms, direction, thresholded, circleDetection, circles,
  circlePixels, linePixels, vote, peaks, extracted, junctions, polygons, cornerDetection, components) {
  const { edges, strong, weak } = thresholded, { corners } = cornerDetection;
  const weakKept = weak.reduce((sum, value, index) => sum + (value && edges[index] ? 1 : 0), 0);
  const directions = [0, 45, 90, 135].map(d => edges.reduce((sum, value, index) => sum + (value && direction[index] === d ? 1 : 0), 0));
  const kinds = ['equilateral_triangle', 'right_triangle', 'triangle', 'square', 'rectangle', 'parallelogram', 'trapezoid', 'quadrilateral'];
  const rows = [
    `image ${image.width} ${image.height}`,
    `gradient_nonzero ${gradient.magnitude.filter(value => value > 0).length}`,
    `gradient_max ${gradient.magnitude.reduce((maximum, value) => Math.max(maximum, value), 0)}`,
    `nms_kept ${nms.filter(value => value > 0).length}`,
    `strong ${count(strong)}`, `weak ${count(weak)}`, `edges ${count(edges)}`,
    `weak_kept ${weakKept}`, `weak_dropped ${count(weak) - weakKept}`,
    `edge_components ${components.length}`,
    ...[0, 45, 90, 135].map((d, i) => `direction_${d} ${directions[i]}`),
    `circle_candidates ${circleDetection.candidates}`, `circle_peaks ${circleDetection.peaks.length}`,
    `circles ${circles.length}`, `circle_edge_pixels ${count(circlePixels)}`, `line_edge_pixels ${linePixels.length}`,
    `hough_max_votes ${vote.maximum}`, `hough_peaks ${peaks.length}`,
    `lines ${extracted.lines.length}`, `segments ${extracted.segments.length}`, `claimed_pixels ${count(extracted.used)}`,
    `junctions ${junctions.count}`, `polygons ${polygons.length}`,
    ...kinds.map(kind => `${kind} ${polygons.filter(p => p.kind === kind).length}`),
    `corner_candidates ${cornerDetection.candidates.length}`, `corners ${corners.length}`,
    `corners_on_vertices ${corners.filter(c => c.matchKind === 'polygon').length}`,
    `corners_on_segments ${corners.filter(c => c.matchKind === 'segment').length}`,
    `corners_unmatched ${corners.filter(c => c.matchKind === 'none').length}`,
    `vertices_with_corner ${polygons.reduce((sum, p) => sum + p.vertexCorners.filter(Boolean).length, 0)}`
  ];
  writeText('report', rows);
}

function main() {
  const image = io.readImage('input/image.pgm'), trig = io.readTrig('input/trig.txt');
  const params = io.readParams('input/params.txt'), { width, height } = image;
  const smoothed = filters.smooth(image, params), gradient = filters.gradient(smoothed, width, height);
  const direction = canny.directions(gradient.gx, gradient.gy);
  const nms = canny.suppress(gradient.magnitude, direction, width, height);
  const thresholded = canny.hysteresis(nms, width, height, params.canny_low, params.canny_high);
  const { edges } = thresholded, groups = canny.components(edges, width, height);
  const circleVotes = hough.circleVotes(edges, width, height, params.circle_min_radius, params.circle_max_radius);
  const circleDetection = hough.circlePeaks(circleVotes, width, height, params.circle_min_percent);
  const circles = selectCircles(circleDetection, edges, width, height, params.circle_max_count);
  const remaining = removeCirclePixels(edges, circles, width);
  const votes = hough.lineVotes(remaining.pixels, trig, params.hough_rho_step);
  const peaks = hough.linePeaks(votes, params.hough_threshold);
  const vote = voteImage(votes, width, height, trig, params.hough_rho_step);
  const extracted = extractSegments(peaks, remaining.pixels, trig, params, edges.length);
  const junctions = findJunctions(extracted.segments, params);
  const polygons = findPolygons(extracted.segments, junctions.adjacency);
  for (const polygon of polygons) polygonAttributes(polygon, edges, width, height, params);
  const shapes = [...polygons, ...circles];
  measureShapes(shapes, image, params.contrast_margin);
  const cornerDetection = harris.detect(gradient.gx, gradient.gy, width, height,
    params.harris_window, params.harris_threshold, params.harris_max_count);
  matchCorners(cornerDetection.corners, polygons, extracted.segments, params.corner_match_distance);
  const components = describeComponents(groups, edges, gradient.magnitude, direction, shapes, width, height);
  const overlay = overlayImage(image, extracted.segments, circles, cornerDetection.corners, params.overlay_divisor);
  fs.mkdirSync('output', { recursive: true });
  io.writeImage('output/edges.pgm', width, height, Array.from(edges, value => 255 * value));
  io.writeImage('output/hough.pgm', 180, vote.height, vote.pixels);
  io.writeImage('output/overlay.pgm', width, height, overlay);
  writeLists(extracted.lines, circles, polygons, cornerDetection.corners, components);
  writeCounts(image, gradient, nms, direction, thresholded, circleDetection, circles,
    remaining.removed, remaining.pixels, vote, peaks, extracted, junctions, polygons, cornerDetection, components);
}

main();
