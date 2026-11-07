#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

static class Report
{
    public static string FixedWidthLine(string label, IEnumerable<string> cells, int labelWidth, int cellWidth) =>
        (label.PadRight(labelWidth) + string.Concat(cells.Select(cell => cell.PadLeft(cellWidth)))).TrimEnd();

    public static int RoundedPercent(int part, int whole) => (200 * part + whole) / (2 * whole);

    public static void WriteFiles(string directory, Dictionary<string, List<string>> files)
    {
        Directory.CreateDirectory(directory);
        foreach (var file in files)
            File.WriteAllText(Path.Combine(directory, file.Key), string.Join("\n", file.Value) + "\n", new UTF8Encoding(false));
    }
}
