# SOPS Configuration for Polyflow Robots

This document explains how to set up and use SOPS (Secrets OPerationS) for managing encrypted configuration values in polyflow-base and robot repositories.

## Overview

The system now uses SOPS to encrypt sensitive configuration values instead of template string replacement. Configuration values are stored in an encrypted `metadata.json` file and decrypted:
1. **Build time**: For Nix builds and launch file generation
2. **Runtime**: For system services and applications

## Configuration Values

The following values are stored in `metadata.json`:

- `ROBOT_ID`: Unique identifier for the robot (also used as hostname)
- `SIGNALING_URL`: WebRTC signaling server URL
- `PASSWORD`: System default password and AP Wi-Fi password
- `GITHUB_USER`: GitHub username for robot repository access
- `TURN_SERVER_URL`: TURN server URL for WebRTC
- `TURN_SERVER_USERNAME`: TURN server authentication username
- `TURN_SERVER_PASSWORD`: TURN server authentication password

## Initial Setup

### 1. Generate Age Encryption Keys

First, generate an age key pair for encryption/decryption:

```bash
# Using Nix (recommended)
nix shell nixpkgs#age --command age-keygen -o .sops/key.txt

# Or if you have age installed directly
age-keygen -o .sops/key.txt
```

This creates a key file at `.sops/key.txt` containing:
- A public key (in the comment line starting with `#`)
- A private key (line starting with `AGE-SECRET-KEY-`)

### 2. Update .sops.yaml

Edit `.sops.yaml` and replace the placeholder public key with your actual public key:

```yaml
creation_rules:
  - path_regex: systems/raspi-4/metadata\.json$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # Replace this
```

Copy the public key from the first line of `.sops/key.txt` (after `# public key: `).

### 3. Create metadata.json

Create your unencrypted configuration file based on the example:

```bash
cd systems/raspi-4
cp metadata.json.example metadata.json
# Edit metadata.json with your actual values
```

Edit `metadata.json`:

```json
{
  "ROBOT_ID": "your-robot-001",
  "SIGNALING_URL": "wss://signaling.yourcompany.com",
  "PASSWORD": "your-secure-password",
  "GITHUB_USER": "your-github-username",
  "TURN_SERVER_URL": "turn:turn.yourcompany.com:3478",
  "TURN_SERVER_USERNAME": "your-turn-username",
  "TURN_SERVER_PASSWORD": "your-turn-password"
}
```

### 4. Encrypt the File

Encrypt `metadata.json` using SOPS:

```bash
# Set the age key file location
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"

# Encrypt the file in place
sops -e -i systems/raspi-4/metadata.json
```

After encryption, `metadata.json` will contain encrypted data with SOPS metadata.

## Building with SOPS

### Building Locally

To build the system with encrypted configuration:

```bash
# Set the age key file location
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"

# Build the system
nix build .#nixosConfigurations.rpi4.config.system.build.sdImage
```

The build process will:
1. Detect the `metadata.json` file
2. Decrypt it using the key from `SOPS_AGE_KEY_FILE`
3. Use the decrypted values in launch files and configuration

### Environment Variable Override

You can still override values using environment variables:

```bash
export ROBOT_ID="override-robot-123"
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"
nix build .#nixosConfigurations.rpi4.config.system.build.sdImage
```

Priority order:
1. SOPS metadata.json (if file exists and key is available)
2. Environment variables
3. Template placeholders (fallback)

## Robot Deployment

### 1. Copy the Age Key to the Robot

After deploying the NixOS image to your robot, copy the age key:

```bash
# On your development machine
scp .sops/key.txt admin@robot-hostname:/tmp/key.txt

# On the robot
sudo mkdir -p /var/lib/sops-nix
sudo mv /tmp/key.txt /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

### 2. Runtime Secret Access

At runtime, secrets are decrypted to `/run/secrets/` by sops-nix:

- `/run/secrets/robot-id`
- `/run/secrets/signaling-url`
- `/run/secrets/password`
- `/run/secrets/github-user`
- `/run/secrets/turn-server-url`
- `/run/secrets/turn-server-username`
- `/run/secrets/turn-server-password`

Services can read these files to access secrets securely.

## Managing Secrets

### Viewing/Editing Encrypted Files

To view or edit the encrypted `metadata.json`:

```bash
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"
sops systems/raspi-4/metadata.json
```

This opens the file in your default editor with decrypted contents. When you save and exit, SOPS automatically re-encrypts the file.

### Rotating Keys

To rotate encryption keys:

1. Generate a new age key pair
2. Update `.sops.yaml` with the new public key
3. Re-encrypt the metadata file:

```bash
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key-new.txt"
sops updatekeys systems/raspi-4/metadata.json
```

## Security Best Practices

### Development

- **NEVER** commit `.sops/key.txt` to version control (already in `.gitignore`)
- Keep your private key secure and backed up
- Use different keys for different environments (dev, staging, production)
- Commit the encrypted `metadata.json` to version control

### Production/Robot Deployment

- Each robot should have its own unique age key pair
- Store private keys securely on the robot filesystem with restricted permissions (600)
- Regularly rotate keys and update encrypted secrets
- Use hardware security modules (HSM) or TPM for key storage when available

## Troubleshooting

### Build Fails with "SOPS_AGE_KEY_FILE not set"

Make sure to export the environment variable before building:

```bash
export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"
```

### "Failed to decrypt" Errors

- Verify the key file path is correct
- Ensure the public key in `.sops.yaml` matches the private key
- Check file permissions on the key file (should be readable)

### Fallback to Template Placeholders

If you see values like `{{ROBOT_ID}}` in your build output:
- The `metadata.json` file may not exist
- The `SOPS_AGE_KEY_FILE` environment variable may not be set
- The key file may not be accessible

Check the build logs for warnings about missing metadata or keys.

## Migration from Template String Replacement

The system maintains backward compatibility:

1. **Old method (still works)**: Set environment variables before building
   ```bash
   export ROBOT_ID="robot-001"
   export SIGNALING_URL="wss://signaling.example.com"
   # ... etc
   nix build ...
   ```

2. **New method (recommended)**: Use SOPS encrypted metadata.json
   ```bash
   export SOPS_AGE_KEY_FILE="$(pwd)/.sops/key.txt"
   nix build ...
   ```

You can migrate gradually by moving values from environment variables to the encrypted metadata file.
