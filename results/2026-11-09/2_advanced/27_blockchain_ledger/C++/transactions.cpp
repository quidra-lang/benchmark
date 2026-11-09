#include "ledger.hpp"
std::vector<std::string> split(const std::string &text, char delimiter) {
    std::vector<std::string> parts;
    std::istringstream stream(text);
    std::string part;
    while (std::getline(stream, part, delimiter))
        parts.push_back(part);
    return parts;
}
bool Coin::mature(int at, int maturity) const {
    return !coinbase || height == 0 || at >= height + maturity;
}
Integer Transaction::total() const {
    Integer amount = 0;
    for (const Output &output : outputs)
        amount += output.second;
    return amount;
}
Transaction parse_transaction(const std::string &text) {
    Transaction tx;
    tx.text = text;
    tx.id = digest(text);
    const std::vector<std::string> fields = split(text, ';');
    for (const std::string &value : split(fields[1].substr(4), ',')) {
        const std::vector<std::string> pair = split(value, ':');
        tx.outputs.emplace_back(pair[0], std::stoll(pair[1]));
    }
    if (fields[0].compare(0, 3, "cb=") == 0)
        tx.coinbase_height = std::stoi(fields[0].substr(3));
    else {
        tx.body = fields[0] + ";" + fields[1];
        for (const std::string &value : split(fields[0].substr(3), ',')) {
            const std::vector<std::string> pair = split(value, ':');
            tx.inputs.emplace_back(pair[0], std::stoi(pair[1]));
        }
        tx.signatures = split(fields[2].substr(4), ',');
    }
    return tx;
}
template <class T> static std::string pairs_text(const std::vector<std::pair<std::string, T>> &values) {
    std::string text;
    for (const auto &value : values) {
        if (!text.empty())
            text += ',';
        text += value.first + ":" + std::to_string(value.second);
    }
    return text;
}
Transaction payment(const std::vector<Reference> &inputs, const std::vector<Output> &outputs,
                    const std::string &secret) {
    const std::string body = "in=" + pairs_text(inputs) + ";out=" + pairs_text(outputs);
    std::string text = body + ";sig=";
    for (std::size_t i = 0; i < inputs.size(); ++i) {
        if (i)
            text += ',';
        text += sign(secret, int(i), body);
    }
    return parse_transaction(text);
}
Transaction coinbase(int height, const std::vector<Output> &outputs) {
    return parse_transaction("cb=" + std::to_string(height) + ";out=" + pairs_text(outputs));
}
std::pair<std::string, Integer> check_transaction(const Transaction &tx, const Utxo &utxo,
                                                  const std::set<Reference> &spent, int height,
                                                  const Owners &owners, int maturity) {
    for (const Output &output : tx.outputs)
        if (!owners.count(output.first) || output.second == 0)
            return {"bad-output", 0};
    std::set<Reference> seen;
    Integer total = 0;
    for (std::size_t i = 0; i < tx.inputs.size(); ++i) {
        const Reference &ref = tx.inputs[i];
        if (spent.count(ref) || seen.count(ref))
            return {"double-spend", 0};
        const auto found = utxo.find(ref);
        if (found == utxo.end())
            return {"missing-input", 0};
        const Coin &coin = found->second;
        if (!coin.mature(height, maturity))
            return {"immature", 0};
        if (tx.signatures[i] != sign(owners.at(coin.address).secret, int(i), tx.body))
            return {"bad-sig", 0};
        seen.insert(ref);
        total += coin.amount;
    }
    if (total < tx.total())
        return {"overspend", 0};
    return {"", total - tx.total()};
}
void apply(Utxo &utxo, const Transaction &tx, int height) {
    for (const Reference &ref : tx.inputs)
        utxo.erase(ref);
    for (std::size_t i = 0; i < tx.outputs.size(); ++i) {
        const Output &output = tx.outputs[i];
        utxo[{tx.id, int(i)}] = {output.first, output.second, height, tx.coinbase()};
    }
}
