#include <stdio.h>
#include <ulib.h>
#include <file.h>
#include <unistd.h>

#define MAXBUF 1024

char buf[MAXBUF+1];

int main(int argc, char **argv) {
    int fd, n, len = MAXBUF;
    if (argc == 1) {
        fd = 0;
        len = 1;
    } else if (argc == 2) {
        if ((fd = open(argv[1], O_RDONLY)) < 0)
            return 0;
    } else {
        fprintf(1, "Usage: %s [file]\n", argv[0]);
        return 0;
    }
    while ((n = read(fd, buf, len)) > 0) {
        fprintf(1, "%s", buf);
    }
    return 0;
}

