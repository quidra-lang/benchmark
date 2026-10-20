export function score(weights: number[], vector: number[]): number {
    let total = 0;
    for (let j = 0; j < weights.length; j++) total += weights[j] * vector[j];
    return total;
}
export function sigmoid(value: number): number {
    if (value >= 0) return 1 / (1 + Math.exp(-value));
    const e = Math.exp(value); return e / (1 + e);
}
export function loss(value: number, target: number): number {
    return Math.max(value, 0) - target * value + Math.log(1 + Math.exp(-Math.abs(value)));
}
export function evaluate(weights: number[], vectors: number[][], targets: number[], lambda = 0) {
    const scores: number[] = [], probabilities: number[] = [];
    let total = 0, squared = 0;
    for (let i = 0; i < vectors.length; i++) {
        const value = score(weights, vectors[i]); scores.push(value); probabilities.push(sigmoid(value));
        total += loss(value, targets[i]);
    }
    for (let j = 1; j < weights.length; j++) squared += weights[j] * weights[j];
    const average = total / vectors.length;
    return { scores, probabilities, loss: average, objective: average + lambda * squared / 2 };
}
export function gradient(weights: number[], vectors: number[][], targets: number[], lambda: number): number[] {
    const errors = vectors.map((vector, i) => sigmoid(score(weights, vector)) - targets[i]);
    return weights.map((weight, j) => {
        let total = 0;
        for (let i = 0; i < vectors.length; i++) total += errors[i] * vectors[i][j];
        const value = total / vectors.length; return j === 0 ? value : value + lambda * weight;
    });
}
export function hessian(weights: number[], vectors: number[][], lambda: number): number[][] {
    const variances = vectors.map(vector => { const p = sigmoid(score(weights, vector)); return p * (1 - p); });
    const matrix: number[][] = weights.map(() => Array(weights.length).fill(0));
    for (let j = 0; j < weights.length; j++) for (let k = 0; k <= j; k++) {
        let total = 0;
        for (let i = 0; i < vectors.length; i++) total += variances[i] * vectors[i][j] * vectors[i][k];
        let value = total / vectors.length;
        if (j === k && j >= 1) value += lambda;
        matrix[j][k] = value; matrix[k][j] = value;
    }
    return matrix;
}
