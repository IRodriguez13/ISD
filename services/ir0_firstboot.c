/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: ir0_firstboot.c
 * Description: First-boot wizard / seed (canonical IR0 paths).
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ir0_auth.h"
#include "ir0_keymap.h"
#include "ir0_profile.h"
#include "ir0_smoke_tag.h"

#define ROOT_DENY_FILE "/etc/ir0-noroot"
#define DONE_FILE_ETC "/etc/firstboot.done"
#define DONE_FILE_VAR "/var/lib/ir0/firstboot.done"
#define DONE_FILE_ETC_LEGACY_SHORT "/etc/fb.done"
#define DONE_FILE_VAR_LEGACY_SHORT "/var/lib/ir0/fb.done"
#define DONE_FILE_ETC_LEGACY_LONG "/etc/ir0-firstboot-done"
#define RECOVERY_FLAG "/etc/recovery"
#define SEED_ENV "FIRSTBOOT_SEED"
#define SEED_FILE_ETC "/etc/firstboot.seed"
#define SEED_FILE_ETC_LEGACY "/etc/fb.seed"

/* Write path in place (create/truncate). FS-agnostic; no rename. */
static int write_file(const char *path, const char *data, mode_t mode)
{
	int fd;
	size_t n;
	const char *p;

	if (!path || !data)
		return -1;

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
	if (fd < 0)
		return -1;
	p = data;
	n = strlen(data);
	while (n > 0)
	{
		ssize_t w = write(fd, p, n);

		if (w <= 0)
		{
			(void)close(fd);
			return -1;
		}
		p += (size_t)w;
		n -= (size_t)w;
	}
#if defined(__linux__) || defined(__IR0__)
	(void)fsync(fd);
#endif
	(void)close(fd);
	(void)chmod(path, mode);
	return 0;
}

static int mark_done(void)
{
	int ok_etc;
	int ok_var;

	(void)mkdir("/var", 0755);
	(void)mkdir("/var/lib", 0755);
	(void)mkdir("/var/lib/ir0", 0755);
	ok_etc = write_file(DONE_FILE_ETC, "ok\n", 0644) == 0;
	ok_var = write_file(DONE_FILE_VAR, "ok\n", 0644) == 0;
	return (ok_etc || ok_var) ? 0 : -1;
}

static int path_is_reg(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int already_done(void)
{
	if (path_is_reg(DONE_FILE_VAR) || path_is_reg(DONE_FILE_ETC))
		return 1;
	/* Legacy markers from older images (read-only accept). */
	if (path_is_reg(DONE_FILE_VAR_LEGACY_SHORT) ||
	    path_is_reg(DONE_FILE_ETC_LEGACY_SHORT) ||
	    path_is_reg(DONE_FILE_ETC_LEGACY_LONG))
		return 1;
	return 0;
}

static int valid_username(const char *user)
{
	size_t i, n;

	if (!user || !user[0])
		return 0;
	n = strlen(user);
	if (n < 2 || n >= IR0_AUTH_NAME_MAX)
		return 0;
	if (!islower((unsigned char)user[0]) && user[0] != '_')
		return 0;
	for (i = 0; i < n; i++)
	{
		char c = user[i];

		if (!(islower((unsigned char)c) || isdigit((unsigned char)c) ||
		      c == '_' || c == '-'))
			return 0;
	}
	if (strcmp(user, "root") == 0 || strcmp(user, "bin") == 0 ||
	    strcmp(user, "daemon") == 0 || strcmp(user, "nobody") == 0)
		return 0;
	return 1;
}

static void try_attach_console(void)
{
	int fd;

	if (isatty(0) && isatty(1))
		return;
	fd = open("/dev/console", O_RDWR);
	if (fd < 0)
		return;
	(void)dup2(fd, 0);
	(void)dup2(fd, 1);
	(void)dup2(fd, 2);
	if (fd > 2)
		(void)close(fd);
}

static int write_accounts(const char *user, const char *host, const char *hash,
			  int wheel, int lock_root, int recovery)
{
	char passwd[256];
	char shadow[512];
	char group[192];
	char home[128];
	char skel_src[64];
	char skel_dst[160];

	snprintf(passwd, sizeof(passwd),
		 "root:x:0:0:root:/root:/bin/sh\n"
		 "%s:x:1000:100:%s:/home/%s:/bin/sh\n",
		 user, user, user);
	snprintf(shadow, sizeof(shadow),
		 "root:%s:0:0:99999:7:::\n"
		 "%s:%s:0:0:99999:7:::\n",
		 lock_root ? "!" : hash, user, hash);
	if (wheel)
		snprintf(group, sizeof(group),
			 "root:x:0:\n"
			 "wheel:x:10:%s\n"
			 "users:x:100:%s\n",
			 user, user);
	else
		snprintf(group, sizeof(group),
			 "root:x:0:\n"
			 "users:x:100:%s\n",
			 user);

	(void)mkdir("/etc", 0755);
	(void)mkdir("/root", 0755);
	(void)mkdir("/home", 0755);
	snprintf(home, sizeof(home), "/home/%s", user);
	(void)mkdir(home, 0700);
	(void)chown(home, 1000, 100);
	snprintf(skel_src, sizeof(skel_src), "/etc/skel/.profile");
	if (access(skel_src, R_OK) == 0)
	{
		snprintf(skel_dst, sizeof(skel_dst), "%s/.profile", home);
		(void)link(skel_src, skel_dst);
	}

	if (write_file("/etc/passwd", passwd, 0644) != 0)
	{
		fprintf(stderr, "firstboot: cannot write /etc/passwd: %s\n",
			strerror(errno));
		return -1;
	}
	if (write_file("/etc/shadow", shadow, 0600) != 0)
	{
		fprintf(stderr, "firstboot: cannot write /etc/shadow: %s\n",
			strerror(errno));
		return -1;
	}
	if (write_file("/etc/group", group, 0644) != 0)
	{
		fprintf(stderr, "firstboot: cannot write /etc/group: %s\n",
			strerror(errno));
		return -1;
	}
	{
		char hostline[80];

		snprintf(hostline, sizeof(hostline), "%s\n", host);
		if (write_file("/etc/hostname", hostline, 0644) != 0)
		{
			fprintf(stderr, "firstboot: cannot write /etc/hostname\n");
			return -1;
		}
	}

	if (lock_root)
		(void)write_file(ROOT_DENY_FILE, "1\n", 0644);
	else
		(void)unlink(ROOT_DENY_FILE);

	if (recovery)
		(void)write_file(RECOVERY_FLAG, "1\n", 0644);
	else
		(void)unlink(RECOVERY_FLAG);

	(void)unlink("/etc/ir0-autologin");
	if (mark_done() != 0)
	{
		fprintf(stderr, "firstboot: cannot write done marker\n");
		return -1;
	}
	return 0;
}

static int seed_development(void)
{
	puts("\n*** IR0 Development profile -- NOT for production ***\n"
	     "root autologin / empty password allowed (labuser fixture).\n");
	if (write_file("/etc/ir0-autologin", "root\n", 0644) != 0)
		return -1;
	if (write_accounts("labuser", "ir0", "", 1, 0, 1) != 0)
		return -1;
	if (write_file("/etc/ir0-autologin", "root\n", 0644) != 0)
		return -1;
	if (write_file("/etc/shadow",
		       "root::0:0:99999:7:::\n"
		       "labuser::0:0:99999:7:::\n",
		       0600) != 0)
		return -1;
	return 0;
}

static int seed_appliance(void)
{
	(void)mkdir("/etc", 0755);
	(void)mkdir("/root", 0755);
	if (write_file("/etc/passwd", "root:x:0:0:root:/root:/bin/sh\n",
		       0644) != 0)
		return -1;
	if (write_file("/etc/shadow", "root:!:0:0:99999:7:::\n", 0600) != 0)
		return -1;
	if (write_file("/etc/group", "root:x:0:\n", 0644) != 0)
		return -1;
	(void)write_file("/etc/hostname", "ir0\n", 0644);
	(void)write_file(ROOT_DENY_FILE, "1\n", 0644);
	(void)unlink("/etc/ir0-autologin");
	return mark_done();
}

static int apply_seed_file(const char *path)
{
	FILE *f;
	char line[256];
	char user[IR0_AUTH_NAME_MAX] = "";
	char host[64] = "ir0";
	char hash[IR0_AUTH_HASH_MAX] = "";
	int wheel = 1;
	int lock_root = 1;
	int recovery = 1;

	f = fopen(path, "r");
	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f))
	{
		char *eq;

		if (line[0] == '#' || line[0] == '\n')
			continue;
		eq = strchr(line, '=');
		if (!eq)
			continue;
		*eq = '\0';
		eq++;
		eq[strcspn(eq, "\r\n")] = '\0';
		if (strcmp(line, "username") == 0)
			snprintf(user, sizeof(user), "%s", eq);
		else if (strcmp(line, "hostname") == 0)
			snprintf(host, sizeof(host), "%s", eq);
		else if (strcmp(line, "password_hash") == 0)
			snprintf(hash, sizeof(hash), "%s", eq);
		else if (strcmp(line, "wheel") == 0)
			wheel = (eq[0] == '1' || eq[0] == 'y' || eq[0] == 'Y');
		else if (strcmp(line, "lock_root") == 0)
			lock_root = (eq[0] == '1' || eq[0] == 'y' || eq[0] == 'Y');
		else if (strcmp(line, "recovery") == 0)
			recovery = (eq[0] == '1' || eq[0] == 'y' || eq[0] == 'Y');
	}
	fclose(f);
	if (!valid_username(user) || hash[0] == '\0')
	{
		fprintf(stderr,
			"firstboot: invalid FIRSTBOOT_SEED (need username + password_hash)\n");
		return -1;
	}
	return write_accounts(user, host, hash, wheel, lock_root, recovery);
}

static void admin_tool_label(char *buf, size_t len)
{
	FILE *f;
	char line[32];

	if (len == 0)
		return;
	buf[0] = '\0';
	f = fopen("/etc/ir0-admin-elevation", "r");
	if (f)
	{
		if (fgets(line, sizeof(line), f))
		{
			line[strcspn(line, "\r\n")] = '\0';
			if (line[0] != '\0' && strcmp(line, "sudo") == 0)
			{
				fclose(f);
				snprintf(buf, len, "sudo");
				return;
			}
		}
		fclose(f);
	}
	if (access("/usr/bin/sudo", X_OK) == 0)
		snprintf(buf, len, "sudo");
	else
		snprintf(buf, len, "doas");
}

static int wizard_interactive(void)
{
	char user[IR0_AUTH_NAME_MAX];
	char host[64];
	char pw1[IR0_AUTH_HASH_MAX];
	char pw2[IR0_AUTH_HASH_MAX];
	char hash[IR0_AUTH_HASH_MAX];
	char admin_tool[16];

	admin_tool_label(admin_tool, sizeof(admin_tool));

	puts("\nWelcome to IR0/Unix\n");
	puts("Create your account on first boot.");
	printf("This password is also used for admin tasks via %s.\n\n", admin_tool);

	for (;;)
	{
		printf("Enter your Unix username: ");
		fflush(stdout);
		if (ir0_read_line(user, sizeof(user), 1) != 0 || user[0] == '\0')
		{
			puts("Username required (no default).");
			continue;
		}
		if (!valid_username(user))
		{
			puts("Invalid or reserved username; try again.");
			continue;
		}
		break;
	}

	printf("Hostname [ir0]: ");
	fflush(stdout);
	if (ir0_read_line(host, sizeof(host), 1) != 0 || host[0] == '\0')
		snprintf(host, sizeof(host), "ir0");

	{
		char layout_line[32];
		int layout = IR0_KBD_LAYOUT_US;

		printf("Keyboard layout [us] (us|latam): ");
		fflush(stdout);
		if (ir0_read_line(layout_line, sizeof(layout_line), 1) == 0 &&
		    layout_line[0] != '\0')
		{
			int parsed = ir0_keymap_parse(layout_line);

			if (parsed >= 0)
				layout = parsed;
			else
				puts("Unknown layout; using us.");
		}
		if (ir0_keymap_write_file(IR0_KEYMAP_FILE, layout) != 0)
			fprintf(stderr, "firstboot: warning: cannot write %s\n",
				IR0_KEYMAP_FILE);
		else
			(void)ir0_keymap_set(layout);
	}

	for (;;)
	{
		printf("Password: ");
		fflush(stdout);
		(void)ir0_read_line(pw1, sizeof(pw1), 0);
		puts("");
		(void)ir0_tty_restore_cooked();
		printf("Confirm password: ");
		fflush(stdout);
		(void)ir0_read_line(pw2, sizeof(pw2), 0);
		puts("");
		(void)ir0_tty_restore_cooked();
		if (strcmp(pw1, pw2) == 0 && pw1[0] != '\0')
			break;
		puts("Passwords empty or do not match; try again.");
		ir0_wipe(pw1, sizeof(pw1));
		ir0_wipe(pw2, sizeof(pw2));
	}

	if (ir0_password_hash(pw1, hash, sizeof(hash)) != 0)
	{
		ir0_wipe(pw1, sizeof(pw1));
		ir0_wipe(pw2, sizeof(pw2));
		(void)ir0_tty_restore_cooked();
		fprintf(stderr, "firstboot: password hash failed\n");
		return -1;
	}
	ir0_wipe(pw1, sizeof(pw1));
	ir0_wipe(pw2, sizeof(pw2));
	(void)ir0_tty_restore_cooked();

	if (write_accounts(user, host, hash, 1, 1, 1) != 0)
		return -1;

	printf("\nAccount '%s' created. You can log in now.\n", user);
	printf("Admin: %s <command> (same password).\n\n", admin_tool);
	return 0;
}

int main(int argc, char **argv)
{
	enum ir0_product_profile profile;
	int interactive;
	int early = 0;
	int wizard = 0;
	const char *seed;
	int i;

	for (i = 1; i < argc; i++)
	{
		if (strcmp(argv[i], "--early") == 0)
			early = 1;
		else if (strcmp(argv[i], "--wizard") == 0)
			wizard = 1;
	}

	if (already_done())
	{
		ir0_smoke_tag("FIRSTBOOT_SKIP\n");
		return 0;
	}

	/*
	 * Stage1 uses --early (no console steal, never interactive).
	 * Console getty uses --wizard after attaching /dev/console.
	 */
	if (!early)
		try_attach_console();

	profile = ir0_read_profile();
	interactive = isatty(0) && isatty(1);
	seed = getenv(SEED_ENV);
	if ((!seed || !seed[0]) && path_is_reg(SEED_FILE_ETC))
		seed = SEED_FILE_ETC;
	else if ((!seed || !seed[0]) && path_is_reg(SEED_FILE_ETC_LEGACY))
		seed = SEED_FILE_ETC_LEGACY;

	if (profile == PROFILE_DEVELOPMENT)
	{
		if (seed && seed[0])
		{
			if (apply_seed_file(seed) != 0)
				goto fail;
		}
		else if (seed_development() != 0)
			goto fail;
		ir0_smoke_tag("FIRSTBOOT_DEV_OK\n");
		(void)ir0_tty_restore_cooked();
		return 0;
	}
	if (profile == PROFILE_APPLIANCE)
	{
		if (seed_appliance() != 0)
			goto fail;
		ir0_smoke_tag("FIRSTBOOT_APPLIANCE_OK\n");
		return 0;
	}

	/* minimal + desktop */
	if (seed && seed[0])
	{
		if (apply_seed_file(seed) != 0)
			goto fail;
		(void)unlink(SEED_FILE_ETC);
		(void)unlink(SEED_FILE_ETC_LEGACY);
		ir0_smoke_tag("FIRSTBOOT_OK\n");
		(void)ir0_tty_restore_cooked();
		return 0;
	}

	if (early)
	{
		/* Leave pending for the console wizard — do not prompt here. */
		ir0_smoke_tag("FIRSTBOOT_PENDING\n");
		return 0;
	}

	if (wizard || interactive)
	{
		if (wizard_interactive() != 0)
			goto fail;
		ir0_smoke_tag("FIRSTBOOT_OK\n");
		(void)ir0_tty_restore_cooked();
		return 0;
	}

	fprintf(stderr,
		"firstboot: no TTY and no %s — leaving firstboot pending\n",
		SEED_ENV);
	ir0_smoke_tag("FIRSTBOOT_PENDING\n");
	return 0;

fail:
	(void)ir0_tty_restore_cooked();
	ir0_smoke_tag("FIRSTBOOT_FAIL\n");
	return 1;
}
