## Image signing and attestation

This workflow signs the multi-arch manifest and attaches per-architecture SBOM attestations using [cosign](https://docs.sigstore.dev/cosign/overview/) and the public [Sigstore](https://www.sigstore.dev/) infrastructure. Signing uses keyless mode: GitHub Actions provides an OIDC token, Fulcio issues a short-lived certificate, and the operation is recorded in the Rekor v2 transparency log.

### What gets signed

The build jobs push per-architecture images and generate an SPDX JSON SBOM for each. The manifest job assembles the multi-arch manifest list, then runs three cosign operations against the **manifest digest**:

1. **Sign** the manifest, proving it was produced by this workflow
2. **Attest** the amd64 SBOM against the manifest
3. **Attest** the arm64 SBOM against the manifest

All three target the same manifest digest. Consumers verify once and get both architecture SBOMs from a single image reference.

### Signing configuration

The workflow uses a static signing config (`signing-config.json` at the repo root) that directs cosign to the Rekor v2 transparency log. Rekor v2 logs hashed entries instead of full payloads, which removes the size limit that previously prevented large SBOM attestations from being recorded.

The signing config pins the Sigstore service URLs including the Rekor v2 instance. The instance name includes a year (`log2025-1.rekor.sigstore.dev`) and will need to be updated when Sigstore rotates to a new instance. The cosign version is pinned to `v3.1.1` in the workflow because that is the minimum version with Rekor v2 DSSE support.

### Registry artifacts

Each cosign operation stores its result as an [OCI referrer](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#listing-referrers) linked to the manifest digest. Each operation creates two objects in the registry (the artifact payload and its referrer descriptor), so the three cosign operations produce **6 digest-only entries** alongside the tagged images. These are normal supply chain artifacts and should not be deleted.

The destination registry must support OCI 1.1 referrers. GHCR, Quay.io, and Docker Hub all support this. Self-hosted registries (Harbor, Artifactory) may require a minimum version — check your registry's OCI 1.1 support.

You can inspect the artifact tree:

```bash
cosign tree $IMAGE_REF
```

### Verifying

The signing certificate is issued by Fulcio using the GitHub Actions OIDC token. The certificate identity contains the GitHub repository path and the OIDC issuer is always `https://token.actions.githubusercontent.com`. These values are the same regardless of which registry the image was pushed to.

Set `IMAGE_REF` to your full image reference (e.g. `quay.io/user/repo:latest` or `ghcr.io/owner/repo:latest`):

```bash
IMAGE_REF="<registry>/<image>:<tag>"
```

Verify the manifest signature:

```bash
cosign verify \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity-regexp "github.com/<owner>/<repo>" \
  $IMAGE_REF
```

Verify the SBOM attestations:

```bash
cosign verify-attestation --type spdxjson \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity-regexp "github.com/<owner>/<repo>" \
  $IMAGE_REF
```

The `--certificate-identity-regexp` matches the repository path in the signing certificate, so it works regardless of which branch, event, or destination registry triggered the build.
