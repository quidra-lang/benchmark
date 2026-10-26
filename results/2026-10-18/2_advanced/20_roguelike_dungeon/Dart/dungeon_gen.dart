import 'dart:math' as math;
import 'entities.dart';
import 'minstd.dart';

class Room {
  final int x;
  final int y;
  final int width;
  final int height;
  Room(this.x, this.y, this.width, this.height);
  Point get center => Point(x + width ~/ 2, y + height ~/ 2);
}
class Region {
  final int x;
  final int y;
  final int width;
  final int height;
  Region? first;
  Region? second;
  var leaf = -1;
  Region(this.x, this.y, this.width, this.height);
}

class Level {
  final int depth;
  final int width;
  final int height;
  final List<List<String>> terrain;
  final List<List<String>> memory;
  final rooms = <Room>[];
  late Point arrival;
  late Point target;
  late int arrivalRoom;
  final monsters = <Monster>[];
  final items = <Item>[];
  var monstersCreated = 0, itemsPlaced = 0, kills = 0, picked = 0;
  Level(this.depth, this.width, this.height)
      : terrain = List.generate(height, (_) => List.filled(width, ' ')), memory = List.generate(height, (_) => List.filled(width, ' '));
  Monster? monsterAt(int x, int y) {
    for (final monster in monsters) {
      if (monster.position == Point(x, y)) {
        return monster;
      }
    }
    return null;
  }
  Item? itemAt(int x, int y) {
    for (final item in items) {
      if (item.position == Point(x, y)) {
        return item;
      }
    }
    return null;
  }
  Point drawInteriorCell(Minstd rng, int index) {
    final room = rooms[index];
    final x = room.x + 1 + rng.rnd(room.width - 2);
    final y = room.y + 1 + rng.rnd(room.height - 2);
    return Point(x, y);
  }
  (int, Point) drawRoomCell(Minstd rng) {
    final index = rng.rnd(rooms.length);
    return (index, drawInteriorCell(rng, index));
  }
}

class LevelGenerator {
  final Minstd rng;
  final int minSize;
  final int maxSplit;
  final int roomMin;
  final int roomMax;
  LevelGenerator(this.rng, this.minSize, this.maxSplit, this.roomMin, this.roomMax);
  Level generate(int depth, int width, int height) {
    final level = Level(depth, width, height);
    final root = Region(0, 0, width, height);
    final leaves = <Region>[];
    split(root, 0, leaves);
    for (final leaf in leaves) {
      level.rooms.add(makeRoom(level, leaf));
    }
    connect(level, root);
    final (room, point) = level.drawRoomCell(rng);
    level.terrain[point.y][point.x] = '<';
    level.arrival = point;
    level.arrivalRoom = room;
    var other = rng.rnd(level.rooms.length - 1);
    if (other >= room) {
      other++;
    }
    level.target = level.drawInteriorCell(rng, other);
    return level;
  }

  void split(Region region, int depth, List<Region> leaves) {
    final cv = region.width >= 2 * minSize, ch = region.height >= 2 * minSize;
    if (depth == maxSplit || (!cv && !ch)) {
      region.leaf = leaves.length;
      leaves.add(region);
      return;
    }
    var vertical = cv;
    if (cv && ch) {
      if (4 * region.width >= 5 * region.height) {
        vertical = true;
      } else if (4 * region.height >= 5 * region.width) {
        vertical = false;
      } else {
        vertical = rng.rnd(2) == 0;
      }
    }
    if (vertical) {
      final cut = minSize + rng.rnd(region.width - 2 * minSize + 1);
      region.first = Region(region.x, region.y, cut, region.height);
      region.second = Region(region.x + cut, region.y, region.width - cut, region.height);
    } else {
      final cut = minSize + rng.rnd(region.height - 2 * minSize + 1);
      region.first = Region(region.x, region.y, region.width, cut);
      region.second = Region(region.x, region.y + cut, region.width, region.height - cut);
    }
    split(region.first!, depth + 1, leaves);
    split(region.second!, depth + 1, leaves);
  }

  Room makeRoom(Level level, Region region) {
    final width = roomMin + rng.rnd(math.min(roomMax, region.width - 1) - roomMin + 1);
    final height = roomMin + rng.rnd(math.min(roomMax, region.height - 1) - roomMin + 1);
    final x = region.x + rng.rnd(region.width - width);
    final y = region.y + rng.rnd(region.height - height);
    for (var row = y; row < y + height; row++) {
      for (var column = x; column < x + width; column++) {
        level.terrain[row][column] = row == y || row == y + height - 1 ? '-' : column == x || column == x + width - 1 ? '|' : '.';
      }
    }
    return Room(x, y, width, height);
  }

  List<int> connect(Level level, Region region) {
    if (region.leaf >= 0) {
      return [region.leaf];
    }
    final first = connect(level, region.first!);
    final second = connect(level, region.second!);
    var aBest = -1, bBest = -1, bestDistance = 0;
    for (final a in first) {
      for (final b in second) {
        final pa = level.rooms[a].center, pb = level.rooms[b].center;
        final distance = (pa.x - pb.x).abs() + (pa.y - pb.y).abs();
        if (aBest < 0 || distance < bestDistance) {
          aBest = a;
          bBest = b;
          bestDistance = distance;
        }
      }
    }
    dig(level, level.rooms[aBest].center, level.rooms[bBest].center, rng.rnd(2) == 0);
    return [...first, ...second];
  }

  void dig(Level level, Point start, Point end, bool horizontal) {
    void digCell(int x, int y) {
      if (level.terrain[y][x] == ' ') {
        level.terrain[y][x] = '#';
      } else if (level.terrain[y][x] == '-' || level.terrain[y][x] == '|') {
        level.terrain[y][x] = '+';
      }
    }
    void horizontalLeg(int y, int x0, int x1) {
      final step = x1 >= x0 ? 1 : -1;
      for (var x = x0;; x += step) {
        digCell(x, y);
        if (x == x1) {
          break;
        }
      }
    }
    void verticalLeg(int x, int y0, int y1) {
      final step = y1 >= y0 ? 1 : -1;
      for (var y = y0;; y += step) {
        digCell(x, y);
        if (y == y1) {
          break;
        }
      }
    }
    if (horizontal) {
      horizontalLeg(start.y, start.x, end.x);
      verticalLeg(end.x, start.y, end.y);
    } else {
      verticalLeg(start.x, start.y, end.y);
      horizontalLeg(end.y, start.x, end.x);
    }
  }
}
