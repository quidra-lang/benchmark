#include <stdio.h>
#include <string.h>

void merge_sort(int *a, int l, int r, int *count) {
    if (l == r)
        return;
    int m = (l + r) / 2;
    merge_sort(a, l, m, count);
    merge_sort(a, m + 1, r, count);
    int temp[10], i = l, j = m + 1, k = 0;
    while (i <= m && j <= r) {
        if (a[i] < a[j]) {
            temp[k++] = a[i++];
        } else {
            temp[k++] = a[j++];
            *count += m - i + 1;
        }
    }
    while (i <= m)
        temp[k++] = a[i++];
    while (j <= r)
        temp[k++] = a[j++];
    memcpy(a + l, temp, (size_t)(r - l + 1) * sizeof(*a));
    printf("merge [%d..%d]:", l, r);
    for (k = l; k <= r; k++)
        printf(" %d", a[k]);
    putchar('\n');
}

int main(void) {
    int a[] = {47, 12, 85, 33, 6, 71, 29, 58, 90, 14};
    int inversions = 0;
    merge_sort(a, 0, 9, &inversions);
    printf("sorted:");
    for (int i = 0; i < 10; i++)
        printf(" %d", a[i]);
    printf("\ninversions: %d\n", inversions);
    return 0;
}
