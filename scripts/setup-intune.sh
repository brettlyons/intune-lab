#!/usr/bin/env bash
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!!                     WARNING: NOT YET TESTED                          !!!
# !!! This script has been written but not validated against a live tenant !!!
# !!! Use --dry-run first and verify behavior before running for real      !!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# setup-intune.sh - Configure Intune and Entra ID via Microsoft Graph API
#
# Creates:
#   - Dynamic device group for Intune-managed devices
#   - Uploads Remove-SetupAdmin.ps1 script
#   - Compliance policy (Defender, password requirements)
#   - Configuration profile (Defender settings)
#
# Prerequisites:
#   - curl, jq
#   - App Registration in Entra ID with appropriate permissions, OR
#   - Interactive login via device code flow
#
# Usage:
#   ./scripts/setup-intune.sh              # Interactive device code login
#   ./scripts/setup-intune.sh --dry-run    # Preview without changes

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
TENANT_DOMAIN="lyonsitlab.onmicrosoft.com"
TENANT_ID=""  # Will be fetched or can be set manually

# Microsoft Graph endpoints
GRAPH_URL="https://graph.microsoft.com"
LOGIN_URL="https://login.microsoftonline.com"

# Resource names
DEVICE_GROUP_NAME="Intune-Managed-Devices"
SCRIPT_NAME="Remove-SetupAdmin"
COMPLIANCE_POLICY_NAME="Lab-Compliance-Defender-Password"
CONFIG_PROFILE_NAME="Lab-Config-Defender-Settings"

# Use Microsoft's well-known client ID for device code flow (Microsoft Azure CLI)
# This avoids needing to create an app registration for simple scripts
CLIENT_ID="04b07795-8ddb-461a-bbee-02f9e1bf7b46"

# State
ACCESS_TOKEN=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--tenant-id <id>]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Preview changes without applying"
            echo "  --tenant-id    Specify tenant ID (otherwise uses tenant domain)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check requirements
check_requirements() {
    local missing=()

    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo "Install them with your package manager:"
        echo "  Debian/Ubuntu: sudo apt install ${missing[*]}"
        echo "  NixOS: nix-shell -p ${missing[*]}"
        exit 1
    fi
}

# Authenticate using device code flow
authenticate() {
    log_step "Authenticating with Microsoft Graph..."

    local tenant="${TENANT_ID:-$TENANT_DOMAIN}"
    local scope="https://graph.microsoft.com/.default offline_access"

    # Request device code
    local device_code_response
    device_code_response=$(curl -s -X POST "$LOGIN_URL/$tenant/oauth2/v2.0/devicecode" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&scope=$scope")

    local user_code device_code verification_uri expires_in interval
    user_code=$(echo "$device_code_response" | jq -r '.user_code')
    device_code=$(echo "$device_code_response" | jq -r '.device_code')
    verification_uri=$(echo "$device_code_response" | jq -r '.verification_uri')
    expires_in=$(echo "$device_code_response" | jq -r '.expires_in')
    interval=$(echo "$device_code_response" | jq -r '.interval // 5')

    if [[ "$user_code" == "null" ]]; then
        log_error "Failed to get device code: $device_code_response"
        exit 1
    fi

    echo ""
    echo -e "  ${YELLOW}To sign in, open a browser to:${NC} $verification_uri"
    echo -e "  ${YELLOW}Enter code:${NC} ${GREEN}$user_code${NC}"
    echo ""
    echo "  Waiting for authentication..."

    # Poll for token
    local start_time=$SECONDS
    while (( SECONDS - start_time < expires_in )); do
        sleep "$interval"

        local token_response
        token_response=$(curl -s -X POST "$LOGIN_URL/$tenant/oauth2/v2.0/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID&grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$device_code")

        local error
        error=$(echo "$token_response" | jq -r '.error // empty')

        if [[ -z "$error" ]]; then
            ACCESS_TOKEN=$(echo "$token_response" | jq -r '.access_token')
            local account
            # Decode JWT to get user info (middle part is payload)
            account=$(echo "$ACCESS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.upn // .unique_name // "unknown"' 2>/dev/null || echo "authenticated")
            log_info "Authenticated as: $account"
            return 0
        elif [[ "$error" == "authorization_pending" ]]; then
            continue
        else
            log_error "Authentication failed: $error"
            exit 1
        fi
    done

    log_error "Authentication timed out"
    exit 1
}

# Make Graph API request
graph_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local url="$GRAPH_URL$endpoint"
    local args=(-s -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi

    curl "${args[@]}" "$url"
}

# Create dynamic device group
create_device_group() {
    log_step "Creating dynamic device group: $DEVICE_GROUP_NAME"

    # Check if exists
    local existing
    existing=$(graph_request GET "/v1.0/groups?\$filter=displayName eq '$DEVICE_GROUP_NAME'" | jq -r '.value[0].id // empty')

    if [[ -n "$existing" ]]; then
        log_warn "Group already exists (ID: $existing)"
        echo "$existing"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would create group"
        echo "dry-run-group-id"
        return
    fi

    local payload
    payload=$(jq -n \
        --arg name "$DEVICE_GROUP_NAME" \
        --arg desc "Dynamic group for all Intune MDM enrolled devices" \
        '{
            displayName: $name,
            description: $desc,
            mailEnabled: false,
            mailNickname: "intune-managed-devices",
            securityEnabled: true,
            groupTypes: ["DynamicMembership"],
            membershipRule: "(device.managementType -eq \"MDM\")",
            membershipRuleProcessingState: "On"
        }')

    local response
    response=$(graph_request POST "/v1.0/groups" "$payload")
    local group_id
    group_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$group_id" ]]; then
        log_info "Created group (ID: $group_id)"
        echo "$group_id"
    else
        log_error "Failed to create group: $response"
        exit 1
    fi
}

# Upload device management script
upload_script() {
    log_step "Uploading device management script: $SCRIPT_NAME"

    local script_path="$REPO_ROOT/scripts/Remove-SetupAdmin.ps1"
    if [[ ! -f "$script_path" ]]; then
        log_error "Script not found: $script_path"
        exit 1
    fi

    # Check if exists
    local existing
    existing=$(graph_request GET "/beta/deviceManagement/deviceManagementScripts" | \
        jq -r --arg name "$SCRIPT_NAME" '.value[] | select(.displayName == $name) | .id // empty')

    if [[ -n "$existing" ]]; then
        log_warn "Script already exists (ID: $existing)"
        echo "$existing"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would upload script"
        echo "dry-run-script-id"
        return
    fi

    local script_content
    script_content=$(base64 -w0 "$script_path")

    local payload
    payload=$(jq -n \
        --arg name "$SCRIPT_NAME" \
        --arg content "$script_content" \
        '{
            displayName: $name,
            description: "Remove temporary SetupAdmin local account after Entra ID enrollment",
            scriptContent: $content,
            runAsAccount: "system",
            enforceSignatureCheck: false,
            runAs32Bit: false,
            fileName: "Remove-SetupAdmin.ps1"
        }')

    local response
    response=$(graph_request POST "/beta/deviceManagement/deviceManagementScripts" "$payload")
    local script_id
    script_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$script_id" ]]; then
        log_info "Uploaded script (ID: $script_id)"
        echo "$script_id"
    else
        log_error "Failed to upload script: $response"
        exit 1
    fi
}

# Assign script to group
assign_script_to_group() {
    local script_id="$1"
    local group_id="$2"

    log_step "Assigning script to group"

    if $DRY_RUN || [[ "$script_id" == "dry-run-script-id" ]] || [[ "$group_id" == "dry-run-group-id" ]]; then
        log_info "[DRY-RUN] Would assign script to group"
        return
    fi

    local payload
    payload=$(jq -n --arg gid "$group_id" '{
        deviceManagementScriptAssignments: [{
            target: {
                "@odata.type": "#microsoft.graph.groupAssignmentTarget",
                groupId: $gid
            }
        }]
    }')

    graph_request POST "/beta/deviceManagement/deviceManagementScripts/$script_id/assign" "$payload" > /dev/null
    log_info "Assigned script to $DEVICE_GROUP_NAME"
}

# Create compliance policy
create_compliance_policy() {
    local group_id="$1"

    log_step "Creating compliance policy: $COMPLIANCE_POLICY_NAME"

    # Check if exists
    local existing
    existing=$(graph_request GET "/beta/deviceManagement/deviceCompliancePolicies" | \
        jq -r --arg name "$COMPLIANCE_POLICY_NAME" '.value[] | select(.displayName == $name) | .id // empty')

    if [[ -n "$existing" ]]; then
        log_warn "Policy already exists (ID: $existing)"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would create compliance policy"
        return
    fi

    local payload
    payload=$(jq -n --arg name "$COMPLIANCE_POLICY_NAME" '{
        "@odata.type": "#microsoft.graph.windows10CompliancePolicy",
        displayName: $name,
        description: "Requires Defender and password standards",
        passwordRequired: true,
        passwordMinimumLength: 8,
        passwordRequiredType: "deviceDefault",
        passwordMinutesOfInactivityBeforeLock: 15,
        defenderEnabled: true,
        bitLockerEnabled: false,
        secureBootEnabled: true,
        codeIntegrityEnabled: false
    }')

    local response
    response=$(graph_request POST "/beta/deviceManagement/deviceCompliancePolicies" "$payload")
    local policy_id
    policy_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$policy_id" ]]; then
        log_info "Created policy (ID: $policy_id)"

        # Assign to group
        if [[ "$group_id" != "dry-run-group-id" ]]; then
            local assign_payload
            assign_payload=$(jq -n --arg gid "$group_id" '{
                assignments: [{
                    target: {
                        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
                        groupId: $gid
                    }
                }]
            }')
            graph_request POST "/beta/deviceManagement/deviceCompliancePolicies/$policy_id/assign" "$assign_payload" > /dev/null
            log_info "Assigned policy to $DEVICE_GROUP_NAME"
        fi
    else
        log_error "Failed to create policy: $response"
        exit 1
    fi
}

# Create configuration profile
create_config_profile() {
    local group_id="$1"

    log_step "Creating configuration profile: $CONFIG_PROFILE_NAME"

    # Check if exists
    local existing
    existing=$(graph_request GET "/beta/deviceManagement/deviceConfigurations" | \
        jq -r --arg name "$CONFIG_PROFILE_NAME" '.value[] | select(.displayName == $name) | .id // empty')

    if [[ -n "$existing" ]]; then
        log_warn "Profile already exists (ID: $existing)"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would create configuration profile"
        return
    fi

    local payload
    payload=$(jq -n --arg name "$CONFIG_PROFILE_NAME" '{
        "@odata.type": "#microsoft.graph.windows10EndpointProtectionConfiguration",
        displayName: $name,
        description: "Configure Defender real-time protection and cloud protection",
        defenderBlockOnAccessProtection: true,
        defenderCloudBlockLevel: "high",
        defenderCloudExtendedTimeout: 50,
        defenderMonitorFileActivity: "monitorAllFiles",
        defenderScanArchiveFiles: true,
        defenderScanDownloads: true,
        defenderScanIncomingMail: true,
        defenderScanScriptsLoadedInInternetExplorer: true,
        defenderSignatureUpdateIntervalInHours: 4
    }')

    local response
    response=$(graph_request POST "/beta/deviceManagement/deviceConfigurations" "$payload")
    local profile_id
    profile_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$profile_id" ]]; then
        log_info "Created profile (ID: $profile_id)"

        # Assign to group
        if [[ "$group_id" != "dry-run-group-id" ]]; then
            local assign_payload
            assign_payload=$(jq -n --arg gid "$group_id" '{
                assignments: [{
                    target: {
                        "@odata.type": "#microsoft.graph.groupAssignmentTarget",
                        groupId: $gid
                    }
                }]
            }')
            graph_request POST "/beta/deviceManagement/deviceConfigurations/$profile_id/assign" "$assign_payload" > /dev/null
            log_info "Assigned profile to $DEVICE_GROUP_NAME"
        fi
    else
        log_error "Failed to create profile: $response"
        exit 1
    fi
}

show_summary() {
    log_step "Setup complete!"
    echo ""
    echo -e "  ${CYAN}Configuration applied:${NC}"
    echo "  - Dynamic device group: $DEVICE_GROUP_NAME"
    echo "  - Device script: $SCRIPT_NAME (removes SetupAdmin after enrollment)"
    echo "  - Compliance policy: $COMPLIANCE_POLICY_NAME"
    echo "  - Configuration profile: $CONFIG_PROFILE_NAME"
    echo ""
    echo -e "  ${CYAN}Next steps:${NC}"
    echo "  1. Build the Windows ISO: ./scripts/build-iso.sh"
    echo "  2. Create a VM with the ISO"
    echo "  3. Sign in with a licensed user to enroll"
    echo "  4. Device will auto-join the group and receive policies"
    echo ""
}

# Main
main() {
    echo ""
    echo -e "${CYAN}=== Intune Lab Setup ===${NC}"
    echo "Tenant: $TENANT_DOMAIN"

    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN mode - no changes will be made]${NC}"
    fi

    check_requirements
    authenticate

    local group_id script_id
    group_id=$(create_device_group)
    script_id=$(upload_script)

    assign_script_to_group "$script_id" "$group_id"
    create_compliance_policy "$group_id"
    create_config_profile "$group_id"

    show_summary
}

main
