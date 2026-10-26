#include "ratings.hpp"

using Matrix = std::vector<Values>;
static Values choleskySolve(const Matrix& matrix, const Values& vector) {
    int count = static_cast<int>(vector.size()); Matrix lower(count, Values(count)); Values forward(count), result(count);
    for (int i = 0; i < count; ++i) for (int j = 0; j <= i; ++j) { double sum = 0; for (int k = 0; k < j; ++k) sum += lower[i][k] * lower[j][k]; lower[i][j] = i == j ? std::sqrt(matrix[i][i] - sum) : (matrix[i][j] - sum) / lower[j][j]; }
    for (int i = 0; i < count; ++i) { double sum = 0; for (int k = 0; k < i; ++k) sum += lower[i][k] * forward[k]; forward[i] = (vector[i] - sum) / lower[i][i]; }
    for (int i = count - 1; i >= 0; --i) { double sum = 0; for (int k = i + 1; k < count; ++k) sum += lower[k][i] * result[k]; result[i] = (forward[i] - sum) / lower[i][i]; }
    return result;
}
static Values gaussianSolve(Matrix matrix, Values vector) {
    int count = static_cast<int>(vector.size()); Values result(count);
    for (int k = 0; k < count; ++k) {
        int pivot = k; for (int row = k + 1; row < count; ++row) if (std::abs(matrix[row][k]) > std::abs(matrix[pivot][k])) pivot = row;
        std::swap(matrix[k], matrix[pivot]); std::swap(vector[k], vector[pivot]);
        for (int i = k + 1; i < count; ++i) { double factor = matrix[i][k] / matrix[k][k]; for (int j = k; j < count; ++j) matrix[i][j] -= factor * matrix[k][j]; vector[i] -= factor * vector[k]; }
    }
    for (int i = count - 1; i >= 0; --i) { double sum = 0; for (int j = i + 1; j < count; ++j) sum += matrix[i][j] * result[j]; result[i] = (vector[i] - sum) / matrix[i][i]; }
    return result;
}
Values colleyRatings(int count, const Matches& matches) {
    Matrix matrix(count, Values(count)); Integers balance(count); Values vector(count);
    for (int i = 0; i < count; ++i) matrix[i][i] = 2;
    for (const Match& match : matches) { int home = match.home, away = match.away; ++matrix[home][home]; ++matrix[away][away]; --matrix[home][away]; --matrix[away][home]; if (match.margin() > 0) { ++balance[home]; --balance[away]; } else if (match.margin() < 0) { --balance[home]; ++balance[away]; } }
    for (int i = 0; i < count; ++i) vector[i] = 1 + balance[i] / 2.0;
    return choleskySolve(matrix, vector);
}
std::pair<Values, double> masseyRatings(int count, const Matches& matches) {
    Matrix matrix(count + 1, Values(count + 1)); Values vector(count + 1);
    for (const Match& match : matches) {
        int home = match.home, away = match.away; ++matrix[home][home]; ++matrix[away][away]; --matrix[home][away]; --matrix[away][home]; ++matrix[home][count]; ++matrix[count][home]; --matrix[away][count]; --matrix[count][away]; ++matrix[count][count];
        vector[home] += match.margin(); vector[away] -= match.margin(); vector[count] += match.margin();
    }
    matrix[count - 1].assign(count + 1, 1); matrix[count - 1][count] = 0; vector[count - 1] = 0;
    Values solution = gaussianSolve(matrix, vector); double advantage = solution.back(); solution.pop_back(); return {solution, advantage};
}
