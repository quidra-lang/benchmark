import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class Turn {
    final Segment target;
    final long weight;
    long vehicles;
    Turn(Segment target, long weight) { this.target = target; this.weight = weight; }
}
final class BusStop {
    final Segment segment;
    final int cell, dwell;
    long buses;
    BusStop(Segment segment, int cell, int dwell) { this.segment = segment; this.cell = cell; this.dwell = dwell; }
}
final class Segment {
    final String id, start, end;
    final int length, lanes, limit;
    final int[][] cells;
    Junction junction;
    BusStop stop;
    final List<Turn> turns = new ArrayList<>();
    long entered, vehicleSum, speedSum, maxVehicles, greenSteps, queueSum, maxQueue, failures, passed, blocked;
    final long[] changes = new long[3];
    Segment(String id, String start, String end, int length, int lanes, int limit) {
        this.id = id; this.start = start; this.end = end; this.length = length; this.lanes = lanes; this.limit = limit; cells = new int[lanes][length];
    }
    boolean empty(int lane, int cell) { return cells[lane - 1][cell] == 0; }
    void put(int lane, int cell, int value) { cells[lane - 1][cell] = value; }
    int free(int lane, int cell, int cap) {
        int count = 0; while (count < cap && cell + count + 1 < length && empty(lane,cell + count + 1)) count++; return count;
    }
    int first(int lane) { for (int cell = 0; cell < length; cell++) if (!empty(lane,cell)) return cell; return length; }
    boolean safe(int lane, int cell) { for (int x = Math.max(0,cell - limit); x <= cell; x++) if (!empty(lane,x)) return false; return true; }
    List<Integer> numbers(int lane) { return Arrays.stream(cells[lane - 1]).filter(x -> x > 0).boxed().toList(); }
    String text(int lane, List<Vehicle> vehicles) {
        StringBuilder text = new StringBuilder(); for (int value : cells[lane - 1]) text.append(value == 0 ? '.' : value < 0 ? '#' : (char)('0' + vehicles.get(value - 1).speed)); return text.toString();
    }
}
final class Incident {
    final Segment segment;
    final int lane, cell;
    final long start, end;
    int activeStart, activeEnd;
    String state = "planned";
    Incident(Segment segment, int lane, int cell, long start, long end) { this.segment = segment; this.lane = lane; this.cell = cell; this.start = start; this.end = end; }
    String update(int step) {
        String event = "";
        if (state.equals("active") && step > end) { state = "cleared"; segment.put(lane,cell,0); event = "INCIDENT_END"; }
        else if (state.equals("planned") && step > end) state = "cancelled";
        else if (state.equals("planned") && step >= start && segment.empty(lane,cell)) { state = "active"; segment.put(lane,cell,-1); activeStart = step; event = "INCIDENT_START"; }
        if (state.equals("active")) activeEnd = step; return event;
    }
}
