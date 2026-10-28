import java.nio.file.*;
import java.util.*;

final class Materials {
    record Material(char code, String name, double k, double rho, double cp) {}
    static List<Material> read() throws Exception {
        List<Material> materials = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input/materials.txt"))) {
            String[] w = line.split(" ");
            materials.add(new Material(w[0].charAt(0), w[1], Double.parseDouble(w[2]),
                                       Double.parseDouble(w[3]), Double.parseDouble(w[4])));
        }
        return materials;
    }
    static double capacity(Material m, double dx, double d) {
        return m.rho() * m.cp() * dx * dx * d;
    }
    static double interior(double k1, double k2, double d) {
        return 2 * k1 * k2 / (k1 + k2) * d;
    }
    static double fixedFace(double k, double d) {
        return 2 * k * d;
    }
    static double convective(double k, double h, double dx, double d) {
        return 1 / (1 / (h * dx * d) + 1 / (2 * k * d));
    }
}
