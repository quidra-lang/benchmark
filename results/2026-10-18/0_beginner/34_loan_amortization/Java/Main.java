public class Main {
    public static void main(String[] args) {
        int balance = 1000000, month = 0, totalInterest = 0, totalPaid = 0;
        while (balance > 0) {
            month++;
            int interest = balance / 100, payment = Math.min(50000, balance + interest), principal = payment - interest;
            balance -= principal;
            totalInterest += interest;
            totalPaid += payment;
            System.out.println("month " + month + ": interest=" + interest + " principal=" + principal + " balance=" + balance);
        }
        System.out.println("total interest: " + totalInterest);
        System.out.println("total paid: " + totalPaid);
    }
}
