#!/usr/bin/env node
// No-op replacement for node-gyp.
// better-sqlite3 ships with prebuilt binaries that work on this platform,
// so we don't need to compile from source (which requires VS Build Tools on Windows).
process.exit(0);
