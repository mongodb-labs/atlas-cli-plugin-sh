is_prerelease() {
  local version="$1"
  [[ "$version" == *-* ]]
}
