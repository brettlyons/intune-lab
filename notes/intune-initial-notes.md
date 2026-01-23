# Intune Lab – Initial Notes

## Objective
Establish a Microsoft Intune test environment and validate basic device enrollment and policy application.

## Environment
- Microsoft 365 Business Premium Trial (M365 Developer Program sandbox was unavailable)
- Tenant: lyonsitlab.onmicrosoft.com
- Entra ID
- Microsoft Intune
- Windows 10/11 test device (local QEMU/KVM VM)

### VM Options Considered
- **Azure VM**: ~$170/mo for D2 Windows instance (Azure offers $200 free credits for new accounts)
- **Local QEMU/KVM**: Free, requires Windows ISO from Microsoft evaluation center or existing media

### Virsh/libvirt Quick Reference

**GUI Management:**
```bash
virt-manager                    # Launch graphical VM manager
```

**VM Lifecycle:**
```bash
virsh list --all                # List all VMs (running and stopped)
virsh start <vm-name>           # Start a VM
virsh shutdown <vm-name>        # Graceful shutdown (ACPI)
virsh destroy <vm-name>         # Force stop (like pulling power)
virsh reboot <vm-name>          # Reboot VM
virsh suspend <vm-name>         # Pause VM
virsh resume <vm-name>          # Resume paused VM
```

**VM Creation:**
```bash
# Create VM from ISO (example for Windows 11)
virt-install \
  --name win11-intune \
  --ram 4096 \
  --vcpus 2 \
  --disk size=60 \
  --cdrom /path/to/Win11_24H2_English_x64.iso \
  --os-variant win11 \
  --network default \
  --graphics spice \
  --tpm backend.type=emulator,backend.version=2.0
```

**Snapshots:**
```bash
virsh snapshot-create-as <vm> <snapshot-name>  # Create snapshot
virsh snapshot-list <vm>                        # List snapshots
virsh snapshot-revert <vm> <snapshot-name>      # Revert to snapshot
virsh snapshot-delete <vm> <snapshot-name>      # Delete snapshot
```

**Console/Display:**
```bash
virsh console <vm-name>         # Serial console (if configured)
virt-viewer <vm-name>           # Graphical console
```

**Info:**
```bash
virsh dominfo <vm-name>         # VM details
virsh domifaddr <vm-name>       # Get VM IP address
```

## Planned Tasks
- Create test users and groups
- Enroll a Windows device into Intune
- Apply a basic compliance policy
- Apply a simple configuration profile
- Observe and troubleshoot policy assignment behavior

## Change Management
Ticket management handled in Zammad homelab instance. All changes follow a ticketed workflow:
1. Create ticket describing the change
2. Document intended configuration
3. Implement change
4. Update ticket with results
5. Close ticket

## Notes
- Intune workflow is heavily group-driven; incorrect group membership is a common failure point
- Device sync timing matters — forced sync is often required during testing
- Documentation-first approach helps reduce trial-and-error during configuration

## Next Steps
- Complete device enrollment
- Document compliance policy creation
- Capture common troubleshooting steps
