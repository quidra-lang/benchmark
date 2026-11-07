using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

static void MergeSort(int[] values, int l, int r, ref int inversions)
{
    if (l == r) return;
    int m = (l + r) / 2;
    MergeSort(values, l, m, ref inversions);
    MergeSort(values, m + 1, r, ref inversions);
    int[] merged = new int[r - l + 1];
    int i = l, j = m + 1, k = 0;
    while (i <= m && j <= r)
    {
        if (values[i] < values[j])
        {
            merged[k++] = values[i++];
        }
        else
        {
            merged[k++] = values[j++];
            inversions += m - i + 1;
        }
    }
    while (i <= m) merged[k++] = values[i++];
    while (j <= r) merged[k++] = values[j++];
    Array.Copy(merged, 0, values, l, merged.Length);
    Console.WriteLine($"merge [{l}..{r}]: {string.Join(" ", merged)}");
}

int[] values = { 47, 12, 85, 33, 6, 71, 29, 58, 90, 14 };
int inversions = 0;
MergeSort(values, 0, values.Length - 1, ref inversions);
Console.WriteLine($"sorted: {string.Join(" ", values)}");
Console.WriteLine($"inversions: {inversions}");
