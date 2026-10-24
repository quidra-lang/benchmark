import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        String[] names = {"Aiko","Kenji","Mika","Ryo","Yuki"};
        int[] heights = {158,172,165,180,150}, weights = {45,68,70,101,52};
        for (int i = 0; i < names.length; i++) {
            double bmi = (double)(weights[i] * 10000) / (heights[i] * heights[i]);
            String category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
            System.out.printf(Locale.ROOT, "%s: BMI %.1f (%s)%n", names[i], bmi, category);
        }
    }
}
