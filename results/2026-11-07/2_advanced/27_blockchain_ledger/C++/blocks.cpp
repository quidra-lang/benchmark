#include "ledger.hpp"
std::string Block::header() const {
    return std::to_string(height) + "|" + previous + "|" + root + "|" + std::to_string(time) + "|" +
           std::to_string(difficulty) + "|" + std::to_string(nonce);
}
void Block::hash_header() {
    hash = digest(header());
}
Integer Block::size() const {
    Integer size = 0;
    for (std::size_t i = 1; i < transactions.size(); ++i)
        size += transactions[i].size();
    return size;
}
bool Block::proof() const {
    return hash.compare(0, difficulty, std::string(difficulty, '0')) == 0;
}
Block parse_block(const std::vector<std::string> &fields, const std::vector<std::string> &texts) {
    Block block;
    block.height = std::stoi(fields[3]);
    block.previous = fields[4];
    block.root = fields[5];
    block.time = std::stoll(fields[6]);
    block.difficulty = std::stoi(fields[7]);
    block.nonce = std::stoll(fields[8]);
    for (const std::string &text : texts)
        block.transactions.push_back(parse_transaction(text));
    block.hash_header();
    return block;
}
Block mine_block(int height, const std::string &previous, std::vector<Transaction> transactions, Integer time,
                 int difficulty) {
    Block block;
    block.height = height;
    block.previous = previous;
    block.transactions = std::move(transactions);
    block.time = time;
    block.difficulty = difficulty;
    std::vector<std::string> ids;
    for (const Transaction &tx : block.transactions)
        ids.push_back(tx.id);
    block.root = merkle(ids);
    do {
        block.hash_header();
        if (block.proof())
            break;
        ++block.nonce;
    } while (true);
    return block;
}
std::string context_error(const Block &block, Integer limit) {
    if (!block.proof())
        return "bad-pow";
    std::vector<std::string> ids;
    for (const Transaction &tx : block.transactions)
        ids.push_back(tx.id);
    if (merkle(ids) != block.root)
        return "bad-merkle";
    if (!block.transactions[0].coinbase() || block.transactions[0].coinbase_height != block.height)
        return "bad-structure";
    for (std::size_t i = 1; i < block.transactions.size(); ++i)
        if (block.transactions[i].coinbase())
            return "bad-structure";
    return block.size() > limit ? "too-large" : "";
}
