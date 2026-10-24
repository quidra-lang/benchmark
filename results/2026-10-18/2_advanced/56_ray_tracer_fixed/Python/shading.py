"""Checker colors, Phong terms, optical directions and color mixing."""

from fixed_point import S, isqrt, mul
from vector3 import add, dot, norm, sc, sub


def base_color(material, point):
    if material.checker is not None:
        alternate, size = material.checker
        if sum(a // size for a in point) % 2:
            return alternate
    return material.color


def phong(material, normal, light, view, ndl, intensity, factor):
    effective = mul(intensity, factor)
    diffuse = mul(mul(material.kd, ndl), effective)
    reflected_light = sub(sc(normal, 2 * ndl), light)
    rv = dot(reflected_light, view)
    specular = 0
    if rv > 0:
        power = S
        for _ in range(material.n):
            power = mul(power, rv)
        specular = mul(mul(material.ks, power), effective)
    return diffuse, specular


def reflected(direction, normal):
    return norm(sub(direction, sc(normal, 2 * dot(direction, normal))))


def refraction(material, direction, normal, front):
    wr, wt = material.kr, material.kt
    if wt == 0:
        return wr, wt, None, False
    eta = S * S // material.ior if front else material.ior
    cosine = -dot(direction, normal)
    discriminant = S * S - mul(eta, eta) * (S * S - cosine * cosine) // S
    if discriminant < 0:
        return wr + wt, 0, None, True
    transmitted = norm(add(sc(direction, eta),
                           sc(normal, mul(eta, cosine) - isqrt(discriminant))))
    r0 = (material.ior - S) * S // (material.ior + S)
    reflectance = mul(r0, r0)
    x = S - min(cosine, S)
    power = S
    for _ in range(5):
        power = mul(power, x)
    fresnel = reflectance + mul(S - reflectance, power)
    transfer = mul(material.kt, fresnel)
    return wr + transfer, wt - transfer, transmitted, False


def mix(*weighted_colors):
    return tuple(sum(color[a] * weight // S for color, weight in weighted_colors)
                 for a in range(3))
