#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../install.sh
source "$PROJECT_ROOT/install.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_rejected() {
    local archive=$1
    local description=$2

    if validate_backup_archive "$archive"; then
        fail "$description"
    fi
}

generated_uuid=$(generate_uuid) || fail "generate_uuid returned an error"
if [[ ! "$generated_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    fail "generate_uuid returned an invalid UUID"
fi

old_x25519_output=$'Private key: old-private\nPublic key: old-public'
new_x25519_output=$'PrivateKey: new-private\nPassword: new-public\nHash32: not-a-public-key'
latest_x25519_output=$'PrivateKey: latest-private\nPassword (PublicKey): latest-public\nHash32: not-a-public-key'

old_private=$(printf '%s\n' "$old_x25519_output" | parse_x25519_private_key)
old_public=$(printf '%s\n' "$old_x25519_output" | parse_x25519_public_key)
new_private=$(printf '%s\n' "$new_x25519_output" | parse_x25519_private_key)
new_public=$(printf '%s\n' "$new_x25519_output" | parse_x25519_public_key)
latest_private=$(printf '%s\n' "$latest_x25519_output" | parse_x25519_private_key)
latest_public=$(printf '%s\n' "$latest_x25519_output" | parse_x25519_public_key)

[[ "$old_private" == "old-private" && "$old_public" == "old-public" ]] ||
    fail "legacy Xray x25519 output was parsed incorrectly"
[[ "$new_private" == "new-private" && "$new_public" == "new-public" ]] ||
    fail "current Xray x25519 output was parsed incorrectly"
[[ "$latest_private" == "latest-private" && "$latest_public" == "latest-public" ]] ||
    fail "Xray 26.3.27 x25519 output was parsed incorrectly"
[[ "$new_public" != "not-a-public-key" ]] ||
    fail "Hash32 was incorrectly accepted as a public key"
[[ "$latest_public" != "not-a-public-key" ]] ||
    fail "Hash32 was incorrectly accepted from Xray 26.3.27 output"

temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT

CONFIG_DIR="$temp_dir/bootstrap"
CONFIG_FILE="$CONFIG_DIR/config.json"
prepare_xray_bootstrap_config || fail "bootstrap Xray config could not be created"
if ! grep -Fq '"inbounds": []' "$CONFIG_FILE" ||
   ! grep -Fq '"protocol": "freedom"' "$CONFIG_FILE"; then
    fail "bootstrap Xray config has unexpected content"
fi

printf '%s\n' '{"existing":true}' > "$CONFIG_FILE"
prepare_xray_bootstrap_config || fail "existing Xray config was rejected"
grep -Fq '"existing":true' "$CONFIG_FILE" ||
    fail "existing Xray config was overwritten by bootstrap preparation"

mkdir -p "$temp_dir/good"
printf '{"ports":[]}\n' > "$temp_dir/good/.xray_port_info.json"
tar -czf "$temp_dir/good.tar.gz" -C "$temp_dir" good
validate_backup_archive "$temp_dir/good.tar.gz" ||
    fail "a regular backup archive was rejected"

printf 'unsafe\n' > "$temp_dir/payload"
tar -czf "$temp_dir/traversal.tar.gz" \
    --transform='s|^payload$|../payload|' -C "$temp_dir" payload 2>/dev/null
assert_rejected "$temp_dir/traversal.tar.gz" \
    "an archive containing path traversal was accepted"

if ln -s /etc/passwd "$temp_dir/unsafe-link" 2>/dev/null; then
    tar -czf "$temp_dir/symlink.tar.gz" -C "$temp_dir" unsafe-link
    assert_rejected "$temp_dir/symlink.tar.gz" \
        "an archive containing a symbolic link was accepted"
fi

if grep -q 'uuidtools\.com' "$PROJECT_ROOT/install.sh"; then
    fail "the script still sends UUID seed data to uuidtools.com"
fi

if grep -q 'main/install-release\.sh' "$PROJECT_ROOT/install.sh"; then
    fail "the script still executes a mutable main-branch helper"
fi

expected_ref=$(awk -F'"' '/^INSTALL_RELEASE_REF=/{print $2; exit}' "$PROJECT_ROOT/install.sh")
expected_hash=$(awk -F'"' '/^INSTALL_RELEASE_SHA256=/{print $2; exit}' "$PROJECT_ROOT/install.sh")
actual_hash=$(tr -d '\r' < "$PROJECT_ROOT/install-release.sh" | sha256sum | awk '{print $1}')

[[ "$actual_hash" == "$expected_hash" ]] ||
    fail "the vendored install-release.sh does not match its pinned SHA-256"
grep -q "$expected_ref" "$PROJECT_ROOT/docs/UPSTREAM.md" ||
    fail "docs/UPSTREAM.md does not contain the pinned upstream revision"
grep -qi "$expected_hash" "$PROJECT_ROOT/docs/UPSTREAM.md" ||
    fail "docs/UPSTREAM.md does not contain the pinned SHA-256"

if grep -Eq 'echo .*([旧新]?私钥|PrivateKey).*\$\{?(old_|new_)?private_key\}?' "$PROJECT_ROOT/install.sh"; then
    fail "the script still prints a Reality private key"
fi

printf 'All security helper tests passed.\n'
