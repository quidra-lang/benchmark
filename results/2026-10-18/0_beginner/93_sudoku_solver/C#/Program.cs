using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static bool Solve(int[,] board, ref long placements) {
    for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
            if (board[r,c] != 0) continue;
            for (int digit = 1; digit <= 9; digit++) {
                bool valid = true;
                for (int i = 0; i < 9; i++) {
                    if (board[r,i] == digit || board[i,c] == digit ||
                        board[r / 3 * 3 + i / 3,c / 3 * 3 + i % 3] == digit) valid = false;
                }
                if (!valid) continue;
                board[r,c] = digit;
                placements++;
                if (Solve(board,ref placements)) return true;
                board[r,c] = 0;
            }
            return false;
        }
    }
    return true;
}
string[] rows = { "800025000", "070080005", "260400070", "000001900", "010000040",
    "600200000", "900010000", "700000004", "020000036" };
int[,] board = new int[9,9];
for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) board[r,c] = rows[r][c] - '0';
}
long placements = 0;
Solve(board,ref placements);
for (int r = 0; r < 9; r++) {
    var values = Enumerable.Range(0,9).Select(c => board[r,c]);
    Console.WriteLine(string.Join(" ",values));
}
Console.WriteLine($"placements: {placements}");
