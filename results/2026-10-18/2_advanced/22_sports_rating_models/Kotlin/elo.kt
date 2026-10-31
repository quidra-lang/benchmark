import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow

class EloRun(count: Int, initial: Long) {
    val ratings = DoubleArray(count) { initial.toDouble() }
    val expected = mutableListOf<Double>()
    val changes = mutableListOf<Double>()
    val roundRatings = mutableListOf<DoubleArray>()
}
object Elo {
    fun expected(home: Double, away: Double, advantage: Long) = 1 / (1 + 10.0.pow((away - home - advantage) / 400))
    private fun multiplier(match: Match, home: Double, away: Double, advantage: Long): Double {
        val goals = abs(match.margin)
        if (goals == 0) return 1.0
        val difference = if (match.margin > 0) home + advantage - away else away - home - advantage
        return ln((goals + 1).toDouble()) * 2.2 / (0.001 * difference + 2.2)
    }
    fun run(count: Int, matches: List<Match>, k: Long, advantage: Long, initial: Long): EloRun {
        val run = EloRun(count, initial)
        for ((i, match) in matches.withIndex()) {
            val home = run.ratings[match.home]
            val away = run.ratings[match.away]
            val expected = expected(home, away, advantage)
            val weight = multiplier(match, home, away, advantage)
            val change = k * weight * (match.result - expected)
            run.ratings[match.home] = home + change
            run.ratings[match.away] = away - change
            run.expected.add(expected)
            run.changes.add(change)
            if (i + 1 == matches.size || matches[i + 1].round != match.round) run.roundRatings.add(run.ratings.copyOf())
        }
        return run
    }
}
