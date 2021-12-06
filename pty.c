#define _GNU_SOURCE
#define _XOPEN_SOURCE 500 /* why? */
#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

void slurp(int from, int to) {
	char buf[512];
	ssize_t sz = read(from, buf, sizeof buf);
	if (sz == -1) return;
	write(to, buf, sz); // assuming it would work in one call
}

int main() {
	/* create and initialise the PTY */
	const char * ppts;
	int ptm = posix_openpt(O_RDWR|O_NOCTTY);
	if (
		ptm == -1
		|| grantpt(ptm) == -1
		|| unlockpt(ptm) == -1
		|| (ppts = ptsname(ptm)) == NULL
	) return -1;

	pid_t child = fork();
	if (child == -1) return -1;

	if (child > 0) { /* in parent */
		struct termios tp, otp;
		if (tcgetattr(0, &tp) == -1) return -1;
		otp = tp;
		cfmakeraw(&tp);
		if (tcsetattr(0, TCSANOW, &tp) == -1) return -1;

		struct pollfd fds[] = {
			{ .fd = 0, .events = POLLIN },
			{ .fd = ptm, .events = POLLIN },
		};

		while (poll(fds, sizeof(fds)/sizeof(*fds), -1)) {
			if (fds[0].revents & POLLIN) slurp(fds[0].fd, fds[1].fd);
			else if (fds[1].revents & POLLIN) slurp(fds[1].fd, fds[0].fd);
			else break; // wait what?
		}

		tcsetattr(0, TCSANOW, &otp);
	} else { /* in child */
		close(ptm); /* shouldn't retain the master fd */
		(void)setsid(); /* the pty must become the controlling TTY for the process */
		int pts = open(ppts, O_RDWR); /* this must set the controlling TTY */
		if (pts == -1) return -1;
		dup2(pts, 0);
		dup2(pts, 1);
		dup2(pts, 2);
		execlp("/bin/sh", "sh", NULL);
	}

	return 0;
}
