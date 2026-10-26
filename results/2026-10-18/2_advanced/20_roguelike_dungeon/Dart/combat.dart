import 'dart:math' as math;
import 'minstd.dart';

class Dice {
  final int count;
  final int sides;
  const Dice(this.count, this.sides);
  int roll(Minstd rng) => rng.roll(count, sides);
}
Dice parseDice(String text) {
  final parts = text.split('d');
  return Dice(int.parse(parts.first), int.parse(parts[1]));
}

(String, int) resolveAttack(Minstd rng, int toHit, int defense, Dice dice, int bonus) {
  final roll = 1 + rng.rnd(20);
  if (roll == 1) {
    return ('miss', 0);
  }
  var outcome = 'hit';
  var damage = 0;
  if (roll == 20) {
    outcome = 'critical';
    damage = dice.roll(rng) + dice.roll(rng) + bonus;
  } else if (roll + toHit >= defense) {
    damage = dice.roll(rng) + bonus;
  } else {
    return ('miss', 0);
  }
  return (outcome, math.max(damage, 1));
}
