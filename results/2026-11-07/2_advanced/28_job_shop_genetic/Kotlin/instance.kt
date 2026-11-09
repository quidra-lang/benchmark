import java.nio.file.Files
import java.nio.file.Path

class Operation(val ident: Int, val job: Int, val index: Int, val machine: Int, val duration: Int, val head: Int) {
    var tail = 0;
    var previous = -1;
    var next = -1
    val code get() = "J$job-$index"
}
data class Job(val number: Int, val operations: List<Operation>, val work: Int)
data class Machine(val number: Int, val operations: List<Operation>, val load: Int, val head: Int, val tail: Int) {
    val bound = head + load + tail
}
class Instance {
    val machineCount: Int
    val jobs = mutableListOf<Job>()
    val operations = mutableListOf<Operation>()
    val machines = mutableListOf<Machine>()
    val errors = mutableListOf<String>()
    val named = mutableMapOf<Int, Job>()
    val durations: IntArray
    init {
        val lines = Files.readAllLines(Path.of("input/instance.txt"));
        val header = lines[0].split(" ");
        machineCount = header[1].toInt()
        for (number in 1..header[0].toInt()) {
            val steps = mutableListOf<Operation>();
            val used = mutableSetOf<Int>();
            var head = 0;
            var valid = true
            for ((k, token) in lines[number].split(" ").withIndex()) {
                val pair = token.split(":");
                val machine = pair[0].toInt();
                val duration = pair[1].toInt()
                val error = when {
                    machine !in 1..machineCount -> "unknown machine $machine";
                    duration !in 1..99 -> "bad duration $duration";
                    machine in used -> "repeated machine $machine";
                    else -> ""
                }
                if (error.isNotEmpty()) {
                    errors.add("job $number operation ${k + 1}: $error");
                    valid = false;
                    break
                }
                used.add(machine);
                steps.add(Operation(operations.size + k, number, k + 1, machine, duration, head));
                head += duration
            }
            if (!valid) continue
            for ((k, operation) in steps.withIndex()) {
                operation.tail = head - operation.head - operation.duration;
                if (k > 0) operation.previous = operation.ident - 1;
                if (k + 1 < steps.size) operation.next = operation.ident + 1
            }
            val job = Job(number, steps, head);
            jobs.add(job);
            named[number] = job;
            operations.addAll(steps)
        }
        durations = operations.map {
            it.duration
        }.toIntArray()
        for (m in 1..machineCount) {
            val tasks = operations.filter {
                it.machine == m
            };
            machines.add(Machine(m, tasks, tasks.sumOf {
                it.duration
            }, tasks.minOf {
                it.head
            }, tasks.minOf {
                it.tail
            }))
        }
    }
}
