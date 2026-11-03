part of 'main.dart';

class Section {
  final String name;
  final int length, row, first, last;
  bool failed = false;
  final List<Train> occupants = [];
  Route? route;
  final Set<Route> overlaps = {};
  int occupiedTicks = 0, lockedTicks = 0;
  final Set<Train> trains = {};
  Section(this.name, this.length, this.row, this.first, this.last);
  bool get occupied => failed || occupants.isNotEmpty;
}

class PointLock {
  final Route route;
  final String position;
  PointLock(this.route, this.position);
}

class Point {
  final String name, side;
  final Section common, normal, reverse;
  final int row, col;
  String position = 'N', target = '';
  bool moving = false, failed = false;
  int completion = -1, throws = 0, lockedTicks = 0, movingTicks = 0;
  final List<PointLock> locks = [];
  Point(
    this.name,
    this.side,
    this.common,
    this.normal,
    this.reverse,
    this.row,
    this.col,
  );
  bool get detected => !moving && !failed;
}

class Signal {
  final String name, direction;
  final Section section;
  final int row, col;
  String aspect = 'RED';
  int red = 0, yellow = 0, green = 0, passes = 0;
  Signal(this.name, this.section, this.direction, this.row, this.col);
}

class Buffer {
  final String name, end;
  final Section section;
  final int row, col;
  Buffer(this.name, this.section, this.end, this.row, this.col);
}

class Boundary {
  final String name, end;
  final Section section;
  Boundary(this.name, this.section, this.end);
}

class Label {
  final int row, col;
  final String text;
  Label(this.row, this.col, this.text);
}

class Endpoint {
  final String kind, name, branch;
  final Section? section;
  final Point? point;
  Endpoint(
    this.kind, {
    this.name = '',
    this.branch = '',
    this.section,
    this.point,
  });
}

String endKey(Section section, String end) => '${section.name}:$end';

class Layout {
  final List<Section> sections = [];
  final List<Point> points = [];
  final List<Signal> signals = [];
  final List<Buffer> buffers = [];
  final List<Boundary> boundaries = [];
  final List<Label> labels = [];
  final Map<String, Section> sectionByName = {};
  final Map<String, Point> pointByName = {};
  final Map<String, Signal> signalByName = {};
  final Map<String, Buffer> bufferByName = {};
  final Map<String, Boundary> boundaryByName = {};
  final Map<String, Endpoint> ends = {};
  final Map<String, Signal> signalAt = {};
  int height = 0, width = 0;
  void position(int row, int col) {
    height = max(height, row + 1);
    width = max(width, col + 1);
  }

  Endpoint beyond(Section section, String direction) {
    final e = ends[endKey(section, direction == 'DOWN' ? 'L' : 'R')]!;
    if (e.kind != 'point') return e;
    final p = e.point!;
    if (p.moving) return Endpoint('impassable');
    final selected = p.position == 'R' ? p.reverse : p.normal;
    if (e.branch == 'common') return Endpoint('section', section: selected);
    return selected != section
        ? Endpoint('impassable')
        : Endpoint('section', section: p.common);
  }
}

Layout readLayout() {
  final l = Layout();
  for (final line in readLines('input/layout.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'SECTION':
        final s = Section(
          a[1],
          number(a[2]),
          number(a[3]),
          number(a[4]),
          number(a[5]),
        );
        l.sections.add(s);
        l.sectionByName[s.name] = s;
        l.position(s.row, s.last);
        break;
      case 'JOINT':
        final x = l.sectionByName[a[1]]!, y = l.sectionByName[a[2]]!;
        l.ends[endKey(x, 'R')] = Endpoint('section', section: y);
        l.ends[endKey(y, 'L')] = Endpoint('section', section: x);
        break;
      case 'POINT':
        final p = Point(
          a[1],
          a[2],
          l.sectionByName[a[3]]!,
          l.sectionByName[a[4]]!,
          l.sectionByName[a[5]]!,
          number(a[6]),
          number(a[7]),
        );
        l.points.add(p);
        l.pointByName[p.name] = p;
        l.position(p.row, p.col);
        final branchEnd = p.side == 'L' ? 'R' : 'L';
        l.ends[endKey(p.common, p.side)] = Endpoint(
          'point',
          point: p,
          branch: 'common',
        );
        l.ends[endKey(p.normal, branchEnd)] = Endpoint(
          'point',
          point: p,
          branch: 'normal',
        );
        l.ends[endKey(p.reverse, branchEnd)] = Endpoint(
          'point',
          point: p,
          branch: 'reverse',
        );
        break;
      case 'SIGNAL':
        final g = Signal(
          a[1],
          l.sectionByName[a[2]]!,
          a[3],
          number(a[4]),
          number(a[5]),
        );
        l.signals.add(g);
        l.signalByName[g.name] = g;
        l.signalAt['${g.section.name}:${g.direction}'] = g;
        l.position(g.row, g.col);
        break;
      case 'BUFFER':
        final b = Buffer(
          a[1],
          l.sectionByName[a[2]]!,
          a[3],
          number(a[4]),
          number(a[5]),
        );
        l.buffers.add(b);
        l.bufferByName[b.name] = b;
        l.ends[endKey(b.section, b.end)] = Endpoint('buffer', name: b.name);
        l.position(b.row, b.col);
        break;
      case 'BOUNDARY':
        final b = Boundary(a[1], l.sectionByName[a[2]]!, a[3]);
        l.boundaries.add(b);
        l.boundaryByName[b.name] = b;
        l.ends[endKey(b.section, b.end)] = Endpoint('boundary', name: b.name);
        break;
      case 'LABEL':
        final label = Label(number(a[1]), number(a[2]), a[3]);
        l.labels.add(label);
        l.position(label.row, label.col + label.text.length - 1);
        break;
    }
  }
  return l;
}
