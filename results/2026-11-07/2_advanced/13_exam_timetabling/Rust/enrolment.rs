use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};

pub struct Course {
    pub id: String,
    pub duration: usize,
    pub name: String,
    pub students: Vec<String>,
}

impl Course {
    pub fn size(&self) -> usize {
        self.students.len()
    }
}

pub type StudentCourses = BTreeMap<String, Vec<usize>>;

pub fn read_records(path: &str) -> io::Result<Vec<(usize, Vec<String>)>> {
    Ok(fs::read_to_string(path)?
        .lines()
        .enumerate()
        .skip(1)
        .map(|(index, line)| (index + 1, line.split(',').map(str::to_owned).collect()))
        .collect())
}

pub fn load_courses(path: &str, errors: &mut Vec<String>) -> io::Result<Vec<Course>> {
    let mut courses = BTreeMap::new();
    for (number, fields) in read_records(path)? {
        let id = &fields[0];
        if courses.contains_key(id) {
            errors.push(format!("courses.csv line {number}: duplicate course {id}"));
        } else {
            courses.insert(id.clone(), Course {
                id: id.clone(),
                duration: fields[1].parse().unwrap(),
                name: fields[2].clone(),
                students: Vec::new(),
            });
        }
    }
    Ok(courses.into_values().collect())
}

pub fn load_enrolments(
    path: &str,
    courses: &mut [Course],
    errors: &mut Vec<String>,
) -> io::Result<StudentCourses> {
    let indices: BTreeMap<_, _> = courses.iter().enumerate()
        .map(|(index, course)| (course.id.clone(), index)).collect();
    let mut accepted = BTreeSet::new();
    let mut students = StudentCourses::new();
    for (number, fields) in read_records(path)? {
        let student = &fields[0];
        let id = &fields[1];
        let Some(&course) = indices.get(id) else {
            errors.push(format!("enrolments.csv line {number}: unknown course {id}"));
            continue;
        };
        if !accepted.insert((student.clone(), course)) {
            errors.push(format!("enrolments.csv line {number}: duplicate enrolment {student} {id}"));
            continue;
        }
        courses[course].students.push(student.clone());
        students.entry(student.clone()).or_default().push(course);
    }
    for course in courses {
        course.students.sort();
    }
    for enrolled in students.values_mut() {
        enrolled.sort_unstable();
    }
    Ok(students)
}
