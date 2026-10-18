#include <iostream>
#include <vector>

int merge_sort(std::vector<int> &a, int l, int r) {
    if (l == r)
        return 0;
    int m = (l + r) / 2, count = merge_sort(a, l, m);
    count += merge_sort(a, m + 1, r);
    std::vector<int> temp;
    int i = l, j = m + 1;
    while (i <= m && j <= r) {
        if (a[i] < a[j])
            temp.push_back(a[i++]);
        else {
            temp.push_back(a[j++]);
            count += m - i + 1;
        }
    }
    while (i <= m)
        temp.push_back(a[i++]);
    while (j <= r)
        temp.push_back(a[j++]);
    for (int k = l; k <= r; k++)
        a[k] = temp[k - l];
    std::cout << "merge [" << l << ".." << r << "]:";
    for (int k = l; k <= r; k++)
        std::cout << ' ' << a[k];
    std::cout << '\n';
    return count;
}

int main() {
    std::vector<int> a = {47, 12, 85, 33, 6, 71, 29, 58, 90, 14};
    int inversions = merge_sort(a, 0, 9);
    std::cout << "sorted:";
    for (int n : a)
        std::cout << ' ' << n;
    std::cout << "\ninversions: " << inversions << '\n';
}
