using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Team(int Index, string Code, string Name);
sealed record Match(int Round, int Home, int Away, int HomeScore, int AwayScore) {
    public int Margin => HomeScore - AwayScore;
    public int ResultTwice => HomeScore > AwayScore ? 2 : HomeScore == AwayScore ? 1 : 0;
    public double Result => ResultTwice / 2.0;
}
sealed class Settings {
    public readonly long WinPoints, DrawPoints, EloK, EloHome, EloInitial, CloseMargin, Upsets, BtIterations, OdIterations, LinkIterations;
    public readonly int FormLength, HoldoutRound, CalibrationBins, Simulations, Seed, TopPositions, BottomPositions;
    public readonly double PythagoreanExponent;
    public readonly List<long> GridK, GridHome;
    public Settings(Dictionary<string, List<string>> values) {
        long Number(string key) => long.Parse(values[key][0], CultureInfo.InvariantCulture);
        int Integer(string key) => int.Parse(values[key][0], CultureInfo.InvariantCulture);
        WinPoints = Number("WIN_POINTS"); DrawPoints = Number("DRAW_POINTS"); FormLength = Integer("FORM_LENGTH"); CloseMargin = Number("CLOSE_MARGIN");
        PythagoreanExponent = double.Parse(values["PYTHAGOREAN_EXPONENT"][0], CultureInfo.InvariantCulture);
        EloK = Number("ELO_K"); EloHome = Number("ELO_HOME"); EloInitial = Number("ELO_INITIAL");
        GridK = values["ELO_GRID_K"].Select(long.Parse).ToList(); GridHome = values["ELO_GRID_HOME"].Select(long.Parse).ToList();
        BtIterations = Number("BT_ITERATIONS"); OdIterations = Number("OD_ITERATIONS"); LinkIterations = Number("LINK_ITERATIONS"); HoldoutRound = Integer("HOLDOUT_ROUND");
        Upsets = Number("UPSETS"); CalibrationBins = Integer("CALIBRATION_BINS"); Simulations = Integer("SIMULATIONS"); Seed = Integer("SIM_SEED"); TopPositions = Integer("TOP_POSITIONS"); BottomPositions = Integer("BOTTOM_POSITIONS");
    }
}
sealed record SeasonData(List<Team> Teams, List<Match> Matches, Settings Settings);
static class Season {
    static List<string> Lines(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    public static List<Match> Before(List<Match> matches, int round) => matches.Where(match => match.Round < round).ToList();
    public static SeasonData Load() {
        List<Team> teams = new();
        Dictionary<string, int> indices = new(StringComparer.Ordinal);
        foreach (string line in Lines("teams.csv").Skip(1)) {
            string[] parts = line.Split(','); indices.Add(parts[0], teams.Count); teams.Add(new Team(teams.Count, parts[0], parts[1]));
        }
        List<Match> matches = new();
        foreach (string line in Lines("matches.csv").Skip(1)) {
            string[] parts = line.Split(','); matches.Add(new Match(int.Parse(parts[0]), indices[parts[1]], indices[parts[2]], int.Parse(parts[3]), int.Parse(parts[4])));
        }
        matches = matches.OrderBy(match => match.Round).ToList();
        Dictionary<string, List<string>> values = new(StringComparer.Ordinal);
        foreach (string line in Lines("params.txt")) { List<string> tokens = line.Split(' ').ToList(); values.Add(tokens[0], tokens.Skip(1).ToList()); }
        return new SeasonData(teams, matches, new Settings(values));
    }
}
