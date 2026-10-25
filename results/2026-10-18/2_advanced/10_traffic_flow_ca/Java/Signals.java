import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

record Phase(int duration, String token, Set<String> greens) {}
final class Junction {
    final String node;
    final int offset;
    int cycle;
    final List<Phase> phases = new ArrayList<>();
    final List<Segment> incoming = new ArrayList<>();
    Junction(String node, int offset, List<String> tokens) {
        this.node = node; this.offset = offset;
        for (String token : tokens) { String[] pair = token.split(":"); int duration = Integer.parseInt(pair[0]); phases.add(new Phase(duration,pair[1],pair[1].equals("-") ? Set.of() : new HashSet<>(List.of(pair[1].split(","))))); cycle += duration; }
    }
    boolean green(String segment, int step) {
        if (phases.isEmpty()) return true; int time = (step - 1 + offset) % cycle;
        for (Phase phase : phases) { if (time < phase.duration()) return phase.greens().contains(segment); time -= phase.duration(); } return false;
    }
    List<String> planLines() {
        if (phases.isEmpty()) return List.of("JUNCTION " + node + " unsignalized");
        List<String> lines = new ArrayList<>(); lines.add("JUNCTION " + node + " signal cycle " + cycle + " offset " + offset); int start = 0;
        for (int i = 0; i < phases.size(); i++) { int end = start + phases.get(i).duration() - 1; lines.add("  PHASE " + (i + 1) + " " + start + "-" + end + " " + phases.get(i).token()); start = end + 1; } return lines;
    }
}
