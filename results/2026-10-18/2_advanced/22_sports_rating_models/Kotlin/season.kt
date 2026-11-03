import java.io.File

data class Team(val index: Int, val code: String, val name: String)
data class Match(val round: Int, val home: Int, val away: Int, val homeScore: Int, val awayScore: Int) {
    val margin get() = homeScore - awayScore
    val resultTwice get() = if (homeScore > awayScore) 2 else if (homeScore == awayScore) 1 else 0
    val result get() = resultTwice / 2.0
}
class Settings(values: Map<String, List<String>>) {
    private val parameters = values
    private fun number(key: String) = parameters.getValue(key).first().toLong()
    private fun integer(key: String) = parameters.getValue(key).first().toInt()
    val winPoints = number("WIN_POINTS")
    val drawPoints = number("DRAW_POINTS")
    val formLength = integer("FORM_LENGTH")
    val closeMargin = number("CLOSE_MARGIN")
    val pythagoreanExponent = parameters.getValue("PYTHAGOREAN_EXPONENT").first().toDouble()
    val eloK = number("ELO_K")
    val eloHome = number("ELO_HOME")
    val eloInitial = number("ELO_INITIAL")
    val gridK = parameters.getValue("ELO_GRID_K").map { it.toLong() }
    val gridHome = parameters.getValue("ELO_GRID_HOME").map { it.toLong() }
    val btIterations = number("BT_ITERATIONS")
    val odIterations = number("OD_ITERATIONS")
    val linkIterations = number("LINK_ITERATIONS")
    val holdoutRound = integer("HOLDOUT_ROUND")
    val upsets = number("UPSETS")
    val calibrationBins = integer("CALIBRATION_BINS")
    val simulations = integer("SIMULATIONS")
    val seed = integer("SIM_SEED")
    val topPositions = integer("TOP_POSITIONS")
    val bottomPositions = integer("BOTTOM_POSITIONS")
}
data class SeasonData(val teams: List<Team>, val matches: List<Match>, val settings: Settings)
object Season {
    private fun lines(name: String) = File("input", name).readLines(Charsets.US_ASCII)
    fun before(matches: List<Match>, round: Int) = matches.filter { it.round < round }
    fun load(): SeasonData {
        val teams = lines("teams.csv").drop(1).mapIndexed { i, line -> val parts = line.split(','); Team(i, parts[0], parts[1]) }
        val indices = teams.associate { it.code to it.index }
        val matches = lines("matches.csv").drop(1).map { line ->
            val parts = line.split(',')
            Match(parts[0].toInt(), indices.getValue(parts[1]), indices.getValue(parts[2]), parts[3].toInt(), parts[4].toInt())
        }.sortedBy { it.round }
        val values = lines("params.txt").associate { val tokens = it.split(' '); tokens.first() to tokens.drop(1) }
        return SeasonData(teams, matches, Settings(values))
    }
}
