import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

final class Scene {
    record Color(long r, long g, long b) {
        long component(int axis) {
            return axis == 0 ? r : axis == 1 ? g : b;
        }
        static Color of(long[] values) {
            return new Color(values[0], values[1], values[2]);
        }
        public String toString() {
            return r + " " + g + " " + b;
        }
    }
    static final class Material {
        String name;
        Color color, checker;
        long kd, ks, kr, kt, ior, checkerSize;
        int exponent;
    }
    static final class Obj {
        int number, leafDepth;
        char label;
        String kind;
        Material material;
        Vector3 center, point, normal, lo, hi;
        long radius;
        Intersect.Bounds bounds;
    }
    static final class Light {
        int number, divisions = 1;
        String kind;
        Vector3 position, direction, u, v;
        long outer, inner, intensity;
        int samples() {
            return kind.equals("area") ? divisions * divisions : 1;
        }
    }
    static final class Data {
        Vector3 eye, forward, right, up;
        long hw, hh, ambient, fogStart, fogEnd;
        Color background, fog;
        Map<String, Material> materials = new LinkedHashMap<>();
        List<Obj> objects = new ArrayList<>();
        List<Light> lights = new ArrayList<>();
    }
    static long value(String[] words, int index) {
        return Long.parseLong(words[index]);
    }
    static Vector3 vector(String[] words, int start) {
        return new Vector3(value(words, start), value(words, start + 1), value(words, start + 2));
    }
    static Color color(String[] words, int start) {
        return new Color(value(words, start), value(words, start + 1), value(words, start + 2));
    }
    static Data read() throws IOException {
        Data scene = new Data();
        for (String line : Files.readAllLines(Path.of("input", "scene.txt"), StandardCharsets.US_ASCII)) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] w = line.split(" ");
            switch (w[0]) {
            case "eye" -> scene.eye = vector(w, 1);
            case "forward" -> scene.forward = vector(w, 1);
            case "right" -> scene.right = vector(w, 1);
            case "up" -> scene.up = vector(w, 1);
            case "view" -> {
                scene.hw = value(w, 1);
                scene.hh = value(w, 2);
            }
            case "background" -> scene.background = color(w, 1);
            case "ambient" -> scene.ambient = value(w, 1);
            case "fog" -> {
                scene.fog = color(w, 1);
                scene.fogStart = value(w, 4);
                scene.fogEnd = value(w, 5);
            }
            case "material" -> {
                Material material = new Material();
                material.name = w[1];
                material.color = color(w, 2);
                material.kd = value(w, 5);
                material.ks = value(w, 6);
                material.exponent = (int)value(w, 7);
                material.kr = value(w, 8);
                material.kt = value(w, 9);
                material.ior = value(w, 10);
                scene.materials.put(material.name, material);
            }
            case "checker" -> {
                Material material = scene.materials.get(w[1]);
                material.checker = color(w, 2);
                material.checkerSize = value(w, 5);
            }
            case "sphere", "plane", "box" -> {
                Obj object = new Obj();
                object.number = scene.objects.size() + 1;
                object.label = w[1].charAt(0);
                object.kind = w[0];
                object.material = scene.materials.get(w[2]);
                if (object.kind.equals("sphere")) {
                    object.center = vector(w, 3);
                    object.radius = value(w, 6);
                } else if (object.kind.equals("plane")) {
                    object.point = vector(w, 3);
                    object.normal = vector(w, 6).normalize();
                } else {
                    object.lo = vector(w, 3);
                    object.hi = vector(w, 6);
                }
                scene.objects.add(object);
            }
            default -> {
                Light light = new Light();
                light.number = scene.lights.size() + 1;
                light.kind = w[0];
                switch (light.kind) {
                case "point" -> {
                    light.position = vector(w, 1);
                    light.intensity = value(w, 4);
                }
                case "spot" -> {
                    light.position = vector(w, 1);
                    light.direction = vector(w, 4).normalize();
                    light.outer = value(w, 7);
                    light.inner = value(w, 8);
                    light.intensity = value(w, 9);
                }
                case "sun" -> {
                    light.direction = vector(w, 1).negate().normalize();
                    light.intensity = value(w, 4);
                }
                case "area" -> {
                    light.position = vector(w, 1);
                    light.u = vector(w, 4);
                    light.v = vector(w, 7);
                    light.divisions = (int)value(w, 10);
                    light.intensity = value(w, 11);
                }
                }
                scene.lights.add(light);
            }
            }
        }
        return scene;
    }
}
