using System.Text;

static class PpmWriter
{
    public static void WritePpm(string path, Rgb[][] image)
    {
        List<string> lines = ["P3",$"{image[0].Length} {image.Length}","255"]; lines.AddRange(image.Select(row => string.Join(' ',row.Select(c => c.ToString())))); File.WriteAllText(path,string.Join('\n',lines) + "\n",new UTF8Encoding(false));
    }
    public static void WritePreview(string path, Rgb[][] image)
    {
        const string ramp = "@%#*+=-:,."; StringBuilder text = new();
        for (int top = 0; top < image.Length; top += 4) { for (int left = 0; left < image[0].Length; left += 2) { int total = 0; for (int y = top; y < top + 4; y++) for (int x = left; x < left + 2; x++) { Rgb c = image[y][x]; total += 299 * c.R + 587 * c.G + 114 * c.B; } text.Append(ramp[(total / 8000) * 10 / 256]); } text.Append('\n'); } File.WriteAllText(path,text.ToString(),new UTF8Encoding(false));
    }
}
