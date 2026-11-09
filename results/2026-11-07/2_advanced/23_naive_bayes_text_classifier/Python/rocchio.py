from collections import Counter
import math


def vector_length(values):
    total = 0.0
    for value in values:
        total += value * value
    return math.sqrt(total)


class RocchioPrediction:
    def __init__(self, similarities):
        self.ranking = sorted(range(len(similarities)), key=lambda label: -similarities[label])
        self.label = self.ranking[0]
        self.score = similarities[self.label]


class Rocchio:
    def __init__(self, sequences, labels, class_count, frequencies):
        self.idf = [math.log(len(sequences) / frequency) for frequency in frequencies]
        sums = [[0.0] * len(frequencies) for _ in range(class_count)]
        documents = [0] * class_count
        for sequence, label in zip(sequences, labels):
            documents[label] += 1
            vector = self.vector(sequence)
            length = vector_length(value for _, value in vector)
            if length > 0:
                row = sums[label]
                for term, value in vector:
                    row[term] += value / length
        self.centroids = [
            [value / documents[label] for value in row] for label, row in enumerate(sums)
        ]
        self.lengths = [vector_length(centroid) for centroid in self.centroids]

    def vector(self, sequence):
        frequencies = Counter(sequence)
        return [(term, frequencies[term] * self.idf[term]) for term in sorted(frequencies)]

    def predict(self, sequence):
        vector = self.vector(sequence)
        length = vector_length(value for _, value in vector)
        similarities = []
        for centroid, centroid_length in zip(self.centroids, self.lengths):
            if length > 0 and centroid_length > 0:
                product = 0.0
                for term, value in vector:
                    product += value * centroid[term]
                similarities.append(product / (length * centroid_length))
            else:
                similarities.append(0.0)
        return RocchioPrediction(similarities)
