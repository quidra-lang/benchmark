fn main() {
    let (mut balance, mut month, mut total_interest, mut total_paid) = (1000000_i32, 0, 0, 0);
    while balance > 0 {
        month += 1;
        let interest = balance / 100;
        let payment = 50000.min(balance + interest);
        let principal = payment - interest;
        balance -= principal;
        total_interest += interest;
        total_paid += payment;
        println!("month {}: interest={} principal={} balance={}", month, interest, principal, balance);
    }
    println!("total interest: {}\ntotal paid: {}", total_interest, total_paid);
}
