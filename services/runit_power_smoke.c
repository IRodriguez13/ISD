/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: runit_power_smoke.c
 * Description: One-shot runit service — request HALT through semantic sysfs control.
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include "ir0_smoke_tag.h"

int main(void)
{
	static const char command[] = "halt\n";
	int fd;

	ir0_smoke_tag("POWER_SMOKE_CALL\n");
	fd = open("/sys/kernel/halt", O_WRONLY);
	if (fd < 0)
	{
		ir0_smoke_tag("POWER_SMOKE_SYSFS_OPEN_FAIL\n");
		return 1;
	}
	ir0_smoke_tag("POWER_SMOKE_SYSFS_CALL\n");
	errno = 0;
	if (write(fd, "x", 1) != -1 || errno != EINVAL)
	{
		ir0_smoke_tag("POWER_SMOKE_SYSFS_INVALID_FAIL\n");
		close(fd);
		return 1;
	}
	ir0_smoke_tag("POWER_SMOKE_SYSFS_INVALID_OK\n");
	if (write(fd, command, sizeof(command) - 1) < 0)
		ir0_smoke_tag("POWER_SMOKE_SYSFS_WRITE_FAIL\n");
	close(fd);
	ir0_smoke_tag("POWER_SMOKE_HALT_RETURNED\n");
	return 1;
}
