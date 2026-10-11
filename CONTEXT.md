# k8s-cd-image

A container image that bundles kubectl with the other CLI tools Kubernetes CI/CD pipelines need, published once per kubectl release and refreshed as the bundled tools change.

## Language

### Versions

**kubectl version**:
The upstream kubectl release (`X.Y.Z`) an image is built for; it forms the first three parts of every image version.
_Avoid_: base version, upstream version

**Image revision**:
The fourth part of an image version: a counter, starting at `0`, that grows by one each time an image with different content is published for the same kubectl version.
_Avoid_: build number, release number, patch

**Image version**:
A kubectl version plus an image revision (`X.Y.Z.R`); it identifies exactly one published image and never moves.
_Avoid_: release, image tag

**Supported kubectl versions**:
The latest patch of each of the three newest Kubernetes minor versions; only these receive new image revisions.
_Avoid_: maintained versions, active versions

### Tags

**Version tag**:
The annotated git tag `vX.Y.Z.R` on the commit an image version was built from; together, the version tags are the record of every image version and the source of the next image revision.
_Avoid_: release tag, release

**Floating tag**:
A registry tag that moves to the newest image version it covers: `X.Y.Z` (newest image revision of that kubectl version), `X.Y` (newest patch of that minor) and `latest` (highest kubectl version).
_Avoid_: alias, rolling tag, moving tag
