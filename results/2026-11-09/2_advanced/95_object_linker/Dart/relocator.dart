part of 'main.dart';

const relocationTypes = [
  'ABS32',
  'REL32',
  'ABS16',
  'HI16',
  'LO16',
  'GPREL16',
  'CALL24',
];
int width(String kind) => switch (kind) {
  'ABS32' || 'REL32' => 4,
  'CALL24' => 3,
  _ => 2,
};
int modulo(int a, int b) => a % b;
int floorDivide(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
(int, int, bool) relocationField(String kind, int s, int a, int p, int gp) {
  var value = s + a;
  if (kind == 'REL32' || kind == 'CALL24') value -= p;
  if (kind == 'GPREL16') value -= gp;
  final valid = switch (kind) {
    'ABS32' || 'HI16' => value >= -(1 << 31) && value < 1 << 32,
    'REL32' => value >= -(1 << 31) && value < 1 << 31,
    'ABS16' => value >= -(1 << 15) && value < 1 << 16,
    'GPREL16' => value >= -(1 << 15) && value < 1 << 15,
    'CALL24' => value >= -(1 << 25) && value < 1 << 25,
    _ => true,
  };
  final field = switch (kind) {
    'ABS32' || 'REL32' => modulo(value, 1 << 32),
    'HI16' => modulo((modulo(value, 1 << 32) + 32768) ~/ 65536, 65536),
    'CALL24' => modulo(floorDivide(value, 4), 1 << 24),
    _ => modulo(value, 65536),
  };
  return (value, field, valid);
}

bool unpaired(List<Relocation> relocations, int index) {
  final r = relocations[index];
  if (r.type != 'HI16') return false;
  if (index + 1 == relocations.length) return true;
  final next = relocations[index + 1];
  return next.type != 'LO16' ||
      !identical(next.symbol, r.symbol) ||
      next.addend != r.addend;
}

void littleEndian(List<int> data, int offset, int value, int n) {
  for (var i = 0; i < n; i++) data[offset + i] = value >> (8 * i) & 255;
}
