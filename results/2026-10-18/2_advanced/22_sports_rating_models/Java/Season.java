import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record Team(int index, String code, String name) {}
record Match(int round, int home, int away, int homeScore, int awayScore) {
    int margin() { return homeScore - awayScore; }
    int resultTwice() { return homeScore > awayScore ? 2 : homeScore == awayScore ? 1 : 0; }
    double result() { return resultTwice() / 2.0; }
}
final class Settings {
    final long winPoints, drawPoints, eloK, eloHome, eloInitial, closeMargin, upsets, btIterations, odIterations, linkIterations;
    final int formLength, holdoutRound, calibrationBins, simulations, seed, topPositions, bottomPositions;
    final double pythagoreanExponent;
    final List<Long> gridK, gridHome;
    Settings(Map<String, List<String>> values) {
        winPoints = number(values, "WIN_POINTS"); drawPoints = number(values, "DRAW_POINTS"); formLength = integer(values, "FORM_LENGTH"); closeMargin = number(values, "CLOSE_MARGIN");
        pythagoreanExponent = Double.parseDouble(values.get("PYTHAGOREAN_EXPONENT").getFirst());
        eloK = number(values, "ELO_K"); eloHome = number(values, "ELO_HOME"); eloInitial = number(values, "ELO_INITIAL");
        gridK = values.get("ELO_GRID_K").stream().map(Long::parseLong).toList(); gridHome = values.get("ELO_GRID_HOME").stream().map(Long::parseLong).toList();
        btIterations = number(values, "BT_ITERATIONS"); odIterations = number(values, "OD_ITERATIONS"); linkIterations = number(values, "LINK_ITERATIONS"); holdoutRound = integer(values, "HOLDOUT_ROUND");
        upsets = number(values, "UPSETS"); calibrationBins = integer(values, "CALIBRATION_BINS"); simulations = integer(values, "SIMULATIONS"); seed = integer(values, "SIM_SEED"); topPositions = integer(values, "TOP_POSITIONS"); bottomPositions = integer(values, "BOTTOM_POSITIONS");
    }
    static long number(Map<String, List<String>> values, String key) { return Long.parseLong(values.get(key).getFirst()); }
    static int integer(Map<String, List<String>> values, String key) { return Integer.parseInt(values.get(key).getFirst()); }
}
record SeasonData(List<Team> teams, List<Match> matches, Settings settings) {}
final class Season {
    static List<String> lines(String name) throws Exception { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static List<Match> before(List<Match> matches, int round) { return matches.stream().filter(match -> match.round() < round).toList(); }
    static SeasonData load() throws Exception {
        List<Team> teams = new ArrayList<>(); Map<String, Integer> indices = new HashMap<>(); List<String> teamLines = lines("teams.csv");
        for (String line : teamLines.subList(1, teamLines.size())) { String[] parts = line.split(","); indices.put(parts[0], teams.size()); teams.add(new Team(teams.size(), parts[0], parts[1])); }
        List<Match> matches = new ArrayList<>(); List<String> matchLines = lines("matches.csv");
        for (String line : matchLines.subList(1, matchLines.size())) { String[] parts = line.split(","); matches.add(new Match(Integer.parseInt(parts[0]), indices.get(parts[1]), indices.get(parts[2]), Integer.parseInt(parts[3]), Integer.parseInt(parts[4]))); }
        matches.sort(Comparator.comparingInt(Match::round));
        Map<String, List<String>> values = new HashMap<>();
        for (String line : lines("params.txt")) { List<String> tokens = List.of(line.split(" ")); values.put(tokens.getFirst(), tokens.subList(1, tokens.size())); }
        return new SeasonData(teams, matches, new Settings(values));
    }
}
