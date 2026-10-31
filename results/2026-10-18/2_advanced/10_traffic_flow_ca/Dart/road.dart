import 'dart:math';
import 'signals.dart';
import 'vehicles.dart';

class Turn {
  final Segment target;
  final int weight;
  int vehicles = 0;
  Turn(this.target, this.weight);
}
class BusStop {
  final Segment segment;
  final int cell, dwell;
  int buses = 0;
  BusStop(this.segment, this.cell, this.dwell);
}
class Segment {
  final String id, start, end;
  final int length, lanes, limit;
  final List<List<int>> cells;
  final turns = <Turn>[];
  final changes = {'overtaking': 0, 'return': 0, 'avoidance': 0};
  Junction? junction;
  BusStop? stop;
  int entered = 0, vehicleSum = 0, speedSum = 0, maxVehicles = 0, greenSteps = 0, queueSum = 0, maxQueue = 0, failures = 0, passed = 0, blocked = 0;
  Segment(this.id, this.start, this.end, this.length, this.lanes, this.limit) : cells = List.generate(lanes, (_) => List.filled(length, 0));
  bool empty(int lane, int cell) => cells[lane - 1][cell] == 0;
  bool obstacle(int lane, int cell) => cells[lane - 1][cell] == -1;
  void put(int lane, int cell, int value) { cells[lane - 1][cell] = value; }
  void clear(int lane, int cell) => put(lane, cell, 0);
  int free(int lane, int cell, int cap) { var count = 0; while (count < cap && cell + count + 1 < length && empty(lane, cell + count + 1)) { count++; } return count; }
  int first(int lane) { for (var cell = 0; cell < length; cell++) { if (!empty(lane, cell)) return cell; } return length; }
  bool safe(int lane, int cell) { for (var x = max(0, cell - limit); x <= cell; x++) { if (!empty(lane, x)) return false; } return true; }
  List<int> vehicleNumbers(int lane) => cells[lane - 1].where((value) => value > 0).toList();
  String cellsText(int lane, List<Vehicle> vehicles) => cells[lane - 1].map((value) => value == 0 ? '.' : value == -1 ? '#' : '${vehicles[value - 1].speed}').join();
}
class Incident {
  final Segment segment;
  final int lane, cell, start, end;
  String state = 'planned';
  int? activeStart, activeEnd;
  Incident(this.segment, this.lane, this.cell, this.start, this.end);
  String? update(int step) {
    String? event;
    if (state == 'active' && step > end) { state = 'cleared'; segment.clear(lane, cell); event = 'INCIDENT_END'; }
    else if (state == 'planned' && step > end) { state = 'cancelled'; }
    else if (state == 'planned' && step >= start && segment.empty(lane, cell)) { state = 'active'; segment.put(lane, cell, -1); activeStart = step; event = 'INCIDENT_START'; }
    if (state == 'active') activeEnd = step; return event;
  }
}
