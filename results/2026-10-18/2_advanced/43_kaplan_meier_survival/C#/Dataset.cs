using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Subject(int id, string group, int time, int eventFlag, int age, string sex, int stage) {
    }
    public sealed class Settings {
        public List<string> groups, subgroups, covariates;
        public string strata;
        public int[] report;
        public int tau, lifeWidth, lifeCount, landmark, residuals, width, height, horizon, divisions;
    }
    public record Data(List<Subject> subjects, Settings settings) {
    }
    public static Data Read() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/subjects.csv"), Encoding.ASCII).ToList();
        List<Subject> subjects = new();
        for (int i = 1; i < lines.Count; i++) {
            string[] w = lines[i].Split(',');
            subjects.Add(new Subject(int.Parse(w[0]), w[1], int.Parse(w[2]), int.Parse(w[3]), int.Parse(w[4]),
                                     w[5], int.Parse(w[6])));
        }
        subjects.Sort(Comparer<Subject>.Create((a, b) => a.id.CompareTo(b.id)));
        Settings s = new Settings();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)
                     .ToList()) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "GROUPS":
                s.groups = w.Skip(1).ToList();
                break;
            case "REPORT_TIMES": {
                s.report = new int[w.Length - 1];
                for (int i = 1; i < w.Length; i++)
                    s.report[i - 1] = int.Parse(w[i]);
                break;
            }
            case "TAU":
                s.tau = int.Parse(w[1]);
                break;
            case "LIFE_TABLE": {
                s.lifeWidth = int.Parse(w[1]);
                s.lifeCount = int.Parse(w[2]);
                break;
            }
            case "STRATA":
                s.strata = w[1];
                break;
            case "SUBGROUPS":
                s.subgroups = w.Skip(1).ToList();
                break;
            case "LANDMARK":
                s.landmark = int.Parse(w[1]);
                break;
            case "COX":
                s.covariates = w.Skip(1).ToList();
                break;
            case "RESIDUALS":
                s.residuals = int.Parse(w[1]);
                break;
            case "PLOT": {
                s.width = int.Parse(w[1]);
                s.height = int.Parse(w[2]);
                s.horizon = int.Parse(w[3]);
                s.divisions = int.Parse(w[4]);
                break;
            }
            }
        }
        return new Data(subjects, s);
    }
}
