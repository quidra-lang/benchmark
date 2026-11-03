using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

sealed class Tokenizer
{
    public List<string> Words { get; } = new();
    public List<string> Bigrams { get; } = new();
    public List<string> BigramTerms { get; }
    public int RawCount { get; }
    public int StopwordCount { get; }
    public int ShortCount { get; }

    public Tokenizer(string text, HashSet<string> stopwords)
    {
        foreach (Match match in Regex.Matches(text, "[A-Za-z0-9]+"))
        {
            string word = match.Value.ToLowerInvariant();
            RawCount++;
            if (stopwords.Contains(word)) StopwordCount++;
            else if (word.Length == 1) ShortCount++;
            else Words.Add(word);
        }
        for (int i = 1; i < Words.Count; i++) Bigrams.Add(Words[i - 1] + "_" + Words[i]);
        BigramTerms = new List<string>(Words);
        BigramTerms.AddRange(Bigrams);
    }

    public List<string> Terms(bool useBigrams) => useBigrams ? BigramTerms : Words;
}
