# ISD package catalog

Recipe directories remain flat at `packages/<name>/`: those paths are part of
the source-cache, download and stamp contracts.  Moving them into category
directories would invalidate incremental builds and needlessly duplicate path
logic in Make and the fetcher.

The `*.list` files are the canonical semantic organization.  Each buildable
recipe must appear exactly once.  They feed the sectioned `make isdconfig`
menu and are checked with:

```sh
make package-catalog-check
```

Categories describe product intent, not build dependencies.  Dependencies
remain explicit in the package graph in the top-level `Makefile`.
