# Security Policy

## Supported versions

Dockside is in public beta. Security fixes land in the latest release only.

## Reporting a vulnerability

Please **don’t open a public issue** for security problems.

Use GitHub’s private reporting instead: go to the **Security** tab of this repository and click **Report a vulnerability**. Include steps to reproduce and the Dockside and macOS versions.

You’ll get an acknowledgement within a few days. Once a fix ships, we’re happy to credit you in the release notes.

## What we care about most

- Anything that exposes a user’s Claude API key (stored in the macOS Keychain).
- Ways for web content (artifacts, claude.ai, YouTube Music tabs) to run code outside its sandbox.
- Unexpected network traffic or data leaving the Mac beyond what the README documents.
