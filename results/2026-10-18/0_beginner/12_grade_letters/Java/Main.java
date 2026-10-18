import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[] grades = {"A", "B", "C", "D", "F"};
        int[] counts = new int[5];
        for (int score : new int[]{78, 90, 100, 59, 80, 85, 89, 70, 45, 93}) {
            int index = score >= 90 ? 0 : score >= 80 ? 1 : score >= 70 ? 2 : score >= 60 ? 3 : 4;
            counts[index]++;
            System.out.println(score + ": " + grades[index]);
        }
        for (int i = 0; i < grades.length; i++) System.out.println(grades[i] + ": " + counts[i]);
    }
}
