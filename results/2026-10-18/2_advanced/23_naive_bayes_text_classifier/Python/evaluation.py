from math import gcd


def real_text(value):
    text = f"{value:.4f}"
    if text == "-0.0000":
        return "0.0000"
    return text


def proportion_text(numerator, denominator):
    return f"{numerator}/{denominator} {real_text(numerator / denominator)}"


def fraction_text(numerator, denominator):
    if denominator == 0:
        return "- -"
    divisor = gcd(numerator, denominator)
    return proportion_text(numerator // divisor, denominator // divisor)


class Evaluation:
    def __init__(self, class_count, truths, predictions):
        self.matrix = [[0] * class_count for _ in range(class_count)]
        for truth, predicted in zip(truths, predictions):
            self.matrix[truth][predicted] += 1
        self.total = len(truths)
        self.correct = sum(self.matrix[label][label] for label in range(class_count))
        self.micro_f1 = self.correct / self.total
        f1_sum = 0.0
        scored = 0
        for label in range(class_count):
            denominator = self.predicted_count(label) + self.support(label)
            if denominator > 0:
                f1_sum += 2 * self.matrix[label][label] / denominator
                scored += 1
        self.macro_f1 = f1_sum / scored

    def support(self, label):
        return sum(self.matrix[label])

    def predicted_count(self, label):
        return sum(row[label] for row in self.matrix)

    def lines(self, names):
        lines = ["true\\predicted " + " ".join(names)]
        for label, name in enumerate(names):
            lines.append(" ".join([name] + [str(count) for count in self.matrix[label]]))
        for label, name in enumerate(names):
            hits = self.matrix[label][label]
            predicted = self.predicted_count(label)
            support = self.support(label)
            lines.append(
                f"class {name} precision {fraction_text(hits, predicted)}"
                f" recall {fraction_text(hits, support)}"
                f" f1 {fraction_text(2 * hits, predicted + support)} support {support}"
            )
        lines.append(f"micro_f1 {real_text(self.micro_f1)} macro_f1 {real_text(self.macro_f1)}")
        return lines
