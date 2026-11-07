#include <algorithm>
#include <iostream>
#include <vector>

void merge_sort(std::vector<int> &a, int l, int r, int &count) {
    if (l == r)
        return;
    int m = (l + r) / 2;
    merge_sort(a, l, m, count);
    merge_sort(a, m + 1, r, count);
    std::vector<int> temp;
    int i = l, j = m + 1;
    while (i <= m && j <= r) {
        if (a[i] < a[j]) {
            temp.push_back(a[i++]);
        } else {
            temp.push_back(a[j++]);
            count += m - i + 1;
        }
    }
    temp.insert(temp.end(), a.begin() + i, a.begin() + m + 1);
    temp.insert(temp.end(), a.begin() + j, a.begin() + r + 1);
    std::copy(temp.begin(), temp.end(), a.begin() + l);
    std::cout << "merge [" << l << ".." << r << "]:";
    for (int k = l; k <= r; k++)
        std::cout << ' ' << a[k];
    std::cout << '\n';
}

int main() {
    std::vector<int> a = {47, 12, 85, 33, 6, 71, 29, 58, 90, 14};
    int inversions = 0;
    merge_sort(a, 0, 9, inversions);
    std::cout << "sorted:";
    for (int n : a)
        std::cout << ' ' << n;
    std::cout << "\ninversions: " << inversions << '\n';
}
