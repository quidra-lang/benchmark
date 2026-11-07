#include "detector.h"
I absolute(I value) {
    return value < 0 ? -value : value;
}
I floor_div(I a, I b) {
    return a / b - (a % b < 0);
}
I clamped(Image image, I x, I y) {
    if (x < 0)
        x = 0;
    if (x >= image.width)
        x = image.width - 1;
    if (y < 0)
        y = 0;
    if (y >= image.height)
        y = image.height - 1;
    return image_at(image, (Point){x, y});
}
Image smooth(Image image, const Params *p) {
    Image out = image_new(image.width, image.height);
    I half = (p->ks - 1) / 2;
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x) {
            I sum = 0;
            for (I j = 0; j < p->ks; ++j)
                for (I i = 0; i < p->ks; ++i)
                    sum += p->kernel[j * p->ks + i] * clamped(image, x + i - half, y + j - half);
            image_set(out, (Point){x, y}, floor_div(sum, p->divisor));
        }
    return out;
}
Gradient gradient(Image image) {
    Gradient out = {image_new(image.width, image.height), image_new(image.width, image.height),
                    image_new(image.width, image.height)};
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x) {
            I q[9];
            for (int j = -1; j <= 1; ++j)
                for (int i = -1; i <= 1; ++i)
                    q[(j + 1) * 3 + i + 1] = clamped(image, x + i, y + j);
            I gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6],
              gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
            image_set(out.gx, (Point){x, y}, gx);
            image_set(out.gy, (Point){x, y}, gy);
            image_set(out.magnitude, (Point){x, y}, absolute(gx) + absolute(gy));
        }
    return out;
}
