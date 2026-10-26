import 'dart:math' as math;
import 'grid_map.dart';

int squaredDistance(Point first, Point second) {
  final dx = first.$1 - second.$1;
  final dy = first.$2 - second.$2;
  return dx * dx + dy * dy;
}
int integerSqrt(int number) {
  var low = 0;
  var high = number + 1;
  while (high - low > 1) {
    final middle = (low + high) ~/ 2;
    if (middle <= number ~/ middle) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low;
}
(Point, bool) advance(Point point, Point goal, int step) {
  final dx = goal.$1 - point.$1;
  final dy = goal.$2 - point.$2;
  final squared = dx * dx + dy * dy;
  if (squared <= step * step) return (goal, true);
  final length = integerSqrt(squared);
  return ((point.$1 + dx * step ~/ length, point.$2 + dy * step ~/ length), false);
}
int damageDealt(int hp, int power, int armor) => math.min(hp, math.max(1, power - armor));
class Effect {
  int strength = 0;
  int remaining = 0;
  int? source;
  bool get active => remaining > 0;
  void receive(int amount, int duration, [int? tower]) {
    if (amount > strength) {
      strength = amount;
      remaining = duration;
      source = tower;
    } else if (amount == strength) {
      remaining = math.max(remaining, duration);
    }
  }
  void advanceTime() {
    remaining--;
    if (remaining == 0) {
      strength = 0;
      source = null;
    }
  }
}
class Projectile {
  final int number;
  final int tower;
  final int target;
  Point position;
  Point aim;
  final String targets;
  final int power;
  final int speed;
  final int splash;
  final int slowRate;
  final int slowTime;
  final int burnAmount;
  final int burnTime;
  Projectile(this.number, this.tower, this.target, this.position, this.aim, this.targets, this.power,
      this.speed, this.splash, this.slowRate, this.slowTime, this.burnAmount, this.burnTime);
  bool fly() {
    if (speed == 0) return true;
    final (point, arrived) = advance(position, aim, speed);
    position = point;
    return arrived;
  }
}
