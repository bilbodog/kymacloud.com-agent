#!/bin/bash

username="kymacloud"
group="kymacloud"

ID="__QUERY_ID__"
API_URL="https://app.kymacloud.com/api/v1/servers/init/"

RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"id\": $ID}")

# Tjek for fejl
if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
  echo "Fejl ved API kald"
  exit 1
fi

public_key_raw=$(echo "$RESPONSE" | jq -r '.ssh_rsa // .SSH_RSA // .public_key // empty')
organization_id=$(echo "$RESPONSE" | jq -r '.kunde_id // .KundeID // .organization_id // empty')

public_key_formated=$(echo "ssh-rsa ${public_key_raw}" | tr -s ' ')


echo "Public Key: ${public_key_formated}"
echo "Organization ID: ${organization_id}"

# Opret bruger og tilføj til gruppe
sudo useradd -m -s /bin/bash "${username}"
sudo usermod -aG "${group}" "${username}"

# Giv Lav nøgle rettigheder
sudo mkdir -p /home/"${username}"/.ssh
echo "$public_key_formated" >> /home/"${username}"/.ssh/authorized_keys
sudo chown -R "${username}:${group}" /home/"${username}"/.ssh
sudo chmod 700 /home/"${username}"/.ssh
sudo chmod 600 /home/"${username}"/.ssh/authorized_keys

