record Vector3(long x, long y, long z) {
    Vector3 add(Vector3 v) {
        return new Vector3(x + v.x, y + v.y, z + v.z);
    }
    Vector3 subtract(Vector3 v) {
        return new Vector3(x - v.x, y - v.y, z - v.z);
    }
    Vector3 negate() {
        return new Vector3(-x, -y, -z);
    }
    long dot(Vector3 v) {
        return FixedPoint.divide(x * v.x + y * v.y + z * v.z, FixedPoint.S);
    }
    Vector3 scale(long k) {
        return new Vector3(FixedPoint.multiply(x, k), FixedPoint.multiply(y, k), FixedPoint.multiply(z, k));
    }
    long length() {
        return FixedPoint.isqrt(x * x + y * y + z * z);
    }
    Vector3 normalize() {
        long l = length();
        return new Vector3(FixedPoint.divide(x * FixedPoint.S, l), FixedPoint.divide(y * FixedPoint.S, l),
                           FixedPoint.divide(z * FixedPoint.S, l));
    }
    long coordinate(int axis) {
        return axis == 0 ? x : axis == 1 ? y : z;
    }
    static Vector3 axis(int axis, long value) {
        return new Vector3(axis == 0 ? value : 0, axis == 1 ? value : 0, axis == 2 ? value : 0);
    }
    public String toString() {
        return x + " " + y + " " + z;
    }
}
