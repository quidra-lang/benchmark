using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int balance = 1000000, month = 0, totalInterest = 0, totalPaid = 0;
while (balance > 0) {
    month++;
    int interest = balance / 100, payment = Math.Min(50000, balance + interest), principal = payment - interest;
    balance -= principal; totalInterest += interest; totalPaid += payment;
    Console.WriteLine($"month {month}: interest={interest} principal={principal} balance={balance}");
}
Console.WriteLine($"total interest: {totalInterest}");
Console.WriteLine($"total paid: {totalPaid}");
