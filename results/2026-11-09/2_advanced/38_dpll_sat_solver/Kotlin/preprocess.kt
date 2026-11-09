import kotlin.math.abs
object Preprocess {
    data class Clause(val id: Int, val literals: IntArray)
    class Result(variables: Int) {
        var tautologies = 0;
        var duplicateLiterals = 0;
        var unitFixed = 0;
        var pureFixed = 0;
        var empty = 0;
        val tautology = mutableListOf<Int>();
        val unit = mutableListOf<Int>();
        val subsumed = mutableListOf<Int>();
        val pure = mutableListOf<Int>();
        val fixed = IntArray(variables + 1);
        val active = mutableListOf<Int>();
        val clauses = mutableListOf<IntArray>();
        fun removed() = tautology.size + unit.size + subsumed.size + pure.size
    }
    fun run(formula: CnfIo.Formula, pureEnabled: Boolean): Result {
        val result = Result(formula.variables);
        var working = mutableListOf<Clause>()
        for (i in formula.clauses.indices) {
            val original = formula.clauses[i];
            val all = mutableSetOf<Int>();
            var tautology = false;
            for (literal in original) {
                if (-literal in all) tautology = true;
                all.add(literal)
            };
            if (tautology) {
                result.tautologies++;
                result.tautology.add(i + 1);
                continue
            };
            val seen = mutableSetOf<Int>();
            val literals = mutableListOf<Int>();
            for (literal in original) if (seen.add(literal)) literals.add(literal) else result.duplicateLiterals++;
            working.add(Clause(i + 1,literals.toIntArray()))
        }
        while (true) {
            var literal = 0;
            for (clause in working) if (clause.literals.isEmpty()) {
                result.empty = clause.id;
                return result
            };
            for (clause in working) if (clause.literals.size == 1) {
                literal = clause.literals[0];
                break
            };
            if (literal == 0) break;
            result.fixed[abs(literal)] = if (literal > 0) 1 else -1;
            result.unitFixed++;
            val next = mutableListOf<Clause>();
            for (clause in working) {
                if (literal in clause.literals) result.unit.add(clause.id) else next.add(Clause(clause.id,clause.literals.filter {
                    it != -literal
                }.toIntArray()))
            };
            working = next
        }
        val sets = working.map {
            it.literals.toSet()
        };
        val removed = BooleanArray(working.size);
        for (b in working.indices) for (a in working.indices) if (a != b && (sets[a].size < sets[b].size || a < b) && sets[b].containsAll(sets[a])) {
            removed[b] = true;
            break
        };
        val retained = mutableListOf<Clause>();
        for (i in working.indices) if (removed[i]) result.subsumed.add(working[i].id) else retained.add(working[i]);
        working = retained
        if (pureEnabled) while (true) {
            val positive = BooleanArray(formula.variables + 1);
            val negative = BooleanArray(positive.size);
            for (clause in working) for (literal in clause.literals) if (literal > 0) positive[literal] = true else negative[-literal] = true;
            val pure = mutableSetOf<Int>();
            for (x in 1..formula.variables) if (positive[x] != negative[x]) {
                pure.add(if (positive[x]) x else -x);
                result.fixed[x] = if (positive[x]) 1 else -1;
                result.pureFixed++
            };
            if (pure.isEmpty()) break;
            val next = mutableListOf<Clause>();
            for (clause in working) if (clause.literals.any {
                it in pure
            }) result.pure.add(clause.id) else next.add(clause);
            working = next
        }
        result.clauses.addAll(working.map {
            it.literals
        });
        for (x in 1..formula.variables) if (result.fixed[x] == 0) result.active.add(x);
        return result
    }
}
