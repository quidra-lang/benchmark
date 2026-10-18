#include <stdio.h>
#include <string.h>

int main(void) {
    const char *values[] = {"Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?"};
    const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (int k = 0; k < 5; k++) {
        const char *s = values[k];
        int len = (int) strlen(s);
        char encoded[128];
        int out = 0;
        for (int i = 0; i < len; i += 3) {
            int remain = len - i;
            unsigned bits = (unsigned char) s[i] << 16;
            if (remain > 1)
                bits |= (unsigned)(unsigned char) s[i + 1] << 8;
            if (remain > 2)
                bits |= (unsigned char) s[i + 2];
            encoded[out++] = alphabet[(bits >> 18) &63];
            encoded[out++] = alphabet[(bits >> 12) &63];
            encoded[out++] = remain > 1 ? alphabet[(bits >> 6) &63]: '=';
            encoded[out++] = remain > 2 ? alphabet[bits &63]: '=';
        }
        encoded[out] = 0;
        printf("\"%s\" -> \"%s\"\n", s, encoded);
    }
    return 0;
}
