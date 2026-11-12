/* Independent rescue process for the bounded Android maintenance window. */
#ifdef _WIN32
int portable_supervise(int argc, char **argv) { (void)argc; (void)argv; return 2; }
#else
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <sys/wait.h>
#include <time.h>

static void close_pair(int *p) { close(p[0]); close(p[1]); }
static void rescue(int channel, int worker, int seconds, char *path, char **environment) {
    struct timespec start, now;
    struct pollfd watch = {channel, POLLIN | POLLHUP, 0};
    char command;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) goto failed;
    for (;;) {
        int result = poll(&watch, 1, 100);
        if (result < 0) goto failed;
        if (result > 0) {
            if (read(channel, &command, 1) == 1 && command == 'S') _exit(0);
            goto failed;
        }
        if (clock_gettime(CLOCK_MONOTONIC, &now) || now.tv_sec-start.tv_sec >= seconds) break;
    }
failed:
    /* The worker is a session/group leader, held unreaped by our parent. Its
     * descendants retain that group even after an abrupt supervisor death. */
    kill(-worker, SIGKILL);
    poll(0, 0, 200);
    close(channel);
    {
        char *arguments[] = {path, 0};
        execve(path, arguments, environment);
    }
    _exit(125);
}

int portable_supervise(int argc, char **argv) {
    int seconds = 0, control[2], gate[2], ready[2], armed[2], worker, guard, status, rescued;
    char byte;
    char **environment = argv + argc + 1;
#ifdef __arm__
    extern int portable_ignore_sigpipe(void);
    if (portable_ignore_sigpipe()) return 1;
#else
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) return 1;
#endif
    if (argc < 5 || !*argv[2]) return 2;
    for (const char *p=argv[2]; *p; p++) {
        if (*p<'0' || *p>'9' || seconds>180) return 2;
        seconds=seconds*10+(*p-'0');
    }
    if (seconds<1 || seconds>180 || argv[3][0]!='/' || argv[4][0]!='/') return 2;
    if (pipe(control) || pipe(gate) || pipe(ready) || pipe(armed)) return 1;
    worker=fork();
    if (worker<0) return 1;
    if (!worker) {
        close_pair(control); close_pair(armed); close(ready[0]); close(gate[1]);
        if (setsid()<0 || write(ready[1], "R", 1)!=1) _exit(125);
        close(ready[1]);
        if (read(gate[0], &byte, 1)!=1 || byte!='G') _exit(125);
        close(gate[0]);
        execve(argv[4], argv+4, environment);
        _exit(125);
    }
    close(ready[1]); close(gate[0]);
    if (read(ready[0], &byte, 1)!=1 || byte!='R') { kill(worker,SIGKILL); return 1; }
    close(ready[0]);
    guard=fork();
    if (guard<0) { kill(-worker,SIGKILL); return 1; }
    if (!guard) {
        close(gate[1]); close(control[1]); close(armed[0]);
        if (setsid()<0 || write(armed[1], "A", 1)!=1) _exit(125);
        close(armed[1]);
        rescue(control[0],worker,seconds,argv[3],environment);
    }
    close(armed[1]); close(control[0]);
    if (read(armed[0], &byte, 1)!=1 || byte!='A') {
        kill(-worker,SIGKILL); close(control[1]); close(gate[1]); return 1;
    }
    close(armed[0]);
    if (write(gate[1], "G", 1)!=1) { close(control[1]); return 1; }
    close(gate[1]);
    if (waitpid(worker,&status,0)!=worker) status=1;
    byte=WIFEXITED(status) && WEXITSTATUS(status)==0 ? 'S':'F';
    if (write(control[1],&byte,1)!=1) byte='F';
    close(control[1]);
    if (waitpid(guard,&rescued,0)!=guard) return 1;
    return byte=='S' && WIFEXITED(rescued) && WEXITSTATUS(rescued)==0 ? 0:1;
}
#endif
