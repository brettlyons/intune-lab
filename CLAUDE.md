# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Documentation-first Microsoft Intune learning lab. The goal is to demonstrate hands-on Intune experience while following MSP/enterprise change management practices.

## Key Context

- **Tenant**: lyonsitlab.onmicrosoft.com (M365 Business Premium Trial)
- **Test Users**: testuser01, testuser02
- **Security Groups**: Intune-Test-Users, Intune-Test-Devices
- **VM Environment**: Local QEMU/KVM with Windows 11 24H2 ISO
- **Change Management**: Zammad homelab instance for ticketing

## File Structure

```
intune-lab/
├── CLAUDE.md           # This file - project context
├── README.md           # Project overview
├── task_plan.md        # Manus-style progress tracking
└── notes/
    └── intune-initial-notes.md  # Lab notes and documentation
```

## Workflow

1. Create ticket in Zammad before making changes
2. Document intended configuration
3. Implement in test tenant
4. Update notes with results
5. Close ticket

## Current Status

See `task_plan.md` for current phase and progress.

## Common Commands

```bash
# VM management (after libvirtd setup)
virt-manager              # GUI for VM management
virsh list --all          # List all VMs
virsh start <vm-name>     # Start a VM
virsh shutdown <vm-name>  # Graceful shutdown
```

## Intune Admin URLs

- Intune Admin Center: https://intune.microsoft.com
- Entra Admin Center: https://entra.microsoft.com
- M365 Admin Center: https://admin.microsoft.com
