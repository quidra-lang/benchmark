#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

int main() {
    std::string accesses = "BACBDABEADDCAEB";
    std::vector<char> cache;
    int hits = 0, misses = 0;
    for (char key : accesses) {
        std::vector<char>::iterator position = std::find(cache.begin(), cache.end(), key);
        bool hit = position != cache.end();
        char evicted = 0;
        if (hit) {
            ++hits;
            cache.erase(position);
        } else {
            ++misses;
            if (cache.size() == 3) {
                evicted = cache.back();
                cache.pop_back();
            }
        }
        cache.insert(cache.begin(), key);
        std::cout << key << ": " << (hit ? "hit" : "miss");
        if (evicted)
            std::cout << ", evict " << evicted;
        std::cout << " [";
        for (std::size_t i = 0; i < cache.size(); i++) {
            if (i)
                std::cout << ' ';
            std::cout << cache[i];
        }
        std::cout << "]\n";
    }
    std::cout << "hits: " << hits << " misses: " << misses << '\n';
}
