using System;
using System.Globalization;
using System.Text;

for (int i = 1; i <= 9; i++)
{
    var row = new StringBuilder();
    for (int j = 1; j <= 9; j++)
        row.Append((i * j).ToString(CultureInfo.InvariantCulture).PadLeft(3));
    Console.WriteLine(row);
}
