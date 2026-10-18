using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[][] boards = { new[] {"XXX","OO.","O.X"}, new[] {"X.O",".X.","O.."},
    new[] {"XO.",".OX","XO."}, new[] {"XOX","XOO","OXX"},
    new[] {"X.O","XO.","O.X"}, new[] {"XOX","OXO","OXX"} };
int[][] lines = { new[] {0,1,2},new[] {3,4,5},new[] {6,7,8},new[] {0,3,6},
    new[] {1,4,7},new[] {2,5,8},new[] {0,4,8},new[] {2,4,6} };
for (int i = 0; i < boards.Length; i++) {
    string cells = string.Concat(boards[i]);
    string result = cells.Contains('.') ? "in progress" : "draw";
    foreach (int[] line in lines) {
        char mark = cells[line[0]];
        if (mark != '.' && mark == cells[line[1]] && mark == cells[line[2]]) {
            result = mark + " wins";
            break;
        }
    }
    Console.WriteLine($"board {i + 1}: {result}");
}
