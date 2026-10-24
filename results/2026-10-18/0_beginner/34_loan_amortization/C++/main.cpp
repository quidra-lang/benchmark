#include <iostream>
#include <algorithm>

int main() {
    int balance = 1000000, month = 0, total_interest = 0, total_paid = 0;
    while (balance > 0) {
        ++month;
        int interest = balance / 100, payment = std::min(50000, balance + interest), principal = payment - interest;
        balance -= principal;
        total_interest += interest;
        total_paid += payment;
        std::cout << "month " << month << ": interest=" << interest << " principal=" << principal << " balance="
            << balance << '\n';
    }
    std::cout << "total interest: " << total_interest << "\ntotal paid: " << total_paid << '\n';
}
