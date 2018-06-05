#!/usr/bin/env bash

if [[ -z $AZURE_KEYVAULT_NAME ]] || [[ -z $PRIVATE_KEY_SECRET_NAME ]] || [[ -z $PUBLIC_KEY_SECRET_NAME ]] || [[ -z $WIN_PASS_SECRET_NAME ]]; then
    echo "ERROR: KEYVAULT_NAME, PRIVATE_KEY_SECRET_NAME, PUBLIC_KEY_SECRET_NAME and WIN_PASS_SECRET_NAME are mandatory"
    exit 1
fi

TMP_DIR=$(mktemp -d)
GENERATED_SSH_KEY_PATH="${TMP_DIR}/id_rsa"

create_linux_ssh_keypair() {
    echo "Generating a random ssh public/private keypair"
    ssh-keygen -b 2048 -t rsa -f $GENERATED_SSH_KEY_PATH -q -N "" || {
        echo "ERROR: Failed to generate ssh keypair"
        return 1
    }
    # Convert ssh key to base64 first and remove newlines
    base64  "$GENERATED_SSH_KEY_PATH" | tr -d '\n' >  "${GENERATED_SSH_KEY_PATH}.b64" || {
        echo "ERROR: Failed to create SSH key base64 file: ${GENERATED_SSH_KEY_PATH}.b64"
        return 1
    }
    # Upload private/public keys as secrets to Azure key vault
    az keyvault secret set --vault-name "$AZURE_KEYVAULT_NAME" --name "$PRIVATE_KEY_SECRET_NAME" --file "${GENERATED_SSH_KEY_PATH}.b64" &>/dev/null || {
        echo "ERROR: Failed to upload private key to Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
    az keyvault secret set --vault-name "$AZURE_KEYVAULT_NAME" --name "$PUBLIC_KEY_SECRET_NAME" --file "${GENERATED_SSH_KEY_PATH}.pub" &>/dev/null || {
        echo "ERROR: Failed to upload private key to Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
}

generate_windows_password() {
    echo "Generating random Windows password"
    WIN_AGENT_ADMIN_PASSWORD="P@s0$(date +%s | sha256sum | base64 | head -c 32)"
    # Upload Windows password to Azure key vault
    az keyvault secret set --vault-name "$AZURE_KEYVAULT_NAME" --name "$WIN_PASS_SECRET_NAME" --value "$WIN_AGENT_ADMIN_PASSWORD" &>/dev/null || {
        echo "ERROR: Failed to upload Windows password to Azure key vault $AZURE_KEYVAULT_NAME"
        return 1
    }
}


create_linux_ssh_keypair || {
    echo "ERROR: Cannot create & upload the Linux SSH keypair to Azure key vault"
    rm -rf $TMP_DIR
    exit 1
}

generate_windows_password || {
    echo "ERROR: Cannot generate & upload the Windows password to Azure key vault"
    rm -rf $TMP_DIR
    exit 1
}

# Cleanup
rm -rf $TMP_DIR
echo "Done generating & uploading new ssh keypair and Windows password to Azure key vault"
