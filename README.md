[![Build and push image](https://github.com/chenwei791129/k8s-cd-image/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/chenwei791129/k8s-cd-image/actions/workflows/build-and-push.yml)

# k8s-cd-image

Alpine-based Docker image with Kubernetes CD tools for CI/CD pipelines.

## Included Tools

| Tool | Description |
|------|-------------|
| **kubectl** | Kubernetes CLI (the image tag is the kubectl version) |
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
requests. kubectl is downloaded in the version of the image tag; bash, curl,
git, ssh, jq and envsubst are Alpine packages from the pinned release. Each
downloaded binary is verified against the checksum file published with its
release, and the build fails if any tool cannot run. The pinned versions are
recorded as image labels:

```bash
docker pull ghcr.io/chenwei791129/k8s-cd-image:latest
docker image inspect ghcr.io/chenwei791129/k8s-cd-image:latest \
  --format '{{json .Config.Labels}}'
```

## Tags

| Tag | Points to |
|-----|-----------|
| `X.Y.Z` | kubectl `vX.Y.Z` |
| `X.Y` | the latest kubectl patch of minor `X.Y` |
| `latest` | the highest kubectl version published |

The latest patch of the three newest Kubernetes minor versions is tagged and
published automatically every day. Whenever a bundled tool or the Alpine base
is updated, those tags are rebuilt and pushed again, so a tag can move to a new
image. Pin the image by digest (`ghcr.io/chenwei791129/k8s-cd-image@sha256:...`)
if you need it to stay unchanged. In the rare case that another build (for a
newly released kubectl version, or a manual build) runs at the same time as
such a rebuild, whichever finishes last decides where the tags they share
point until the next build.

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

`KUBECTL_VERSION` is required; the other tool versions default to the ones
pinned in the Dockerfile.

```bash
docker buildx build \
  --build-arg KUBECTL_VERSION=v1.37.1 \
  --platform linux/amd64,linux/arm64 \
  -t k8s-cd-image:latest .
```

## Supported Platforms

- `linux/amd64`
- `linux/arm64`
