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
# Create VM from ISO (Windows 11 with VirtIO and TPM 2.0)
# Must use sudo and qemu:///system for TPM support via swtpm
sudo virt-install \
  --connect qemu:///system \
  --name win11-intune \
  --ram 4096 \
  --vcpus 2 \
  --disk size=60,bus=virtio \
  --cdrom /home/blyons/Downloads/Win11_24H2_English_x64.iso \
  --os-variant win11 \
  --network network=default,model=virtio \
  --graphics spice \
  --tpm backend.type=emulator,backend.version=2.0 \
  --boot uefi \
  --noautoconsole
```

**VirtIO Drivers (NixOS):**
- Package: `virtio-win` (added to `system.nix` environment.systemPackages)
- Location: `/nix/store/*-virtio-win-*/`
- Contains: Driver directories for disk (viostor), network (NetKVM), balloon, etc.
- Windows installer: `virtio-win-guest-tools.exe` in package root

**Required for Windows Install with VirtIO disk**:

When using `bus=virtio` for the disk, Windows installer will show **no drives available** at the "Where do you want to install Windows?" screen. This is because Windows doesn't have VirtIO drivers built-in.

**Solution**: Load the VirtIO storage driver (viostor) during installation. However, the NixOS `virtio-win` package contains extracted driver directories, NOT an ISO file, so you must first create an ISO and attach it to the VM.

1. Create an ISO from the nix store directory:
```bash
nix-shell -p cdrtools --run "mkisofs -o /tmp/virtio-win.iso -J -r /nix/store/*-virtio-win-*/"
```

2. Attach ISO to running VM:
```bash
# This fails - SATA cannot be hotplugged:
sudo virsh attach-disk win11-intune /tmp/virtio-win.iso sdb --type cdrom --mode readonly --targetbus sata
# error: Operation not supported: disk bus 'sata' cannot be hotplugged.

# Use USB instead:
sudo virsh attach-disk win11-intune /tmp/virtio-win.iso sdb --type cdrom --mode readonly --targetbus usb
```

3. In Windows installer at "Where do you want to install Windows?":
   - Click "Load driver"
   - Click "Browse"
   - Navigate to USB drive → `viostor/w11/amd64`
   - Select the driver and click OK
   - The 60GB VirtIO disk will now appear

## Unattended Windows Installation

**Problem**: Manual Windows installation requires multiple interactions:
- Clicking through language/region selection
- Manually loading VirtIO drivers when disk isn't visible
- Partitioning the disk
- Clicking through OOBE screens
- Setting up user accounts

This makes it tedious to spin up fresh VMs for testing, and the VirtIO driver step is easy to forget.

**Solution**: Use `autounattend.xml` answer file for fully automated installation.

The `autounattend.xml` in this repo automates:
- Language/locale (en-US)
- Skips product key (evaluation)
- Auto-partitions disk (GPT/UEFI: EFI + MSR + Windows partitions)
- Loads VirtIO drivers automatically (tries D:, E:, F: drive letters)
- Auto-generates computer name
- Skips most OOBE screens
- Presents Microsoft/Entra ID sign-in for Intune enrollment

### Creating the Combined ISO

Combine `autounattend.xml` with VirtIO drivers into one ISO:

```bash
# Copy virtio drivers and autounattend.xml to temp directory
mkdir -p /tmp/virtio-combined
cp -r /nix/store/*-virtio-win-*/* /tmp/virtio-combined/
cp autounattend.xml /tmp/virtio-combined/

# Create ISO
nix-shell -p cdrtools --run "mkisofs -o virtio-autounattend.iso -J -r /tmp/virtio-combined/"
```

### One-Command VM Creation (Unattended)

```bash
# Remove existing VM if present
sudo virsh destroy win11-intune 2>/dev/null
sudo virsh undefine win11-intune --nvram 2>/dev/null

# Create VM with both ISOs - boots and installs automatically
sudo virt-install \
  --connect qemu:///system \
  --name win11-intune \
  --ram 4096 \
  --vcpus 2 \
  --disk size=60,bus=virtio \
  --cdrom /home/blyons/Downloads/Win11_24H2_English_x64.iso \
  --disk virtio-autounattend.iso,device=cdrom \
  --os-variant win11 \
  --network network=default,model=virtio \
  --graphics spice \
  --tpm backend.type=emulator,backend.version=2.0 \
  --boot uefi \
  --noautoconsole
```

After boot, Windows will install automatically and present the Entra ID sign-in screen. Sign in with a work account (e.g., `testuser01@lyonsitlab.onmicrosoft.com`) to join Entra ID and auto-enroll in Intune.

### Intune Auto-Enrollment Prerequisites

For automatic Intune enrollment when signing in with a work account:
1. User must have Intune license (included in M365 Business Premium)
2. MDM auto-enrollment enabled in Entra ID:
   - https://entra.microsoft.com → Identity → Devices → Device settings
   - Set "MDM user scope" to "All" or select security group

**Network Autostart (Potential Issue):**
- The default libvirt network may not autostart after reboot
- If VMs fail to start with "network 'default' is not active":
  ```bash
  sudo virsh net-start default
  sudo virsh net-autostart default
  ```
- This is a known NixOS/libvirt quirk - no declarative fix currently
- Consider NixVirt flake for fully declarative network management

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
