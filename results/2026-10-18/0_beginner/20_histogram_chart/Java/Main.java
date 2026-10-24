public class Main {
    public static void main(String[] args) {
        String[] days = {"Mon","Tue","Wed","Thu","Fri","Sat","Sun"};
        int[] counts = {7,12,4,15,9,18,11};
        for (int i = 0; i < days.length; i++) System.out.println(days[i] + " | " + "*".repeat(counts[i]) + " " + counts[i]);
    }
}
