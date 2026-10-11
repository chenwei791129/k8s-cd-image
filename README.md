[![Release image versions](https://github.com/chenwei791129/k8s-cd-image/actions/workflows/release.yml/badge.svg)](https://github.com/chenwei791129/k8s-cd-image/actions/workflows/release.yml)

# k8s-cd-image

Alpine-based Docker image with Kubernetes CD tools for CI/CD pipelines.

## Included Tools

| Tool | Description |
|------|-------------|
| **kubectl** | Kubernetes CLI (the first three parts of the image version) |
| **kustomize** | Kubernetes configuration customization |
| **helm** | Kubernetes package manager |
| **helm-diff** | Helm plugin for diffing releases |
| **yq** | YAML/JSON/XML processor (mikefarah) |
| **envsubst** | Environment variable substitution (only `envsubst`; the rest of GNU gettext is not included) |
| **jq** | JSON processor |
| **curl** | HTTP client for health checks and webhooks |
| **git**, **ssh** | Git client with SSH support, e.g. for GitOps write-back and kustomize remote bases |
| **bash** | Bash shell for scripts that need more than POSIX `sh` |

kustomize, helm, helm-diff and yq are pinned in the [Dockerfile](Dockerfile),
together with the Alpine base image, and updated through Renovate pull
requests. kubectl is downloaded in the kubectl version the image is built for;
bash, curl, git, ssh, jq and envsubst are Alpine packages from the pinned
release. Each downloaded binary is verified against the checksum file published
with its release, and the build fails if any tool cannot run. The pinned versions are
recorded as image labels, and the `org.opencontainers.image.version` label is
the image version (`X.Y.Z.R`):

```bash
docker pull ghcr.io/chenwei791129/k8s-cd-image:latest
docker image inspect ghcr.io/chenwei791129/k8s-cd-image:latest \
  --format '{{json .Config.Labels}}'
```

## Tags

Every published image has an image version `X.Y.Z.R`: the kubectl version
`X.Y.Z` plus an image revision `R` that starts at `0` and grows by one each
time an image with different content is published for the same kubectl
version. An image version is pushed once and never moved. The other tags float
to the newest image version they cover:

| Tag | Points to | Moves |
|-----|-----------|-------|
| `X.Y.Z.R` | one image of kubectl `vX.Y.Z` | never |
| `X.Y.Z` | the newest image revision of kubectl `vX.Y.Z` | yes |
| `X.Y` | the newest image of the latest published patch of minor `X.Y` | yes |
| `latest` | the newest image of the highest kubectl version published | yes |

Pin `X.Y.Z.R` (or a digest, `ghcr.io/chenwei791129/k8s-cd-image@sha256:...`)
if you need the image to stay unchanged; Renovate can update a pinned `X.Y.Z.R`
to the next image revision.

Only the supported kubectl versions, the latest patch of each of the three
newest Kubernetes minors, receive new image versions. A new image version is
released when:

- a new supported kubectl version appears (checked daily): `X.Y.Z.0`;
- the [Dockerfile](Dockerfile) changes on `main`, e.g. a Renovate update of a
  bundled tool or the Alpine base: the next image revision of every supported
  kubectl version;
- a maintainer runs the release workflow with `force`.

Older kubectl patches keep their last image version; images published before
image versions were introduced, and not converted to one, keep their
three-part `X.Y.Z` tag. In the rare case that two image versions that share a
floating tag are built at the same time (e.g. a new image revision and a new
kubectl patch of the same minor), that floating tag can stay on the one that
finishes last until another image version moves it. Each image version
has an annotated git tag `vX.Y.Z.R` on the commit it was built from; its
message lists the bundled tool versions and the changes since the previous
image revision.

## Usage

```bash
# Pull from GHCR
docker pull ghcr.io/chenwei791129/k8s-cd-image:latest

# Run kubectl
docker run --rm ghcr.io/chenwei791129/k8s-cd-image:latest kubectl version --client

# Run helm and helm-diff
docker run --rm ghcr.io/chenwei791129/k8s-cd-image:latest helm version
docker run --rm ghcr.io/chenwei791129/k8s-cd-image:latest helm diff version

# Run kustomize
docker run --rm ghcr.io/chenwei791129/k8s-cd-image:latest kustomize version
```

The image has no entrypoint, so it can be used directly as a CI job image.

### Running as a non-root user

helm-diff is installed under `HELM_PLUGINS=/usr/local/share/helm/plugins`
instead of the root user's home, so `helm diff` works for any user. Helm 4
still needs a writable `HOME` (or `HELM_CACHE_HOME`) to load plugins, so set
one when running with a user that has no writable home directory, e.g.
`docker run --user 1000 -e HOME=/tmp ...`.

Because `HELM_PLUGINS` is set, Helm no longer looks in the per-user plugin
directory (`~/.local/share/helm/plugins`) that earlier images used. The
plugin directory is owned by root; to install additional plugins as a
non-root user, point `HELM_PLUGINS` at a writable directory and copy
helm-diff along:

```bash
export HELM_PLUGINS="$HOME/.local/share/helm/plugins"
mkdir -p "$HELM_PLUGINS"
cp -R /usr/local/share/helm/plugins/diff "$HELM_PLUGINS/"
# then `helm plugin install ...` as usual
```

## Verify the image signature

Published images are signed keylessly with [cosign](https://github.com/sigstore/cosign)
by the shared build workflow:

```bash
cosign verify ghcr.io/chenwei791129/k8s-cd-image:latest \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/chenwei791129/.github/.github/workflows/build-and-push-image.yml@refs/heads/main \
  --certificate-github-workflow-repository chenwei791129/k8s-cd-image
```

## Build

`KUBECTL_VERSION` is required and is the kubectl version without the image
revision (e.g. `v1.37.1` for image version `1.37.1.0`); the other tool versions
default to the ones pinned in the Dockerfile.

```bash
docker buildx build \
  --build-arg KUBECTL_VERSION=v1.37.1 \
  --platform linux/amd64,linux/arm64 \
  -t k8s-cd-image:latest .
```

## Supported Platforms

- `linux/amd64`
- `linux/arm64`
