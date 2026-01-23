# Task Plan: Microsoft Intune Lab Setup

## Goal
Complete a documentation-first Intune lab demonstrating device enrollment, policy management, and troubleshooting workflows.

## Phases
- [x] Phase 1: Environment setup
- [x] Phase 2: Create test users and groups in Entra ID
- [ ] Phase 3: Enroll Windows test device into Intune
- [ ] Phase 4: Apply compliance and configuration policies
- [ ] Phase 5: Document troubleshooting workflows

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
**Currently in Phase 3** - Setting up Windows VM for Intune enrollment
