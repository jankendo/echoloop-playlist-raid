# Toolchain management

toolchain.lock.json is the source of versions and licenses for managed tools.
current.json points at the active generation; history is retained for staged
environment rollback. Runtime state, models, downloaded audio, secrets, and
build output are ignored and must not be committed.

Use bootstrap_all for the complete environment, install_ytdlp for the package
only, verify_toolchain for read-only diagnostics, and the existing
rollback_toolchain for switching a complete Python generation.
