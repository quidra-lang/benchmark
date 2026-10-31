final class Numerics {
    static final double Z = 1.959963984540054;
    static double[][] zeros(int n) {
        return new double[n][n];
    }
    static double[] solve(double[][] matrix, double[] right) {
        int n = right.length;
        double[][] a = zeros(n);
        for (int i = 0; i < n; i++)
            a[i] = matrix[i].clone();
        double[] b = right.clone(), x = new double[n];
        for (int k = 0; k < n; k++)
            for (int i = k + 1; i < n; i++) {
                double f = a[i][k] / a[k][k];
                for (int j = k; j < n; j++)
                    a[i][j] -= f * a[k][j];
                b[i] -= f * b[k];
            }
        for (int i = n - 1; i >= 0; i--) {
            double value = b[i];
            for (int j = i + 1; j < n; j++)
                value -= a[i][j] * x[j];
            x[i] = value / a[i][i];
        }
        return x;
    }
    static double[][] inverse(double[][] matrix) {
        int n = matrix.length;
        double[][] result = zeros(n);
        for (int c = 0; c < n; c++) {
            double[] unit = new double[n];
            unit[c] = 1;
            double[] y = solve(matrix, unit);
            for (int a = 0; a < n; a++)
                result[a][c] = y[a];
        }
        return result;
    }
    static double logGamma(double a) {
        double[] coefficients = {76.18009172947146,  -86.50532032941677,   24.01409824083091,
                                 -1.231739572450155, 0.001208650973866179, -0.000005395239384953};
        double xi0 = a + 5.5, xi1 = xi0 - (a + 0.5) * Math.log(xi0), sigma = 1.000000000190015, y = a;
        for (double coefficient : coefficients) {
            y += 1;
            sigma += coefficient / y;
        }
        return -xi1 + Math.log(2.5066282746310005 * sigma / a);
    }
    static double gammaQ(double a, double x) {
        if (x == 0)
            return 1;
        double pref = Math.exp(-x + a * Math.log(x) - logGamma(a));
        if (x < a + 1) {
            double alpha = a, xi = 1 / a, sigma = xi;
            for (int i = 0; i < 1000; i++) {
                alpha += 1;
                xi *= x / alpha;
                sigma += xi;
                if (Math.abs(xi) < Math.abs(sigma) * 1e-15)
                    break;
            }
            return 1 - sigma * pref;
        }
        double eps = 1e-300, b = x + 1 - a, c = 1 / eps, d = 1 / b, h = d;
        for (int i = 1; i <= 1000; i++) {
            double an = -i * (i - a);
            b += 2;
            d = an * d + b;
            if (Math.abs(d) < eps)
                d = eps;
            c = b + an / c;
            if (Math.abs(c) < eps)
                c = eps;
            d = 1 / d;
            double delta = d * c;
            h *= delta;
            if (Math.abs(delta - 1) < 1e-15)
                break;
        }
        return pref * h;
    }
    static double pvalue(double chi2, int degrees) {
        return gammaQ(degrees / 2.0, chi2 / 2);
    }
}
