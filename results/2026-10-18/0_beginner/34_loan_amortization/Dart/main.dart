import 'dart:math' as math;

void main() {
    var balance = 1000000, month = 0, totalInterest = 0, totalPaid = 0;
    while (balance > 0) {
        month++;
        final interest = balance ~/ 100;
        final payment = math.min(50000, balance + interest);
        final principal = payment - interest;
        balance -= principal;
        totalInterest += interest;
        totalPaid += payment;
        print('month $month: interest=$interest principal=$principal balance=$balance');
    }
    print('total interest: $totalInterest\ntotal paid: $totalPaid');
}
