#include "renderer.h"
Color base_color(Material material, Vec point) {
    if (!material.checker_size)
        return material.color;
    I cell = floor_div(point.data[0], material.checker_size) +
             floor_div(point.data[1], material.checker_size) +
             floor_div(point.data[2], material.checker_size);
    return cell % 2 != 0 ? material.second : material.color;
}
void phong(Material material, Vec normal, Vec light, Vec view, I effective, I *diffuse, I *specular) {
    I ndl = dot(normal, light);
    *diffuse = mul(mul(material.kd, ndl), effective);
    Vec reflection = sub(sc(normal, 2 * ndl), light);
    I rv = dot(reflection, view);
    *specular = 0;
    if (rv > 0) {
        I power = SCALE;
        for (I n = 0; n < material.exponent; ++n)
            power = mul(power, rv);
        *specular = mul(mul(material.ks, power), effective);
    }
}
Vec reflected(Vec direction, Vec normal) {
    return norm(sub(direction, sc(normal, 2 * dot(direction, normal))));
}
Weights refracted(Material material, Vec direction, Vec normal, bool front) {
    Weights out = {.reflection = material.kr, .refraction = material.kt};
    if (!material.kt)
        return out;
    I eta = front ? floor_div((I)SCALE * SCALE, material.ior) : material.ior, cn = -dot(direction, normal),
      disc = (I)SCALE * SCALE - floor_div(mul(eta, eta) * ((I)SCALE * SCALE - cn * cn), SCALE);
    if (disc < 0) {
        out.reflection = material.kr + material.kt;
        out.refraction = 0;
        out.total_internal = true;
        return out;
    }
    out.direction = norm(add(sc(direction, eta), sc(normal, mul(eta, cn) - isqrt(disc))));
    out.has_direction = true;
    I r0 = floor_div((material.ior - SCALE) * SCALE, material.ior + SCALE), base = mul(r0, r0),
      x = SCALE - (cn < SCALE ? cn : SCALE), power = SCALE;
    for (int i = 0; i < 5; ++i)
        power = mul(power, x);
    I fresnel = base + mul(SCALE - base, power), reflection = mul(material.kt, fresnel);
    out.reflection = material.kr + reflection;
    out.refraction = material.kt - reflection;
    return out;
}
Color mix(Color local, I local_weight, Color reflection, I reflected_weight, Color refraction,
          I refracted_weight) {
    Color out;
    for (int i = 0; i < 3; ++i)
        out.data[i] = floor_div(local.data[i] * local_weight, SCALE) +
                      floor_div(reflection.data[i] * reflected_weight, SCALE) +
                      floor_div(refraction.data[i] * refracted_weight, SCALE);
    return out;
}
