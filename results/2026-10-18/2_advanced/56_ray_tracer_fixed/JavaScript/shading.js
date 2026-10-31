'use strict';

const { S, div, mul, isqrt } = require('./fixed_point');
const { add, sub, dot, scale, normalize } = require('./vector3');

function baseColor(material, point) {
  if (!material.checker) return material.color;
  const parity = point.reduce((sum, value) => sum + div(value, material.checker.size), 0);
  return parity % 2 !== 0 ? material.checker.color : material.color;
}

function components(material, normal, light, view, ndl, intensity) {
  const diffuse = mul(mul(material.kd, ndl), intensity);
  const reflected = sub(scale(normal, 2 * ndl), light), rv = dot(reflected, view);
  let specular = 0;
  if (rv > 0) {
    let power = S;
    for (let i = 0; i < material.exponent; i++) power = mul(power, rv);
    specular = mul(mul(material.ks, power), intensity);
  }
  return { diffuse, specular };
}

const reflection = (direction, normal) => normalize(sub(direction, scale(normal, 2 * dot(direction, normal))));

function refraction(direction, normal, front, material) {
  let wr = material.kr, wt = material.kt, transmitted = null, totalInternal = false;
  if (material.kt > 0) {
    const eta = front ? div(S * S, material.ior) : material.ior;
    const cn = -dot(direction, normal);
    const discriminant = S * S - div(mul(eta, eta) * (S * S - cn * cn), S);
    if (discriminant < 0) { wr += wt; wt = 0; totalInternal = true; }
    else {
      transmitted = normalize(add(scale(direction, eta), scale(normal, mul(eta, cn) - isqrt(discriminant))));
      const r0 = div((material.ior - S) * S, material.ior + S), R0 = mul(r0, r0);
      const x = S - Math.min(cn, S);
      let power = S;
      for (let i = 0; i < 5; i++) power = mul(power, x);
      const fresnel = R0 + mul(S - R0, power), extra = mul(material.kt, fresnel);
      wr += extra;
      wt -= extra;
    }
  }
  return { wr, wt, transmitted, totalInternal };
}

function mix(colors, weights) {
  return [0, 1, 2].map(axis => colors.reduce((sum, color, i) => sum + mul(color[axis], weights[i]), 0));
}

module.exports = { baseColor, components, reflection, refraction, mix };
