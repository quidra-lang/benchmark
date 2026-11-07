import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.stream.IntStream;

public class Main {
    record Student(String name, int total) {}

    public static void main(String[] args) {
        String[] names = {"Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori"};
        int[][] scores = {{78, 85, 94}, {88, 74, 82}, {65, 90, 71}, {80, 79, 85}, {92, 88, 95}, {70, 62, 78}};
        List<Student> students = IntStream.range(0, names.length)
                .mapToObj(i -> new Student(names[i], Arrays.stream(scores[i]).sum()))
                .sorted(Comparator.comparingInt(Student::total).reversed().thenComparing(Student::name))
                .toList();
        int rank = 0, previous = -1;
        for (int position = 0; position < students.size(); position++) {
            Student student = students.get(position);
            if (student.total() != previous) {
                rank = position + 1;
            }
            previous = student.total();
            System.out.printf(Locale.ROOT, "%d. %s total=%d average=%.2f%n",
                    rank, student.name(), student.total(), student.total() / 3.0);
        }
    }
}
