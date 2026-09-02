/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: runit_console_run.c
 * Description: runit console service — Unix getty/login; fork+wait ash session.
 *              Shell SEGV / abnormal exit restarts the same user session without
 *              re-login; clean exit (exit 0 / Ctrl-D) returns to the login prompt.
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ir0_auth.h"
#include "ir0_keymap.h"
#include "ir0_profile.h"
#include "ir0_smoke_tag.h"

/* Linux uapi — musl may lack these on the ISD sysroot. */
#ifndef TIOCSCTTY
#define TIOCSCTTY 0x540Eu
#endif
#ifndef TIOCSPGRP
#define TIOCSPGRP 0x5410u
#endif

/* Desktop profile marker: direct root login is refused before any password. */
#define ROOT_LOGIN_DENY_FILE "/etc/ir0-noroot"

static void puts_fd(const char *s)
{
	const char *p = s;

	if (!s)
		return;
	while (*p)
		p++;
	(void)write(1, s, (size_t)(p - s));
}

static void strip_ws(char *s)
{
	char *p;

	if (!s)
		return;
	p = s;
	while (*p)
	{
		if (*p == '\n' || *p == '\r' || *p == ' ' || *p == '\t')
		{
			*p = '\0';
			return;
		}
		p++;
	}
}

static void attach_console(void)
{
	int fd;

	fd = open("/dev/console", O_RDWR);
	if (fd < 0)
		return;
	(void)dup2(fd, 0);
	(void)dup2(fd, 1);
	(void)dup2(fd, 2);
	if (fd > 2)
		(void)close(fd);
}

static int path_is_reg(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int firstboot_pending(void)
{
	if (path_is_reg("/var/lib/ir0/firstboot.done") ||
	    path_is_reg("/etc/firstboot.done"))
		return 0;
	/* Legacy markers from older images. */
	if (path_is_reg("/var/lib/ir0/fb.done") || path_is_reg("/etc/fb.done") ||
	    path_is_reg("/etc/ir0-firstboot-done"))
		return 0;
	return 1;
}

/* Interactive wizard once, on the real console TTY (not in stage1). */
static void run_firstboot_if_pending(void)
{
	pid_t pid;
	int status;

	if (!firstboot_pending())
		return;
	if (access("/sbin/ir0-firstboot", X_OK) != 0)
		return;

	pid = fork();
	if (pid < 0)
		return;
	if (pid == 0)
	{
		char *const argv[] = { "/sbin/ir0-firstboot", "--wizard", NULL };

		execv(argv[0], argv);
		_exit(127);
	}
	(void)waitpid(pid, &status, 0);
	(void)ir0_tty_restore_cooked();
}

/* Audit trail without secrets: user, tty and outcome only. */
static void audit(const char *what, const char *user)
{
	char line[160];

	snprintf(line, sizeof(line), "[AUTH] %s user=%s tty=console\n", what,
		 user && user[0] ? user : "?");
	puts_fd(line);
}

static int root_login_denied(const char *user)
{
	if (strcmp(user, "root") != 0)
		return 0;
	return access(ROOT_LOGIN_DENY_FILE, F_OK) == 0;
}

static int auth_user(const char *user, const char *password,
		     struct ir0_account *acct)
{
	char hash[IR0_AUTH_HASH_MAX];
	const char *stored;

	if (!user || !acct)
		return -1;
	if (ir0_account_by_name(user, acct) != 0)
		return -1;
	if (root_login_denied(user))
	{
		ir0_smoke_tag("LOGIN_ROOT_DENIED\n");
		audit("root login refused", user);
		return -1;
	}

	stored = acct->passwd;
	if (strcmp(acct->passwd, "x") == 0 || strcmp(acct->passwd, "*") == 0)
	{
		if (ir0_shadow_hash(user, hash, sizeof(hash)) != 0)
			return -1;
		stored = hash;
	}

	if (!ir0_password_verify(stored, password))
		return -1;
	return 0;
}

static void session_setup_env(const struct ir0_account *acct)
{
	char host[64];
	char termbuf[64];
	const char *term;
	FILE *cf;
	char line[128];

	ir0_hostname(host, sizeof(host));
	(void)setenv("HOME", acct->home, 1);
	(void)setenv("USER", acct->name, 1);
	(void)setenv("LOGNAME", acct->name, 1);
	(void)setenv("SHELL", acct->shell, 1);
	(void)setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin", 1);
	(void)setenv("HOSTNAME", host, 1);

	/*
	 * TERM: inherited env → /etc/console.conf → documented fallback "linux".
	 * ncurses/nano are built with linux/vt100/xterm fallbacks only.
	 */
	memcpy(termbuf, "linux", 6);
	term = getenv("TERM");
	if (!term || !term[0])
	{
		cf = fopen("/etc/console.conf", "r");
		if (cf)
		{
			while (fgets(line, sizeof(line), cf))
			{
				if (strncmp(line, "TERM=", 5) == 0)
				{
					char *v = line + 5;
					size_t n;

					strip_ws(v);
					n = strlen(v);
					if (n >= sizeof(termbuf))
						n = sizeof(termbuf) - 1;
					if (n > 0)
					{
						memcpy(termbuf, v, n);
						termbuf[n] = '\0';
					}
					break;
				}
			}
			fclose(cf);
		}
		term = termbuf;
	}
	(void)setenv("TERM", term, 1);
}

/*
 * Child path: new session on /dev/console, drop privileges, exec login shell.
 * Never returns on success.
 */
static void session_child(const struct ir0_account *acct)
{
	char *argv[3];
	gid_t groups[IR0_AUTH_GROUPS_MAX];
	int ngroups;
	pid_t pg;
	char tag[64];

	/* New session; console becomes controlling TTY (Linux getty model). */
	if (setsid() < 0)
		_exit(111);
	(void)ioctl(0, TIOCSCTTY, 0);
	pg = getpid();
	(void)setpgid(0, 0);
	(void)ioctl(0, TIOCSPGRP, &pg);

	ngroups = ir0_group_list(acct->name, acct->gid, groups,
				 IR0_AUTH_GROUPS_MAX);
	if (ngroups > 0)
		(void)setgroups((size_t)ngroups, groups);
	if (setgid(acct->gid) != 0)
		_exit(111);
	if (setuid(acct->uid) != 0)
		_exit(111);

	if (chdir(acct->home) != 0)
		(void)chdir("/");

	session_setup_env(acct);

	snprintf(tag, sizeof(tag), "LOGIN_UID=%u EUID=%u\n",
		 (unsigned)getuid(), (unsigned)geteuid());
	ir0_smoke_tag(tag);

	/*
	 * Password entry may leave ECHO off if restore failed. Ash then looks
	 * dead (no echo, lines never finish). Force cooked+echo before exec.
	 */
	(void)ir0_tty_restore_cooked();

	/*
	 * argv[0] starts with '-' so ash treats this as a login shell and reads
	 * /etc/profile, which owns PS1 (no hardcoded prompt here).
	 */
	argv[0] = "-sh";
	argv[1] = "-i";
	argv[2] = NULL;
	execv(acct->shell[0] ? acct->shell : "/bin/sh", argv);
	execv("/bin/sh", argv);
	_exit(127);
}

/*
 * Fork the interactive shell and wait.
 * Returns:
 *   1  — voluntary logout (exit 0): caller should show the login prompt
 *   0  — crash / signal / non-zero exit: caller should respawn same user
 *  -1  — fork failed
 * The console supervisor process stays alive across shell SEGV/exit.
 */
static int start_session(const struct ir0_account *acct)
{
	pid_t pid;
	int status = 0;
	int logout = 0;

	if (!acct)
		return -1;

	ir0_smoke_tag("CONSOLE_SESSION_START\n");
	(void)ir0_tty_restore_cooked();

	pid = fork();
	if (pid < 0)
	{
		ir0_smoke_tag("RUNSV_CONSOLE_FORK_FAIL\n");
		return -1;
	}
	if (pid == 0)
		session_child(acct);

	if (waitpid(pid, &status, 0) < 0)
	{
		ir0_smoke_tag("CONSOLE_SESSION_WAIT_FAIL\n");
		(void)ir0_tty_restore_cooked();
		(void)ir0_tty_flush_input();
		/* Treat as crash — keep the authenticated user. */
		ir0_smoke_tag("CONSOLE_SESSION_RESUME\n");
		return 0;
	}

	if (WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV)
	{
		ir0_smoke_tag("CONSOLE_SESSION_SEGV\n");
		puts_fd("\n[console] shell crashed (SIGSEGV); restarting session...\n");
	}
	else if (WIFSIGNALED(status))
	{
		ir0_smoke_tag("CONSOLE_SESSION_SIGNAL\n");
		puts_fd("\n[console] shell killed; restarting session...\n");
	}
	else if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
	{
		ir0_smoke_tag("CONSOLE_SESSION_END\n");
		logout = 1;
	}
	else
	{
		ir0_smoke_tag("CONSOLE_SESSION_END\n");
		puts_fd("\n[console] shell exited abnormally; restarting session...\n");
	}

	(void)ir0_tty_restore_cooked();
	(void)ir0_tty_flush_input();
	if (logout)
	{
		ir0_smoke_tag("CONSOLE_SESSION_REPROMPT\n");
		return 1;
	}
	ir0_smoke_tag("CONSOLE_SESSION_RESUME\n");
	return 0;
}

/* Keep spawning shells for @acct until voluntary logout or fork failure. */
static int run_user_sessions(const struct ir0_account *acct)
{
	for (;;)
	{
		int r = start_session(acct);

		if (r < 0)
			return -1;
		if (r > 0)
			return 0; /* logged out */
		/* r == 0: same user, new shell */
	}
}

static void print_issue(void)
{
	struct utsname u;
	FILE *f;
	char line[256];
	char banner[96];

	memset(&u, 0, sizeof(u));
	(void)uname(&u);
	snprintf(banner, sizeof(banner), "\nIR0/Unix %s\n",
		 u.release[0] ? u.release : "0.0.1");
	puts_fd(banner);

	f = fopen("/etc/issue", "r");
	if (f)
	{
		while (fgets(line, sizeof(line), f))
			puts_fd(line);
		fclose(f);
	}
}

static void read_virt_label(char *out, size_t outlen)
{
	FILE *f;
	char line[128];

	if (!out || outlen == 0)
		return;
	snprintf(out, outlen, "unknown");
	f = fopen("/proc/cpuinfo", "r");
	if (!f)
		return;
	while (fgets(line, sizeof(line), f))
	{
		if (strncmp(line, "hypervisor_vendor\t", 18) == 0)
		{
			char *v = line + 18;

			strip_ws(v);
			if (v[0])
			{
				size_t n = 0;

				while (v[n] && n + 1 < outlen)
				{
					out[n] = v[n];
					n++;
				}
				out[n] = '\0';
			}
			break;
		}
	}
	fclose(f);
}

/*
 * The whole banner goes out in a single write: other services and the kernel
 * log share this console, and a line-by-line banner interleaves with them.
 */
static void print_welcome(enum ir0_product_profile profile)
{
	struct utsname u;
	FILE *f;
	char uptime[64];
	char virt[48];
	char banner[640];
	char *dot;

	memset(&u, 0, sizeof(u));
	(void)uname(&u);
	read_virt_label(virt, sizeof(virt));

	uptime[0] = '\0';
	f = fopen("/proc/uptime", "r");
	if (f)
	{
		if (fgets(uptime, sizeof(uptime), f))
			strip_ws(uptime);
		fclose(f);
	}
	dot = strchr(uptime, '.');
	if (dot)
		*dot = '\0';

	{
		char docs[80] = "";
		char status[80] = "";

		if (access("/bin/man", X_OK) == 0 || access("/usr/bin/man", X_OK) == 0)
			snprintf(docs, sizeof(docs), "  Docs:    man IR0-boot\n");
		if (access("/bin/ir0-status", X_OK) == 0)
			snprintf(status, sizeof(status), "  Status:  ir0-status\n");
		snprintf(banner, sizeof(banner),
			 "\nWelcome to IR0/Unix\n"
			 "  Kernel:  %s %s\n"
			 "  Machine: %s · %s\n"
			 "  Uptime:  %s s\n"
			 "%s%s"
			 "%s\n",
			 u.sysname[0] ? u.sysname : "IR0",
			 u.release[0] ? u.release : "?",
			 u.machine[0] ? u.machine : "?", virt,
			 uptime[0] ? uptime : "unknown",
			 docs, status,
			 profile == PROFILE_DEVELOPMENT
				 ? "\nIR0/Unix development environment\n"
				   "WARNING: automatic root login is enabled\n"
				 : "");
	}
	puts_fd(banner);
}

int main(void)
{
	char user[IR0_AUTH_NAME_MAX];
	char pass[IR0_AUTH_HASH_MAX];
	char prompt[96];
	struct ir0_account acct;
	enum ir0_product_profile profile;
	FILE *auto_f;

	ir0_smoke_tag("RUNSV_CONSOLE_START\n");
	attach_console();
	ir0_smoke_tag("GETTY_READY\n");

	/* Persist layout from /etc/keymap when present (kernel default otherwise). */
	(void)ir0_keymap_apply_file(IR0_KEYMAP_FILE);

	profile = ir0_read_profile();
	if (profile == PROFILE_APPLIANCE)
	{
		/* Appliance images run services only: no getty, no shell. */
		ir0_smoke_tag("CONSOLE_NO_LOGIN\n");
		for (;;)
			(void)pause();
	}

	run_firstboot_if_pending();
	/* Firstboot may have written /etc/keymap — re-apply before login. */
	(void)ir0_keymap_apply_file(IR0_KEYMAP_FILE);
	(void)ir0_tty_restore_cooked();

	auto_f = fopen("/etc/ir0-autologin", "r");
	if (auto_f)
	{
		if (fgets(user, sizeof(user), auto_f))
			strip_ws(user);
		else
			user[0] = '\0';
		fclose(auto_f);
		pass[0] = '\0';
		if (user[0] && auth_user(user, pass, &acct) == 0)
		{
			ir0_smoke_tag("LOGIN_OK\n");
			audit("login granted", user);
			print_welcome(profile);
			ir0_smoke_tag("ASH_INTERACTIVE_READY\n");
			if (run_user_sessions(&acct) != 0)
				ir0_smoke_tag("RUNSV_CONSOLE_EXEC_FAIL\n");
			/* Logged out (or fork fail) — interactive login below. */
		}
		else
		{
			ir0_smoke_tag("LOGIN_AUTO_FAIL\n");
		}
	}

	snprintf(prompt, sizeof(prompt), "Enter your Unix username: ");

	for (;;)
	{
		int line_rc;

		/* Drop keys typed during the prior delay / password silence. */
		(void)ir0_tty_restore_cooked();
		(void)ir0_tty_flush_input();
		print_issue();
		puts_fd(prompt);
		(void)ir0_tty_flush_input();
		line_rc = ir0_read_line(user, sizeof(user), 1);
		strip_ws(user);
		/*
		 * Do not emit LOGIN_USER_READ on empty/EOF/EINTR spin: that tag
		 * was flooding the serial log next to the prompt after firstboot
		 * while read() returned without a real username.
		 */
		if (line_rc != 0)
		{
			sleep(1);
			continue;
		}
		if (user[0] == '\0')
		{
			/* Empty Enter / whitespace — do not spin the banner. */
			sleep(1);
			continue;
		}
		ir0_smoke_tag("LOGIN_USER_READ\n");
		puts_fd("Password: ");
		(void)ir0_read_line(pass, sizeof(pass), 0);
		ir0_smoke_tag("LOGIN_PASS_READ\n");
		puts_fd("\n");
		(void)ir0_tty_restore_cooked();

		if (auth_user(user, pass, &acct) != 0)
		{
			ir0_wipe(pass, sizeof(pass));
			puts_fd("Login incorrect\n");
			audit("login denied", user);
			sleep(1);
			/* Typing during the delay must not become the next username. */
			(void)ir0_tty_flush_input();
			continue;
		}
		ir0_wipe(pass, sizeof(pass));

		ir0_smoke_tag("LOGIN_OK\n");
		audit("login granted", user);
		print_welcome(profile);
		ir0_smoke_tag("ASH_INTERACTIVE_READY\n");
		if (run_user_sessions(&acct) != 0)
		{
			ir0_smoke_tag("RUNSV_CONSOLE_EXEC_FAIL\n");
			sleep(1);
			continue;
		}
		/* Voluntary logout — loop back to username prompt. */
	}
}
