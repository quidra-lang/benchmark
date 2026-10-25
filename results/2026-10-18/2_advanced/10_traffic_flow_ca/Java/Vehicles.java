import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

record VehicleClass(String name, int vmax, long weight, boolean overtakes, boolean stops) {}
final class Vehicle {
    final int number, arrival;
    final VehicleClass kind;
    final String source;
    int inserted, exited, lane, cell, speed, dwell;
    String sink = "";
    Segment segment;
    Turn turn;
    final List<String> route = new ArrayList<>();
    final Set<String> completedStops = new HashSet<>();
    long steps, distance, stoppedSteps, stopCount, laneChanges;
    Vehicle(int number, VehicleClass kind, String source, int arrival) { this.number = number; this.kind = kind; this.source = source; this.arrival = arrival; }
    int maxSpeed() { return Math.min(kind.vmax(),segment.limit); }
    boolean headingForStop() { return segment != null && kind.stops() && segment.stop != null && !completedStops.contains(segment.id) && cell <= segment.stop.cell; }
    int travelTime() { return exited - inserted + 1; }
    void place(Segment target, int lane, int cell) {
        if (segment != null) segment.put(this.lane,this.cell,0); target.put(lane,cell,number); segment = target; this.lane = lane; this.cell = cell;
    }
    void leave() { segment.put(lane,cell,0); segment = null; }
    static int slowdown(int speed, int previous, long draw, int dawdle, int stopped) { return speed > 0 && draw % 1000 < (previous == 0 ? stopped : dawdle) ? speed - 1 : speed; }
}
