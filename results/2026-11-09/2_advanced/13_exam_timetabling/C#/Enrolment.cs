#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

sealed class Course
{
    public string Id { get; }
    public int Duration { get; }
    public string Name { get; }
    public List<string> Students { get; } = new();
    public int Size => Students.Count;

    public Course(string id, int duration, string name)
    {
        Id = id;
        Duration = duration;
        Name = name;
    }
}

static class Enrolment
{
    public static IEnumerable<string[]> Records(string path) =>
        File.ReadAllLines(path, Encoding.ASCII).Skip(1).Select(line => line.Split(','));

    public static SortedDictionary<string, Course> LoadCourses(string path, List<string> errors)
    {
        var courses = new SortedDictionary<string, Course>(StringComparer.Ordinal);
        int line = 1;
        foreach (string[] fields in Records(path))
        {
            line++;
            string id = fields[0];
            if (courses.ContainsKey(id))
                errors.Add($"courses.csv line {line}: duplicate course {id}");
            else courses[id] = new Course(id, int.Parse(fields[1]), fields[2]);
        }
        return courses;
    }

    public static SortedDictionary<string, List<string>> LoadEnrolments(
        string path, SortedDictionary<string, Course> courses, List<string> errors)
    {
        var accepted = new HashSet<(string, string)>();
        var students = new SortedDictionary<string, List<string>>(StringComparer.Ordinal);
        int line = 1;
        foreach (string[] fields in Records(path))
        {
            line++;
            string student = fields[0], id = fields[1];
            if (!courses.ContainsKey(id))
                errors.Add($"enrolments.csv line {line}: unknown course {id}");
            else if (!accepted.Add((student, id)))
                errors.Add($"enrolments.csv line {line}: duplicate enrolment {student} {id}");
            else
            {
                courses[id].Students.Add(student);
                if (!students.ContainsKey(student)) students[student] = new List<string>();
                students[student].Add(id);
            }
        }
        foreach (Course course in courses.Values) course.Students.Sort(StringComparer.Ordinal);
        foreach (List<string> ids in students.Values) ids.Sort(StringComparer.Ordinal);
        return students;
    }
}
