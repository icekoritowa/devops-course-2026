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
echo "Passed: $PASS; failed: $FAIL"
[[ $FAIL -eq 0 ]]
