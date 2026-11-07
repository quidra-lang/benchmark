using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Shading {
    public record Phong(long diffuse, long specular) {
    }
    public record Refraction(long reflected, long transmitted, Vector3 direction, bool totalInternal) {
    }
    public static Scene.Color Base(Scene.Material material, Vector3 point) {
        if (material.checker != null) {
            long k = FixedPoint.Divide(point.x, material.checkerSize) +
                     FixedPoint.Divide(point.y, material.checkerSize) +
                     FixedPoint.Divide(point.z, material.checkerSize);
            if (k % 2 != 0)
                return material.checker;
        }
        return material.color;
    }
    public static Phong PhongTerms(Scene.Material material, Vector3 normal, Vector3 light, Vector3 view,
                                   long ndl, long intensity, long factor) {
        long effective = FixedPoint.Multiply(intensity, factor),
             diffuse = FixedPoint.Multiply(FixedPoint.Multiply(material.kd, ndl), effective),
             rv = normal.Scale(2 * ndl).Subtract(light).Dot(view), specular = 0;
        if (rv > 0) {
            long power = FixedPoint.S;
            for (int n = 0; n < material.exponent; n++)
                power = FixedPoint.Multiply(power, rv);
            specular = FixedPoint.Multiply(FixedPoint.Multiply(material.ks, power), effective);
        }
        return new Phong(diffuse, specular);
    }
    public static Vector3 Reflected(Vector3 direction, Vector3 normal) {
        return direction.Subtract(normal.Scale(2 * direction.Dot(normal))).Normalize();
    }
    public static Refraction Refracted(Scene.Material material, Vector3 direction, Vector3 normal,
                                       bool front) {
        long wr = material.kr, wt = material.kt;
        if (wt == 0)
            return new Refraction(wr, wt, null, false);
        long eta = front ? FixedPoint.Divide(FixedPoint.S * FixedPoint.S, material.ior) : material.ior,
             cn = -direction.Dot(normal),
             disc = FixedPoint.S * FixedPoint.S -
                    FixedPoint.Divide(FixedPoint.Multiply(eta, eta) * (FixedPoint.S * FixedPoint.S - cn * cn),
                                      FixedPoint.S);
        if (disc < 0)
            return new Refraction(wr + wt, 0, null, true);
        Vector3 transmitted = direction.Scale(eta)
                                  .Add(normal.Scale(FixedPoint.Multiply(eta, cn) - FixedPoint.Isqrt(disc)))
                                  .Normalize();
        long r0 =
                 FixedPoint.Divide((material.ior - FixedPoint.S) * FixedPoint.S, material.ior + FixedPoint.S),
             reflectance = FixedPoint.Multiply(r0, r0), x = FixedPoint.S - Math.Min(cn, FixedPoint.S),
             power = FixedPoint.S;
        for (int n = 0; n < 5; n++)
            power = FixedPoint.Multiply(power, x);
        long fresnel = reflectance + FixedPoint.Multiply(FixedPoint.S - reflectance, power),
             transfer = FixedPoint.Multiply(material.kt, fresnel);
        return new Refraction(wr + transfer, wt - transfer, transmitted, false);
    }
    public static Scene.Color Mix(Scene.Color[] colors, long[] weights) {
        long[] values = new long[3];
        for (int c = 0; c < 3; c++)
            for (int i = 0; i < colors.Length; i++)
                values[c] += FixedPoint.Divide(colors[i].Component(c) * weights[i], FixedPoint.S);
        return Scene.Color.Of(values);
    }
}
