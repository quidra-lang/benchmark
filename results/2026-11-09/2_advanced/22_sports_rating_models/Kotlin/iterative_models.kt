data class BradleyTerry(val strengths: DoubleArray, val homeFactor: Double)
data class OffenseDefense(val offense: DoubleArray, val defense: DoubleArray, val ratings: DoubleArray)
object IterativeModels {
    fun bradleyTerry(count: Int, matches: List<Match>, iterations: Long): BradleyTerry {
        val winsTwice = IntArray(count)
        var homeWinsTwice = 0
        for (match in matches) { winsTwice[match.home] += match.resultTwice; winsTwice[match.away] += 2 - match.resultTwice; homeWinsTwice += match.resultTwice }
        val strengths = DoubleArray(count) { 1.0 }
        var theta = 1.0
        for (iteration in 0L until iterations) {
            val zeta = DoubleArray(count)
            for (match in matches) {
                val q = theta * strengths[match.home] + strengths[match.away]
                zeta[match.home] += theta / q
                zeta[match.away] += 1 / q
            }
            for (i in 0 until count) strengths[i] = winsTwice[i] / 2.0 / zeta[i]
            var total = 0.0
            for (strength in strengths) total += strength
            for (i in 0 until count) strengths[i] = strengths[i] * count / total
            var denominator = 0.0
            for (match in matches) { val home = strengths[match.home]; denominator += home / (theta * home + strengths[match.away]) }
            theta = homeWinsTwice / 2.0 / denominator
        }
        return BradleyTerry(strengths, theta)
    }
    fun offenseDefense(count: Int, matches: List<Match>, iterations: Long): OffenseDefense {
        val points = Array(count) { IntArray(count) }
        for (match in matches) { points[match.home][match.away] += match.awayScore; points[match.away][match.home] += match.homeScore }
        val offense = DoubleArray(count)
        val defense = DoubleArray(count) { 1.0 }
        for (iteration in 0L until iterations) {
            for (j in 0 until count) { var total = 0.0; for (i in 0 until count) total += points[i][j] / defense[i]; offense[j] = total }
            for (i in 0 until count) { var total = 0.0; for (j in 0 until count) total += points[i][j] / offense[j]; defense[i] = total }
        }
        return OffenseDefense(offense, defense, DoubleArray(count) { offense[it] / defense[it] })
    }
}
