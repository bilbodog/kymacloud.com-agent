#!/bin/bash

set -e
set -o pipefail

################################################################################
# Configuration
################################################################################

QUERY_ID=__QUERY_ID__
API_INIT_URL="https://app.kymacloud.com/api/v1/servers/init/"
API_DEPLOY_URL="https://app.kymacloud.com/api/v1/servers/deploy"
API_HEARTBEAT_URL="https://app.kymacloud.com/api/v1/servers/heartbeat"

################################################################################
# Validation
################################################################################

validate_input() {

    if [ -z "$QUERY_ID" ]; then
        echo "Missing QUERY_ID"
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        echo "This script must run as root"
        exit 1
    fi

}

################################################################################
# Fetch organization data from API
################################################################################

fetch_organization_data() {

    echo "Fetching organization data from API..."

    apt-get update -qq
    apt-get install -y -qq curl jq

    RESPONSE=$(curl -s -X POST "$API_INIT_URL" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"id\": \"$QUERY_ID\"}")

    if [ -z "$RESPONSE" ]; then
        echo "API request failed"
        exit 1
    fi

    SSH_KEY_RAW=$(echo "$RESPONSE" | jq -r '.public_key // empty')
    ORG_ID=$(echo "$RESPONSE" | jq -r '.organization_id // empty')

    if [ -z "$SSH_KEY_RAW" ] || [ -z "$ORG_ID" ]; then
        echo "Invalid API response"
        echo "$RESPONSE"
        exit 1
    fi

    SSH_KEY_FORMATTED="ssh-rsa ${SSH_KEY_RAW} RSA-by-KymaCloud"

    echo "Organization ID: $ORG_ID"
    echo "SSH Key received"

}

################################################################################
# Notify deploy
################################################################################

notify_deploy() {

    echo "Notifying deploy..."

    curl -s -X POST "$API_DEPLOY_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"identifier\": \"$QUERY_ID\"
        }"

}

################################################################################
# Send heartbeat
################################################################################

send_heartbeat() {

    STATUS="$1"
    DESCRIPTION="$2"

    curl -s -X POST "$API_HEARTBEAT_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"identifier\": \"$QUERY_ID\",
            \"status_description\": \"$DESCRIPTION\",
            \"status\": \"$STATUS\"
        }"

}

################################################################################
# Main
################################################################################

main() {

    validate_input

    fetch_organization_data

    notify_deploy

    send_heartbeat "Deploying" "Server connected to API"

    echo "Server successfully connected to API"

}

main "$@"
