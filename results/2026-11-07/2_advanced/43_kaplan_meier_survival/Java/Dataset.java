import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataset {
    record Subject(int id, String group, int time, int event, int age, String sex, int stage) {}
    static final class Settings {
        List<String> groups, subgroups, covariates;
        String strata;
        int[] report;
        int tau, lifeWidth, lifeCount, landmark, residuals, width, height, horizon, divisions;
    }
    record Data(List<Subject> subjects, Settings settings) {}
    static Data read() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/subjects.csv"), StandardCharsets.US_ASCII);
        List<Subject> subjects = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            subjects.add(new Subject(Integer.parseInt(w[0]), w[1], Integer.parseInt(w[2]),
                                     Integer.parseInt(w[3]), Integer.parseInt(w[4]), w[5],
                                     Integer.parseInt(w[6])));
        }
        subjects.sort(Comparator.comparingInt(Subject::id));
        Settings s = new Settings();
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "GROUPS" -> s.groups = new ArrayList<>(Arrays.asList(w).subList(1, w.length));
            case "REPORT_TIMES" -> {
                s.report = new int[w.length - 1];
                for (int i = 1; i < w.length; i++)
                    s.report[i - 1] = Integer.parseInt(w[i]);
            }
            case "TAU" -> s.tau = Integer.parseInt(w[1]);
            case "LIFE_TABLE" -> {
                s.lifeWidth = Integer.parseInt(w[1]);
                s.lifeCount = Integer.parseInt(w[2]);
            }
            case "STRATA" -> s.strata = w[1];
            case "SUBGROUPS" -> s.subgroups = new ArrayList<>(Arrays.asList(w).subList(1, w.length));
            case "LANDMARK" -> s.landmark = Integer.parseInt(w[1]);
            case "COX" -> s.covariates = new ArrayList<>(Arrays.asList(w).subList(1, w.length));
            case "RESIDUALS" -> s.residuals = Integer.parseInt(w[1]);
            case "PLOT" -> {
                s.width = Integer.parseInt(w[1]);
                s.height = Integer.parseInt(w[2]);
                s.horizon = Integer.parseInt(w[3]);
                s.divisions = Integer.parseInt(w[4]);
            }
            }
        }
        return new Data(subjects, s);
    }
}
