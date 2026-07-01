#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: build.sh <target-triple>}"

rustup target add "$target"
cargo build --release --target "$target"
