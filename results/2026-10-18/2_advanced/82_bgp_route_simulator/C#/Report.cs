using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class Report {
    public static string PathText(List<int> path) => string.Join(",", path);
    public static string AttributeText(Decision.Attribute attribute) =>
        "path " + PathText(attribute.path) + " origin " + attribute.origin + " med " + attribute.med
        + " comm " + Policy.CommunityText(attribute.communities);
    public static string RouteText(Decision.Route route) {
        if (route == null)
            return "NONE";
        string comm = Policy.CommunityText(route.communities);
        if (route.Local())
            return "LOCAL origin " + route.origin + " comm " + comm;
        return "next " + route.Neighbor() + " path " + PathText(route.path) + " link " +
               route.link.name + " lp " + route.localPref + " med " + route.med + " origin " +
               route.origin + " comm " + comm;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(System.IO.Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"),
                          Encoding.ASCII);
    }
}
