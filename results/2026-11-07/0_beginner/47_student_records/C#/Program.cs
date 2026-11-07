using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
string[] names = { "Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori" };
int[][] scores =
[
    [78, 85, 94], [88, 74, 82], [65, 90, 71], [80, 79, 85], [92, 88, 95], [70, 62, 78],
];
var students = names.Zip(scores, (name, row) => (Name: name, Total: row.Sum()))
    .OrderByDescending(student => student.Total)
    .ThenBy(student => student.Name, StringComparer.Ordinal)
    .ToArray();
int rank = 0, previous = -1;
for (int position = 0; position < students.Length; position++)
{
    var student = students[position];
    if (student.Total != previous) rank = position + 1;
    previous = student.Total;
    Console.WriteLine($"{rank}. {student.Name} total={student.Total} average={student.Total / 3.0:F2}");
}
