/* SPDX-License-Identifier: GPL-3.0-only */
/* Deterministic root service that exercises /sys/kernel/panic. */

#include <fcntl.h>
#include <unistd.h>

#include "ir0_smoke_tag.h"

int main(void)
{
	int fd;

	ir0_smoke_tag("SYSFS_PANIC_CALL\n");
	fd = open("/sys/kernel/panic", O_WRONLY);
	if (fd < 0)
	{
		ir0_smoke_tag("SYSFS_PANIC_OPEN_FAIL\n");
		return 1;
	}
	(void)write(fd, "panic\n", 6);
	ir0_smoke_tag("SYSFS_PANIC_RETURNED\n");
	close(fd);
	return 1;
}
