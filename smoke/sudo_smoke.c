/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * File: sudo_smoke.c
 * Description: PID1 driver for unmodified GNU sudo over a controlling PTY.
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
	out("SUDO_SMOKE_FAIL ");
	out(what);
	out("\n");
	_exit(1);
}

static unsigned int count_prompts(const char *capture)
{
	const char *p = capture;
	unsigned int count = 0;

	while ((p = strstr(p, "password for " TEST_USER ":")) != NULL)
	{
		count++;
		p += sizeof("password for " TEST_USER ":") - 1;
	}
	return count;
}

static int run_sudo(char *const argv[], const char *script, char *capture,
		    size_t capture_sz)
{
	int master;
	pid_t pid;
	int status = 0;
	int reaped = 0;
	unsigned int spins;
	unsigned int prompts_answered = 0;
	size_t script_pos = 0;
	size_t total = 0;

	pid = forkpty(&master, NULL, NULL, NULL);
	if (pid < 0)
		return -1;

	if (pid == 0)
	{
		gid_t groups[IR0_AUTH_GROUPS_MAX];
		char *envp[5];
		int ngroups;

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
		envp[3] = "LOGNAME=labuser";
		envp[4] = NULL;
		execve("/usr/bin/sudo", argv, envp);
		_exit(94);
	}

	(void)fcntl(master, F_SETFL, fcntl(master, F_GETFL, 0) | O_NONBLOCK);
	for (spins = 0; spins < 3000 && total + 1 < capture_sz; spins++)
	{
		ssize_t n = read(master, capture + total, capture_sz - 1 - total);

		if (n > 0)
		{
			total += (size_t)n;
			capture[total] = '\0';
			if (script && script[script_pos] != '\0' &&
			    count_prompts(capture) > prompts_answered)
			{
				const char *line = script + script_pos;
				const char *newline = strchr(line, '\n');
				size_t line_len = newline
					? (size_t)(newline - line) + 1
					: strlen(line);
				ssize_t nw = write(master, line, line_len);

				if (nw == (ssize_t)line_len)
				{
					script_pos += line_len;
					prompts_answered++;
				}
			}
		}
		if (!reaped && waitpid(pid, &status, WNOHANG) == pid)
			reaped = 1;
		if (reaped && n <= 0)
			break;
		(void)usleep(10000);
	}
	capture[total] = '\0';
	(void)close(master);

	if (!reaped && waitpid(pid, &status, 0) != pid)
		return -1;
	if ((status & 0x7f) != 0)
		return 128 + (status & 0x7f);
	return (status >> 8) & 0xff;
}

static int seed_accounts(void)
{
	char hash[IR0_AUTH_HASH_MAX];
	struct ir0_account acct;

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

static int file_contains(const char *path, const char *needle)
{
	char buf[128];
	ssize_t n;
	int fd;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return 0;
	n = read(fd, buf, sizeof(buf) - 1);
	(void)close(fd);
	if (n <= 0)
		return 0;
	buf[n] = '\0';
	return strstr(buf, needle) != NULL;
}

int main(void)
{
	char buf[2048];
	struct stat st;
	char *argv_grant[] = { "sudo", "/bin/busybox", "touch",
			       "/root/sudo-grant", NULL };
	char *argv_env[] = { "sudo", "/bin/busybox", "sh", "-c",
			     "printf '%s' \"$SUDO_USER\" > /root/sudo-env",
			     NULL };
	char *argv_bad[] = { "sudo", "/bin/busybox", "id", NULL };
	int ec;

	if (geteuid() != 0)
		fail("not_root");
	if (seed_accounts() != 0)
		fail("seed");
	out("SUDO_SETUP_OK\n");

	(void)unlink("/root/sudo-grant");
	buf[0] = '\0';
	ec = run_sudo(argv_grant, TEST_PW "\n", buf, sizeof(buf));
	{
		int stat_rc = stat("/root/sudo-grant", &st);

		if (ec != 0 || stat_rc != 0 || st.st_uid != 0)
		{
			char ecbuf[96];

			snprintf(ecbuf, sizeof(ecbuf),
				 "SUDO_EXIT %d PROOF_STAT %d PROOF_UID %u\n",
				 ec, stat_rc,
				 stat_rc == 0 ? (unsigned)st.st_uid : 0);
			out(ecbuf);
			out("SUDO_DIAG ");
			out(buf[0] ? buf : "(empty)\n");
			fail("grant");
		}
	}
	out("SUDO_GRANT_OK\n");

	(void)unlink("/root/sudo-env");
	buf[0] = '\0';
	ec = run_sudo(argv_env, TEST_PW "\n", buf, sizeof(buf));
	if (ec != 0 || !file_contains("/root/sudo-env", TEST_USER))
	{
		out("SUDO_DIAG ");
		out(buf[0] ? buf : "(empty)\n");
		fail("sudo_user_env");
	}
	out("SUDO_ENV_OK\n");

	buf[0] = '\0';
	ec = run_sudo(argv_bad, BAD_PW "\n" BAD_PW "\n" BAD_PW "\n",
		      buf, sizeof(buf));
	if (ec == 0)
		fail("bad_password_accepted");
	out("SUDO_DENY_AUTH_OK\n");

	out("SUDO_ALL_OK\n");
	for (;;)
		(void)sleep(60);
	return 0;
}
