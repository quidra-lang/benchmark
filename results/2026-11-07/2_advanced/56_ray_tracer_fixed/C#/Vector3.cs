using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public readonly record struct Vector3(long x, long y, long z) {
    public Vector3 Add(Vector3 v) {
        return new Vector3(x + v.x, y + v.y, z + v.z);
    }
    public Vector3 Subtract(Vector3 v) {
        return new Vector3(x - v.x, y - v.y, z - v.z);
    }
    public Vector3 Negate() {
        return new Vector3(-x, -y, -z);
    }
    public long Dot(Vector3 v) {
        return FixedPoint.Divide(x * v.x + y * v.y + z * v.z, FixedPoint.S);
    }
    public Vector3 Scale(long k) {
        return new Vector3(FixedPoint.Multiply(x, k), FixedPoint.Multiply(y, k), FixedPoint.Multiply(z, k));
    }
    public long Length() {
        return FixedPoint.Isqrt(x * x + y * y + z * z);
    }
    public Vector3 Normalize() {
        long l = Length();
        return new Vector3(FixedPoint.Divide(x * FixedPoint.S, l), FixedPoint.Divide(y * FixedPoint.S, l),
                           FixedPoint.Divide(z * FixedPoint.S, l));
    }
    public long Coordinate(int axis) {
        return axis == 0 ? x : axis == 1 ? y : z;
    }
    public static Vector3 Axis(int axis, long value) {
        return new Vector3(axis == 0 ? value : 0, axis == 1 ? value : 0, axis == 2 ? value : 0);
    }
    public override string ToString() {
        return x + " " + y + " " + z;
    }
}
