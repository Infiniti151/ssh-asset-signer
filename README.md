# SSH Asset Signer GitHub Action (`ssh-asset-signer`)

[![Marketplace](https://img.shields.io/github/v/release/Infiniti151/ssh-asset-signer?label=Marketplace&style=for-the-badge&logo=github&color=blue)](https://github.com/marketplace/actions/ssh-asset-signer)
[![Build](https://img.shields.io/github/actions/workflow/status/Infiniti151/ssh-asset-signer/release.yml?branch=main&style=for-the-badge&logo=github-actions&logoColor=white&label=Build&color=%23007808)](https://github.com/Infiniti151/ssh-asset-signer/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/Infiniti151/ssh-asset-signer?style=for-the-badge&logo=spdx&logoColor=white&color=yellow&label=License)](https://github.com/Infiniti151/ssh-asset-signer/blob/main/LICENSE)

A lightweight, secure, and zero-dependency GitHub Action designed to cryptographically sign release assets, binaries, tarballs, and build artifacts using OpenSSH signatures (`ssh-keygen -Y sign`).

---

## 💡 Why This Repository Exists

While GitHub Actions has plenty of actions for Git commit/tag signing (`git commit -S`) and SSH network authentication, **there was no dedicated action for signing arbitrary release assets using native OpenSSH keys**.

Historically, release engineers wanting to produce detached `.sig` files for release artifacts had to write custom, fragile inline Bash scripts in their workflows. Managing `ssh-agent` setup, handling passphrases non-interactively without hanging CI runners, masking trace execution logs, and outputting formatted `allowed_signers` files requires non-obvious shell hacks.

`ssh-asset-signer` abstracts all of this into a clean, single-step action.

---

## 📌 Important Distinction: Do You Need This Action?

> [!NOTE]
> **If your goal is simply to authenticate with remote servers or pull/push private Git repositories via SSH:**
> **Do not use this action.** Use [`webfactory/ssh-agent`](https://github.com/webfactory/ssh-agent) instead.
>
> * **`webfactory/ssh-agent`** is specifically designed for Git deployment and network authentication (and intentionally rejects passphrases).
> * **`ssh-asset-signer`** *(this action)* is specifically designed to perform cryptographic file/asset signing (`ssh-keygen -Y sign`) and supports both passphrase-less and passphrase-encrypted private keys.

---

## ✨ Features

* **Native OpenSSH Signing:** Uses standard OpenSSH signature functionality (`ssh-keygen -Y sign`).
* **Passphrase Support:** Supports encrypted private SSH keys using non-interactive `SSH_ASKPASS` hooks without hanging runners.
* **Trace-Protected Security:** Guarantees private keys and passphrases never leak in console logs, even when `ACTIONS_STEP_DEBUG` or `set -x` shell tracing is active.
* **`allowed_signers` File Generation:** Optionally creates a ready-to-publish OpenSSH `allowed_signers` file for easy end-user verification.
* **Glob & Multi-File Support:** Sign single files, spaces-separated files, or directories.
* **Automatic Cleanup:** Safely purges temporary private key files and terminates spawned `ssh-agent` processes upon job completion (even if build steps crash).

---

## 🚀 Usage Example

### Basic Release Asset Signing

```yaml
name: Release Pipeline

on:
  release:
    types: [published]

jobs:
  sign-assets:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v7

      - name: Build Assets
        run: |
          tar -czvf app-v1.0.0-linux.tar.gz ./bin

      - name: Sign Release Assets
        id: sign
        uses: Infiniti151/ssh-asset-signer@v1
        with:
          private-key: ${{ secrets.SSH_PRIVATE_KEY }}
          passphrase: ${{ secrets.SSH_PASSPHRASE }} # Optional
          files: "app-v1.0.0-linux.tar.gz"
          principal: "release-signer@yourcompany.com"
          generate-allowed-signers: true

      - name: Upload Signatures to GitHub Release
        uses: softprops/action-gh-release@v3
        with:
          files: |
            app-v1.0.0-linux.tar.gz
            app-v1.0.0-linux.tar.gz.sig
            allowed_signers
```

## ⚙️ Action Inputs

| Input | Required | Default | Description |
|:---:|:---:|:---:|-------------|
| `private-key` | Yes | — | Raw SSH private key string or path to a private key file. |
| `files` | Yes | — | Space-separated file paths or glob patterns to sign. |
| `passphrase` | No | "" | Passphrase for the private key (if encrypted). |
| `namespace` | No |`file` | OpenSSH signature namespace (defaults to standard `file` namespace). |
| `principal` | Conditional | "" | Principal ID (e.g., email or identity) added to the allowed_signers file. Required if `generate-allowed-signers` is true. |
| `generate-allowed-signers` | No | false | Set to "true" to enable automatic generation of the `allowed_signers` verification file. |
| `sig-dir` | No | "" | Directory to output generated `.sig` signature files. Defaults to placing `.sig` files alongside source files. |
| `allowed-signers-dir` | No | . | Output directory for the `allowed_signers` file (defaults to working directory). |

## 📤 Action Outputs

| Output | Description |
|:---:|-------------|
| `signed-files` | Space‑separated list of successfully signed target file paths. |
| `sig-files` | Space‑separated list of generated signature file (`.sig`) paths. |
| `allowed-signers-path` | Path to the generated `allowed_signers` file (empty if generation was not enabled). |
| `public-key` | Extracted public key (e.g., `ssh-ed25519 AAAAC3...`). |


## 🔍 How to Verify Signatures Locally

End users can verify the integrity of downloaded release assets using standard OpenSSH tools.

### Option A: Using the Generated `allowed_signers` File

If you generated and published an `allowed_signers` file alongside your release assets:

```bash
ssh-keygen -Y verify \
  -f allowed_signers \
  -I "your-principal-id" \
  -n file \
  -s app-v1.0.0-linux.tar.gz.sig \
  < app-v1.0.0-linux.tar.gz
```

### Option B: Verifying with the Public Key

If an allowed_signers file was not generated, you can create one manually using the public key:
```bash
# 1. Create a local allowed_signers file with <principal> <public_key>
echo 'your-principal-id ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...' > my_allowed_signers

# 2. Verify the asset
ssh-keygen -Y verify \
  -f my_allowed_signers \
  -I "your-principal-id" \
  -n file \
  -s app-v1.0.0-linux.tar.gz.sig \
  < app-v1.0.0-linux.tar.gz
```

### Expected Output on Success:
`Good "file" signature for your-principal-id with ED25519 key SHA256:...`

## 🛡️ License

Distributed under the MIT License. See LICENSE for more information.