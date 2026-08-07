# Changelog

## [1.0.1] - 2026-08-07

### ⚙️ Continuous Integration
- (**release**) Add commit step to push updated CHANGELOG.md

### 📚 Documentation
- (**readme**) Update usage example to use @v1 instead of @main for ssh-asset-signer
## [1.0.0] - 2026-08-07
### 🚀 v1.0.0 — Initial Release
This is the initial release of SSH Asset Signer (Infiniti151/ssh-asset-signer@v1)!

Highlights:
- Sign release binaries and archives using native OpenSSH signatures (ssh-keygen -Y sign).
- Support for passphrase-protected keys via ssh-agent.
- Automatic generation of allowed_signers files.
- Configurable signature output directories and namespaces.

📖 Full Documentation & Usage Examples: See the [README](https://github.com/Infiniti151/ssh-asset-signer#readme).