#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Set by GH actions, see
# https://docs.github.com/en/actions/learn-github-actions/environment-variables#default-environment-variables
TAG=${GITHUB_REF_NAME}
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="rules_fpga-${TAG:1}"
ARCHIVE="rules_fpga-$TAG.tar.gz"
ARCHIVE_TMP=$(mktemp)

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} > $ARCHIVE_TMP

gzip < $ARCHIVE_TMP > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

cat << EOF
Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "gateweavers_rules_fpga", version = "${TAG:1}")
\`\`\`

And also register a Vivado toolchain. For example:

\`\`\`starlark
vivado_toolchains = use_extension("@gateweavers_rules_fpga//vivado:extensions.bzl", "vivado_toolchains")
vivado_toolchains.vivado(
    name = "vivado_2024_2",
    path = "/opt/Xilinx/Vivado/2024.2/",
    version = "2024.2",
    is_default = True,
)
use_repo(vivado_toolchains, "fpga_toolchains")

register_toolchains("@fpga_toolchains//:all")
\`\`\`

EOF
