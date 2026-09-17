/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: ash_direct_console_run.c
 * Description: Console runit stub — interactive ash on /dev/console with NO
 *              getty/login. Used to repro ash SEGV without the fragile login path.
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#include <fcntl.h>
#include <unistd.h>

#include "ir0_smoke_tag.h"

static void attach_console(void)
{
	int fd;

	fd = open("/dev/console", O_RDWR);
	if (fd < 0)
		fd = open("/dev/tty", O_RDWR);
	if (fd < 0)
		return;
	(void)dup2(fd, 0);
	(void)dup2(fd, 1);
	(void)dup2(fd, 2);
	if (fd > 2)
		(void)close(fd);
}

int main(void)
{
	char *argv[3];

	attach_console();
	ir0_smoke_tag("ASH_DIRECT_START\n");
	/*
	 * Login-shell argv0 (-sh) matches product session after getty exec.
	 * No auth, no firstboot wizard — ash only.
	 */
	argv[0] = "-sh";
	argv[1] = "-i";
	argv[2] = NULL;
	execv("/bin/sh", argv);
	ir0_smoke_tag("ASH_DIRECT_EXEC_FAIL\n");
	return 111;
}
