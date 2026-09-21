/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * Minimal Linux-baseline reproducer for xterm-411 MapSelections / isSELECT
 * vulnerability class (vanilla upstream logic, no IR0 code).
 *
 * Build: cc -O0 -g -o linux-baseline-repro linux-baseline-repro.c
 * Run:   ./linux-baseline-repro
 *
 * Expected on any Linux host: SIGSEGV in strcmp (cr2=0x9), exit 139.
 * Patched logic (InvalidSelectionParam) exits 0 without fault.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

#define isSELECT(value) (!strcmp((value) ? (value) : "<null>", "SELECT"))

static int
invalid_selection_param(const char *value)
{
	if (value == NULL)
		return 0;
	if ((unsigned long) (const char *) value < 4096UL)
		return 1;
	return 0;
}

static void
vanilla_mapselections_probe(const char *param)
{
	/* Mirrors vanilla xterm-411 MapSelections inner check (no low-address guard). */
	if (param != NULL && isSELECT(param))
		puts("map");
}

static void
patched_mapselections_probe(const char *param)
{
	if (invalid_selection_param(param)) {
		fprintf(stderr, "patched: ignore invalid param=%p\n", (void *) param);
		return;
	}
	if (param != NULL && isSELECT(param))
		puts("map");
}

int
main(void)
{
	const char *garbage = (const char *) 9;

	printf("=== vanilla logic (expect SIGSEGV, cr2~9) ===\n");
	fflush(stdout);
	vanilla_mapselections_probe(garbage);
	printf("vanilla: unexpected success\n");
	return 1;
}
