# shellcheck shell=bash
# Print the configuration baked into the agent .deb downloaded from Secureframe
# (a preconfigured Fleet orbit package), labelled by the
# services.secureframe-agent option each value maps to.
#
# Wrapped by the flake (supplies dpkg-deb, tar and strict mode):
#   nix run .#read-deb -- secureframe-agent.deb

if [[ $# -ne 1 ]]; then
  echo "usage: secureframe-deb-config <secureframe-agent.deb>" >&2
  exit 2
fi
deb=$1

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -r $deb ]] || die "cannot read $deb"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Everything except the binaries: a few hundred KiB on disk instead of ~130 MiB.
dpkg-deb --fsys-tarfile "$deb" | tar -x -C "$tmp" --exclude=./opt/orbit/bin

envFile=$tmp/etc/default/orbit
unitFile=$tmp/usr/lib/systemd/system/orbit.service
flagsFile=$tmp/opt/orbit/osquery.flags
for f in "$envFile" "$unitFile"; do
  [[ -f $f ]] || die "${f#"$tmp"} missing from $deb; not a Fleet orbit package?"
done

# /etc/default/orbit: KEY=VALUE lines, kept in file order.
declare -A env=()
envKeys=()
while IFS='=' read -r key value; do
  [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  env[$key]=$value
  envKeys+=("$key")
done <"$envFile"

# orbit.service: ExecStart=<orbit> [orbit args] [-- osquery args]
execStart=
while IFS= read -r line; do
  [[ $line == ExecStart=* ]] && execStart=${line#ExecStart=}
done <"$unitFile"
[[ -n $execStart ]] || die "no ExecStart in ${unitFile#"$tmp"}"

read -ra words <<<"$execStart"
orbitArgs=()
osqueryArgs=()
hostIdentifier=
inOsquery=false
i=1 # words[0] is the orbit binary
while ((i < ${#words[@]})); do
  word=${words[i]}
  next=${words[i + 1]-}
  if ! $inOsquery; then
    if [[ $word == -- ]]; then inOsquery=true; else orbitArgs+=("$word"); fi
  elif [[ $word == --host_identifier && $next == specified ]]; then
    # Implied by hostIdentifier; the module emits it itself.
    i=$((i + 1))
  elif [[ $word == --specified_identifier && -n $next ]]; then
    hostIdentifier=$next
    i=$((i + 1))
  else
    osqueryArgs+=("$word")
  fi
  i=$((i + 1))
done

row() {
  printf '  %-18s %s\n' "$1" "${2:-(unset)}"
}

# shellcheck disable=SC2016 # ${...} here is dpkg-deb's format syntax, not shell
dpkg-deb --showformat='${Package} ${Version} (${Architecture})\n' -W "$deb"
echo
echo "services.secureframe-agent (the enroll secret is the content of enrollSecretFile):"
row fleetUrl "${env[ORBIT_FLEET_URL]-}"
row "enroll secret" "${env[ORBIT_ENROLL_SECRET]-}"
row hostIdentifier "$hostIdentifier"
row orbit.extraArgs "${orbitArgs[*]}"
row osquery.extraArgs "${osqueryArgs[*]}"
row desktop.enable "${env[ORBIT_FLEET_DESKTOP]-}"
row debug "${env[ORBIT_DEBUG]-}"
row insecure "${env[ORBIT_INSECURE]-}"

echo
echo "Other vendor settings (/etc/default/orbit):"
for key in "${envKeys[@]}"; do
  case $key in
    ORBIT_FLEET_URL | ORBIT_ENROLL_SECRET | ORBIT_FLEET_DESKTOP | ORBIT_DEBUG | ORBIT_INSECURE) ;;
    *) echo "  $key=${env[$key]}" ;;
  esac
done

echo
if [[ -s $flagsFile ]]; then
  echo "osquery.flags:"
  while IFS= read -r line; do
    echo "  $line"
  done <"$flagsFile"
else
  echo "osquery.flags: (empty)"
fi
