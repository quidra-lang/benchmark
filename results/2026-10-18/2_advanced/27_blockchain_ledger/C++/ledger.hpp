#pragma once
#include <algorithm>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using Integer = std::int64_t;
using Reference = std::pair<std::string, int>;
using Output = std::pair<std::string, Integer>;
std::vector<std::string> split(const std::string &, char);
std::string digest(const std::string &);
std::string merkle(std::vector<std::string>);
std::string short_hash(const std::string &);
struct Wallet {
    std::string name, secret, address;
};
std::vector<Wallet> read_wallets();
std::string sign(const std::string &, int, const std::string &);
struct Coin {
    std::string address;
    Integer amount;
    int height;
    bool coinbase;
    bool mature(int, int) const;
};
using Utxo = std::map<Reference, Coin>;
using Owners = std::map<std::string, Wallet>;
struct Transaction {
    std::string text, id, body;
    std::vector<Reference> inputs;
    std::vector<Output> outputs;
    std::vector<std::string> signatures;
    int coinbase_height = -1;
    bool coinbase() const {
        return coinbase_height >= 0;
    }
    Integer size() const {
        return text.size();
    }
    Integer total() const;
};
Transaction parse_transaction(const std::string &);
Transaction payment(const std::vector<Reference> &, const std::vector<Output> &, const std::string &);
Transaction coinbase(int, const std::vector<Output> &);
std::pair<std::string, Integer> check_transaction(const Transaction &, const Utxo &,
                                                  const std::set<Reference> &, int, const Owners &, int);
void apply(Utxo &, const Transaction &, int);
struct Block {
    int height = 0, difficulty = 0;
    Integer time = 0, nonce = 0;
    std::string previous, root, hash;
    std::vector<Transaction> transactions;
    std::string header() const;
    void hash_header();
    Integer size() const;
    bool proof() const;
};
Block parse_block(const std::vector<std::string> &, const std::vector<std::string> &);
Block mine_block(int, const std::string &, std::vector<Transaction>, Integer, int);
std::string context_error(const Block &, Integer);
struct Record {
    Block block;
    Record *parent;
    Utxo utxo;
    std::vector<Integer> transaction_fees;
    std::string source;
    Integer fees = 0, work = 1;
    Record(Block, Record *, Utxo, std::vector<Integer>, std::string);
};
Integer reward(int, Integer, int);
Record *ancestor(Record *, int);
Record *fork_point(Record *, Record *);
std::vector<Record *> chain_to(Record *);
Integer median_time(Record *);
int required_difficulty(Record *, int, int, Integer);
