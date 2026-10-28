import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import kotlin.math.abs
val commands = listOf("SOLVE","ENUM","CORE","QUEENS","PIGEON","COLOR","CHROMATIC")
val argumentTypes = mapOf("SOLVE" to listOf("file"),"ENUM" to listOf("file","limit"),"CORE" to listOf("file"),"QUEENS" to listOf("small","limit"),"PIGEON" to listOf("small","small","limit"),"COLOR" to listOf("graph","color","limit"),"CHROMATIC" to listOf("graph","color"))
class Graph(val name: String, val vertices: Int) {
    var invalid: String? = null;
    var maximumDegree = 0;
    var used = 0;
    val edges = mutableListOf<IntArray>();
    var degree = intArrayOf();
    var greedy = intArrayOf()
}
class Solution(val formula: CnfIo.Formula, val limit: Int) {
    val preparation = Preprocess.run(formula,limit == 1);
    val models = mutableListOf<BooleanArray>();
    val stats = Dpll.Stats();
    var trace = listOf<String>();
    var rounds = 0;
    var stop = "limit";
    fun status() = if (models.isEmpty()) "UNSAT" else "SAT"
}
data class Attempt(val colors: Int, val solution: Solution)
class Job(val number: Int, val text: String, val command: String, val arguments: List<String>) {
    var removed = 0;
    var rounds = 0;
    var colors = 0;
    var coreDecisions = 0;
    var coreConflicts = 0;
    var error: String? = null;
    var graph: Graph? = null;
    lateinit var formula: CnfIo.Formula;
    lateinit var solution: Solution;
    var stats = Dpll.Stats();
    val attempts = mutableListOf<Attempt>();
    val core = mutableListOf<Int>()
}
fun graphs(): Map<String,Graph> {
    val graphs = mutableMapOf<String,Graph>();
    var current: Graph? = null;
    val lines = Files.readAllLines(Path.of("input/graphs.txt"),StandardCharsets.US_ASCII)
    for (i in lines.indices) {
        val line = lines[i];
        if (current == null) {
            if (line.isEmpty() || line.startsWith("#")) continue;
            val parts = line.split(' ');
            current = Graph(parts[1],parts[2].toInt());
            continue
        };
        val graph = current ?: continue
        if (line == "END") {
            graph.edges.sortWith(compareBy<IntArray> {
                it[0]
            }.thenBy {
                it[1]
            });
            if (graph.invalid == null) greedy(graph);
            graphs[graph.name] = graph;
            current = null;
            continue
        };
        if (graph.invalid != null) continue
        val parts = line.split(' ');
        var error: String? = null
        if (parts.size != 2 || !CnfIo.number(parts[0]) || !CnfIo.number(parts[1])) error = "bad edge line"
        else {
            val a = parts[0].toInt();
            val b = parts[1].toInt();
            if (a !in 1..graph.vertices || b !in 1..graph.vertices) error = "vertex out of range" else if (a == b) error = "self loop" else {
                val first = minOf(a,b);
                val second = maxOf(a,b);
                if (graph.edges.any {
                    it[0] == first && it[1] == second
                }) error = "duplicate edge" else graph.edges.add(intArrayOf(first,second))
            }
        };
        if (error != null) graph.invalid = "$error at line ${i + 1}"
    }
    return graphs
}
fun greedy(graph: Graph) {
    graph.degree = IntArray(graph.vertices + 1);
    for (edge in graph.edges) {
        graph.degree[edge[0]]++;
        graph.degree[edge[1]]++
    };
    val order = (1..graph.vertices).sortedWith(compareByDescending<Int> {
        graph.degree[it]
    }.thenBy {
        it
    });
    val colors = IntArray(graph.vertices + 1);
    for (vertex in order) {
        val used = mutableSetOf<Int>();
        for (edge in graph.edges) {
            if (edge[0] == vertex) used.add(colors[edge[1]]);
            if (edge[1] == vertex) used.add(colors[edge[0]])
        };
        var color = 1;
        while (color in used) color++;
        colors[vertex] = color;
        graph.used = maxOf(graph.used,color);
        graph.maximumDegree = maxOf(graph.maximumDegree,graph.degree[vertex])
    };
    graph.greedy = colors.copyOfRange(1,colors.size)
}
fun jobs(): List<Job> {
    val jobs = mutableListOf<Job>();
    for (line in Files.readAllLines(Path.of("input/jobs.txt"),StandardCharsets.US_ASCII)) {
        if (line.isEmpty() || line.startsWith("#")) continue;
        val parts = line.split(' ');
        jobs.add(Job(jobs.size + 1,line,parts[0],parts.drop(1)))
    };
    return jobs
}
fun validate(job: Job, graphs: Map<String,Graph>): String? {
    val types = argumentTypes[job.command] ?: return "unknown command ${job.command}";
    if (job.arguments.size != types.size) return "wrong argument count";
    for (i in types.indices) {
        val token = job.arguments[i];
        val type = types[i];
        if (type == "file") {
            if (!Regex("[a-z0-9_]{1,20}\\.cnf").matches(token)) return "bad file name $token"
        } else if (type == "graph") {
            val graph = graphs[token] ?: return "unknown graph $token";
            if (graph.invalid != null) return "invalid graph $token: ${graph.invalid}";
            job.graph = graph
        } else {
            if (!CnfIo.number(token)) return "bad number $token";
            val value = token.toInt();
            val maximum = if (type == "small") 8 else if (type == "color") 6 else 200;
            if (value !in 1..maximum) return "out of range $token"
        }
    };
    return null
}
fun solve(formula: CnfIo.Formula, limit: Int): Solution {
    val solution = Solution(formula,limit);
    if (solution.preparation.empty != 0) {
        solution.stop = "preprocess";
        return solution
    };
    val search = solution.preparation.clauses.toMutableList();
    while (solution.models.size < limit) {
        solution.rounds++;
        val result = Dpll.run(formula.variables,search);
        if (solution.rounds == 1) solution.trace = result.trace;
        solution.stats.add(result.stats);
        val model = result.model;
        if (model == null) {
            solution.stop = "all";
            break
        };
        for (x in 1..formula.variables) if (solution.preparation.fixed[x] != 0) model[x] = solution.preparation.fixed[x] > 0;
        solution.models.add(model);
        search.add(solution.preparation.active.map {
            x -> if (model[x]) -x else x
        }.toIntArray())
    };
    return solution
}
fun core(job: Job) {
    val count = job.formula.clauses.size;
    val retained = BooleanArray(count) {
        true
    };
    for (i in 0 until count) {
        val clauses = job.formula.clauses.filterIndexed {
            j, _ -> retained[j] && j != i
        };
        val test = solve(CnfIo.Formula(job.formula.variables,clauses),1);
        job.coreDecisions += test.stats.decisions;
        job.coreConflicts += test.stats.conflicts;
        if (test.models.isEmpty()) retained[i] = false
    };
    for (i in 0 until count) if (retained[i]) job.core.add(i + 1)
}
fun execute(job: Job) {
    if (job.command == "CHROMATIC") {
        val maximum = job.arguments[1].toInt();
        val graph = job.graph!!;
        for (k in 1..maximum) {
            val solution = solve(Encoders.coloring(graph.vertices,graph.edges,k),1);
            job.attempts.add(Attempt(k,solution));
            job.stats.add(solution.stats);
            job.removed += solution.preparation.removed();
            job.rounds += solution.rounds;
            job.solution = solution;
            job.formula = solution.formula;
            job.colors = k;
            if (solution.models.isNotEmpty()) break
        };
        return
    }
    var limit = 1
    when (job.command) {
        "SOLVE","ENUM","CORE" -> {
            job.formula = CnfIo.read(job.arguments[0]);
            if (job.command == "ENUM") limit = job.arguments[1].toInt()
        }
        "QUEENS" -> {
            job.formula = Encoders.queens(job.arguments[0].toInt());
            limit = job.arguments[1].toInt()
        }
        "PIGEON" -> {
            job.formula = Encoders.pigeon(job.arguments[0].toInt(),job.arguments[1].toInt());
            limit = job.arguments[2].toInt()
        }
        else -> {
            job.colors = job.arguments[1].toInt();
            val graph = job.graph!!;
            job.formula = Encoders.coloring(graph.vertices,graph.edges,job.colors);
            limit = job.arguments[2].toInt()
        }
    }
    job.solution = solve(job.formula,limit);
    job.stats = job.solution.stats;
    job.removed = job.solution.preparation.removed();
    job.rounds = job.solution.rounds;
    if (job.command == "CORE" && job.solution.models.isEmpty()) core(job)
}
fun trueLiteral(model: BooleanArray, literal: Int) = if (literal > 0) model[literal] else !model[-literal]
fun clauseTrue(model: BooleanArray, clause: IntArray) = clause.any {
    trueLiteral(model,it)
}
fun satisfies(model: BooleanArray, clauses: List<IntArray>) = clauses.all {
    clauseTrue(model,it)
}
fun analysis(solution: Solution, extended: Boolean): List<String> {
    val lines = mutableListOf<String>();
    if (solution.models.isEmpty()) return lines;
    val clauses = solution.formula.clauses;
    val first = solution.models.first();
    var failureModel = 0;
    var failureClause = 0
    for (i in solution.models.indices) {
        for (j in clauses.indices) if (!clauseTrue(solution.models[i],clauses[j])) {
            failureModel = i + 1;
            failureClause = j + 1;
            break
        };
        if (failureModel != 0) break
    }
    val distribution = clauses.map {
        clause -> clause.count {
            trueLiteral(first,it)
        }
    };
    lines.add(if (failureModel == 0) "verify ok models=${solution.models.size} clauses=${clauses.size} true_literals=${Report.frequency(distribution)}" else "verify failed model=$failureModel clause=$failureClause")
    val safe = mutableListOf<Int>();
    for (x in 1 until first.size) {
        val flipped = first.copyOf();
        flipped[x] = !flipped[x];
        if (satisfies(flipped,clauses)) safe.add(x)
    };
    lines.add("flips safe=${safe.size} variables=${Report.numbers(safe)}")
    if (extended && solution.models.size >= 2) {
        var pairs = 0;
        var minimum = Int.MAX_VALUE;
        var maximum = 0;
        for (i in solution.models.indices) for (j in i + 1 until solution.models.size) {
            val distance = (1 until first.size).count {
                solution.models[i][it] != solution.models[j][it]
            };
            pairs++;
            minimum = minOf(minimum,distance);
            maximum = maxOf(maximum,distance)
        };
        lines.add("diversity pairs=$pairs min_distance=$minimum max_distance=$maximum")
    }
    if (extended && solution.stop == "all") {
        val backbone = (1 until first.size).filter {
            x -> solution.models.all {
                it[x] == first[x]
            }
        }.map {
            if (first[it]) it else -it
        };
        lines.add("backbone size=${backbone.size} literals=${Report.numbers(backbone)}")
    };
    return lines
}
fun lengths(clauses: List<IntArray>) = clauses.map {
    it.size
}
fun literals(clauses: List<IntArray>) = clauses.sumOf {
    it.size
}
fun heading(job: Job) = "JOB ${job.number} ${job.text}"
fun graphLine(graph: Graph) = "graph vertices=${graph.vertices} edges=${graph.edges.size} max_degree=${graph.maximumDegree} greedy=${graph.used}"
fun resultLines(job: Job): List<String> {
    val lines = mutableListOf(heading(job));
    if (job.error != null) {
        lines.add("error ${job.error}");
        return lines
    };
    val solution = job.solution
    if (job.command == "CHROMATIC") {
        lines.add(graphLine(job.graph!!));
        for (attempt in job.attempts) {
            val result = attempt.solution;
            lines.add("attempt k=${attempt.colors} clauses=${result.formula.clauses.size} removed=${result.preparation.removed()} result=${result.status()} stop=${result.stop} ${Report.search(result.stats)}")
        };
        lines.add("result ${solution.status()} chromatic=${if (solution.models.isEmpty()) "-" else job.colors.toString()} attempts=${job.attempts.size}");
        lines.add("search ${Report.search(job.stats)}");
        lines.addAll(analysis(solution,false));
        return lines
    }
    if (job.command == "COLOR") lines.add(graphLine(job.graph!!));
    val formula = job.formula;
    val p = solution.preparation
    lines.add("formula variables=${formula.variables} clauses=${formula.clauses.size} literals=${literals(formula.clauses)} lengths=${Report.frequency(lengths(formula.clauses))}")
    lines.add("preprocess pure=${if (solution.limit == 1) "on" else "off"} tautologies=${p.tautologies} duplicate_literals=${p.duplicateLiterals} unit_fixed=${p.unitFixed} unit_removed=${p.unit.size} subsumed=${p.subsumed.size} pure_fixed=${p.pureFixed} pure_removed=${p.pure.size} removed=${p.removed()}")
    lines.add("removed_clauses tautology=${Report.numbers(p.tautology.sorted())} unit=${Report.numbers(p.unit.sorted())} subsumed=${Report.numbers(p.subsumed.sorted())} pure=${Report.numbers(p.pure.sorted())}")
    if (p.empty != 0) lines.add("simplified empty_clause=${p.empty}") else {
        val fixed = (1 until p.fixed.size).filter {
            p.fixed[it] != 0
        }.map {
            if (p.fixed[it] > 0) it else -it
        };
        lines.add("simplified clauses=${p.clauses.size} literals=${literals(p.clauses)} lengths=${Report.frequency(lengths(p.clauses))} fixed=${fixed.size} active=${p.active.size}");
        lines.add("fixed literals=${Report.numbers(fixed)}")
    }
    lines.add("result ${solution.status()} models=${solution.models.size} rounds=${solution.rounds} stop=${solution.stop}");
    lines.add("search ${Report.search(solution.stats)}");
    if (solution.rounds > 0) lines.add("trace " + if (solution.trace.isEmpty()) "-" else solution.trace.take(12).joinToString(" ") + if (solution.trace.size > 12) " +${solution.trace.size - 12}" else "");
    lines.addAll(analysis(solution,true));
    if (job.command == "CORE" && solution.models.isEmpty()) lines.add("core size=${job.core.size} decisions=${job.coreDecisions} conflicts=${job.coreConflicts} clauses=${Report.numbers(job.core)}");
    return lines
}
fun compare(first: IntArray, second: IntArray): Int {
    for (i in first.indices) if (first[i] != second[i]) return first[i].compareTo(second[i]);
    return 0
}
data class Symmetry(val canonical: IntArray, val orbit: Int)
fun queenSymmetry(positions: IntArray): Symmetry {
    val n = positions.size;
    val boards = Array(8) {
        IntArray(n)
    };
    for (i in 0 until n) {
        val r = i + 1;
        val c = positions[i];
        val mapped = arrayOf(intArrayOf(r,c),intArrayOf(c,n + 1 - r),intArrayOf(n + 1 - r,n + 1 - c),intArrayOf(n + 1 - c,r),intArrayOf(r,n + 1 - c),intArrayOf(n + 1 - r,c),intArrayOf(c,r),intArrayOf(n + 1 - c,n + 1 - r));
        for (j in 0..7) boards[j][mapped[j][0] - 1] = mapped[j][1]
    };
    var canonical = boards[0];
    val distinct = mutableSetOf<String>();
    for (board in boards) {
        distinct.add(Report.numbers(board));
        if (compare(board,canonical) < 0) canonical = board
    };
    return Symmetry(canonical,distinct.size)
}
fun colorCanonical(colors: IntArray): IntArray {
    val numbers = mutableMapOf<Int,Int>();
    return IntArray(colors.size) {
        i -> numbers.getOrPut(colors[i]) {
            numbers.size + 1
        }
    }
}
class ClassInfo(val canonical: IntArray, val orbit: Int, val first: Int) {
    var found = 0
}
fun boardLines(job: Job): List<String> {
    val lines = mutableListOf<String>();
    val solution = job.solution;
    val classes = mutableListOf<ClassInfo>();
    val classNumbers = mutableMapOf<String,Int>()
    if (job.command == "QUEENS") {
        val n = job.arguments[0].toInt();
        lines.add("QUEENS job=${job.number} n=$n")
        for (i in solution.models.indices) {
            val positions = Encoders.positions(solution.models[i],n,n);
            val symmetry = queenSymmetry(positions);
            val key = Report.numbers(symmetry.canonical);
            val first = key !in classNumbers;
            if (first) {
                classNumbers[key] = classes.size + 1;
                classes.add(ClassInfo(symmetry.canonical,symmetry.orbit,i + 1))
            };
            val number = classNumbers.getValue(key);
            classes[number - 1].found++;
            lines.add("solution ${i + 1} columns=${Report.numbers(positions)} class=$number");
            if (first) lines.addAll(Report.board(positions))
        }
        for (i in classes.indices) {
            val c = classes[i];
            lines.add("class ${i + 1} orbit=${c.orbit} found=${c.found} first=${c.first} canonical=${Report.numbers(c.canonical)}")
        };
        lines.add("summary solutions=${solution.models.size} stop=${solution.stop} classes=${classes.size}")
    } else if (job.command == "PIGEON") {
        val pigeons = job.arguments[0].toInt();
        val holes = job.arguments[1].toInt();
        lines.add("PIGEON job=${job.number} pigeons=$pigeons holes=$holes")
        for (i in solution.models.indices) {
            val positions = Encoders.positions(solution.models[i],pigeons,holes);
            val empty = (1..holes).filter {
                it !in positions
            };
            lines.add("assignment ${i + 1} holes=${Report.numbers(positions)} empty=${Report.numbers(empty)}")
        };
        var expected = if (pigeons <= holes) 1 else 0;
        if (pigeons <= holes) for (i in 0 until pigeons) expected *= holes - i;
        lines.add("summary assignments=${solution.models.size} stop=${solution.stop} expected=$expected")
    } else {
        val graph = job.graph!!;
        val colors = job.colors;
        lines.add("${job.command} job=${job.number} graph=${graph.name} vertices=${graph.vertices} edges=${graph.edges.size} colors=$colors");
        lines.add("greedy used=${graph.used} colors=${Report.numbers(graph.greedy)}")
        for (i in solution.models.indices) {
            val positions = Encoders.positions(solution.models[i],graph.vertices,colors);
            val canonical = colorCanonical(positions);
            val sizes = IntArray(colors);
            val used = mutableSetOf<Int>();
            for (color in positions) {
                used.add(color);
                sizes[color - 1]++
            };
            val key = Report.numbers(canonical);
            if (key !in classNumbers) {
                classNumbers[key] = classes.size + 1;
                classes.add(ClassInfo(canonical,0,i + 1))
            };
            val number = classNumbers.getValue(key);
            classes[number - 1].found++;
            lines.add("coloring ${i + 1} colors=${Report.numbers(positions)} used=${used.size} sizes=${Report.numbers(sizes)} class=$number")
        }
        for (i in classes.indices) {
            val c = classes[i];
            lines.add("class ${i + 1} found=${c.found} first=${c.first} canonical=${Report.numbers(c.canonical)}")
        };
        lines.add("summary colorings=${solution.models.size} stop=${solution.stop} classes=${classes.size}")
    }
    return lines
}
fun statistics(job: Job) = "${job.number},${job.command},${job.solution.status()},${job.formula.variables},${job.formula.clauses.size},${job.removed},${job.stats.decisions},${job.stats.propagations},${job.stats.conflicts},${job.stats.maxDepth},${job.solution.models.size},${job.rounds}"
fun summary(jobs: List<Job>): List<String> {
    var sat = 0;
    var unsat = 0;
    var errors = 0;
    val totals = IntArray(6);
    val commandCounts = mutableMapOf<String,IntArray>();
    var hardest: Job? = null;
    var deepest: Job? = null;
    var busiest: Job? = null
    for (job in jobs) {
        if (job.error != null) {
            errors++;
            continue
        };
        val satisfied = job.solution.models.isNotEmpty();
        if (satisfied) sat++ else unsat++;
        totals[0] += job.solution.models.size;
        totals[1] += job.rounds;
        totals[2] += job.stats.decisions;
        totals[3] += job.stats.propagations;
        totals[4] += job.stats.conflicts;
        totals[5] += job.removed;
        val count = commandCounts.getOrPut(job.command) {
            IntArray(6)
        };
        count[0]++;
        count[if (satisfied) 1 else 2]++;
        count[3] += job.stats.decisions;
        count[4] += job.stats.propagations;
        count[5] += job.stats.conflicts;
        if (hardest == null || job.stats.conflicts > hardest.stats.conflicts) hardest = job;
        if (deepest == null || job.stats.maxDepth > deepest.stats.maxDepth) deepest = job;
        if (busiest == null || job.stats.propagations > busiest.stats.propagations) busiest = job
    }
    val lines = mutableListOf("SUMMARY jobs=${jobs.size} sat=$sat unsat=$unsat error=$errors","totals models=${totals[0]} rounds=${totals[1]} decisions=${totals[2]} propagations=${totals[3]} conflicts=${totals[4]} removed_clauses=${totals[5]}")
    for (command in commands) {
        val count = commandCounts[command] ?: continue;
        lines.add("command $command jobs=${count[0]} sat=${count[1]} unsat=${count[2]} decisions=${count[3]} propagations=${count[4]} conflicts=${count[5]}")
    }
    hardest?.let {
        lines.add("hardest job=${it.number} conflicts=${it.stats.conflicts}")
    };
    deepest?.let {
        lines.add("deepest job=${it.number} max_depth=${it.stats.maxDepth}")
    };
    busiest?.let {
        lines.add("busiest job=${it.number} propagations=${it.stats.propagations}")
    };
    return lines
}
fun main() {
    val graphs = graphs();
    val jobs = jobs();
    val results = mutableListOf<String>();
    val models = mutableListOf<String>();
    val boards = mutableListOf<String>();
    val stats = mutableListOf("job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds")
    for (job in jobs) {
        job.error = validate(job,graphs);
        if (job.error == null) try {
            execute(job)
        } catch (error: CnfIo.Invalid) {
            job.error = error.message
        };
        Report.paragraph(results,resultLines(job));
        if (job.error != null) continue;
        stats.add(statistics(job));
        if (job.solution.models.isNotEmpty()) {
            val paragraph = mutableListOf(heading(job));
            for (i in job.solution.models.indices) {
                paragraph.add("model ${i + 1}");
                paragraph.addAll(CnfIo.modelLines(job.solution.models[i]))
            };
            Report.paragraph(models,paragraph)
        };
        if (job.command in setOf("QUEENS","PIGEON","COLOR","CHROMATIC")) Report.paragraph(boards,boardLines(job))
    }
    Report.paragraph(results,summary(jobs));
    Files.createDirectories(Path.of("output"));
    Report.write("results.txt",results);
    Report.write("models.txt",models);
    Report.write("boards.txt",boards);
    Report.write("stats.csv",stats)
}
