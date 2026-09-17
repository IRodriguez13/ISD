/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: ash_ulimit_segv_smoke.c
 * Description: Reproduce ash SEGV after ulimit without getty/login — replace
 *              console/run on a temp disk; fork+exec /bin/sh -c scripts.
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ir0_smoke_tag.h"

static void attach_serial_stdout(void)
{
	int fd;

	fd = open("/dev/serial", O_RDWR);
	if (fd < 0)
		fd = open("/dev/console", O_RDWR);
	if (fd < 0)
		return;
	(void)dup2(fd, 0);
	(void)dup2(fd, 1);
	(void)dup2(fd, 2);
	if (fd > 2)
		(void)close(fd);
}

/*
 * Run /bin/sh -c @script. Tags:
 *   *_OK on exit 0, *_SEGV if child dies SIGSEGV, *_FAIL otherwise.
 */
static int run_sh_script(const char *script, const char *tag_ok,
			 const char *tag_segv, const char *tag_fail)
{
	pid_t pid;
	int status = 0;

	pid = fork();
	if (pid < 0)
	{
		ir0_smoke_tag(tag_fail);
		return -1;
	}
	if (pid == 0)
	{
		execl("/bin/sh", "sh", "-c", script, (char *)0);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0)
	{
		ir0_smoke_tag(tag_fail);
		return -1;
	}
	if (WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV)
	{
		ir0_smoke_tag(tag_segv);
		return 1;
	}
	if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
	{
		ir0_smoke_tag(tag_ok);
		return 0;
	}
	ir0_smoke_tag(tag_fail);
	return -1;
}

int main(void)
{
	int saw_segv = 0;
	int rc;

	attach_serial_stdout();
	ir0_smoke_tag("ASH_ULIMIT_PROBE_START\n");

	/* Case A: bare ulimit (matches guest session after Tab / builtins). */
	rc = run_sh_script("ulimit", "ASH_ULIMIT_A_OK\n", "ASH_ULIMIT_A_SEGV\n",
			   "ASH_ULIMIT_A_FAIL\n");
	if (rc == 1)
		saw_segv = 1;

	/* Case B: ulimit then ulimit -a (closer to interactive follow-up). */
	rc = run_sh_script("ulimit; ulimit -a; echo ULIMIT_B_DONE",
			   "ASH_ULIMIT_B_OK\n", "ASH_ULIMIT_B_SEGV\n",
			   "ASH_ULIMIT_B_FAIL\n");
	if (rc == 1)
		saw_segv = 1;

	/* Case C: exec builtin misuse (guest typed exec --version). */
	rc = run_sh_script("exec --version; echo EXEC_DONE",
			   "ASH_ULIMIT_C_OK\n", "ASH_ULIMIT_C_SEGV\n",
			   "ASH_ULIMIT_C_FAIL\n");
	if (rc == 1)
		saw_segv = 1;

	/*
	 * Case D: interactive-ish via pipe (no getty). Feeds ulimit + exit.
	 * Ash -i without a TTY may still exercise the same builtins.
	 */
	rc = run_sh_script("printf 'ulimit\\nexit\\n' | /bin/sh -i",
			   "ASH_ULIMIT_D_OK\n", "ASH_ULIMIT_D_SEGV\n",
			   "ASH_ULIMIT_D_FAIL\n");
	if (rc == 1)
		saw_segv = 1;

	if (saw_segv)
		ir0_smoke_tag("ASH_ULIMIT_PROBE_SEGV\n");
	else
		ir0_smoke_tag("ASH_ULIMIT_PROBE_CLEAN\n");

	ir0_smoke_tag("ASH_ULIMIT_PROBE_DONE\n");

	/* Stay supervised; do not reboot — keep PF log stable for autokill. */
	for (;;)
		(void)pause();
}
