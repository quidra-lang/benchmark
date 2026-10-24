using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

bool[,] black = new bool[11,11];
int r = 5, c = 5, direction = 0;
int[] dr = { -1,0,1,0 }, dc = { 0,1,0,-1 };
for (int step = 0; step < 300; step++) {
    direction = (direction + (black[r,c] ? 3 : 1)) % 4;
    black[r,c] = !black[r,c];
    r = (r + dr[direction] + 11) % 11;
    c = (c + dc[direction] + 11) % 11;
}
int count = 0;
for (int row = 0; row < 11; row++) {
    for (int column = 0; column < 11; column++) {
        if (black[row,column]) count++;
        Console.Write(row == r && column == c ? 'A' : black[row,column] ? '#' : '.');
    }
    Console.WriteLine();
}
Console.WriteLine($"black: {count}");
