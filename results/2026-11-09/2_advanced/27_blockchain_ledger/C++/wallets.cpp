#include "ledger.hpp"
std::vector<Wallet> read_wallets() {
    std::ifstream file("input/wallets.txt");
    std::vector<Wallet> result;
    Wallet wallet;
    while (file >> wallet.name >> wallet.secret) {
        wallet.address = digest("addr:" + wallet.secret).substr(0, 16);
        result.push_back(wallet);
    }
    return result;
}
std::string sign(const std::string &secret, int index, const std::string &body) {
    return digest(secret + ":" + std::to_string(index) + ":" + body).substr(0, 16);
}
