#!/bin/bash
set -e

umask 0022

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
#  (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#   "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
function file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

# envs=(
#   XYZ_API_TOKEN
# )
# haveConfig=
# for e in "${envs[@]}"; do
#   file_env "$e"
#   if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
#     haveConfig=1
#   fi
# done

# return true if specified directory is empty
function directory_empty() {
  [ -n "$(find "${1}"/ -prune -empty)" ]
}

echo Running: "$@"

SRA_BIND=${SRA_BIND:-":9443"}
SRA_DNS=${SRA_DNS:-'"localhost","acmera"'}

STEP_CA_URL=${STEP_CA_URL:-"https://stepca:9000"}
STEP_CA_FINGERPRINT=${STEP_CA_FINGERPRINT:-"foobar"}
STEP_CA_PROVISIONER=${STEP_CA_PROVISIONER:-"acme-ra"}
STEP_CA_PASSWORD=${STEP_CA_PASSWORD:-$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n1)}

SRA_DATABASE=${SRA_DATABASE:-"acmera"}
SRA_DB_USER=${SRA_DB_USER:-"acmera"}
SRA_DB_PASS=${SRA_DB_PASS:-$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n1)}
SRA_DB_HOST=${SRA_DB_HOST:-"db"}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n1)}

production=false
if [[ ${ENVIRONMENT,,} == "production" ]]; then
  production=true
fi

. /mo

# Avoid destroying bootstrapping by simple start/stop
if [[ ! -e ${STEPPATH}/.bootstrapped ]]; then
  ### list none idempotent code blocks, here...

  touch ${STEPPATH}/.bootstrapped
fi

###
### ACME RA DB bootstrapping...
###

if [ -n ${MARIADB_ROOT_PASSWORD} -a ! ${production} ]; then
echo "Bootstrapping ACME RA Database..."
set +e
/wait-for-it.sh -t 3600 -s db:3306 -- echo "quit" | mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -h"${SRA_DB_HOST}" -D"${SRA_DATABASE}"
if [ "$?" != "0" ]; then # bootstrap DB
set -e
echo "Create ${SRA_DATABASE}..."
cat <<EOSQL | mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -h"${SRA_DB_HOST}"
CREATE DATABASE IF NOT EXISTS ${SRA_DATABASE};
CREATE USER IF NOT EXISTS ${SRA_DB_USER}@'%' IDENTIFIED BY '${SRA_DB_PASS}';
GRANT ALL ON ${SRA_DATABASE}.* TO ${SRA_DB_USER}@'%';
FLUSH PRIVILEGES;
EOSQL
else # change password
set -e
echo "Change password ${SRA_DB_PASS}..."
cat <<EOSQL | mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -h"${SRA_DB_HOST}"
ALTER USER IF EXISTS ${SRA_DB_USER}@'%' IDENTIFIED BY '${SRA_DB_PASS}';
FLUSH PRIVILEGES;
EOSQL
fi
fi

###
### ACME RA bootstrapping...
###

echo -n "${STEP_CA_PASSWORD}" >${STEPPATH}/.acme-ra.pass

echo "Creating ACME RA configuration..."
mkdir -p -m 0700 ${STEPPATH}/config
mkdir -p -m 0700 ${STEPPATH}/certs

# mkdir -p -m 0700 ${STEPPATH}/db
# "db": {
#   "type": "badgerV2",
#   "dataSource": "${STEPPATH}/db" },

  cat <<EOF >${STEPPATH}/config/ca.json
{ "address": "${SRA_BIND}",
  "dnsNames": [${SRA_DNS}],
  "db": {
   "type": "mysql",
    "dataSource": "${SRA_DB_USER}:${SRA_DB_PASS}@tcp(${SRA_DB_HOST}:3306)/",
    "database": "${SRA_DATABASE}" },
  "logger": {"format": "text"},
  "authority": {
    "type": "stepcas",
    "certificateAuthority": "${STEP_CA_URL}",
    "certificateAuthorityFingerprint": "${STEP_CA_FINGERPRINT}",
    "certificateIssuer": {
      "type" : "jwk",
      "provisioner": "${STEP_CA_PROVISIONER}"
    },
    "provisioners": [{
      "type": "ACME",
      "name": "acme",
      "forceCN": true,
      "claims": {
        "maxTLSCertDuration": "4320h0m0s",
        "defaultTLSCertDuration": "2160h0m0s" } }]
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
      "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
      "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
      "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305" ],
    "minVersion": 1.2,
    "maxVersion": 1.3,
    "renegotiation": false } }
EOF

/wait-for-it.sh -t 3600 -s $(echo ${STEP_CA_URL} | sed -e 's#\(http\|https\)://##') -- \
  step ca bootstrap -f --ca-url ${STEP_CA_URL} --fingerprint ${STEP_CA_FINGERPRINT}

if [[ `basename ${1}` == "step-ca" ]]; then # prod
    exec "$@" </dev/null #>/dev/null 2>&1
else # dev
    step-ca ${STEPPATH}/config/ca.json --issuer-password-file ${STEPPATH}/.acme-ra.pass || true
fi

# fallthrough...
exec "$@"
