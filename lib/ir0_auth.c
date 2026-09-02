/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: ir0_auth.c
 * Description: Userspace account policy: passwd(5), shadow(5), group(5), crypt(3).
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#define _GNU_SOURCE

#include "ir0_auth.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <termios.h>
#include <unistd.h>

/* musl provides crypt(3) in libc; some sysroots ship no <crypt.h>. */
extern char *crypt(const char *key, const char *salt);

/*
 * Kernel TCGETS/TCSETS use the Linux uapi termios (NCCS=19 → 36 bytes).
 * musl's struct termios is larger (NCCS=32); tcsetattr() can corrupt
 * c_lflag/ICANON on IR0 and leave Password: unable to accept keys.
 */
#define IR0_TCGETS 0x5401u
#define IR0_TCSETS 0x5402u
#define IR0_TCSETSF 0x5404u
#define IR0_TCFLSH 0x540Bu
/* Must match includes/ir0/console.h (Linux asm-generic/termbits). */
#define IR0_IFLAG_ICRNL  0x00000100u
#define IR0_LFLAG_ISIG   0x00000001u
#define IR0_LFLAG_ICANON 0x00000002u
#define IR0_LFLAG_ECHO   0x00000008u
#define IR0_LFLAG_ECHOE  0x00000010u
#define IR0_LFLAG_ECHOK  0x00000020u
#define IR0_LFLAG_ECHONL 0x00000040u
#define IR0_CC_VERASE    2
#define IR0_CC_VEOF      4
#define IR0_CC_VTIME     5
#define IR0_CC_VMIN      6

struct ir0_ktios
{
	unsigned int c_iflag;
	unsigned int c_oflag;
	unsigned int c_cflag;
	unsigned int c_lflag;
	unsigned char c_line;
	unsigned char c_cc[19];
};

static int ir0_tty_set_echo(int enable)
{
	struct ir0_ktios t;

	memset(&t, 0, sizeof(t));
	if (syscall(SYS_ioctl, 0, IR0_TCGETS, &t) != 0)
		return -1;
	/*
	 * QEMU/PS2 Enter is CR. Without ICRNL, canon never sees '\\n' and
	 * Password: hangs forever. Force line discipline bits after TCGETS
	 * (do not trust a zeroed/partial iflag from a bad get).
	 */
	t.c_iflag |= IR0_IFLAG_ICRNL;
	t.c_lflag |= (IR0_LFLAG_ISIG | IR0_LFLAG_ICANON);
	/* Keep ECHONL so Enter still advances the cursor with ECHO off. */
	t.c_lflag |= IR0_LFLAG_ECHONL;
	if (enable)
		t.c_lflag |= (IR0_LFLAG_ECHO | IR0_LFLAG_ECHOE | IR0_LFLAG_ECHOK);
	else
		t.c_lflag &= ~(IR0_LFLAG_ECHO | IR0_LFLAG_ECHOE | IR0_LFLAG_ECHOK);
	return syscall(SYS_ioctl, 0, IR0_TCSETS, &t) == 0 ? 0 : -1;
}

int ir0_tty_flush_input(void)
{
	/*
	 * Linux ioctl(TCFLSH) takes the queue id as the third argument value
	 * (TCIFLUSH=0), not a userspace pointer.
	 */
	return syscall(SYS_ioctl, 0, IR0_TCFLSH, 0) == 0 ? 0 : -1;
}

/* Public: restore cooked+echo and drop pending keystrokes (login prompts). */
int ir0_tty_restore_cooked(void)
{
	struct ir0_ktios t;

	memset(&t, 0, sizeof(t));
	if (syscall(SYS_ioctl, 0, IR0_TCGETS, &t) != 0)
		memset(&t, 0, sizeof(t));

	t.c_iflag |= IR0_IFLAG_ICRNL;
	t.c_lflag |= (IR0_LFLAG_ISIG | IR0_LFLAG_ICANON | IR0_LFLAG_ECHO |
		      IR0_LFLAG_ECHOE | IR0_LFLAG_ECHOK | IR0_LFLAG_ECHONL);
	if (t.c_cc[IR0_CC_VERASE] == 0)
		t.c_cc[IR0_CC_VERASE] = 127;
	if (t.c_cc[IR0_CC_VEOF] == 0)
		t.c_cc[IR0_CC_VEOF] = 4;
	t.c_cc[IR0_CC_VMIN] = 1;
	t.c_cc[IR0_CC_VTIME] = 0;

	/*
	 * TCSETSF: apply flags and flush the canon queue. Without this, keys
	 * typed during sleep(1) after "Login incorrect" complete into
	 * canon_readq and the next username read returns instantly — then
	 * "Password:" is glued onto the username prompt.
	 */
	if (syscall(SYS_ioctl, 0, IR0_TCSETSF, &t) == 0)
		return 0;
	return ir0_tty_set_echo(1);
}

#define SALT_CHARS "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
#define SALT_LEN 16

int ir0_auth_field(const char *line, int idx, char *out, size_t outlen)
{
	const char *p = line;
	int i = 0;
	size_t n = 0;

	if (!line || !out || outlen == 0)
		return -1;

	out[0] = '\0';
	while (*p && i < idx)
	{
		if (*p == ':')
			i++;
		p++;
	}
	if (i != idx)
		return -1;

	while (*p && *p != ':' && *p != '\n' && *p != '\r' && n + 1 < outlen)
		out[n++] = *p++;
	out[n] = '\0';
	return 0;
}

static int account_from_line(const char *line, struct ir0_account *out)
{
	char uid_s[32];
	char gid_s[32];

	if (ir0_auth_field(line, 0, out->name, sizeof(out->name)) != 0)
		return -1;
	if (ir0_auth_field(line, 1, out->passwd, sizeof(out->passwd)) != 0)
		return -1;
	if (ir0_auth_field(line, 2, uid_s, sizeof(uid_s)) != 0)
		return -1;
	if (ir0_auth_field(line, 3, gid_s, sizeof(gid_s)) != 0)
		return -1;
	if (ir0_auth_field(line, 5, out->home, sizeof(out->home)) != 0 ||
	    out->home[0] == '\0')
		snprintf(out->home, sizeof(out->home), "/");
	if (ir0_auth_field(line, 6, out->shell, sizeof(out->shell)) != 0 ||
	    out->shell[0] == '\0')
		snprintf(out->shell, sizeof(out->shell), "/bin/sh");

	out->uid = (uid_t)strtoul(uid_s, NULL, 10);
	out->gid = (gid_t)strtoul(gid_s, NULL, 10);
	return 0;
}

static int account_lookup(const char *user, const uid_t *uid,
			  struct ir0_account *out)
{
	FILE *f;
	char line[512];

	if (!out)
		return -1;

	memset(out, 0, sizeof(*out));
	f = fopen(IR0_PASSWD_FILE, "r");
	if (!f)
		return -1;

	while (fgets(line, sizeof(line), f))
	{
		struct ir0_account cand;

		if (line[0] == '#' || line[0] == '\n')
			continue;
		memset(&cand, 0, sizeof(cand));
		if (account_from_line(line, &cand) != 0)
			continue;
		if (user && strcmp(cand.name, user) != 0)
			continue;
		if (uid && cand.uid != *uid)
			continue;

		*out = cand;
		fclose(f);
		return 0;
	}

	fclose(f);
	return -1;
}

int ir0_account_by_name(const char *user, struct ir0_account *out)
{
	if (!user || !user[0])
		return -1;
	return account_lookup(user, NULL, out);
}

int ir0_account_by_uid(uid_t uid, struct ir0_account *out)
{
	return account_lookup(NULL, &uid, out);
}

int ir0_shadow_hash(const char *user, char *hash, size_t hashlen)
{
	FILE *f;
	char line[512];

	if (!user || !hash || hashlen == 0)
		return -1;

	hash[0] = '\0';
	f = fopen(IR0_SHADOW_FILE, "r");
	if (!f)
		return -1;

	while (fgets(line, sizeof(line), f))
	{
		char name[IR0_AUTH_NAME_MAX];

		if (ir0_auth_field(line, 0, name, sizeof(name)) != 0)
			continue;
		if (strcmp(name, user) != 0)
			continue;
		if (ir0_auth_field(line, 1, hash, hashlen) != 0)
		{
			fclose(f);
			return -1;
		}
		fclose(f);
		return 0;
	}

	fclose(f);
	return -1;
}

int ir0_hash_is_locked(const char *stored)
{
	if (!stored)
		return 1;
	/* shadow(5): a leading '!' or a lone '*' means "no password login". */
	return stored[0] == '!' || strcmp(stored, "*") == 0;
}

int ir0_password_verify(const char *stored, const char *password)
{
	const char *pw = password ? password : "";

	if (ir0_hash_is_locked(stored))
		return 0;

	if (stored[0] == '\0')
		return pw[0] == '\0';

	if (stored[0] == '$')
	{
		char *hashed = crypt(pw, stored);

		return hashed && strcmp(hashed, stored) == 0;
	}

	/* No plaintext passwords: an unrecognised field never authenticates. */
	return 0;
}

static int random_salt(char *out, size_t outlen)
{
	unsigned char raw[SALT_LEN];
	size_t i;
	int fd;
	ssize_t got;
	unsigned int mix;

	if (outlen < SALT_LEN + 1)
		return -1;

	memset(raw, 0, sizeof(raw));
	fd = open("/dev/urandom", O_RDONLY);
	if (fd >= 0)
	{
		got = read(fd, raw, sizeof(raw));
		(void)close(fd);
	}
	else
		got = -1;
	if (got != (ssize_t)sizeof(raw))
	{
		/* Firstboot must not fail if urandom is briefly unavailable. */
		mix = (unsigned int)getpid() ^ (unsigned int)getppid();
		mix ^= (unsigned int)(uintptr_t)&mix;
		for (i = 0; i < SALT_LEN; i++)
		{
			mix = mix * 1664525u + 1013904223u;
			raw[i] = (unsigned char)(mix >> 16);
		}
	}

	for (i = 0; i < SALT_LEN; i++)
		out[i] = SALT_CHARS[raw[i] % (sizeof(SALT_CHARS) - 1)];
	out[SALT_LEN] = '\0';
	return 0;
}

int ir0_password_hash(const char *password, char *out, size_t outlen)
{
	char salt[SALT_LEN + 8];
	char setting[SALT_LEN + 16];
	char *hashed;

	if (!out || outlen == 0)
		return -1;
	out[0] = '\0';

	if (random_salt(salt, sizeof(salt)) != 0)
		return -1;
	snprintf(setting, sizeof(setting), "$6$%s", salt);

	hashed = crypt(password ? password : "", setting);
	if (!hashed || hashed[0] != '$')
		return -1;
	if (strlen(hashed) + 1 > outlen)
		return -1;

	snprintf(out, outlen, "%s", hashed);
	return 0;
}

/*
 * Advisory lock around passwd/shadow updates. IR0 flock(2) cannot block yet, so
 * the caller retries a bounded number of times instead of waiting forever.
 */
static int lock_accounts(void)
{
	int fd;
	int tries;

	fd = open(IR0_LOCK_FILE, O_WRONLY | O_CREAT, 0600);
	if (fd < 0)
		return -1;

	for (tries = 0; tries < 20; tries++)
	{
		if (flock(fd, LOCK_EX | LOCK_NB) == 0)
			return fd;
		usleep(50000);
	}

	(void)close(fd);
	return -1;
}

static void unlock_accounts(int fd)
{
	if (fd < 0)
		return;
	(void)flock(fd, LOCK_UN);
	(void)close(fd);
}

int ir0_shadow_set_hash(const char *user, const char *hash)
{
	static const char *tmp_path = IR0_SHADOW_FILE ".new";
	FILE *src;
	FILE *dst;
	char line[512];
	int lock_fd;
	int found = 0;
	int rc = -1;

	if (!user || !user[0] || !hash)
		return -1;

	lock_fd = lock_accounts();
	if (lock_fd < 0)
		return -1;

	src = fopen(IR0_SHADOW_FILE, "r");
	if (!src)
		goto out_unlock;

	dst = fopen(tmp_path, "w");
	if (!dst)
	{
		fclose(src);
		goto out_unlock;
	}
	(void)chmod(tmp_path, 0600);

	while (fgets(line, sizeof(line), src))
	{
		char name[IR0_AUTH_NAME_MAX];
		char rest[512];
		size_t i;
		int field = 0;
		const char *tail = "0:0:99999:7:::";

		if (ir0_auth_field(line, 0, name, sizeof(name)) != 0 ||
		    strcmp(name, user) != 0)
		{
			if (fputs(line, dst) == EOF)
				goto out_files;
			continue;
		}

		/* Preserve the aging fields (everything after the hash). */
		rest[0] = '\0';
		for (i = 0; line[i]; i++)
		{
			if (line[i] != ':')
				continue;
			field++;
			if (field == 2)
			{
				snprintf(rest, sizeof(rest), "%s", &line[i + 1]);
				break;
			}
		}
		if (rest[0])
		{
			size_t n = strlen(rest);

			while (n > 0 && (rest[n - 1] == '\n' || rest[n - 1] == '\r'))
				rest[--n] = '\0';
			tail = rest;
		}

		if (fprintf(dst, "%s:%s:%s\n", user, hash, tail) < 0)
			goto out_files;
		found = 1;
	}

	if (!found && fprintf(dst, "%s:%s:0:0:99999:7:::\n", user, hash) < 0)
		goto out_files;

	if (fflush(dst) != 0)
		goto out_files;
	fclose(dst);
	fclose(src);

	if (rename(tmp_path, IR0_SHADOW_FILE) != 0)
	{
		(void)unlink(tmp_path);
		goto out_unlock;
	}
	(void)chmod(IR0_SHADOW_FILE, 0600);
	rc = 0;
	goto out_unlock;

out_files:
	fclose(dst);
	fclose(src);
	(void)unlink(tmp_path);
out_unlock:
	unlock_accounts(lock_fd);
	return rc;
}

int ir0_group_list(const char *user, gid_t gid, gid_t *groups, int max)
{
	FILE *f;
	char line[512];
	int n = 0;

	if (!user || !groups || max <= 0)
		return -1;

	groups[n++] = gid;

	f = fopen(IR0_GROUP_FILE, "r");
	if (!f)
		return n;

	while (fgets(line, sizeof(line), f) && n < max)
	{
		char gid_s[32];
		char members[256];
		char *tok;
		char *save;
		gid_t g;
		int i;
		int dup = 0;

		if (ir0_auth_field(line, 2, gid_s, sizeof(gid_s)) != 0)
			continue;
		if (ir0_auth_field(line, 3, members, sizeof(members)) != 0)
			continue;

		g = (gid_t)strtoul(gid_s, NULL, 10);
		for (tok = strtok_r(members, ",", &save); tok;
		     tok = strtok_r(NULL, ",", &save))
		{
			if (strcmp(tok, user) == 0)
				break;
		}
		if (!tok)
			continue;

		for (i = 0; i < n; i++)
		{
			if (groups[i] == g)
				dup = 1;
		}
		if (!dup)
			groups[n++] = g;
	}

	fclose(f);
	return n;
}

int ir0_user_in_group(const char *user, const char *group)
{
	FILE *f;
	char line[512];
	int found = 0;

	if (!user || !group)
		return 0;

	f = fopen(IR0_GROUP_FILE, "r");
	if (!f)
		return 0;

	while (!found && fgets(line, sizeof(line), f))
	{
		char name[IR0_AUTH_NAME_MAX];
		char members[256];
		char *tok;
		char *save;

		if (ir0_auth_field(line, 0, name, sizeof(name)) != 0)
			continue;
		if (strcmp(name, group) != 0)
			continue;
		if (ir0_auth_field(line, 3, members, sizeof(members)) != 0)
			continue;

		for (tok = strtok_r(members, ",", &save); tok;
		     tok = strtok_r(NULL, ",", &save))
		{
			if (strcmp(tok, user) == 0)
			{
				found = 1;
				break;
			}
		}
	}

	fclose(f);
	return found;
}

int ir0_read_line(char *buf, size_t buflen, int echo)
{
	int restore = 0;
	ssize_t r;
	size_t n;

	if (!buf || buflen < 2)
		return -1;
	buf[0] = '\0';

	/*
	 * One canonical read() for the whole line (not read(1) loops).
	 * Password: silence echo via kernel-sized TCSETS (see ir0_tty_set_echo).
	 * Retry EINTR (SIGCHLD from runsv/logger must not abort the prompt).
	 * r==0 is EOF, not an empty username line.
	 */
	if (!echo)
		restore = ir0_tty_set_echo(0) == 0;

	for (;;)
	{
		r = read(0, buf, buflen - 1);
		if (r < 0)
		{
			if (errno == EINTR)
				continue;
			buf[0] = '\0';
			if (restore)
				(void)ir0_tty_set_echo(1);
			return -1;
		}
		if (r == 0)
		{
			buf[0] = '\0';
			if (restore)
				(void)ir0_tty_set_echo(1);
			return -1;
		}
		break;
	}

	n = (size_t)r;
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r'))
		n--;
	buf[n] = '\0';

	if (restore)
		(void)ir0_tty_set_echo(1);
	return 0;
}

void ir0_wipe(void *buf, size_t len)
{
	volatile unsigned char *p = buf;

	while (len--)
		*p++ = 0;
}

void ir0_hostname(char *out, size_t outlen)
{
	FILE *f;

	if (!out || outlen == 0)
		return;

	snprintf(out, outlen, "ir0");
	f = fopen("/etc/hostname", "r");
	if (!f)
		return;
	if (fgets(out, (int)outlen, f))
	{
		size_t n = strlen(out);

		while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r' ||
				 out[n - 1] == ' ' || out[n - 1] == '\t'))
			out[--n] = '\0';
	}
	if (out[0] == '\0')
		snprintf(out, outlen, "ir0");
	fclose(f);
}
