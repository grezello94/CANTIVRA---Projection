# Getting a macOS Developer ID certificate

You can continue developing and testing the local Cantivra build without buying a Developer ID certificate. Developer ID is Apple's mechanism for identifying the publisher when distributing a Mac app outside the App Store. It does not add a cloud dependency or subscription to essential Cantivra presentation features.

Apple issues the certificate to the developer account; an assistant cannot supply an Apple-trusted certificate for someone else's identity. An Apple Development certificate, already available on this Mac, is a different certificate type. See Apple's [certificate overview](https://developer.apple.com/help/account/certificates/certificates-overview/).

## When you are ready to distribute

1. Enroll your own account or the church's legal organization in the [Apple Developer Program](https://developer.apple.com/help/account/membership/program-enrollment/). Apple's published fee is normally US$99 per year, with regional pricing. A qualifying nonprofit organization may request a [fee waiver](https://developer.apple.com/help/account/membership/fee-waivers/); a church is not automatically eligible simply because this is a church app. Review eligibility before paying.
2. As the account's Account Holder, open Apple's developer-account certificate area and create a **Developer ID Application** certificate. **Developer ID Installer** is for signing installer packages. Follow [Apple's Developer ID instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
3. Create the requested certificate-signing request using Keychain Access on the Mac that will sign the app. Follow [Apple's CSR instructions](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/), upload the request to Apple, and install the returned certificate on that Mac. Keep its associated private key in your keychain; no passwords or private keys need to be pasted into this chat or committed to the project.
4. Once the signing identity is installed, use the release-signing and notarization procedure in [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md). Rebuild the normal app, sign it, submit it for notarization, staple the result, and verify the downloaded app on a clean Mac. Those are release checks, distinct from local development signing.

The Windows test machine can be used when it is available again; macOS certificates do not replace Windows testing or Windows publisher signing. Until the actual platform/display checks run, their acceptance rows remain pending and Phase 4 stays paused.
