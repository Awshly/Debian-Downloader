#!/usr/bin/env bash
set -Eeuo pipefail
VERSION="0.1.0"
MODE="installer"; ARCH="amd64"; OUT_DIR="$PWD"; ISO_URL=""; KEYRING=""; VERIFY=1
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; RESET=$'\033[0m'
info(){ printf '[INFO] %s\n' "$*"; }
good(){ printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
die(){ printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
usage(){ cat <<'EOF'
Debian Downloader — official Debian installer/live ISO downloader

Usage: ./debian-downloader [options]
  --type installer|live   Image family (default: installer)
  --arch ARCH             Installer architecture (default: amd64)
  --output DIR            Destination directory
  --url URL               Direct official Debian ISO URL
  --keyring FILE          Trusted GPG keyring for signature verification
  --no-verify             Skip verification (not recommended)
  -h, --help              Help
  --version               Version

Dependencies: bash, curl, gpg, sha512sum, awk, grep, sed, mktemp.
Interrupted downloads retain a .part file and can be resumed by rerunning.
EOF
}
while (($#)); do
 case "$1" in
  --type) [[ $# -ge 2 ]] || die "--type needs a value"; MODE="$2"; shift 2;;
  --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; ARCH="$2"; shift 2;;
  --output) [[ $# -ge 2 ]] || die "--output needs a value"; OUT_DIR="$2"; shift 2;;
  --url) [[ $# -ge 2 ]] || die "--url needs a value"; ISO_URL="$2"; shift 2;;
  --keyring) [[ $# -ge 2 ]] || die "--keyring needs a value"; KEYRING="$2"; shift 2;;
  --no-verify) VERIFY=0; shift;;
  -h|--help) usage; exit 0;;
  --version) echo "Debian Downloader $VERSION"; exit 0;;
  *) die "Unknown option: $1 (use --help)";;
 esac
done
for c in curl gpg sha512sum awk grep sed mktemp; do command -v "$c" >/dev/null 2>&1 || die "Missing dependency: $c"; done
[[ "$MODE" == installer || "$MODE" == live ]] || die "--type must be installer or live"
[[ "$ARCH" =~ ^[a-z0-9_-]+$ ]] || die "Invalid architecture"
mkdir -p -- "$OUT_DIR"; OUT_DIR="$(cd -- "$OUT_DIR" && pwd -P)"
if [[ -z "$ISO_URL" ]]; then
 if [[ "$MODE" == live ]]; then
  [[ "$ARCH" == amd64 ]] || die "Official live images currently target amd64."
  die "Live directory layout changes; select an official ISO URL from https://www.debian.org/CD/live/ and pass it with --url."
 fi
 IMAGE_DIR="https://cdimage.debian.org/debian-cd/current/$ARCH/iso-cd"
 INDEX="$(curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$IMAGE_DIR/")" || die "Could not read Debian image index."
 ISO_NAME="$(printf '%s\n' "$INDEX" | grep -oE 'href="debian-[^"]+\.iso"' | sed -E 's/^href="([^"]+)".*/\1/' | head -n1 || true)"
 [[ -n "$ISO_NAME" ]] || die "No ISO found in $IMAGE_DIR"
 ISO_URL="$IMAGE_DIR/$ISO_NAME"
else
 [[ "$ISO_URL" == https://cdimage.debian.org/* ]] || die "--url must use official cdimage.debian.org HTTPS."
 ISO_NAME="${ISO_URL##*/}"; [[ "$ISO_NAME" == *.iso ]] || die "--url must point directly to an .iso"
 IMAGE_DIR="${ISO_URL%/*}"
fi
DEST="$OUT_DIR/$ISO_NAME"; PART="$DEST.part"; WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
if [[ -e "$DEST" ]]; then
 read -r -p "$DEST exists. Replace it? [y/N] " ans
 [[ "$ans" =~ ^[Yy]$ ]] || die "Cancelled"
 mv -- "$DEST" "$DEST.backup.$(date +%Y%m%d%H%M%S)"
fi
info "Downloading $ISO_NAME from official Debian HTTPS infrastructure"
curl --fail --location --show-error --progress-bar --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --continue-at - --output "$PART" "$ISO_URL" || die "Download failed; partial file retained at $PART"
mv -- "$PART" "$DEST"; good "Download completed: $DEST"
if [[ "$VERIFY" -eq 0 ]]; then echo "WARNING: verification skipped; image is not authenticated."; exit 0; fi
SUMS="$WORK/SHA512SUMS"; SIGN="$WORK/SHA512SUMS.sign"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 -o "$SUMS" "$IMAGE_DIR/SHA512SUMS" || die "ISO saved, but SHA512SUMS could not be fetched."
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 -o "$SIGN" "$IMAGE_DIR/SHA512SUMS.sign" || die "ISO saved, but signature could not be fetched."
if [[ -z "$KEYRING" ]]; then
 for k in /usr/share/keyrings/debian-role-keys.gpg /usr/share/keyrings/debian-keyring.gpg; do [[ -r "$k" ]] && { KEYRING="$k"; break; }; done
fi
[[ -n "$KEYRING" && -r "$KEYRING" ]] || die "ISO downloaded but NOT verified: supply --keyring with a trusted Debian signing keyring. See README."
mkdir -m 700 "$WORK/gnupg"
if ! gpg --batch --no-options --homedir "$WORK/gnupg" --no-default-keyring --keyring "$KEYRING" --status-fd 1 --verify "$SIGN" "$SUMS" >"$WORK/status" 2>"$WORK/gpg.log"; then
 cat "$WORK/gpg.log" >&2; die "Signature verification failed; ISO is NOT verified."
fi
grep -q '^\[GNUPG:\] GOODSIG ' "$WORK/status" || die "No good signature status; ISO is NOT verified."
grep -F "  $ISO_NAME" "$SUMS" >/dev/null || die "ISO not listed in signed checksum file."
EXPECTED="$(awk -v n="$ISO_NAME" '$2 == n || $2 == "*" n {print $1; exit}' "$SUMS")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{128}$ ]] || die "Could not parse SHA-512."
ACTUAL="$(sha512sum "$DEST" | awk '{print $1}')"
[[ "${ACTUAL,,}" == "${EXPECTED,,}" ]] || die "SHA-512 mismatch; ISO is NOT verified."
good "Signature valid and SHA-512 checksum matches."
good "Verified Debian ISO: $DEST"
