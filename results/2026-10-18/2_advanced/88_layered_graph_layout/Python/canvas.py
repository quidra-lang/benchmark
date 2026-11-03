"""Sparse character layers, coordinate mapping, and final drawing rows."""


class Canvas:
    def __init__(self, direction, main_length, secondary_length):
        self.direction = direction
        self.main_length = main_length
        self.vertical = direction in ("TB", "BT")
        self.rows = main_length if self.vertical else secondary_length
        self.columns = secondary_length if self.vertical else main_length
        self.line_bits = {}
        self.arrows = {}
        self.boxes = {}
        self.highlighted = set()
        self.main_character = "|" if self.vertical else "-"
        self.secondary_character = "-" if self.vertical else "|"

    def cell(self, main, secondary):
        if self.direction in ("BT", "RL"):
            main = self.main_length - 1 - main
        return (main, secondary) if self.vertical else (secondary, main)

    def add_line(self, main, secondary, character):
        cell = self.cell(main, secondary)
        bit = {"|": 1, "-": 2, "+": 4}[character]
        self.line_bits[cell] = self.line_bits.get(cell, 0) | bit

    def main_line(self, start, end, secondary):
        for main in range(start, end + 1):
            self.add_line(main, secondary, self.main_character)

    def segment(self, start, gap, first, second, offset):
        if first == second:
            self.main_line(start, start + gap - 1, first)
            return
        self.main_line(start, start + offset - 1, first)
        self.add_line(start + offset, first, "+")
        self.add_line(start + offset, second, "+")
        for secondary in range(min(first, second) + 1, max(first, second)):
            self.add_line(start + offset, secondary, self.secondary_character)
        self.main_line(start + offset + 1, start + gap - 1, second)

    def arrow(self, point, reversed_edge):
        forward = {"TB": "v", "BT": "^", "LR": ">", "RL": "<"}
        backward = {"TB": "^", "BT": "v", "LR": "<", "RL": ">"}
        self.arrows[self.cell(*point)] = (backward if reversed_edge else forward)[self.direction]

    def highlight_route(self, points):
        for (row1, column1), (row2, column2) in zip(points, points[1:]):
            row_step = (row2 > row1) - (row2 < row1)
            column_step = (column2 > column1) - (column2 < column1)
            distance = abs(row2 - row1) + abs(column2 - column1)
            for step in range(distance + 1):
                self.highlighted.add((row1 + step * row_step, column1 + step * column_step))

    def box(self, label, band_start, coordinate, left, on_path):
        text = "{" + label + "}" if on_path else "[" + label + "]"
        if self.vertical:
            row, column = self.cell(band_start, coordinate - left)
        elif self.direction == "LR":
            row, column = coordinate, band_start
        else:
            row, column = coordinate, self.main_length - band_start - len(text)
        for offset, character in enumerate(text):
            self.boxes[row, column + offset] = character

    def character(self, row, column):
        cell = row, column
        if cell in self.boxes:
            return self.boxes[cell]
        if cell in self.arrows:
            return self.arrows[cell]
        if cell in self.highlighted:
            return "#"
        return {0: " ", 1: "|", 2: "-", 4: "+"}.get(self.line_bits.get(cell, 0), "+")

    def crossing_cells(self):
        return sum(bits & 3 == 3 for bits in self.line_bits.values())

    def drawing_lines(self):
        lines = ["    " + "".join(str(column % 10) for column in range(self.columns))]
        for row in range(self.rows):
            characters = "".join(self.character(row, column) for column in range(self.columns))
            lines.append((f"{row:3d} " + characters).rstrip())
        return lines
