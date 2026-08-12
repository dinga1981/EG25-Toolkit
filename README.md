# EG25-Toolkit

An open-source toolkit for automating LTE modem workflows across macOS, Linux virtual machines, and IoT environments.

EG25-Toolkit helps developers manage cellular modem connectivity in complex environments where USB modem devices, virtual machines, and different networking modes need to work together reliably.

The toolkit was originally developed for Quectel EG25-G LTE modules running with macOS hosts and UTM Ubuntu virtual machines. It provides automated workflows for switching between ECM, QMI, and VoHive modes, while handling device detection, connectivity verification, diagnostics, and recovery operations.

## Why EG25-Toolkit?

Using cellular modules in desktop and virtualized environments often involves multiple layers:

- USB device passthrough
- Modem AT command communication
- QMI network interfaces
- Virtual machine networking
- Cellular service management
- Failure detection and recovery

Manually managing these components can be time-consuming and error-prone.

EG25-Toolkit reduces this complexity by providing a unified command-line interface and automated workflows.

## Features

- Automated LTE modem mode switching
- macOS ECM network management
- Ubuntu VM QMI / VoHive workflow support
- Automatic modem interface detection
- AT command communication testing
- LTE connectivity verification
- Network health monitoring
- Automatic recovery workflows
- Diagnostic commands and troubleshooting information
- Operation history tracking
- Exclusive operation locking with stale-lock recovery

## Supported Environment

Current tested environment:

- macOS host
- UTM Ubuntu virtual machine
- Quectel EG25-G LTE module
- Compatible LTE modem modules
- VoHive cellular networking environment

## Quick Start

Install:

```bash
cd eg25-toolkit-v3.3.1
chmod +x install.sh uninstall.sh bin/eg25
./install.sh
```

Check system status:
```bash
eg25 doctor
eg25 status
```

Switch networking mode:
macOS ECM mode:
```bash
eg25 mac
```

Ubuntu VM QMI / VoHive mode:
```bash
eg25 vohive
```

Repair connectivity:
```bash
eg25 repair
```

Run full health check:
```bash
eg25 health
```

## Project Goals

The goal of EG25-Toolkit is to make cellular connectivity development more reliable and accessible by reducing the complexity of modem management across operating systems and virtualized environments.
Future development will focus on broader hardware compatibility, improved diagnostics, and easier integration with IoT edge platforms.

## Documentation
中文详细文档:
➡️ [README_CN.md](README_CN.md)

## License

EG25-Toolkit is released under the [MIT License](LICENSE).


