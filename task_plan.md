# Task Plan: Microsoft Intune Lab Setup

## Goal
Complete a documentation-first Intune lab demonstrating device enrollment, policy management, and troubleshooting workflows.

## Phases
- [x] Phase 1: Environment setup
- [x] Phase 2: Create test users and groups in Entra ID
- [x] Phase 3: Enroll Windows test device into Intune
- [ ] Phase 4: Apply compliance and configuration policies
- [ ] Phase 5: Document troubleshooting workflows

## Next Session Tasks
- [ ] Confirm Intune license assigned to test user
- [ ] Force a device sync from Intune console
- [ ] Apply one compliance policy (e.g., require PIN/BitLocker)
- [ ] Apply one configuration profile (e.g., screen lock/password requirements)
- [ ] Break → fix one thing (intentional troubleshooting exercise)

## Key Questions
1. What compliance policies are most relevant for demonstrating real-world scenarios?
2. What configuration profiles should be applied?
3. What common troubleshooting scenarios should be documented?

## Decisions Made
- **M365 Business Premium Trial**: M365 Developer sandbox was unavailable
- **Tenant name**: lyonsitlab.onmicrosoft.com
- **Local QEMU/KVM VM**: Chosen over Azure VM for cost efficiency
- **Zammad ticketing**: Using homelab Zammad instance for change management

## Errors Encountered
- M365 Developer Program sandbox qualification failed - used Business Premium trial instead
- Azure VM default pricing (~$170/mo D2) - switched to local VM approach

## Status
**Currently in Phase 3** - Windows 11 VM created (`win11-intune`), ready for OS installation and Intune enrollment

### Phase 3 Progress
- [x] Configured libvirt default network
- [x] Added `virtio-win` to NixOS system packages
- [x] Created Windows 11 VM with VirtIO disk/network and TPM 2.0
- [x] Created `autounattend.xml` for automated future installs
- [x] Complete Windows installation (loaded VirtIO drivers manually)
- [x] Enroll device into Intune (confirmed via dsregcmd /status)
