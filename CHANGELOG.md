# Changelog

All notable changes to EG25-Toolkit are documented in this file.

## [3.3.2] - 2026-08-12

### Added

- Added an exclusive cross-process operation lock for `mac`, `vohive`, `repair`, `reset`, and `at` commands.
- Added lock owner metadata, including PID, command, process start signature, and start time.
- Added stale-lock detection and safe recovery, including PID reuse protection.
- Added lock cleanup on normal exit, `SIGINT`, and `SIGTERM`.
- Added the MIT License.

### Changed

- Documented operation locking in the English and Chinese READMEs.
- Updated all stable-version references to v3.3.2.

## [3.3.1] - 2026-08-07

### Added

- Initial public release.
- Added macOS ECM and UTM Ubuntu QMI / VoHive mode switching.
- Added automatic USB, AT port, QMI, network, and service status checks.
- Added controlled CFUN recovery for failed QMI data connections.
- Added operation history, recovery statistics, and runtime logs.

[3.3.2]: https://github.com/dinga1981/EG25-Toolkit/compare/v3.3.1...v3.3.2
[3.3.1]: https://github.com/dinga1981/EG25-Toolkit/releases/tag/v3.3.1
