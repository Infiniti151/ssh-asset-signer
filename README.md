# SSH Asset Signer GitHub Action (`ssh-asset-signer`)

[![Build](https://img.shields.io/github/actions/workflow/status/Infiniti151/ssh-asset-signer/release.yml?branch=main&style=for-the-badge&logo=github-actions&logoColor=white&label=Build&color=%23007808)](https://github.com/Infiniti151/ssh-asset-signer/actions/workflows/release.yml) [![License](https://img.shields.io/github/license/Infiniti151/ssh-asset-signer?style=for-the-badge&logo=spdx&logoColor=white&color=yellow&label=License)](https://github.com/Infiniti151/ssh-asset-signer/blob/main/LICENSE)

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
        uses: actions/checkout@v4

      - name: Build Assets
        run: |
          tar -czvf app-v1.0.0-linux.tar.gz ./bin

      - name: Sign Release Assets
        id: sign
        uses: your-org/ssh-asset-signer@v1
        with:
          private_key: ${{ secrets.SSH_SIGNING_KEY }}
          passphrase: ${{ secrets.SSH_SIGNING_PASSPHRASE }} # Optional
          files: "app-v1.0.0-linux.tar.gz"
          principal: "release-signer@yourcompany.com"
          generate_allowed_signers: true

      - name: Upload Signatures to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            app-v1.0.0-linux.tar.gz.sig
            allowed_signers
```

## ⚙️ Action Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| **private_key** | Yes | None | Raw PEM or OpenSSH private key string. |
| **files** | Yes | None | Space‑separated paths of target files/assets to sign. |
| **passphrase** | No | "" | Passphrase for the private key (if encrypted). |
| **namespace** | No | "file" | OpenSSH signature namespace (defaults to OpenSSH file‑signing standard *file*). |
| **principal** | Conditional | "" | Principal ID (e.g., email or identity) added to the allowed_signers file. Required if `generate_allowed_signers` is true. |
| **generate_allowed_signers** | No | false | Set to "true" to enable automatic generation of the allowed_signers verification file. |
| **sig_dir** | No | "" | Directory to output generated `.sig` signature files. Defaults to placing `.sig` files alongside source files. |
| **allowed_signers_dir** | No | "" | Output directory for the allowed_signers file (defaults to working directory). |

## 📤 Action Outputs

| Output | Description |
|--------|-------------|
| **signed_files** | Space‑separated list of successfully signed target file paths. |
| **sig_files** | Space‑separated list of generated signature file (`.sig`) paths. |
| **allowed_signers_path** | Absolute path to the generated allowed_signers file (if enabled). |
| **public_key** | Extracted public key (e.g., `ssh-ed25519 AAAAC3... release-signer@yourcompany.com`). |


## 🔍 How to Verify Signatures Locally

End users who download your signed release assets and allowed_signers file can easily verify integrity using OpenSSH:

```bash
# 1. Verify the asset using the published allowed_signers file
ssh-keygen -Y verify \
  -f allowed_signers \
  -I "release-signer@yourcompany.com" \
  -n file \
  -s app-v1.0.0-linux.tar.gz.sig \
  < app-v1.0.0-linux.tar.gz

# Successful Output:
# Good "file" signature for release-signer@yourcompany.com with ED25519 key ...
```

## 🛡️ License

Distributed under the MIT License. See LICENSE for more information.