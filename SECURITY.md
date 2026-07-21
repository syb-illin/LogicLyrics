# Security Policy

## Supported versions

Security fixes are applied to the latest published release. Please reproduce against the newest version before reporting when it is safe to do so.

## Reporting a vulnerability

Do not open a public issue for a vulnerability or attach private Logic projects, lyrics, audio, credentials, full paths or personal information.

Use GitHub's private vulnerability reporting feature when it is available for this repository. Otherwise contact the maintainer privately through the account information on the [syb-illin GitHub profile](https://github.com/syb-illin).

Include:

- affected Logic Lyrics version and build;
- macOS and Logic Pro versions;
- minimal reproduction steps using synthetic content;
- expected and observed impact;
- whether original project or audio data can be modified, exposed or lost.

You should receive an acknowledgement within seven days. Please allow time for investigation and a coordinated release before public disclosure.

## Security boundaries

Logic Lyrics is local-first and does not send application telemetry. Project and audio writers target copies and validate results before presenting them. Update assets are verified against published SHA-256 checksums. The public app remains ad-hoc signed until Apple Developer ID signing and notarization are configured; this limitation is not concealed from users.
