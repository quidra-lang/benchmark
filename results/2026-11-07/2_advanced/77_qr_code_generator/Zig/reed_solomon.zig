const b = @import("bitstream.zig");
const Words = b.Words;
pub const Correction = struct { syndromes: Words, corrected: Words, positions: Words = &.{}, success: bool = true };
pub const ReedSolomon = struct {
    exp: [255]i64 = @splat(0),
    log: [256]i64 = @splat(0),
    pub fn init() ReedSolomon {
        var self: ReedSolomon = .{};
        self.exp[0] = 1;
        for (1..255) |i| {
            const doubled = self.exp[i - 1] * 2;
            self.exp[i] = if (doubled >= 256) doubled ^ 285 else doubled;
        }
        for (self.exp, 0..) |value, i| self.log[b.u(value)] = b.n(i);
        return self;
    }
    pub fn multiply(self: *const ReedSolomon, left: i64, right: i64) i64 {
        return if (left != 0 and right != 0) self.exp[b.u(@mod(self.log[b.u(left)] + self.log[b.u(right)],
             255))] else 0;
    }
    pub fn divide(self: *const ReedSolomon, left: i64, right: i64) i64 {
        return if (left != 0) self.exp[b.u(@mod(self.log[b.u(left)] - self.log[b.u(right)] + 255, 255))] else 0;
    }
    fn generator(self: *const ReedSolomon, degree: i64) Words {
        var coefficients: Words = &.{1};
        for (0..b.u(degree)) |exponent| {
            const product = b.alloc(i64, coefficients.len + 1);
            @memset(product, 0);
            for (coefficients, 0..) |coefficient, i| {
                product[i] ^= coefficient;
                product[i + 1] ^= self.multiply(coefficient, self.exp[exponent]);
            }
            coefficients = product;
        }
        return coefficients;
    }
    pub fn parity(self: *const ReedSolomon, data: Words, degree: i64) Words {
        const polynomial = self.generator(degree);
        const remainder = b.alloc(i64, data.len + b.u(degree));
        @memset(remainder, 0);
        @memcpy(remainder[0..data.len], data);
        for (0..data.len) |i| {
            const leading = remainder[i];
            if (leading != 0) for (polynomial, 0..) |coefficient, j| {
                remainder[i + j] ^= self.multiply(leading, coefficient);
            };
        }
        return remainder[data.len..];
    }
    pub fn syndromes(self: *const ReedSolomon, words: Words, degree: i64) Words {
        const out = b.alloc(i64, b.u(degree));
        for (out, 0..) |*value, j| {
            value.* = 0;
            for (words) |word| value.* = self.multiply(value.*, self.exp[j]) ^ word;
        }
        return out;
    }
    fn polynomial(self: *const ReedSolomon, coefficients: Words, argument: i64) i64 {
        var value: i64 = 0;
        var i = coefficients.len;
        while (i > 0) {
            i -= 1;
            value = self.multiply(value, argument) ^ coefficients[i];
        }
        return value;
    }
    pub fn correct(self: *const ReedSolomon, received: Words, degree: i64) Correction {
        var out: Correction = .{ .syndromes = self.syndromes(received, degree), .corrected = received };
        if (allZero(out.syndromes)) return out;
        const locator = b.alloc(i64, b.u(degree + 1));
        @memset(locator, 0);
        locator[0] = 1;
        var previous = b.dupe(i64, locator);
        var length: i64 = 0;
        var shift: i64 = 1;
        var beta: i64 = 1;
        for (0..b.u(degree)) |q| {
            var delta = out.syndromes[q];
            for (1..b.u(length + 1)) |i| delta ^= self.multiply(locator[i], out.syndromes[q - i]);
            if (delta == 0) {
                shift += 1;
                continue;
            }
            const saved = b.dupe(i64, locator);
            const multiplier = self.divide(delta, beta);
            var i: i64 = 0;
            while (i < degree + 1 - shift) : (i += 1) locator[b.u(i + shift)] ^= self.multiply(multiplier,
                 previous[b.u(i)]);
            if (2 * length <= b.n(q)) {
                length = b.n(q) + 1 - length;
                previous = saved;
                beta = delta;
                shift = 1;
            } else shift += 1;
        }
        if (length > @divTrunc(degree, 2)) {
            out.success = false;
            return out;
        }
        const coefficients = locator[0..b.u(length + 1)];
        var positions: @import("std").ArrayList(i64) = .empty;
        const count = b.n(received.len);
        for (0..received.len) |i| if (self.polynomial(coefficients, self.exp[b.u(@mod(255 - (count - 1 - b.n(i)),
             255))]) == 0) b.append(i64, &positions, b.n(i));
        if (b.n(positions.items.len) != length) {
            out.success = false;
            return out;
        }
        const omega = b.alloc(i64, b.u(degree));
        @memset(omega, 0);
        const derivative = b.alloc(i64, b.u(length));
        @memset(derivative, 0);
        for (out.syndromes, 0..) |syndrome, i| for (coefficients, 0..) |coefficient, j| if (i + j < b.u(degree)) {
            omega[i + j] ^= self.multiply(syndrome, coefficient);
        };
        var h: i64 = 1;
        while (h <= length) : (h += 2) derivative[b.u(h - 1)] = locator[b.u(h)];
        const corrected = b.dupe(i64, received);
        for (positions.items) |i| {
            const location = self.exp[b.u(@mod(count - 1 - i, 255))];
            const inverse = self.exp[b.u(@mod(255 - (count - 1 - i), 255))];
            const denominator = self.polynomial(derivative, inverse);
            if (denominator == 0) {
                out.success = false;
                return out;
            }
            corrected[b.u(i)] ^= self.multiply(location, self.divide(self.polynomial(omega, inverse), denominator));
        }
        if (!allZero(self.syndromes(corrected, degree))) {
            out.success = false;
            return out;
        }
        var changed: @import("std").ArrayList(i64) = .empty;
        for (positions.items) |i| if (corrected[b.u(i)] != received[b.u(i)]) b.append(i64, &changed, i);
        out.corrected = corrected;
        out.positions = changed.items;
        return out;
    }
};
fn allZero(words: Words) bool {
    for (words) |value| if (value != 0) return false;
    return true;
}
