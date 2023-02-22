[![CI workflow](https://img.shields.io/github/workflow/status/dns3l/sra/main?label=ci&logo=github)](https://github.com/dns3l/sra/actions/workflows/main.yml)
[![GitHub release](https://img.shields.io/github/release/dns3l/sra.svg&logo=github)](https://github.com/dns3l/sra/releases/latest)
[![Semantic Release](https://img.shields.io/badge/semantic--release-angular-e10079?logo=semantic-release)](https://github.com/semantic-release/semantic-release)
![License](https://img.shields.io/github/license/dns3l/sra)

## [Smallstep][1] registration authority for DNS3L

`docker pull ghcr.io/dns3l/sra`

[1]: https://smallstep.com/docs/registration-authorities/acme-for-certificate-manager

### Configuration

| variable | note | default |
| --- | --- | --- |
| ENVIRONMENT | `production` or other deployments | |
| SRA_BIND | Registration Authority Bind Port or Address | `:9443` |
| SRA_DNS | Registration Authority DNS Names | `"localhost", "acmera"` |
| STEP_CA_URL | Certificate Manager Authority URL | `https://stepca:9000` |
| STEP_CA_FINGERPRINT | Certificate Manager Authority Fingerprint | `foobar` |
| STEP_CA_PROVISIONER | Certificate Manager JWK Provisioner Name | `acme-ra` |
| STEP_CA_PASSWORD | JWK provisioner password | random |
| SRA_DATABASE | MariaDB database name | `acmera` |
| SRA_DB_USER | database user | `acmera` |
| SRA_DB_PASS | user password | random |
| SRA_DB_HOST | MariaDB server IP/FQDN | `db` |
| SRA_RESOLVER | Optional DNS resolver IP (1.2.3.4:53) | |
| MARIADB_ROOT_PASSWORD | MariaDB root password | |

If `ENVIRONMENT` is `! production` and `MARIADB_ROOT_PASSWORD` is set the database and user are created.

Mount a custom step-ca config to `/etc/stepca.conf.json` if environment based template seems not sufficient.
