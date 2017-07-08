#include <ulib.h>
#include <stdio.h>
#include <string.h>
#include <dir.h>
#include <file.h>
#include <error.h>
#include <unistd.h>

#define printf(...) fprintf(1, __VA_ARGS__)
#define BUFFER_SIZE 4096
#define WAIT_TIME 100

int fd[2];
char send_buf[] = "Hello World";
char recv_buf[BUFFER_SIZE];

int
main(void) {
    printf("pipe test: start\n");
    int ret, pid;
    if ((ret = pipe(fd)) < 0) {
        printf("error: %d - %e\n", ret, ret);
    }
    // Single process
    printf("pipe test: single proces test\n");
    if ((ret = write(fd[1], send_buf, strlen(send_buf))) < 0) {
        printf("error: %d - %e\n", ret, ret);
    }
    if ((ret = read(fd[0], recv_buf, strlen(send_buf))) < 0) {
        printf("error: %d - %e\n", ret, ret);
    }
    assert(strcmp(send_buf, recv_buf) == 0);
    // Multiple process: read block
    printf("pipe test: read block test\n");
    if ((pid = fork()) == 0) {
        if ((ret = read(fd[0], recv_buf, strlen(send_buf))) < 0) {
            printf("error: %d - %e\n", ret, ret);
        }
        assert(strcmp(send_buf, recv_buf) == 0);
        exit(0);
    }
    sleep(WAIT_TIME);
    if ((ret = write(fd[1], send_buf, strlen(send_buf))) < 0) {
        printf("error: %d - %e\n", ret, ret);
    }
    waitpid(pid, &ret);
    // Multiple proces: write block
    printf("pipe test: write block test\n");
    if ((pid = fork()) == 0) {
        if ((ret = write(fd[1], send_buf, strlen(send_buf))) < 0) {
            printf("error: %d - %e\n", ret, ret);
        }
        if ((ret = write(fd[1], recv_buf, BUFFER_SIZE-1)) < 0) {
            printf("error: %d - %e\n", ret, ret);
        }
        exit(0);
    }
    sleep(WAIT_TIME);
    if ((ret = read(fd[0], recv_buf, strlen(send_buf))) < 0) {
        printf("error: %d - %e\n", ret, ret);
    }
    assert(strcmp(send_buf, recv_buf) == 0);
    waitpid(pid, &ret);
    printf("pipe test: pass\n");
    return 0;
}
