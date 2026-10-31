import 'dart:math';
import 'road.dart';

class VehicleClass {
  final String name;
  final int vmax, weight;
  final bool overtakes, stops;
  VehicleClass(this.name, this.vmax, this.weight, this.overtakes, this.stops);
}
class Vehicle {
  final int number, arrival;
  final VehicleClass kind;
  final String source;
  int? inserted, exited;
  String? sink;
  Segment? segment;
  Turn? turn;
  int lane = 0, cell = 0, speed = 0, steps = 0, distance = 0, stoppedSteps = 0, stopCount = 0, laneChanges = 0, dwell = 0;
  final route = <String>[], completedStops = <String>{};
  Vehicle(this.number, this.kind, this.source, this.arrival);
  int maxSpeed() => min(kind.vmax, segment!.limit);
  void place(Segment target, int lane, int cell) { segment?.clear(this.lane, this.cell); target.put(lane, cell, number); segment = target; this.lane = lane; this.cell = cell; }
  void leave() { segment!.clear(lane, cell); segment = null; }
  bool headingForStop() { final current = segment, stop = segment?.stop; return current != null && kind.stops && stop != null && !completedStops.contains(current.id) && cell <= stop.cell; }
  int travelTime() => exited! - inserted! + 1;
}
int randomSlowdown(int speed, int previous, int value, int dawdle, int dawdleStopped) => speed > 0 && value % 1000 < (previous == 0 ? dawdleStopped : dawdle) ? speed - 1 : speed;
