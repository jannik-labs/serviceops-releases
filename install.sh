#!/bin/sh
#
# Installs ServiceOps on a server you control.
#
#   curl -fsSLO https://raw.githubusercontent.com/jannik-labs/serviceops-releases/main/install.sh
#   less install.sh          # read it. it runs as root
#   sudo sh install.sh
#
# It asks for your licence key first, then for a domain, an address for the
# first administrator and, if you want mail, an SMTP server. Everything else
# it works out or generates. You are never asked to invent a secret.
#
# The software arrives as an encrypted bundle from a public registry, and
# your licence key is what opens it. Nothing here is loaded before the key
# has been checked, and nothing is written to this machine before the key
# has opened the release. The key is never sent anywhere.
#
# What it changes on this machine is listed before it changes anything, and
# it asks. See docs/adr/0041-the-product-operates-itself.md and
# docs/adr/0047-a-release-is-encrypted-to-the-people-who-bought-it.md in the
# source, if you have it.
set -eu

VERSION_OF_THIS_SCRIPT='2026.9'
RELEASE_REPOSITORY="${SERVICEOPS_RELEASE_REPOSITORY:-ghcr.io/jannik-labs/serviceops-release}"
RELEASE_TAG="${SERVICEOPS_RELEASE:-latest}"
INSTALL_DIR="${SERVICEOPS_DIR:-/opt/serviceops}"

# ---------------------------------------------------------------- talking --

red=''; bold=''; dim=''; off=''
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    red="$(tput setaf 1)"; bold="$(tput bold)"; dim="$(tput dim)"; off="$(tput sgr0)"
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s\n' "$bold" "$off" "$*"; }
note() { printf '    %s%s%s\n' "$dim" "$*" "$off"; }
die()  { printf '\n%sStopped:%s %s\n' "$red$bold" "$off" "$*" >&2; exit 1; }

# Reads an answer from the person even when this script arrived on a pipe,
# which is when stdin is the script itself rather than a keyboard.
ask() {
    _prompt="$1"; _fallback="${2:-}"
    if [ -n "$_fallback" ]; then
        printf '%s [%s]: ' "$_prompt" "$_fallback" > /dev/tty
    else
        printf '%s: ' "$_prompt" > /dev/tty
    fi
    IFS= read -r _answer < /dev/tty || _answer=''
    printf '%s' "${_answer:-$_fallback}"
}

confirm() {
    _answer="$(ask "$1 [y/N]" 'n')"
    case "$_answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; docker rm -f serviceops-fetch >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ------------------------------------------------------------- the ground --

step 'Looking at this machine'

[ "$(id -u)" -eq 0 ] || die 'Run this with sudo. It installs packages and writes to /opt.'

command -v curl >/dev/null 2>&1 || die 'curl is needed and is not here. Install it and run this again.'

. /etc/os-release 2>/dev/null || die 'This does not look like a Linux with /etc/os-release.'
case "${ID:-}${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) note "This is written for Debian and Ubuntu; ${PRETTY_NAME:-this system} is neither."
       confirm 'Carry on anyway' || die 'Nothing was changed.' ;;
esac

TOTAL_RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
FREE_DISK_GB="$(df -k / 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')"
note "${PRETTY_NAME:-unknown system}, ${TOTAL_RAM_MB} MB memory, ${FREE_DISK_GB:-?} GB free on /"

if [ -n "$FREE_DISK_GB" ] && [ "$FREE_DISK_GB" -lt 10 ]; then
    die "Only ${FREE_DISK_GB} GB free. This needs at least 10, and a business's photographs need a great deal more."
fi

if [ -e "$INSTALL_DIR/compose.yaml" ]; then
    die "$INSTALL_DIR already holds an installation. Use \"serviceops update\" to move it forward."
fi

# ------------------------------------------------------------- the key --

step 'Your licence key'

say ''
say 'It was given to you with the software. It is one line and begins with'
say 'AGE-SECRET-KEY-1. Nothing is fetched before it has been checked, and'
say 'nothing is written before it has opened the release.'
LICENCE_KEY="$(ask '  Licence key' '')"
case "$LICENCE_KEY" in
    AGE-SECRET-KEY-1*) ;;
    '') die 'Without a licence key there is nothing this can install.' ;;
    *)  die 'That is not a licence key: it has to begin with AGE-SECRET-KEY-1.' ;;
esac
[ "${#LICENCE_KEY}" -eq 74 ] || die "That is not a whole licence key: it has ${#LICENCE_KEY} characters and should have 74."

# ------------------------------------------------------------- the asking --

step 'Three questions'

say ''
say 'The domain this will be reached at. Point its A record at this machine'
say 'first, or leave it empty to reach the installation by IP address with a'
say 'self-signed certificate, which you can change later.'
DOMAIN="$(ask '  Domain' '')"

TLS_DIRECTIVE=''
ACME_EMAIL=''
if [ -z "$DOMAIN" ]; then
    PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
    [ -n "$PUBLIC_IP" ] || die 'No domain given and this machine could not work out its own address.'
    DOMAIN="$PUBLIC_IP"
    TLS_DIRECTIVE='tls internal'
    note "Reached at https://$DOMAIN with a certificate this machine signs itself."
    note 'Browsers will warn about it. Give it a domain when you have one.'
fi

say ''
ADMIN_EMAIL="$(ask '  E-mail address of the first administrator' '')"
[ -n "$ADMIN_EMAIL" ] || die 'The first administrator needs an address to sign in with.'
case "$ADMIN_EMAIL" in *@*.*) ;; *) die "\"$ADMIN_EMAIL\" is not an address." ;; esac

if [ -z "$TLS_DIRECTIVE" ]; then
    ACME_EMAIL="email $ADMIN_EMAIL"
fi

say ''
say 'An SMTP server, so the installation can send a service report to a'
say 'customer. Leave it empty and it sends nothing, and every screen that'
say 'would have sent something says so plainly.'
MAILER_DSN="$(ask '  SMTP, as smtp://user:password@host:port' '')"
MAIL_FROM=''
if [ -n "$MAILER_DSN" ]; then
    MAIL_FROM="$(ask '  The address it sends from' "$ADMIN_EMAIL")"
else
    MAILER_DSN='null://null'
fi

# -------------------------------------------------------- what will happen --

step 'What this is about to do'

NEEDS_DOCKER='no'
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || NEEDS_DOCKER='yes'

NEEDS_AGE='no'
command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1 || NEEDS_AGE='yes'

NEEDS_SWAP='no'
if [ "$TOTAL_RAM_MB" -lt 3000 ] && [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -eq 0 ]; then
    NEEDS_SWAP='yes'
fi

PROXY_PROFILE='caddy'
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ':(80|443)$'; then
    note 'Something is already listening on port 80 or 443.'
    if confirm '  Is that your own reverse proxy, which should stay in front'; then
        PROXY_PROFILE=''
    else
        die 'Free ports 80 and 443, or answer yes so this leaves them alone.'
    fi
fi

say ''
[ "$NEEDS_DOCKER" = yes ] && say '  - install Docker, from get.docker.com'
[ "$NEEDS_AGE" = yes ] && say '  - install age, the tool that opens the release with your key'
say "  - fetch $RELEASE_REPOSITORY:$RELEASE_TAG and open it with your key"
say "  - write the installation to $INSTALL_DIR"
[ "$PROXY_PROFILE" = caddy ] && say "  - serve https://$DOMAIN, obtaining the certificate itself"
say '  - turn on automatic security updates for this machine'
say '  - allow only ports 22, 80 and 443 through the firewall'
[ "$NEEDS_SWAP" = yes ] && say "  - add 2 GB of swap, because this machine has ${TOTAL_RAM_MB} MB of memory"
say ''

confirm 'Go ahead' || die 'Nothing was changed.'

# ------------------------------------------------------------- doing it --

if [ "$NEEDS_DOCKER" = yes ]; then
    step 'Installing Docker'
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

if [ "$NEEDS_AGE" = yes ]; then
    step 'Installing age'
    command -v apt-get >/dev/null 2>&1 || die 'age is not installed and this is not an apt system. Install age and run this again.'
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq age >/dev/null
fi

if [ "$NEEDS_SWAP" = yes ]; then
    step 'Adding swap'
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
fi

step 'Checking the key'

umask 077
printf '%s\n' "$LICENCE_KEY" > "$WORK/licence.key"
LICENCE_PUBLIC="$(age-keygen -y "$WORK/licence.key" 2>/dev/null)" \
    || die 'That licence key does not check out. One character is wrong somewhere.'
umask 022
note "It belongs to $LICENCE_PUBLIC"

# ------------------------------------------------------------ the release --
#
# What follows is the same in "serviceops update", and is written out twice
# on purpose: this script has to work before anything of ours is on the
# machine, and the update has to work without this script.

step "Fetching $RELEASE_REPOSITORY:$RELEASE_TAG"

docker pull -q "$RELEASE_REPOSITORY:$RELEASE_TAG" >/dev/null \
    || die "Could not pull $RELEASE_REPOSITORY:$RELEASE_TAG. Check this machine can reach ghcr.io."

# The release image is nothing but a manifest and an encrypted bundle, so it
# is not run; the two files are copied out of it.
docker rm -f serviceops-fetch >/dev/null 2>&1 || true
docker create --name serviceops-fetch "$RELEASE_REPOSITORY:$RELEASE_TAG" true >/dev/null
docker cp serviceops-fetch:/manifest.json "$WORK/manifest.json"
docker cp serviceops-fetch:/core.age "$WORK/core.age"
docker rm serviceops-fetch >/dev/null
RELEASE_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "$RELEASE_REPOSITORY:$RELEASE_TAG" 2>/dev/null || echo "$RELEASE_REPOSITORY:$RELEASE_TAG")"

RELEASE_VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$WORK/manifest.json" | head -1)"
[ -n "$RELEASE_VERSION" ] || die 'The release carries no version. That is not a release of ours.'
note "This is version $RELEASE_VERSION"

step 'Opening it with your key'

mkdir -p "$WORK/bundle"
if ! age -d -i "$WORK/licence.key" "$WORK/core.age" 2>/dev/null | tar -xz -C "$WORK/bundle"; then
    die "Your licence key does not cover version $RELEASE_VERSION. Nothing was written. Ask whoever gave you the key."
fi
[ -f "$WORK/bundle/Dockerfile" ] || die 'The bundle opened but is not one of ours. Nothing was written.'

step 'Assembling the application'

# The base image is pulled on its own first, so that the one thing likely to
# go wrong here says so plainly: the package is still private, or ghcr.io
# cannot be reached.
BASE_IMAGE="$(sed -n 's/^FROM //p' "$WORK/bundle/Dockerfile" | head -1)"
docker pull -q "$BASE_IMAGE" >/dev/null \
    || die "Could not pull the base image $BASE_IMAGE. It has to be public on ghcr.io, and this machine has to reach it."

# The bundle's own Dockerfile: our files on a public base image, pinned by
# digest. It copies and nothing else, which is why this takes seconds and
# needs no toolchain.
docker build -q -t "serviceops:$RELEASE_VERSION" "$WORK/bundle" >/dev/null \
    || die 'Assembling the image failed. The output above says why.'
IMAGE="serviceops:$RELEASE_VERSION"

# ----------------------------------------------------- the installation --

step 'Laying the installation down'

mkdir -p "$INSTALL_DIR"/data/postgres "$INSTALL_DIR"/data/files \
         "$INSTALL_DIR"/data/backups "$INSTALL_DIR"/data/caddy "$INSTALL_DIR"/data/caddy-config
chmod 700 "$INSTALL_DIR"

for file in compose.yaml compose.traefik.yaml Caddyfile serviceops; do
    cp "$WORK/bundle/deploy/$file" "$INSTALL_DIR/$file"
done
chmod +x "$INSTALL_DIR/serviceops"
ln -sf "$INSTALL_DIR/serviceops" /usr/local/bin/serviceops

cp "$WORK/manifest.json" "$INSTALL_DIR/manifest.json"
printf 'core\n' > "$INSTALL_DIR/opened"

# The key stays here, readable by root only, so that "serviceops update" can
# open the next release without asking. Root here could copy it, which gains
# them what they already have.
umask 077
cp "$WORK/licence.key" "$INSTALL_DIR/licence.key"
umask 022

# Every secret is made here. The operator invents nothing, which is the whole
# difference between this and a page of instructions.
random() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

APP_SECRET="$(random 32)"
POSTGRES_PASSWORD="$(random 24)"
SETUP_TOKEN="$(random 24)"

step 'Making the key your backups are encrypted with'

# X25519, through libsodium, which is in the image already. A backup holds
# every customer a business has; it must not be readable by whoever ends up
# with the bucket.
#
# **Past the entrypoint, not through it.** The entrypoint insists on an
# APP_SECRET and a DATABASE_URL before it runs anything, which is right for
# starting the application and wrong here: neither exists yet, and making a
# keypair is not starting anything.
BACKUP_KEYS="$(docker run --rm --entrypoint php "$IMAGE" \
    -r '$k=sodium_crypto_box_keypair();
        echo sodium_bin2hex(sodium_crypto_box_publickey($k)), " ",
             sodium_bin2hex(sodium_crypto_box_secretkey($k));')" \
    || die 'Could not make a backup key. The output above says why.'

BACKUP_PUBLIC="${BACKUP_KEYS% *}"
BACKUP_SECRET="${BACKUP_KEYS#* }"

ORIGIN="https://$DOMAIN"

umask 077
cat > "$INSTALL_DIR/.env" <<ENV
# Written by install.sh. Everything in here is this installation's own.
# Keep it: losing it loses the database password and the backup key.
SERVICEOPS_IMAGE=$IMAGE
SERVICEOPS_RELEASE_REPOSITORY=$RELEASE_REPOSITORY
SERVICEOPS_RELEASE_DIGEST=$RELEASE_DIGEST
SERVICEOPS_DOMAIN=$DOMAIN
SERVICEOPS_ORIGIN=$ORIGIN
SERVICEOPS_TLS=$TLS_DIRECTIVE
SERVICEOPS_ACME_EMAIL=$ACME_EMAIL
COMPOSE_PROFILES=$PROXY_PROFILE

APP_SECRET=$APP_SECRET
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Opens /setup for the first administrator and shuts for good on the first
# account. See docs/adr/0029-the-first-way-in-needs-a-token-and-closes-for-good.md
SERVICEOPS_SETUP_TOKEN=$SETUP_TOKEN

MAILER_DSN=$MAILER_DSN
MAIL_FROM=$MAIL_FROM

# The public half of the backup key. The installation can encrypt a backup
# with this and cannot read one back: that needs the secret half, which is
# printed once by this script and written nowhere.
SERVICEOPS_BACKUP_KEY=$BACKUP_PUBLIC
SERVICEOPS_BACKUP_KEEP_DAYS=30

# Where a copy goes, off this machine. Empty means backups stay here, which
# is no protection at all against this machine being gone. Fill these in and
# run "serviceops backup" to try it.
SERVICEOPS_BACKUP_S3_ENDPOINT=
SERVICEOPS_BACKUP_S3_REGION=
SERVICEOPS_BACKUP_S3_BUCKET=
SERVICEOPS_BACKUP_S3_KEY=
SERVICEOPS_BACKUP_S3_SECRET=
ENV
chmod 600 "$INSTALL_DIR/.env"
umask 022

step 'Starting it'

cd "$INSTALL_DIR"
docker compose --profile tools run --rm migrate
docker compose up -d --wait

step 'Hardening this machine'

if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades ufw >/dev/null
    dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true

    SSH_PORT="$(awk '/^Port /{print $2}' /etc/ssh/sshd_config 2>/dev/null | tail -1)"
    ufw allow "${SSH_PORT:-22}"/tcp >/dev/null
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw allow 443/udp >/dev/null
    ufw --force enable >/dev/null
    note "Firewall on. Open: ${SSH_PORT:-22}, 80, 443."
fi

# ------------------------------------------------------------------ done --

cat <<DONE

$bold  ServiceOps $RELEASE_VERSION is running.$off

  Open this once, and make the first administrator:

    $ORIGIN/setup?token=$SETUP_TOKEN

  The link works until the first account exists and then never again.

$bold  BACKUP KEY - shown once, written nowhere$off

    $BACKUP_SECRET

  Without it, every backup this installation makes is unreadable. Put it
  somewhere that survives this machine: a password manager, a piece of
  paper in a different building. Not on this server.

  Your licence key is kept in $INSTALL_DIR/licence.key, readable by root
  only, so that updates can open the next release without asking for it.

  Then:

    serviceops doctor        what is wrong, if anything
    serviceops backup        take one now, and prove the key works
    serviceops update        move to a newer version, with a way back

DONE
