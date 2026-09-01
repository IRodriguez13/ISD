/**
 * IR0 Kernel — Core system software
 * Copyright (C) 2026  Iván Rodriguez
 *
 * This file is part of the IR0 Operating System.
 * Distributed under the terms of the GNU General Public License v3.0.
 * See the LICENSE file in the project root for full license information.
 *
 * File: lsblk.c
 * Description: List block devices. BusyBox ships no lsblk applet, so the
 *              product provides its own port on top of /proc/blockdevices.
 *              Builds on Linux first, then for IR0 (see natives/README.md).
 */

/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define BLOCKDEVICES_PATH "/proc/blockdevices"
#define MOUNTS_PATH "/proc/mounts"
#define NAME_MAX_LEN 32
#define MOUNT_MAX_LEN 96
#define MAX_ROWS 64

struct row
{
	char name[NAME_MAX_LEN];
	char type[16];
	char size[16];
	unsigned maj;
	unsigned min;
	char mountpoint[MOUNT_MAX_LEN];
};

/*
 * /proc/mounts holds the device path (/dev/hda1), lsblk shows the bare name,
 * so match on the trailing component only.
 */
static void fill_mountpoint(struct row *r)
{
	FILE *f;
	char line[256];

	r->mountpoint[0] = '\0';
	f = fopen(MOUNTS_PATH, "r");
	if (!f)
		return;

	while (fgets(line, sizeof(line), f))
	{
		char dev[128];
		char mnt[MOUNT_MAX_LEN];
		const char *base;

		if (sscanf(line, "%127s %95s", dev, mnt) != 2)
			continue;

		base = strrchr(dev, '/');
		base = base ? base + 1 : dev;
		if (strcmp(base, r->name) != 0)
			continue;

		snprintf(r->mountpoint, sizeof(r->mountpoint), "%s", mnt);
		break;
	}
	fclose(f);
}

static int read_rows(struct row *rows, int max_rows)
{
	FILE *f;
	char line[256];
	int n = 0;

	f = fopen(BLOCKDEVICES_PATH, "r");
	if (!f)
	{
		fprintf(stderr, "lsblk: cannot open %s\n", BLOCKDEVICES_PATH);
		return -1;
	}

	while (fgets(line, sizeof(line), f) && n < max_rows)
	{
		struct row *r = &rows[n];
		char model[64];
		char serial[64];
		char sectors[32];

		if (line[0] == '#')
			continue;

		/* type name maj min sectors_512 size model serial */
		if (sscanf(line, "%15s %31s %u %u %31s %15s %63s %63s",
			   r->type, r->name, &r->maj, &r->min, sectors,
			   r->size, model, serial) < 6)
			continue;

		fill_mountpoint(r);
		n++;
	}
	fclose(f);
	return n;
}

/* Partitions of a disk are indented under it, as lsblk does with its tree. */
static int is_child_of(const char *name, const char *parent)
{
	size_t plen = strlen(parent);

	return strncmp(name, parent, plen) == 0 && name[plen] != '\0';
}

int main(int argc, char **argv)
{
	struct row rows[MAX_ROWS];
	int n;
	int i;

	if (argc > 1 && strcmp(argv[1], "--help") == 0)
	{
		printf("Usage: lsblk\n");
		printf("List block devices from %s.\n", BLOCKDEVICES_PATH);
		return 0;
	}

	n = read_rows(rows, MAX_ROWS);
	if (n < 0)
		return 1;

	printf("%-12s %-7s %6s %-5s %s\n", "NAME", "MAJ:MIN", "SIZE", "TYPE",
	       "MOUNTPOINT");
	for (i = 0; i < n; i++)
	{
		const struct row *r = &rows[i];
		char label[NAME_MAX_LEN + 4];
		char majmin[16];
		int child = (i > 0) && is_child_of(r->name, rows[i - 1].name);

		snprintf(label, sizeof(label), "%s%.*s", child ? "`-" : "",
			 (int)(NAME_MAX_LEN - 1), r->name);
		snprintf(majmin, sizeof(majmin), "%u:%u", r->maj, r->min);
		printf("%-12s %-7s %6s %-5s %s\n", label, majmin, r->size,
		       r->type, r->mountpoint);
	}

	return 0;
}
