#!/bin/bash
set -e

SOURCE_CONFIG="k3s_kubeconfig.yaml"
DEST_CONFIG="$HOME/.kube/config"

if [ ! -f "$SOURCE_CONFIG" ]; then
    echo "Error: Source config $SOURCE_CONFIG not found in current directory."
    exit 1
fi

# Ensure .kube directory exists
mkdir -p "$HOME/.kube"

if [ ! -f "$DEST_CONFIG" ]; then
    echo "No existing kubeconfig found at $DEST_CONFIG."
    echo "Copying $SOURCE_CONFIG to $DEST_CONFIG..."
    cp "$SOURCE_CONFIG" "$DEST_CONFIG"
else
    echo "Existing kubeconfig found. Backing up to $DEST_CONFIG.bak"
    cp "$DEST_CONFIG" "$DEST_CONFIG.bak"

    echo "Merging $SOURCE_CONFIG into $DEST_CONFIG..."
    # Flatten combines the contexts from both files
    KUBECONFIG="$DEST_CONFIG:$SOURCE_CONFIG" kubectl config view --flatten > /tmp/kubeconfig_merged
    mv /tmp/kubeconfig_merged "$DEST_CONFIG"
fi

# Set proper permissions
chmod 600 "$DEST_CONFIG"
echo "Successfully updated $DEST_CONFIG"
