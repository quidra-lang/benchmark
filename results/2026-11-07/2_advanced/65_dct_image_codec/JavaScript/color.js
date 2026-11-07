'use strict';

function clamp(value) { return Math.min(Math.max(value, 0), 255); }

function toYCbCr([R, G, B]) {
  return [Math.floor((19595 * R + 38470 * G + 7471 * B + 32768) / 65536),
    Math.floor((-11059 * R - 21709 * G + 32768 * B + 8421375) / 65536),
    Math.floor((32768 * R - 27439 * G - 5329 * B + 8421375) / 65536)];
}

function toRGB([Y, Cb, Cr]) {
  return [clamp(Y + Math.floor((91881 * (Cr - 128) + 32768) / 65536)),
    clamp(Y + Math.floor((-22554 * (Cb - 128) - 46802 * (Cr - 128) + 32768) / 65536)),
    clamp(Y + Math.floor((116130 * (Cb - 128) + 32768) / 65536))];
}

function planes(image) {
  const converted = image.pixels.map(row => row.map(toYCbCr));
  return [0, 1, 2].map(k => converted.map(row => row.map(pixel => pixel[k])));
}

function components(image, geometry) {
  const original = planes(image);
  return geometry.components.map((component, k) => {
    const fx = geometry.hMax / component.h, fy = geometry.vMax / component.v;
    const width = 8 * component.h * geometry.mx, height = 8 * component.v * geometry.my;
    return Array.from({ length: height }, (_, y) => Array.from({ length: width }, (_, x) => {
      let sum = 0;
      for (let j = 0; j < fy; j++) for (let i = 0; i < fx; i++) {
        sum += original[k][Math.min(fy * y + j, image.height - 1)][Math.min(fx * x + i, image.width - 1)];
      }
      return Math.floor(sum / (fx * fy));
    }));
  });
}

function upsample(componentPlanes, geometry) {
  const decodedPlanes = geometry.components.map((component, k) =>
    Array.from({ length: geometry.height }, (_, y) => Array.from({ length: geometry.width }, (_, x) =>
      componentPlanes[k][Math.floor(y * component.v / geometry.vMax)][Math.floor(x * component.h / geometry.hMax)])));
  const pixels = Array.from({ length: geometry.height }, (_, y) => Array.from({ length: geometry.width }, (_, x) =>
    toRGB(decodedPlanes.map(plane => plane[y][x]))));
  return { planes: decodedPlanes, image: { width: geometry.width, height: geometry.height, pixels } };
}

module.exports = { clamp, toYCbCr, toRGB, planes, components, upsample };
