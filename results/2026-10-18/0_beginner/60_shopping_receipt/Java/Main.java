public class Main {
    public static void main(String[] args) {
        String[] names = {"milk", "notebook", "bread", "apple", "detergent", "eggs"};
        int[] prices = {198, 165, 248, 128, 437, 268};
        int[] quantities = {2, 3, 1, 4, 1, 1};
        boolean[] food = {true, false, true, true, false, true};
        int foodTotal = 0, generalTotal = 0;
        for (int i = 0; i < names.length; i++) {
            int subtotal = prices[i] * quantities[i];
            if (food[i]) foodTotal += subtotal;
            else generalTotal += subtotal;
            System.out.println(names[i] + " " + prices[i] + " x " + quantities[i] + " = " + subtotal);
        }
        int foodTax = foodTotal * 8 / 100, generalTax = generalTotal * 10 / 100;
        System.out.println("food: " + foodTotal + " yen, tax " + foodTax + " yen");
        System.out.println("general: " + generalTotal + " yen, tax " + generalTax + " yen");
        System.out.println("total: " + (foodTotal + generalTotal + foodTax + generalTax) + " yen");
    }
}
