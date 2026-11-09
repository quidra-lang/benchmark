'use strict';

const fs = require('fs');
const { normalize, neg } = require('./vector3');

function readScene(path) {
  const scene = { materials: new Map(), objects: [], lights: [], fog: null };
  for (const line of fs.readFileSync(path, 'ascii').split('\n')) {
    if (line === '' || line.startsWith('#')) continue;
    const [kind, ...tokens] = line.split(' ');
    if (kind === 'material') {
      const name = tokens[0], v = tokens.slice(1).map(Number);
      scene.materials.set(name, { name, color: v.slice(0, 3), kd: v[3], ks: v[4], exponent: v[5],
        kr: v[6], kt: v[7], ior: v[8], checker: null });
    } else if (kind === 'checker') {
      const v = tokens.slice(1).map(Number);
      scene.materials.get(tokens[0]).checker = { color: v.slice(0, 3), size: v[3] };
    } else if (['sphere', 'plane', 'box'].includes(kind)) {
      const [label, name] = tokens, v = tokens.slice(2).map(Number);
      const object = { kind, label, material: scene.materials.get(name), number: scene.objects.length + 1 };
      if (kind === 'sphere') { object.center = v.slice(0, 3); object.radius = v[3]; }
      else if (kind === 'plane') { object.point = v.slice(0, 3); object.normal = normalize(v.slice(3, 6)); }
      else { object.lo = v.slice(0, 3); object.hi = v.slice(3, 6); }
      scene.objects.push(object);
    } else if (['point', 'spot', 'sun', 'area'].includes(kind)) {
      const v = tokens.map(Number), light = { kind, number: scene.lights.length + 1, samples: 1 };
      if (kind === 'sun') { light.direction = normalize(neg(v.slice(0, 3))); light.intensity = v[3]; }
      else {
        light.position = v.slice(0, 3);
        if (kind === 'point') light.intensity = v[3];
        else if (kind === 'spot') {
          light.direction = normalize(v.slice(3, 6));
          light.outer = v[6]; light.inner = v[7]; light.intensity = v[8];
        } else {
          light.u = v.slice(3, 6); light.v = v.slice(6, 9);
          light.divisions = v[9]; light.samples = v[9] * v[9]; light.intensity = v[10];
        }
      }
      scene.lights.push(light);
    } else {
      const v = tokens.map(Number);
      if (kind === 'fog') scene.fog = { color: v.slice(0, 3), start: v[3], end: v[4] };
      else scene[kind] = kind === 'ambient' ? v[0] : v;
    }
  }
  return scene;
}

module.exports = { readScene };
