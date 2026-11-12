#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
check() {
 local desc="$1" expected="$2" actual="$3"
 if [[ "$actual" == "$expected" ]]; then
  echo "[OK] $desc"; ((PASS+=1))
 else
  echo "[FAIL] $desc (expected=$expected actual=$actual)"; ((FAIL+=1))
 fi
}
if (( EUID != 0 )); then exec sudo bash "$0" "$@"; fi
SSH=$(sshd -T) || exit 1
UFW=$(ufw status verbose) || exit 1
value() { awk -v k="$1" '$1==k {print $2}' <<< "$SSH"; }
echo "Audit: $(hostname -f)"
check 'Root login disabled' no "$(value permitrootlogin)"
check 'Password login disabled' no "$(value passwordauthentication)"
PORTS=$(value port)
NONSTANDARD=no
if [[ -n "$PORTS" ]] && ! grep -qx 22 <<< "$PORTS"; then NONSTANDARD=yes; fi
check 'All SSH ports are nonstandard' yes "$NONSTANDARD"
check 'MaxAuthTries' 3 "$(value maxauthtries)"
check 'UFW active' active "$(awk '/^Status:/{print $2}' <<< "$UFW")"
check 'Incoming policy deny' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW")"
awk -F: '$3>=1000 && $3<65534 {printf "User: %s uid=%s\n",$1,$3}' /etc/passwd
echo '[4] Web server'
check 'Nginx active' active "$(systemctl is-active nginx)"
if nginx -t >/dev/null 2>&1; then syntax=yes; else syntax=no; fi
check 'Nginx syntax' yes "$syntax"
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${CERT_MIN_SECONDS:-2592000}" >/dev/null 2>&1; then cert=yes; else cert=no; fi
check 'Certificate validity' yes "$cert"
secure=no
if [[ -d /var/www/devops-site ]] && writable=$(find /var/www/devops-site -perm -o+w) && [[ -z "$writable" ]] && [[ $(stat -c '%a' /etc/ssl/private/devops.key) == 600 ]]; then secure=yes; fi
check 'Site and key permissions' yes "$secure"
echo "Passed: $PASS; failed: $FAIL"
[[ $FAIL -eq 0 ]]
