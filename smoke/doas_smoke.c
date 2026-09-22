/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: doas_smoke.c
 * Description: PID1 driver for OpenDoas grant/deny/env contract.
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#define _GNU_SOURCE

#include <fcntl.h>
#include <grp.h>
#include <pty.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../lib/ir0_auth.h"

#define TEST_USER "labuser"
#define TEST_UID 1000
#define TEST_GID 100
#define TEST_PW "labuser"
#define BAD_PW "wrongpass"

static void out(const char *s)
{
	if (s)
		(void)write(1, s, strlen(s));
}

static void fail(const char *what)
{
	out("DOAS_SMOKE_FAIL ");
	out(what);
	out("\n");
	_exit(1);
}

/*
 * Run unmodified /usr/bin/doas as the unprivileged test user on a real PTY.
 * OpenDoas deliberately requires /dev/tty; using a pipe here would test an
 * IR0-specific userspace workaround instead of the Linux/OpenDoas contract.
 */
static int run_doas(char *const argv[], const char *script, char *capture,
		    size_t capture_sz)
{
	int master;
	pid_t pid;
	int status = 0;
	int script_sent = 0;
	int reaped = 0;
	unsigned int spins;
	size_t total = 0;

	pid = forkpty(&master, NULL, NULL, NULL);
	if (pid < 0)
		return -1;

	if (pid == 0)
	{
		gid_t groups[IR0_AUTH_GROUPS_MAX];
		int ngroups;
		char *envp[4];

		ngroups = ir0_group_list(TEST_USER, TEST_GID, groups,
					 IR0_AUTH_GROUPS_MAX);
		if (ngroups < 1)
			_exit(90);
		if (setgroups((size_t)ngroups, groups) != 0)
			_exit(91);
		if (setgid(TEST_GID) != 0)
			_exit(92);
		if (setuid(TEST_UID) != 0)
			_exit(93);

		envp[0] = "PATH=/bin:/sbin:/usr/bin:/usr/sbin";
		envp[1] = "HOME=/home/labuser";
		envp[2] = "USER=labuser";
		envp[3] = NULL;
		execve("/usr/bin/doas", argv, envp);
		_exit(94);
	}

	(void)fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	if (capture && capture_sz)
	{
		for (spins = 0; spins < 3000 && total + 1 < capture_sz; spins++)
		{
			ssize_t n = read(master, capture + total,
					 capture_sz - 1 - total);

			if (n > 0)
			{
				total += (size_t)n;
				capture[total] = '\0';
				/*
				 * readpassphrase(TCSAFLUSH) discards typeahead by design.
				 * Feed credentials only after the upstream prompt appears.
				 */
				if (!script_sent && script &&
				    strstr(capture, "password:"))
				{
					ssize_t nw = write(master, script, strlen(script));

					if (nw == (ssize_t)strlen(script))
					{
						script_sent = 1;
						out("DOAS_INPUT_SENT\n");
					}
					else
						out("DOAS_INPUT_WRITE_FAIL\n");
				}
			}
			if (!reaped && waitpid(pid, &status, WNOHANG) == pid)
				reaped = 1;
			if (reaped && n <= 0)
				break;
			(void)usleep(10000);
		}
		capture[total] = '\0';
	}
	(void)close(master);

	if (!reaped && waitpid(pid, &status, 0) != pid)
		return -1;
	if ((status & 0x7f) != 0)
		return -1;
	return (status >> 8) & 0xff;
}

static int seed_accounts(void)
{
	char hash[IR0_AUTH_HASH_MAX];
	struct ir0_account acct;

	(void)mkdir("/run", 0755);
	(void)mkdir("/run/doas", 0700);

	if (ir0_account_by_name(TEST_USER, &acct) != 0)
		return -1;
	if (ir0_password_hash(TEST_PW, hash, sizeof(hash)) != 0)
		return -1;
	if (ir0_shadow_set_hash(TEST_USER, hash) != 0)
		return -1;
	if (!ir0_user_in_group(TEST_USER, "wheel"))
		return -1;
	return 0;
}

int main(void)
{
	char buf[1024];
	/* Absolute busybox path: PATH applets may be absent from the slim manifest. */
	char *argv_id[] = { "doas", "/bin/busybox", "id", "-u", NULL };
	char *argv_env[] = { "doas", "/bin/busybox", "printenv", "DOAS_USER",
			     NULL };
	char *argv_bad[] = { "doas", "/bin/busybox", "id", NULL };
	int ec;

	if (geteuid() != 0)
		fail("not_root");
	if (seed_accounts() != 0)
		fail("seed");
	out("DOAS_SETUP_OK\n");

	/* Positive: wheel member elevates with their own password. */
	buf[0] = '\0';
	ec = run_doas(argv_id, TEST_PW "\n", buf, sizeof(buf));
	if (ec != 0)
	{
		char dig[48];

		(void)snprintf(dig, sizeof(dig), "grant_exit ec=%d ", ec);
		out("DOAS_DIAG ");
		out(dig);
		out(buf[0] ? buf : "(empty)\n");
		fail("grant_exit");
	}
	if (!strstr(buf, "0"))
		fail("grant_uid");
	out("DOAS_GRANT_OK\n");

	/* DOAS_USER must name the real invoking account. */
	buf[0] = '\0';
	ec = run_doas(argv_env, TEST_PW "\n", buf, sizeof(buf));
	if (ec != 0 || !strstr(buf, TEST_USER))
	{
		char dig[48];

		(void)snprintf(dig, sizeof(dig), "env_exit ec=%d ", ec);
		out("DOAS_DIAG ");
		out(dig);
		out(buf[0] ? buf : "(empty)\n");
		fail("doas_user_env");
	}
	out("DOAS_ENV_OK\n");

	/* Negative: wrong password never elevates. */
	buf[0] = '\0';
	ec = run_doas(argv_bad, BAD_PW "\n", buf, sizeof(buf));
	if (ec == 0)
		fail("bad_password_accepted");
	out("DOAS_DENY_AUTH_OK\n");

	out("DOAS_ALL_OK\n");
	for (;;)
		(void)sleep(60);
	return 0;
}
