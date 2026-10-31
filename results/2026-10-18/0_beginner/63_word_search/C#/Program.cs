using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] board = { "MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
    "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR" };
string[] directions = { "E", "SE", "S", "SW", "W", "NW", "N", "NE" };
int[] dr = { 0, 1, 1, 1, 0, -1, -1, -1 }, dc = { 1, 1, 0, -1, -1, -1, 0, 1 };
foreach (string word in new[] { "TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT" })
{
    string result = "not found";
    bool found = false;
    for (int r = 0; r < 10 && !found; r++)
    {
        for (int c = 0; c < 10 && !found; c++)
        {
            for (int d = 0; d < 8; d++)
            {
                bool match = Enumerable.Range(0, word.Length).All(k =>
                {
                    int nr = r + k * dr[d], nc = c + k * dc[d];
                    return nr >= 0 && nr < 10 && nc >= 0 && nc < 10 && board[nr][nc] == word[k];
                });
                if (match)
                {
                    result = $"({r}, {c}) {directions[d]}";
                    found = true;
                    break;
                }
            }
        }
    }
    Console.WriteLine($"{word}: {result}");
}
