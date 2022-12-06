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

function random_token() {
  tr -cd '[:alnum:]' </dev/urandom | fold -w32 | head -n1
}

SERVICE_TIMEOUT=${SERVICE_TIMEOUT:-300s} # wait for dependencies

echo Running: "$@"

export SRA_BIND=${SRA_BIND:-":9443"}
export SRA_DNS=${SRA_DNS:-'"localhost","sra","acmera"'}

export STEP_CA_URL=${STEP_CA_URL:-"https://stepca:9000"}
export STEP_CA_FINGERPRINT=${STEP_CA_FINGERPRINT:-"foobar"}
export STEP_CA_PROVISIONER=${STEP_CA_PROVISIONER:-"acme-ra"}
export STEP_CA_PASSWORD=${STEP_CA_PASSWORD:-$(random_token)}

export SRA_DATABASE=${SRA_DATABASE:-"sra"}
export SRA_DB_USER=${SRA_DB_USER:-"sra"}
export SRA_DB_PASS=${SRA_DB_PASS:-$(random_token)}
export SRA_DB_HOST=${SRA_DB_HOST:-"db"}

production=false
if [[ ${ENVIRONMENT,,} == "production" ]]; then
  production=true
fi

# Avoid destroying bootstrapping by simple start/stop
if [[ ! -e ${STEPPATH}/.bootstrapped ]]; then
  ### list none idempotent code blocks, here...

  touch ${STEPPATH}/.bootstrapped
fi

###
### ACME RA DB bootstrapping...
###

if [[ "${production}" == "false" && -n "${MARIADB_ROOT_PASSWORD}" ]]; then
  echo "Bootstrapping ACME RA Database..."
  set +e
  /dckrz -wait tcp://${SRA_DB_HOST}:3306 -timeout ${SERVICE_TIMEOUT} -- \
    echo "quit" | mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -h"${SRA_DB_HOST}" -D"${SRA_DATABASE}"
  if [ "$?" != "0" ]; then # create DB
    set -e
    echo "Create ${SRA_DATABASE}..."
    /dckrz -wait tcp://${SRA_DB_HOST}:3306 -timeout ${SERVICE_TIMEOUT} -- \
      cat <<EOSQL | mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -h"${SRA_DB_HOST}"
CREATE DATABASE IF NOT EXISTS ${SRA_DATABASE};
CREATE USER IF NOT EXISTS ${SRA_DB_USER}@'%' IDENTIFIED BY '${SRA_DB_PASS}';
GRANT ALL ON ${SRA_DATABASE}.* TO ${SRA_DB_USER}@'%';
FLUSH PRIVILEGES;
EOSQL
  else # change password (optionally)
    set -e
    echo "Change password ${SRA_DB_PASS}..."
    /dckrz -wait tcp://${SRA_DB_HOST}:3306 -timeout ${SERVICE_TIMEOUT} -- \
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

if [ -r /etc/stepca.conf.json -a -s /etc/stepca.conf.json ]; then
  ln -fs /etc/stepca.conf.json ${STEPPATH}/config/ca.json
else
  /dckrz -template ${STEPPATH}/ca.json.tmpl:${STEPPATH}/config/ca.json
fi

# Workaround for https://github.com/dns3l/sra/issues/7
# /dckrz -wait ${STEP_CA_URL} -skip-tls-verify -wait-http-status-code 401 -timeout ${SERVICE_TIMEOUT} -- \
step ca bootstrap -f --ca-url ${STEP_CA_URL} --fingerprint ${STEP_CA_FINGERPRINT} # --install

/dckrz -wait tcp://${SRA_DB_HOST}:3306 -timeout ${SERVICE_TIMEOUT} -- echo "Ok. MariaDB is there."

if [[ `basename ${1}` == "step-ca" ]]; then # prod
    exec "$@" </dev/null #>/dev/null 2>&1
else # dev
    step-ca ${STEPPATH}/config/ca.json --issuer-password-file ${STEPPATH}/.acme-ra.pass || true
fi

# fallthrough...
exec "$@"
