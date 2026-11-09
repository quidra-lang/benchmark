import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class Operation {
    final int ident, job, index, machine, duration, head;
    int tail, previous = -1, next = -1;
    Operation(int ident, int job, int index, int machine, int duration, int head) {
        this.ident = ident;
        this.job = job;
        this.index = index;
        this.machine = machine;
        this.duration = duration;
        this.head = head;
    }
    String code() {
        return "J" + job + "-" + index;
    }
}
record Job(int number, List<Operation> operations, int work) {}
record Machine(int number, List<Operation> operations, int load, int head, int tail, int bound) {}
final class Instance {
    final int machineCount;
    final List<Job> jobs = new ArrayList<>();
    final List<Operation> operations = new ArrayList<>();
    final List<Machine> machines = new ArrayList<>();
    final List<String> errors = new ArrayList<>();
    final Map<Integer, Job> named = new HashMap<>();
    int[] durations;
    Instance() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/instance.txt"), StandardCharsets.US_ASCII);
        String[] header = lines.getFirst().split(" ");
        machineCount = Integer.parseInt(header[1]);
        for (int number = 1; number <= Integer.parseInt(header[0]); number++) {
            List<Operation> steps = new ArrayList<>();
            Set<Integer> used = new HashSet<>();
            int head = 0;
            boolean valid = true;
            String[] tokens = lines.get(number).split(" ");
            for (int k = 0; k < tokens.length; k++) {
                String[] pair = tokens[k].split(":");
                int machine = Integer.parseInt(pair[0]), duration = Integer.parseInt(pair[1]);
                String error = machine < 1 || machine > machineCount ? "unknown machine " + machine
                               : duration < 1 || duration > 99       ? "bad duration " + duration
                               : used.contains(machine)              ? "repeated machine " + machine
                                                                     : "";
                if (!error.isEmpty()) {
                    errors.add("job " + number + " operation " + (k + 1) + ": " + error);
                    valid = false;
                    break;
                }
                used.add(machine);
                steps.add(new Operation(operations.size() + k, number, k + 1, machine, duration, head));
                head += duration;
            }
            if (!valid)
                continue;
            for (int k = 0; k < steps.size(); k++) {
                Operation operation = steps.get(k);
                operation.tail = head - operation.head - operation.duration;
                if (k > 0)
                    operation.previous = operation.ident - 1;
                if (k + 1 < steps.size())
                    operation.next = operation.ident + 1;
            }
            Job job = new Job(number, steps, head);
            jobs.add(job);
            named.put(number, job);
            operations.addAll(steps);
        }
        durations = new int[operations.size()];
        for (Operation operation : operations)
            durations[operation.ident] = operation.duration;
        for (int m = 1; m <= machineCount; m++) {
            List<Operation> tasks = new ArrayList<>();
            int load = 0, head = Integer.MAX_VALUE, tail = Integer.MAX_VALUE;
            for (Operation operation : operations)
                if (operation.machine == m) {
                    tasks.add(operation);
                    load += operation.duration;
                    head = Math.min(head, operation.head);
                    tail = Math.min(tail, operation.tail);
                }
            machines.add(new Machine(m, tasks, load, head, tail, head + load + tail));
        }
    }
}
