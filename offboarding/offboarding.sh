#!/usr/bin/env bash
# User Offboarding Script
# Jason Satti

# Initialize the full path of GAM
GAM=~/bin/gam/gam

# Get Command line arguments for Employee Email and Term Type
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -e | --email)
        EMPLOYEE="$2"
        shift # past argument
        shift # past value
        ;;
    -t | --termtype)
        TERMTYPE="$2"
        shift # past argument
        shift # past value
        ;;
    *) # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift              # past argument
        ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Verify user exists in Google Suite
email_verification() {
    if ${GAM} info user "${EMPLOYEE}" >/dev/null 2>&1; then
        return
    else
        echo "$EMPLOYEE does not exist in Google Suite."
    fi
    printf %s\\n "Please enter a valid email address."
    exit 1
}

# Verify Termination Type
term_type() {
    case "$TERMTYPE" in
    [Vv] | [Vv]oluntary)
        TERMTYPE=Voluntary
        ;;
    [Ii] | [Ii]nvoluntary)
        TERMTYPE=Involuntary
        ;;
    *)
        printf %s\\n "Please enter 'V' or 'I' for Term Type"
        exit 1
        ;;
    esac
}

# Create log file and record user information
start_logger() {
    exec &> >(tee offboard.log)
    echo "$(whoami) conducting $TERMTYPE offboarding for $EMPLOYEE on $(date)"
}

# Get the username and last name of employee
get_name() {
    USER_NAME="${EMPLOYEE//@company.com/}"
    LAST_NAME=$(echo "$USER_NAME" | cut -f2 -d'.')
}

# Reset Employee's account password to a randomly generated password
# This will also reset sign-in cookies
# Forcing change password on next sign-in and then disabling immediately.
# Speculation that this will sign user out within 5 minutes and not allow
# user to send messages without reauthentication
reset_password() {
    echo "Resetting GSuite password"
    PASSWORD=$(openssl rand -base64 12)
    ${GAM} update user "${EMPLOYEE}" password "${PASSWORD}"
    ${GAM} update user "${EMPLOYEE}" changepassword on
    sleep 2
    ${GAM} update user "${EMPLOYEE}" changepassword off
}

# Remove all App-Specific account passwords, delete MFA Recovery Codes,
# Delete all OAuth tokens
# Generating new set of MFA recovery codes for the user
reset_token() {
    echo "Resetting GSuite tokens"
    ${GAM} user "${EMPLOYEE}" deprovision
    ${GAM} user "${EMPLOYEE}" update backupcodes
}

# Remove all email delegation
remove_delegates() {
    echo "Removing email delegates"
    DELEGATES=$(${GAM} user "${EMPLOYEE}" print delegates)
    for DELEGATE in "${DELEGATES[@]}"; do
        ${GAM} user "${EMPLOYEE}" delete delegate "${DELEGATE}"
    done
}

# Wipe device profile and remove Google accounts from all mobile devices
wipe_devices() {
    echo "Wiping all associated mobile devices"
    $GAM print mobile query "email:$EMPLOYEE" >>/tmp/tmp.mobile-data.csv
    $GAM csv /tmp/tmp.mobile-data.csv gam update mobile ~resourceId action account_wipe
}

# Remove all forwarding addresses
# Disable IMAP
# Disable POP
# Hide user from directory
disable_user() {
    echo "Disabling Email and hiding from Directory"
    $GAM user "${EMPLOYEE}" forward off
    $GAM user "${EMPLOYEE}" imap off
    $GAM user "${EMPLOYEE}" pop off
    $GAM update user "${EMPLOYEE}" gal off
}

# Retrieve the employee's manager information from Google Suite
# Transfer Google Drive and Documents ownership to Employee's Manager
transfer_drive() {
    echo "Transfering Google Drive and documents to manager"
    MANAGER=$(${GAM} info user "${EMPLOYEE}" | grep "manager" -A1 | grep "value" |
        cut -f3 -f4 -d' ' | tr " " .)
    ${GAM} create datatransfer "${EMPLOYEE}" gdrive "${MANAGER}"
}

# Get a list of all groups the employee belongs to
# Remove the employee from all groups
remove_groups() {
    echo "Removing user from all groups"
    ${GAM} info user "${EMPLOYEE}" | grep -A 10000 "Groups:" | awk 'BEGIN { FS = ">|<" } ; { print $2 }' >/tmp/"${EMPLOYEE}".txt
    while read -r GROUP; do
        [ -z "$GROUP" ] && continue
        ${GAM} update group "${GROUP}" remove member "${EMPLOYEE}"
    done </tmp/"${EMPLOYEE}".txt
}

# Delegate email access to manager if termination is Involuntary
# Suspend user to kick off all logged in sessions
# Unsuspend Involuntary termination user for email delgation
# Verify that user was moved to correct Organizational Unit
suspend_user() {
    ${GAM} update user "${EMPLOYEE}" suspended on
    if [ "$TERMTYPE" = 'Involuntary' ]; then
        echo "Granting delegate access to employee manager and moving to Involuntary Terminations OU"
        ${GAM} update user "${EMPLOYEE}" suspended off
        ${GAM} user "${EMPLOYEE}" delegate to "${MANAGER}"
        ${GAM} update org 'Involuntary Terminations' add users "${EMPLOYEE}"
    else
        echo "Suspending user and moving to Voluntary Terminations OU"
        ${GAM} update org 'Voluntary Terminations' add users "${EMPLOYEE}"
    fi
    ORG_UNIT=$(${GAM} info user "${EMPLOYEE}" | grep "Google Org")
    echo "$EMPLOYEE moved to $ORG_UNIT"
}

# Slack deprovisioning
#deprovision_slack() {
#    echo "Deprovisioning in Slack"
#    python3 Slack_API.py --email "$EMPLOYEE"
#}

# Update Jamf device info
#update_jamf() {
#    echo "Updating Device information in JAMF"
#    python3 Update_Jamf_Device.py --l "$LAST_NAME" -s 'TERMED'
#}

# Main
start_logger
email_verification
term_type
get_name
reset_password
reset_token
remove_delegates
wipe_devices
disable_user
transfer_drive
remove_groups
suspend_user
#deprovision_slack
#update_jamf
