public class Main {
    public static void main(String[] args) {
        int[] values = {1000,900,500,400,100,90,50,40,10,9,5,4,1}, digitValues = {1,5,10,50,100,500,1000};
        String[] symbols = {"M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"};
        for (int n : new int[]{9,14,49,94,444,1994,2768,3999}) {
            int remaining = n;
            StringBuilder roman = new StringBuilder();
            for (int i = 0; i < values.length; i++) while (remaining >= values[i]) {
                roman.append(symbols[i]);
                remaining -= values[i];
            }
            int decoded = 0;
            for (int i = 0; i < roman.length(); i++) {
                int value = digitValues["IVXLCDM".indexOf(roman.charAt(i))];
                int next = i + 1 < roman.length() ? digitValues["IVXLCDM".indexOf(roman.charAt(i + 1))] : 0;
                decoded += value < next ? -value : value;
            }
            System.out.println(n + " -> " + roman + " -> " + decoded);
        }
    }
}
