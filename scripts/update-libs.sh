#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SFUI Library Synchronizer
# Syncs upstream vendor libraries into Libs/ based on canonical repositories.
# ─────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS_DIR="${REPO_ROOT}/Libs"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "${TMP_DIR}"' EXIT

echo "=== Updating SFUI Libraries in ${LIBS_DIR} ==="

mkdir -p "${LIBS_DIR}"

# 1. LibStub
echo "-> [1/6] Fetching LibStub..."
git clone --depth 1 https://github.com/lua-wow/LibStub.git "${TMP_DIR}/LibStub" >/dev/null 2>&1
mkdir -p "${LIBS_DIR}/LibStub"
cp "${TMP_DIR}/LibStub/LibStub.lua" "${LIBS_DIR}/LibStub/"
[ -f "${TMP_DIR}/LibStub/LibStub.toc" ] && cp "${TMP_DIR}/LibStub/LibStub.toc" "${LIBS_DIR}/LibStub/"
echo "   LibStub updated."

# 2. CallbackHandler-1.0
echo "-> [2/6] Fetching CallbackHandler-1.0 (CurseForge SVN)..."
rm -rf "${LIBS_DIR}/CallbackHandler-1.0"
mkdir -p "${LIBS_DIR}/CallbackHandler-1.0"
svn export --force https://repos.curseforge.com/wow/callbackhandler/trunk/CallbackHandler-1.0 "${LIBS_DIR}/CallbackHandler-1.0" >/dev/null
echo "   CallbackHandler-1.0 updated."

# 3. LibSharedMedia-3.0
echo "-> [3/6] Fetching LibSharedMedia-3.0 (CurseForge SVN)..."
rm -rf "${LIBS_DIR}/LibSharedMedia-3.0"
mkdir -p "${LIBS_DIR}/LibSharedMedia-3.0"
svn export --force https://repos.curseforge.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 "${LIBS_DIR}/LibSharedMedia-3.0" >/dev/null
echo "   LibSharedMedia-3.0 updated."

# 4. LibCustomGlow-1.0
echo "-> [4/6] Fetching LibCustomGlow-1.0..."
git clone --depth 1 https://github.com/Stanzilla/LibCustomGlow.git "${TMP_DIR}/LibCustomGlow" >/dev/null 2>&1
mkdir -p "${LIBS_DIR}/LibCustomGlow-1.0"
cp "${TMP_DIR}/LibCustomGlow/LibCustomGlow-1.0.lua" "${LIBS_DIR}/LibCustomGlow-1.0/"
cp "${TMP_DIR}/LibCustomGlow/LibCustomGlow-1.0.xml" "${LIBS_DIR}/LibCustomGlow-1.0/"
[ -f "${TMP_DIR}/LibCustomGlow/LICENSE" ] && cp "${TMP_DIR}/LibCustomGlow/LICENSE" "${LIBS_DIR}/LibCustomGlow-1.0/"
echo "   LibCustomGlow-1.0 updated."

# 5. LibDataBroker-1.1
echo "-> [5/6] Fetching LibDataBroker-1.1..."
git clone --depth 1 https://github.com/tekkub/libdatabroker-1-1.git "${TMP_DIR}/LibDataBroker" >/dev/null 2>&1
mkdir -p "${LIBS_DIR}/LibDataBroker-1.1"
cp "${TMP_DIR}/LibDataBroker/LibDataBroker-1.1.lua" "${LIBS_DIR}/LibDataBroker-1.1/"
echo "   LibDataBroker-1.1 updated."

# 6. LibDBIcon-1.0
echo "-> [6/6] Fetching LibDBIcon-1.0 (CurseForge SVN)..."
rm -rf "${LIBS_DIR}/LibDBIcon-1.0"
mkdir -p "${LIBS_DIR}/LibDBIcon-1.0"
svn export --force https://repos.curseforge.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 "${LIBS_DIR}/LibDBIcon-1.0" >/dev/null
echo "   LibDBIcon-1.0 updated."

echo "=== All libraries successfully updated! ==="
