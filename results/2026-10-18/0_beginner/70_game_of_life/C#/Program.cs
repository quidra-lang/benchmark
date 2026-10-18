using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] initial = { ".#......", "..#.....", "###.....", "........",
    "........", "........", ".....###", "........" };
bool[,] board = new bool[8,8];
for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) board[r,c] = initial[r][c] == '#';
}
for (int generation = 0; generation <= 4; generation++) {
    Console.WriteLine($"generation {generation}");
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) Console.Write(board[r,c] ? '#' : '.');
        Console.WriteLine();
    }
    if (generation == 4) break;
    bool[,] next = new bool[8,8];
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            int neighbors = 0;
            for (int dr = -1; dr <= 1; dr++) {
                for (int dc = -1; dc <= 1; dc++) {
                    if (dr == 0 && dc == 0) continue;
                    int nr = r + dr, nc = c + dc;
                    if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr,nc]) neighbors++;
                }
            }
            next[r,c] = neighbors == 3 || (board[r,c] && neighbors == 2);
        }
    }
    board = next;
}
int alive = 0;
foreach (bool cell in board) {
    if (cell) alive++;
}
Console.WriteLine($"alive: {alive}");
