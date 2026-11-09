package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Course struct {
	id       string
	duration int
	name     string
	students []string
}

func (c *Course) size() int { return len(c.students) }

type Record struct {
	number int
	fields []string
}

func integer(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func readRecords(path string) []Record {
	lines := readLines(path)
	records := make([]Record, 0, len(lines)-1)
	for index, line := range lines[1:] {
		records = append(records, Record{index + 2, strings.Split(line, ",")})
	}
	return records
}
func loadCourses(path string, errors *[]string) map[string]*Course {
	courses := map[string]*Course{}
	for _, record := range readRecords(path) {
		fields := record.fields
		id := fields[0]
		if _, exists := courses[id]; exists {
			*errors = append(*errors, fmt.Sprintf("courses.csv line %d: duplicate course %s", record.number, id))
			continue
		}
		courses[id] = &Course{id: id, duration: integer(fields[1]), name: fields[2]}
	}
	return courses
}
func loadEnrolments(path string, courses map[string]*Course, errors *[]string) map[string][]string {
	accepted := map[[2]string]bool{}
	students := map[string][]string{}
	for _, record := range readRecords(path) {
		student, id := record.fields[0], record.fields[1]
		pair := [2]string{student, id}
		if _, exists := courses[id]; !exists {
			*errors = append(*errors, fmt.Sprintf("enrolments.csv line %d: unknown course %s", record.number, id))
		} else if accepted[pair] {
			*errors = append(*errors, fmt.Sprintf("enrolments.csv line %d: duplicate enrolment %s %s", record.number, student, id))
		} else {
			accepted[pair] = true
			courses[id].students = append(courses[id].students, student)
			students[student] = append(students[student], id)
		}
	}
	for _, course := range courses {
		sort.Strings(course.students)
	}
	for _, ids := range students {
		sort.Strings(ids)
	}
	return students
}
