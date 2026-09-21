/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: sysvinit_boot.c
 * Description: sysvinit rcS — fsck, firstboot, mounts (stage1 parity without runit).
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ir0_smoke_tag.h"

static int cmdline_has_recovery(void)
{
	FILE *f;
	char buf[256];

	f = fopen("/proc/cmdline", "r");
	if (!f)
		return 0;
	if (!fgets(buf, sizeof(buf), f))
	{
		fclose(f);
		return 0;
	}
	fclose(f);
	return strstr(buf, "ir0.recovery=1") != NULL;
}

static void run_helper(const char *path)
{
	pid_t pid;
	int status;

	pid = fork();
	if (pid < 0)
		return;
	if (pid == 0)
	{
		char *const argv[] = { (char *)path, NULL };

		execv(path, argv);
		_exit(127);
	}
	(void)waitpid(pid, &status, 0);
}

static void run_firstboot_early(void)
{
	pid_t pid;
	int status;

	pid = fork();
	if (pid < 0)
		return;
	if (pid == 0)
	{
		char *const argv[] = { "/sbin/ir0-firstboot", "--early", NULL };

		execv(argv[0], argv);
		_exit(127);
	}
	(void)waitpid(pid, &status, 0);
}

static int want_fsck(void)
{
	return access("/etc/ir0-skip-fsck", F_OK) != 0;
}

static void try_mount_dennis_src(void)
{
	if (access("/heart/dennis/src", F_OK) != 0)
		return;
	if (mount("dennis", "/heart/dennis/src", "9p", 0, NULL) == 0)
		ir0_smoke_tag("DENNIS_9P_MOUNT_OK\n");
	else
		ir0_smoke_tag("DENNIS_9P_MOUNT_SKIP\n");
}

static void mount_runtime_tmp(void)
{
	if (mount("tmpfs", "/tmp", "tmpfs", 0, "mode=1777") == 0)
	{
		(void)chmod("/tmp", 01777);
		ir0_smoke_tag("RUNTIME_TMPFS_OK\n");
		return;
	}

	(void)chmod("/tmp", 01777);
	ir0_smoke_tag("RUNTIME_TMPFS_FALLBACK\n");
}

static void mount_persistent_home(void)
{
	if (access("/etc/ir0-home", F_OK) != 0)
		return;
	(void)mkdir("/home", 0755);
	if (mount("/dev/hdb", "/home", "ext2", 0, NULL) == 0)
	{
		ir0_smoke_tag("EXT2_HOME_MOUNT_OK\n");
		return;
	}
	ir0_smoke_tag("EXT2_HOME_MOUNT_FAIL\n");
}

int main(void)
{
	char *const argv_rec[] = { "/sbin/ir0-recovery", NULL };

	if (want_fsck())
		run_helper("/sbin/fsck.ir0");
	mount_runtime_tmp();
	mount_persistent_home();
	run_firstboot_early();
	try_mount_dennis_src();

	ir0_smoke_tag("SYSVINIT_BOOT_OK\n");

	if (cmdline_has_recovery())
	{
		ir0_smoke_tag("RECOVERY_BOOT_SELECTED\n");
		execv("/sbin/ir0-recovery", argv_rec);
		ir0_smoke_tag("RECOVERY_HANDOFF_FAIL\n");
		return 111;
	}

	return 0;
}
