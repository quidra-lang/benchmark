let balance = 1000000, month = 0, totalInterest = 0, totalPaid = 0;
while (balance > 0) {
  month++;
  const interest = Math.floor(balance / 100);
  const payment = Math.min(50000, balance + interest);
  const principal = payment - interest;
  balance -= principal;
  totalInterest += interest;
  totalPaid += payment;
  console.log(`month ${month}: interest=${interest} principal=${principal} balance=${balance}`);
}
console.log(`total interest: ${totalInterest}`);
console.log(`total paid: ${totalPaid}`);
