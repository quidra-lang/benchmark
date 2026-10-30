#include "irc.hpp"
std::string Client::addressee() const { return nickname.value_or("*"); }
std::string Client::prefix() const {
    return nickname.value_or("*") + "!" + username.value_or("*") + "@" + hostname;
}
std::string Client::mode() const { return invisible ? "+i" : "+"; }
void Client::use_token(int time, int capacity, int interval) {
    if (tokens == capacity)
        refill_time = time + interval;
    --tokens;
}
void Client::refill(int time, int capacity, int interval) {
    if (refill_time == time) {
        ++tokens;
        if (tokens < capacity)
            refill_time = time + interval;
        else
            refill_time.reset();
    }
}
