import java.io.File
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sqrt

private val RATING_MODELS = listOf("elo", "colley", "massey", "bt", "od", "winpct")
private val COMPARISON_MODELS = listOf("standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag")
private val LINK_MODELS = listOf("colley", "massey", "od", "winpct")
private val PREDICTION_MODELS = listOf("base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble")
private const val STANDINGS_HEADER = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
private const val RATINGS_HEADER = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
private const val HISTORY_HEADER = "round,team,elo,change,elo_rank,points,position"
private const val PREDICTIONS_HEADER = "round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble"
private const val PROJECTION_HEADER = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"
private class Appearance(val match: Match, team: Int) {
    val home = match.home == team
    val opponent = if (home) match.away else match.home
    val scored = if (home) match.homeScore else match.awayScore
    val conceded = if (home) match.awayScore else match.homeScore
    val letter = if (scored > conceded) "W" else if (scored == conceded) "D" else "L"
}
private class TeamRecord {
    var played = 0
    var won = 0
    var drawn = 0
    var lost = 0
    var scored = 0
    var conceded = 0
    var points = 0L
    val difference get() = scored - conceded
    fun add(scored: Int, conceded: Int, settings: Settings) {
        played++
        this.scored += scored
        this.conceded += conceded
        if (scored > conceded) { won++; points += settings.winPoints }
        else if (scored == conceded) { drawn++; points += settings.drawPoints }
        else lost++
    }
    fun percentage() = Fraction(2 * won + drawn, 2 * played)
}
private fun teamRecords(count: Int, matches: List<Match>, settings: Settings): Array<TeamRecord> {
    val records = Array(count) { TeamRecord() }
    for (match in matches) { records[match.home].add(match.homeScore, match.awayScore, settings); records[match.away].add(match.awayScore, match.homeScore, settings) }
    return records
}
private class Standings(teams: List<Team>, matches: List<Match>, settings: Settings) {
    val records = teamRecords(teams.size, matches, settings)
    val headPoints = LongArray(teams.size)
    val headDifference = IntArray(teams.size)
    val positions = IntArray(teams.size)
    val order: List<Int>
    init {
        for (match in matches) if (records[match.home].points == records[match.away].points) {
            if (match.margin > 0) headPoints[match.home] += settings.winPoints
            else if (match.margin < 0) headPoints[match.away] += settings.winPoints
            else { headPoints[match.home] += settings.drawPoints; headPoints[match.away] += settings.drawPoints }
            headDifference[match.home] += match.margin
            headDifference[match.away] -= match.margin
        }
        order = teams.indices.sortedWith(compareByDescending<Int> { records[it].points }.thenByDescending { headPoints[it] }.thenByDescending { headDifference[it] }
            .thenByDescending { records[it].difference }.thenByDescending { records[it].scored }.thenBy { teams[it].code })
        for ((i, team) in order.withIndex()) positions[team] = i + 1
    }
    fun tiedGroups(): List<List<Int>> {
        val groups = mutableListOf<MutableList<Int>>()
        for (team in order) {
            if (groups.isEmpty() || records[groups.last().first()].points != records[team].points) groups.add(mutableListOf())
            groups.last().add(team)
        }
        return groups.filter { it.size > 1 }
    }
}
private data class Streak(val length: Int, val first: Int, val last: Int)
private fun longest(items: List<Appearance>, allowed: String): Streak {
    var best = Streak(0, 0, 0)
    var start = 0
    var length = 0
    for ((i, item) in items.withIndex()) {
        if (item.letter !in allowed) { length = 0; continue }
        if (length == 0) start = i
        length++
        if (length > best.length) best = Streak(length, items[start].match.round, item.match.round)
    }
    return best
}
private fun currentStreak(items: List<Appearance>): String {
    val letter = items.last().letter
    var count = 0
    for (item in items.asReversed()) { if (item.letter != letter) break; count++ }
    return letter + count
}
private fun recordText(items: List<Appearance>) = "${items.count { it.letter == "W" }}-${items.count { it.letter == "D" }}-${items.count { it.letter == "L" }}"
private fun competitionRanks(values: Array<Fraction>) = IntArray(values.size) { i -> 1 + values.count { it > values[i] } }
private fun csv(vararg fields: Any) = fields.joinToString(",")
private fun parts(parts: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (part in parts) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(part) }
    return lines
}
private class ModelFit(count: Int, matches: List<Match>, settings: Settings) {
    val elo = Elo.run(count, matches, settings.eloK, settings.eloHome, settings.eloInitial)
    val colley = LinearModels.colley(count, matches)
    private val fittedMassey = LinearModels.massey(count, matches)
    val massey = fittedMassey.ratings
    val homeAdvantage = fittedMassey.homeAdvantage
    private val bt = IterativeModels.bradleyTerry(count, matches, settings.btIterations)
    val strengths = bt.strengths
    val homeFactor = bt.homeFactor
    private val fittedOd = IterativeModels.offenseDefense(count, matches, settings.odIterations)
    val offense = fittedOd.offense
    val defense = fittedOd.defense
    val od = fittedOd.ratings
    val percentages = teamRecords(count, matches, settings).map { it.percentage() }.toTypedArray()
    fun feature(model: String, match: Match): Double {
        val home = match.home
        val away = match.away
        return when (model) { "colley" -> colley[home] - colley[away]; "massey" -> massey[home] - massey[away]; "od" -> ln(od[home]) - ln(od[away]); else -> percentages[home].real() - percentages[away].real() }
    }
    fun btProbability(match: Match): Double { val home = homeFactor * strengths[match.home]; return home / (home + strengths[match.away]) }
    fun margin(match: Match) = massey[match.home] - massey[match.away] + homeAdvantage
}
private class Prediction(val match: Match, val probabilities: DoubleArray, val marginError: Double) {
    val losses = DoubleArray(8) { Evaluation.logLoss(probabilities[it], match.resultTwice) }
    val briers = DoubleArray(8) { Evaluation.brier(probabilities[it], match.resultTwice) }
    val scoresTwice = IntArray(8) { Evaluation.correctnessTwice(probabilities[it], match.resultTwice) }
}
private class ValidationRound(val number: Int, count: Int, matches: List<Match>, settings: Settings) {
    val training = Season.before(matches, number)
    val fit = ModelFit(count, training, settings)
    val base = Fraction(training.sumOf { it.resultTwice }, 2 * training.size).real()
    val links = linkedMapOf<String, Link>()
    val predictions: List<Prediction>
    init {
        for (model in LINK_MODELS) links[model] = Evaluation.fitLink(DoubleArray(training.size) { fit.feature(model, training[it]) }, training, settings.linkIterations)
        predictions = matches.filter { it.round == number }.map { predict(it, settings) }
    }
    private fun predict(match: Match, settings: Settings): Prediction {
        val probabilities = DoubleArray(8)
        probabilities[0] = base
        probabilities[1] = Elo.expected(fit.elo.ratings[match.home], fit.elo.ratings[match.away], settings.eloHome)
        for (model in LINK_MODELS) { val link = links.getValue(model); probabilities[PREDICTION_MODELS.indexOf(model)] = Evaluation.sigma(link.alpha + link.beta * fit.feature(model, match)) }
        probabilities[4] = fit.btProbability(match)
        var ensemble = 0.0
        for (i in 1..6) ensemble += probabilities[i]
        probabilities[7] = ensemble / 6
        return Prediction(match, probabilities, match.margin - fit.margin(match))
    }
}
private class ModelScores(predictions: List<Prediction>) {
    val losses = DoubleArray(8)
    val briers = DoubleArray(8)
    val skills = DoubleArray(8)
    val accuracies: Array<Fraction>
    val lossRanking: List<Int>
    val brierRanking: List<Int>
    val accuracyRanking: List<Int>
    init {
        accuracies = Array(8) { i ->
            var loss = 0.0
            var brier = 0.0
            var score = 0
            for (prediction in predictions) { loss += prediction.losses[i]; brier += prediction.briers[i]; score += prediction.scoresTwice[i] }
            losses[i] = loss / predictions.size
            briers[i] = brier / predictions.size
            Fraction(score, 2 * predictions.size)
        }
        for (i in 0 until 8) skills[i] = 1 - briers[i] / briers[0]
        lossRanking = (0 until 8).sortedWith(compareBy<Int> { Report.comparison(losses[it], 4) }.thenBy { it })
        brierRanking = (0 until 8).sortedWith(compareBy<Int> { Report.comparison(briers[it], 4) }.thenBy { it })
        accuracyRanking = (0 until 8).sortedWith(compareByDescending<Int> { accuracies[it] }.thenBy { it })
    }
}
private class Projection(teams: List<Team>, matches: List<Match>, settings: Settings) {
    private val currentMatches = Season.before(matches, settings.holdoutRound)
    val current = Standings(teams, currentMatches, settings)
    val ratings = Elo.run(teams.size, currentMatches, settings.eloK, settings.eloHome, settings.eloInitial).ratings
    val remaining = matches.filter { it.round >= settings.holdoutRound }
    val totalPoints = LongArray(teams.size)
    val titles = IntArray(teams.size)
    val tops = IntArray(teams.size)
    val bottoms = IntArray(teams.size)
    val ranks = IntArray(teams.size)
    val order: List<Int>
    init {
        val probabilities = remaining.map { Elo.expected(ratings[it.home], ratings[it.away], settings.eloHome) }
        var state = settings.seed.toLong()
        repeat(settings.simulations) {
            val points = LongArray(teams.size) { current.records[it].points }
            for ((i, match) in remaining.withIndex()) {
                state = 48271 * state % 2147483647
                val uniform = state.toDouble() / 2147483647
                points[if (uniform < probabilities[i]) match.home else match.away] += settings.winPoints
            }
            for ((i, team) in ordered(points).withIndex()) {
                val place = i + 1
                totalPoints[team] += points[team]
                if (place == 1) titles[team]++
                if (place <= settings.topPositions) tops[team]++
                if (place >= teams.size - settings.bottomPositions + 1) bottoms[team]++
            }
        }
        order = ordered(totalPoints)
        for ((i, team) in order.withIndex()) ranks[team] = i + 1
    }
    private fun ordered(points: LongArray) = points.indices.sortedWith(compareByDescending<Int> { points[it] }.thenBy { current.positions[it] })
    fun opponentStrength(team: Int): Double {
        var total = 0.0
        var count = 0
        for (match in remaining) {
            if (match.home == team) { total += ratings[match.away]; count++ }
            else if (match.away == team) { total += ratings[match.home]; count++ }
        }
        return total / count
    }
}
private data class Upset(val match: Match, val expected: Double, val gain: Double, val index: Int)
private data class Similarity(val first: String, val second: String, val tau: Fraction)
private class LeagueAnalysis(season: SeasonData) {
    private val teams = season.teams
    private val matches = season.matches
    private val settings = season.settings
    private val count = teams.size
    private val finalRound = matches.last().round
    private val appearances = teams.indices.map { team -> matches.filter { it.home == team || it.away == team }.map { Appearance(it, team) } }
    private val wins = appearances.map { longest(it, "W") }
    private val unbeaten = appearances.map { longest(it, "WD") }
    private val finalTable = Standings(teams, matches, settings)
    private val fit = ModelFit(count, matches, settings)
    private val roundTables = (1..finalRound).map { Standings(teams, Season.before(matches, it + 1), settings) }
    private val sos = Array(count) { opponentAverage(it, fit.percentages) }
    private val sos2 = Array(count) { opponentAverage(it, sos) }
    private val rpi = Array(count) { fit.percentages[it].add(sos[it].multiply(2)).add(sos2[it]).divide(4) }
    private val pythag = DoubleArray(count) { val record = finalTable.records[it]; 1 / (1 + (record.conceded.toDouble() / record.scored).pow(settings.pythagoreanExponent)) }
    private val luck = DoubleArray(count) { fit.percentages[it].real() - pythag[it] }
    private val comparison = linkedMapOf("standings" to Array(count) { Fraction(-finalTable.positions[it]) }, "elo" to rounded(fit.elo.ratings, 2), "colley" to rounded(fit.colley, 4),
        "massey" to rounded(fit.massey, 4), "bt" to rounded(fit.strengths, 4), "od" to rounded(fit.od, 2), "winpct" to fit.percentages, "rpi" to rpi, "pythag" to rounded(pythag, 4))
    private val ranks = RATING_MODELS.associateWith { competitionRanks(comparison.getValue(it)) }
    private val rounds = (settings.holdoutRound..finalRound).map { ValidationRound(it, count, matches, settings) }
    private val predictions = rounds.flatMap { it.predictions }
    private val scores = ModelScores(predictions)
    private val projection = Projection(teams, matches, settings)
    private fun opponentAverage(team: Int, values: Array<Fraction>): Fraction {
        var total = Fraction(0)
        for (appearance in appearances[team]) total = total.add(values[appearance.opponent])
        return total.divide(appearances[team].size)
    }
    private fun rounded(values: DoubleArray, places: Int) = Array(values.size) { Report.comparison(values[it], places) }
    private fun code(team: Int) = teams[team].code
    private fun standingsLines(): List<String> {
        val lines = mutableListOf(STANDINGS_HEADER)
        for (team in finalTable.order) {
            val record = finalTable.records[team]
            val items = appearances[team]
            val form = items.takeLast(settings.formLength).joinToString("") { it.letter }
            lines.add(csv(finalTable.positions[team], code(team), teams[team].name, record.played, record.won, record.drawn, record.lost, record.scored, record.conceded, record.difference, record.points,
                recordText(items.filter { it.home }), recordText(items.filter { !it.home }), form, currentStreak(items), recordText(items.filter { abs(it.scored.toLong() - it.conceded) <= settings.closeMargin }),
                wins[team].length, unbeaten[team].length, fit.percentages[team], Report.fixed(sos[team]), Report.fixed(sos2[team]), Report.fixed(rpi[team]), Report.fixed(pythag[team]), Report.fixed(luck[team])))
        }
        return lines
    }
    private fun ratingsLines(): List<String> {
        val totals = IntArray(count) { team -> RATING_MODELS.sumOf { ranks.getValue(it)[team] } }
        val lines = mutableListOf(RATINGS_HEADER)
        for (team in teams.indices.sortedWith(compareBy<Int> { totals[it] }.thenBy { code(it) })) {
            val values = RATING_MODELS.map { ranks.getValue(it)[team] }
            lines.add(csv(code(team), Report.fixed(fit.elo.ratings[team], 2), ranks.getValue("elo")[team], Report.fixed(fit.colley[team]), ranks.getValue("colley")[team],
                Report.fixed(fit.massey[team]), ranks.getValue("massey")[team], Report.fixed(fit.strengths[team]), ranks.getValue("bt")[team], Report.fixed(fit.offense[team], 2), Report.fixed(fit.defense[team]),
                Report.fixed(fit.od[team], 2), ranks.getValue("od")[team], Report.fixed(fit.percentages[team]), ranks.getValue("winpct")[team], totals[team], values.min(), values.max()))
        }
        return lines
    }
    private fun historyLines(): List<String> {
        val lines = mutableListOf(HISTORY_HEADER)
        var previous = DoubleArray(count) { settings.eloInitial.toDouble() }
        for ((r, table) in roundTables.withIndex()) {
            val ratings = fit.elo.roundRatings[r]
            val eloRanks = competitionRanks(rounded(ratings, 2))
            for (team in teams.indices) lines.add(csv(r + 1, code(team), Report.fixed(ratings[team], 2), Report.fixed(ratings[team] - previous[team], 2), eloRanks[team], table.records[team].points, table.positions[team]))
            previous = ratings
        }
        return lines
    }
    private fun summaryLines(): List<String> {
        val home = matches.count { it.resultTwice == 2 }
        val drawn = matches.count { it.resultTwice == 1 }
        val away = matches.count { it.resultTwice == 0 }
        val rate = Fraction(matches.sumOf { it.resultTwice }, 2 * matches.size)
        return listOf("season teams $count matches ${matches.size} rounds $finalRound", "home won $home drawn $drawn lost $away rate ${Report.fractionWithReal(rate)}",
            "massey_home_advantage ${Report.fixed(fit.homeAdvantage)}", "bt_home_factor ${Report.fixed(fit.homeFactor)}")
    }
    private fun upsetLines(): List<String> {
        val candidates = mutableListOf<Upset>()
        for ((i, match) in matches.withIndex()) if (match.margin != 0) candidates.add(Upset(match, if (match.margin > 0) fit.elo.expected[i] else 1 - fit.elo.expected[i], abs(fit.elo.changes[i]), i))
        val lines = mutableListOf("upsets top ${settings.upsets}")
        for (item in candidates.sortedWith(compareBy<Upset> { Report.comparison(it.expected, 4) }.thenBy { it.index }).take(minOf(settings.upsets, candidates.size.toLong()).toInt())) {
            val match = item.match
            val home = match.margin > 0
            val winner = if (home) match.home else match.away
            val loser = if (home) match.away else match.home
            val score = if (home) "${match.homeScore}-${match.awayScore}" else "${match.awayScore}-${match.homeScore}"
            lines.add("round ${match.round} ${code(winner)} beat ${code(loser)} $score ${if (home) "home" else "away"} expected ${Report.fixed(item.expected)} gain ${Report.fixed(item.gain, 2)}")
        }
        return lines
    }
    private fun tiebreakLines(): List<String> {
        val lines = mutableListOf("tiebreaks")
        for (group in finalTable.tiedGroups()) lines.add("points ${finalTable.records[group.first()].points} order ${group.joinToString(" ") { code(it) }} h2h_points ${group.joinToString(" ") { finalTable.headPoints[it].toString() }} h2h_diff ${group.joinToString(" ") { finalTable.headDifference[it].toString() }}")
        if (lines.size == 1) lines.add("none")
        return lines
    }
    private fun leaderLines(): List<String> {
        val lines = mutableListOf("leaders")
        var previous = -1
        var recorded = 0
        for ((r, table) in roundTables.withIndex()) {
            val leader = table.order.first()
            if (leader != previous) { lines.add("round ${r + 1} ${code(leader)} points ${table.records[leader].points}"); recorded++ }
            previous = leader
        }
        lines.add("lead_changes ${recorded - 1}")
        return lines
    }
    private fun streakLines(): List<String> {
        val lines = mutableListOf<String>()
        for ((label, streaks) in listOf("longest_win_streak" to wins, "longest_unbeaten_streak" to unbeaten)) {
            val longest = streaks.maxOf { it.length }
            for ((team, streak) in streaks.withIndex()) if (streak.length == longest) lines.add("$label ${code(team)} length ${streak.length} rounds ${streak.first}-${streak.last}")
        }
        return lines
    }
    private fun crosstableLines(): List<String> {
        val top = finalTable.order.take(settings.topPositions)
        val lines = mutableListOf("crosstable top ${settings.topPositions}", "team " + top.joinToString(" ") { code(it) })
        for (first in top) {
            val entries = top.map { second -> if (first == second) "-" else recordText(appearances[first].filter { it.opponent == second }) }
            lines.add(code(first) + " " + entries.joinToString(" "))
        }
        return lines
    }
    private fun trajectoryLines(): List<String> {
        val lines = mutableListOf("trajectories")
        for (team in teams.indices) {
            var peak = 0
            var low = 0
            var best = 0
            var worst = 0
            for (r in 1 until finalRound) {
                val value = Report.comparison(fit.elo.roundRatings[r][team], 2)
                if (value > Report.comparison(fit.elo.roundRatings[peak][team], 2)) peak = r
                if (value < Report.comparison(fit.elo.roundRatings[low][team], 2)) low = r
                if (roundTables[r].positions[team] < roundTables[best].positions[team]) best = r
                if (roundTables[r].positions[team] > roundTables[worst].positions[team]) worst = r
            }
            lines.add("${code(team)} elo_peak ${Report.fixed(fit.elo.roundRatings[peak][team], 2)} round ${peak + 1} elo_low ${Report.fixed(fit.elo.roundRatings[low][team], 2)} round ${low + 1} best_position ${roundTables[best].positions[team]} round ${best + 1} worst_position ${roundTables[worst].positions[team]} round ${worst + 1}")
        }
        return lines
    }
    private fun correlationLines(spearman: Boolean): List<String> {
        val lines = mutableListOf(if (spearman) "spearman" else "kendall", "model " + COMPARISON_MODELS.joinToString(" "))
        for (first in COMPARISON_MODELS) {
            val values = COMPARISON_MODELS.map { second ->
                if (spearman) Evaluation.spearman(comparison.getValue(first), comparison.getValue(second)) else Evaluation.kendall(comparison.getValue(first), comparison.getValue(second))
            }
            lines.add(first + " " + values.joinToString(" "))
        }
        return lines
    }
    private fun similarityLines(): List<String> {
        var most: Similarity? = null
        var least: Similarity? = null
        for (i in COMPARISON_MODELS.indices) for (j in i + 1 until COMPARISON_MODELS.size) {
            val a = COMPARISON_MODELS[i]
            val b = COMPARISON_MODELS[j]
            val pair = Similarity(a, b, Evaluation.kendall(comparison.getValue(a), comparison.getValue(b)))
            if (most == null || pair.tau > most.tau) most = pair
            if (least == null || pair.tau < least.tau) least = pair
        }
        val maximum = most!!
        val minimum = least!!
        return listOf("most_similar ${maximum.first} ${maximum.second} tau ${Report.fractionWithReal(maximum.tau)}", "least_similar ${minimum.first} ${minimum.second} tau ${Report.fractionWithReal(minimum.tau)}")
    }
    private fun seasonLines() = parts(listOf(summaryLines(), upsetLines(), tiebreakLines(), leaderLines(), streakLines(), crosstableLines(), trajectoryLines(), correlationLines(false), correlationLines(true), similarityLines()))
    private fun predictionLines(): List<String> {
        val lines = mutableListOf(PREDICTIONS_HEADER)
        for (prediction in predictions) {
            val match = prediction.match
            val fields = mutableListOf(match.round.toString(), code(match.home), code(match.away), match.homeScore.toString(), match.awayScore.toString(), when (match.resultTwice) { 2 -> "H"; 1 -> "D"; else -> "A" })
            fields.addAll(prediction.probabilities.map { Report.fixed(it) })
            lines.add(fields.joinToString(","))
        }
        return lines
    }
    private fun linkLines(): List<String> {
        val lines = mutableListOf("links")
        for (validation in rounds) {
            val fields = mutableListOf("round ${validation.number} train ${validation.training.size} base ${Report.fixed(validation.base)} bt_home ${Report.fixed(validation.fit.homeFactor)}")
            for (model in LINK_MODELS) { val link = validation.links.getValue(model); fields.add("$model ${Report.fixed(link.alpha)} ${Report.fixed(link.beta)}") }
            lines.add(fields.joinToString(" "))
        }
        return lines
    }
    private fun scoreLines(): List<String> {
        val lines = mutableListOf("scores", "model log_loss brier skill accuracy")
        for (i in 0 until 8) lines.add("${PREDICTION_MODELS[i]} ${Report.fixed(scores.losses[i])} ${Report.fixed(scores.briers[i])} ${Report.fixed(scores.skills[i])} ${Report.fractionWithReal(scores.accuracies[i])}")
        lines.add("ranking_log_loss " + scores.lossRanking.joinToString(" ") { PREDICTION_MODELS[it] })
        lines.add("ranking_brier " + scores.brierRanking.joinToString(" ") { PREDICTION_MODELS[it] })
        lines.add("ranking_accuracy " + scores.accuracyRanking.joinToString(" ") { PREDICTION_MODELS[it] })
        return lines
    }
    private fun pairedLines(): List<String> {
        val reference = scores.lossRanking.first()
        val size = predictions.size
        val lines = mutableListOf("paired_log_loss reference ${PREDICTION_MODELS[reference]}")
        for (i in 0 until 8) {
            if (i == reference) continue
            val deltas = DoubleArray(size)
            var total = 0.0
            for ((j, prediction) in predictions.withIndex()) { deltas[j] = prediction.losses[i] - prediction.losses[reference]; total += deltas[j] }
            val mean = total / size
            var squares = 0.0
            for (delta in deltas) squares += (delta - mean) * (delta - mean)
            val spread = sqrt(squares / (size - 1))
            val t = mean / (spread / sqrt(size.toDouble()))
            lines.add("${PREDICTION_MODELS[i]} mean_diff ${Report.fixed(mean)} sd ${Report.fixed(spread)} t ${Report.fixed(t, 2)}")
        }
        return lines
    }
    private fun marginLines(): List<String> {
        var absolute = 0.0
        var squares = 0.0
        var total = 0.0
        for (prediction in predictions) { val error = prediction.marginError; absolute += abs(error); squares += error * error; total += error }
        val size = predictions.size
        return listOf("massey_margin mae ${Report.fixed(absolute / size)} rmse ${Report.fixed(sqrt(squares / size))} bias ${Report.fixed(total / size)}")
    }
    private fun roundLossLines(): List<String> {
        val lines = mutableListOf("round_log_loss", "round " + PREDICTION_MODELS.joinToString(" "))
        for (validation in rounds) {
            val values = (0 until 8).map { i ->
                var total = 0.0
                for (prediction in validation.predictions) total += prediction.losses[i]
                Report.fixed(total / validation.predictions.size)
            }
            lines.add("${validation.number} " + values.joinToString(" "))
        }
        return lines
    }
    private fun calibrationLines(): List<String> {
        val bins = settings.calibrationBins
        val lines = mutableListOf("calibration bins $bins")
        for (i in 0 until 8) {
            val members = List(bins) { mutableListOf<Prediction>() }
            for (prediction in predictions) members[minOf(floor(bins * prediction.probabilities[i]).toInt(), bins - 1)].add(prediction)
            for ((k, group) in members.withIndex()) {
                val prefix = "${PREDICTION_MODELS[i]} bin ${k + 1} count ${group.size}"
                if (group.isEmpty()) { lines.add("$prefix predicted - observed -"); continue }
                var total = 0.0
                var observedTwice = 0
                for (prediction in group) { total += prediction.probabilities[i]; observedTwice += prediction.match.resultTwice }
                lines.add("$prefix predicted ${Report.fixed(total / group.size)} observed ${Fraction(observedTwice, 2 * group.size)}")
            }
        }
        return lines
    }
    private fun gridLines(): List<String> {
        val lines = mutableListOf("elo_grid", "k " + settings.gridHome.joinToString(" ") { "h$it" })
        var bestRounded: Fraction? = null
        var bestK = 0L
        var bestHome = 0L
        var bestLoss = 0.0
        for (k in settings.gridK) {
            val row = mutableListOf(k.toString())
            for (home in settings.gridHome) {
                val run = Elo.run(count, matches, k, home, settings.eloInitial)
                var total = 0.0
                var size = 0
                for ((i, match) in matches.withIndex()) if (match.round >= settings.holdoutRound) { total += Evaluation.logLoss(run.expected[i], match.resultTwice); size++ }
                val loss = total / size
                row.add(Report.fixed(loss))
                val rounded = Report.comparison(loss, 4)
                if (bestRounded == null || rounded < bestRounded) { bestRounded = rounded; bestK = k; bestHome = home; bestLoss = loss }
            }
            lines.add(row.joinToString(" "))
        }
        lines.add("best k $bestK home $bestHome log_loss ${Report.fixed(bestLoss)}")
        return lines
    }
    private fun projectionTau() = Evaluation.kendall(Array(count) { Fraction(-projection.ranks[it]) }, Array(count) { Fraction(-finalTable.positions[it]) })
    private fun evaluationLines() = parts(listOf(listOf("holdout rounds ${settings.holdoutRound}-$finalRound matches ${predictions.size}"), linkLines(), scoreLines(), pairedLines(), marginLines(), roundLossLines(), calibrationLines(), gridLines(),
        listOf("projection simulations ${settings.simulations} kendall ${Report.fractionWithReal(projectionTau())}")))
    private fun projectionLines(): List<String> {
        val lines = mutableListOf(PROJECTION_HEADER)
        for (team in projection.order) lines.add(csv(projection.ranks[team], code(team), projection.current.records[team].points, projection.current.positions[team], Report.fixed(projection.opponentStrength(team), 2),
            Report.fixed(Fraction(projection.totalPoints[team], settings.simulations)), Report.fixed(Fraction(projection.titles[team], settings.simulations)), Report.fixed(Fraction(projection.tops[team], settings.simulations)),
            Report.fixed(Fraction(projection.bottoms[team], settings.simulations)), finalTable.records[team].points, finalTable.positions[team]))
        return lines
    }
    fun outputFiles() = linkedMapOf("standings.csv" to standingsLines(), "ratings.csv" to ratingsLines(), "history.csv" to historyLines(), "season.txt" to seasonLines(),
        "predictions.csv" to predictionLines(), "evaluation.txt" to evaluationLines(), "projection.csv" to projectionLines())
}
fun main() {
    val analysis = LeagueAnalysis(Season.load())
    File("output").mkdirs()
    for ((name, lines) in analysis.outputFiles()) Report.write(name, lines)
}
