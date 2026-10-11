# syntax=docker/dockerfile:1

# kubectl's version is the image tag, so the build workflow always passes it in.
ARG KUBECTL_VERSION

# The other downloaded tools are pinned so a rebuild never picks up a new
# release implicitly and nothing is resolved through the rate-limited GitHub
# API at build time (Alpine packages follow the pinned Alpine release).
# Renovate bumps these through the `# renovate:` comments
# (customManagers:dockerfileVersions in renovate.json).
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v4.3.0
# renovate: datasource=github-releases depName=databus23/helm-diff
ARG HELM_DIFF_VERSION=v3.15.15
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/(?<version>v.+)$
ARG KUSTOMIZE_VERSION=v5.8.3
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.54.1

# Downloads run natively on the build host (no QEMU) and fetch the TARGETARCH
# binaries. Each one is checked against the checksum file its project publishes
# next to the release, and only the verified files reach the final image.
FROM --platform=$BUILDPLATFORM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS fetcher
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache curl
WORKDIR /work

FROM fetcher AS kubectl
ARG KUBECTL_VERSION
ARG TARGETARCH
RUN test -n "${KUBECTL_VERSION}" || { echo 'KUBECTL_VERSION build argument is required, e.g. v1.37.1' >&2; exit 1; } && \
    base="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}" && \
    curl -fsSLo kubectl "${base}/kubectl" && \
    sha=$(curl -fsSL "${base}/kubectl.sha256") && \
    echo "${sha}  kubectl" | sha256sum -c - && \
    chmod 0755 kubectl

FROM fetcher AS helm
ARG HELM_VERSION
ARG TARGETARCH
RUN tarball="helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    curl -fsSLo "${tarball}" "https://get.helm.sh/${tarball}" && \
    curl -fsSLo checksum "https://get.helm.sh/${tarball}.sha256sum" && \
    sha=$(awk -v f="${tarball}" '$2 == f { print $1 }' checksum) && \
    test -n "${sha}" && \
    echo "${sha}  ${tarball}" | sha256sum -c - && \
    tar -xzf "${tarball}" --strip-components=1 "linux-${TARGETARCH}/helm"

# The release tarball already contains the plugin binary, so it is unpacked as
# is instead of running `helm plugin install`, which clones the repository and
# downloads the binary again from an install hook.
FROM fetcher AS helm-diff
ARG HELM_DIFF_VERSION
ARG TARGETARCH
RUN base="https://github.com/databus23/helm-diff/releases/download/${HELM_DIFF_VERSION}" && \
    tarball="helm-diff-linux-${TARGETARCH}.tgz" && \
    curl -fsSLo "${tarball}" "${base}/${tarball}" && \
    curl -fsSLo checksums.txt "${base}/helm-diff_${HELM_DIFF_VERSION#v}_checksums.txt" && \
    sha=$(awk -v f="${tarball}" '$2 == f { print $1 }' checksums.txt) && \
    test -n "${sha}" && \
    echo "${sha}  ${tarball}" | sha256sum -c - && \
    tar -xzf "${tarball}"

FROM fetcher AS kustomize
ARG KUSTOMIZE_VERSION
ARG TARGETARCH
RUN base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}" && \
    tarball="kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    curl -fsSLo "${tarball}" "${base}/${tarball}" && \
    curl -fsSLo checksums.txt "${base}/checksums.txt" && \
    sha=$(awk -v f="${tarball}" '$2 == f { print $1 }' checksums.txt) && \
    test -n "${sha}" && \
    echo "${sha}  ${tarball}" | sha256sum -c - && \
    tar -xzf "${tarball}" kustomize

# yq's `checksums` file lists many digests per asset; the column order is
# published separately in `checksums_hashes_order`.
FROM fetcher AS yq
ARG YQ_VERSION
ARG TARGETARCH
RUN base="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}" && \
    binary="yq_linux_${TARGETARCH}" && \
    curl -fsSLo "${binary}" "${base}/${binary}" && \
    curl -fsSLo checksums "${base}/checksums" && \
    curl -fsSLo checksums_hashes_order "${base}/checksums_hashes_order" && \
    row=$(awk '$0 == "SHA-256" { print NR }' checksums_hashes_order) && \
    test -n "${row}" && \
    sha=$(awk -v f="${binary}" -v col="$((row + 1))" '$1 == f { print $col }' checksums) && \
    test -n "${sha}" && \
    echo "${sha}  ${binary}" | sha256sum -c - && \
    install -m 0755 "${binary}" yq

FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

# Everyday tools for deploy scripts: bash for scripts that need more than POSIX
# sh, curl for health checks and webhooks, git and openssh-client for GitOps
# write-back and kustomize remote bases, jq for `kubectl -o json`.
# gettext-envsubst ships only envsubst, not the whole gettext toolchain.
RUN apk add --no-cache \
      bash \
      curl \
      gettext-envsubst \
      git \
      jq \
      openssh-client

# Plugins live outside $HOME (/root is mode 0700) so `helm diff` also works
# when the job runs as a non-root user.
ENV HELM_PLUGINS=/usr/local/share/helm/plugins

COPY --from=kubectl /work/kubectl /usr/bin/kubectl
COPY --from=helm /work/helm /usr/bin/helm
COPY --from=helm-diff /work/diff ${HELM_PLUGINS}/diff
COPY --from=kustomize /work/kustomize /usr/bin/kustomize
COPY --from=yq /work/yq /usr/bin/yq

# Fail the build, for every platform, if any tool cannot run; helm-diff is
# checked as a non-root user too. Helm 4 needs a writable cache directory to
# load plugins, so the checks use throwaway HOME directories that are removed
# afterwards instead of leaving a cache behind in the image.
RUN export HOME=/tmp/smoke-root && \
    kubectl version --client && \
    helm version && \
    helm diff version && \
    su -s /bin/sh nobody -c 'HOME=/tmp/smoke-nobody helm diff version' && \
    kustomize version && \
    yq --version && \
    envsubst --version && \
    bash --version && \
    curl --version && \
    git --version && \
    jq --version && \
    ssh -V && \
    rm -rf /tmp/smoke-root /tmp/smoke-nobody

ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG HELM_DIFF_VERSION
ARG KUSTOMIZE_VERSION
ARG YQ_VERSION
LABEL io.github.chenwei791129.k8s-cd-image.kubectl.version="${KUBECTL_VERSION}" \
      io.github.chenwei791129.k8s-cd-image.helm.version="${HELM_VERSION}" \
      io.github.chenwei791129.k8s-cd-image.helm-diff.version="${HELM_DIFF_VERSION}" \
      io.github.chenwei791129.k8s-cd-image.kustomize.version="${KUSTOMIZE_VERSION}" \
      io.github.chenwei791129.k8s-cd-image.yq.version="${YQ_VERSION}"
