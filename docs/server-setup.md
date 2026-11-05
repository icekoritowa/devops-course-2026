# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
VirtualBox 7.2.22 на macOS ARM64. Ubuntu Server 24.04 LTS ARM64 из официального cloud image (без GUI).
2 CPU, 2048 MiB RAM, динамический VDI 25 GiB. Раздел / занимает около 24 GiB, остальное /boot и EFI.
VM зарегистрирована как devops-vm. Система обновлена apt update && apt upgrade -y.

## 2. Сетевые интерфейсы
- enp0s8: NAT, 10.0.2.15/24, шлюз 10.0.2.2, Интернет и обновления.
- enp0s9: Host-only devops-hostonly, 192.168.56.101/24, доступ с Mac.
- Сеть Host-only: 192.168.56.0/24, DHCP диапазон .100–.200. При изменении адреса обновить hosts.
- Netplan /etc/netplan/50-cloud-init.yaml: DHCP для обеих карт; use-routes:false и use-dns:false для Host-only.
- MAC NAT 08:00:27:05:00:01, Host-only 08:00:27:05:00:02.

## 3. Правило проброса портов
NAT ssh: TCP 127.0.0.1:2222 -> гость:2222 после усиления защиты.
До hardening и при восстановлении 01/02 порт гостя 22.
Команды на Mac (VM включена):
```
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```
Если VM выключена, использовать modifyvm --natpf1 вместо controlvm natpf1.

## 4. Учётные записи
student: исходный пользователь, sudo. devops: отдельный пользователь, группа sudo.
В итоговой конфигурации sudo требует пароль; временный cloud-init NOPASSWD удалён.
SSH принимает только devops и только отдельный ключ ed25519 devops_vm.
~/.ssh имеет права 700, authorized_keys 600, владелец devops.
Закрытые ключи и пароль не включены в Git и архив отчёта.

## 5. Служба SSH
Основной /etc/ssh/sshd_config не менялся, копия sshd_config.backup.
В /etc/ssh/sshd_config.d/50-cloud-init.conf закомментирована строка PasswordAuthentication yes.
В /etc/ssh/sshd_config.d/99-hardening.conf:
```
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```
Проверки: sudo sshd -t; sudo sshd -T; sudo ss -tlnp | grep sshd.
ssh.socket отключён; ssh.service включён. В окончательном состоянии слушается только 2222.
Старая управляющая сессия сохранялась до успешного отдельного подключения.

## 6. Правила межсетевого экрана
```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment SSH
sudo ufw allow 80/tcp comment HTTP
sudo ufw allow 443/tcp comment HTTPS
sudo ufw --force enable
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```
limit обновляет правило для того же порта без промежуточного закрытия доступа.
Итог: active; deny incoming; allow outgoing; LIMIT 2222; ALLOW 80/443 (IPv4 и IPv6).
Проверка curl -m 3 http://192.168.56.101:8080 дала таймаут и запись UFW BLOCK.

## 7. Снимки состояния
Штатные снимки VirtualBox, созданы после полного выключения гостя:
1. 01-clean-install — установленная и обновлённая система, SSH 22, student.
2. 02-keys-configured — devops, ключ и права, SSH 22.
3. 03-ssh-hardened — SSH 2222, запрещены root и пароль, до настройки UFW.
VM и снимки сохраняются для следующих практических работ.
Откат: выключить VM, VBoxManage snapshot devops-vm restore 01-clean-install.
После отката на 01/02 выставить гостевой порт NAT 22.

## 8. Имя узла и клиент
/etc/hosts на Mac: 192.168.56.101 devops.local.
/etc/hosts VM: 127.0.1.1 devops-vm.devops.local devops-vm.
Команда: sudo hostnamectl set-hostname devops-vm.
Профиль Mac ~/.ssh/config:
```
Host devops devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile /путь/к/отдельному/devops_vm
    IdentitiesOnly yes
```
В фактическом профиле также заданы отдельный UserKnownHostsFile и HostKeyAlias
для закреплённого ключа той же VM. Отпечаток проверен по ключу сервера.
Проверки с Mac: ping devops.local; ssh devops; ssh -p 2222 devops@devops.local.

## 9. Восстановление после 01-clean-install за 10 минут
1. Подключиться student@127.0.0.1 -p 2222; оставить эту сессию открытой.
2. sudo adduser devops; sudo usermod -aG sudo devops. Задать пароль для sudo.
3. На Mac: ssh-copy-id -i /путь/devops_vm.pub -p 2222 devops@127.0.0.1.
4. Проверить новый вход по ключу и права .ssh=700, authorized_keys=600.
5. Сохранить backup, создать 99-hardening.conf из раздела 5, закомментировать
   конфликтующую PasswordAuthentication yes в 50-cloud-init.conf.
6. sudo sshd -t; sudo systemctl disable --now ssh.socket;
   sudo systemctl enable --now ssh.service; sudo systemctl restart ssh.
7. На Mac изменить NAT на гостевой порт 2222. Проверить новое соединение и отказы root/без ключа.
8. Применить UFW из раздела 6. Настроить hostname и hosts из раздела 8.
9. Удалить bootstrap NOPASSWD: sudo rm -f /etc/sudoers.d/90-cloud-init-users; sudo visudo -c.
10. sudo bash scripts/audit.sh — 6 OK, exit 0.

## 10. Аудит и туннель
Для отрицательного теста только в файле конфигурации временно выставлено MaxAuthTries 10.
Аудит вернул 1; значение возвращено на 3; sshd -t и повторный аудит прошли.
Скрипт проверяет текущую конфигурацию на диске через sshd -T, а не значения уже запущенного процесса.
Факультативно: python3 -m http.server 8080 --bind 127.0.0.1 на VM,
ssh -L 9090:127.0.0.1:8080 -N devops на Mac; curl localhost:9090 возвращает HTML.
Трафик идёт внутри SSH через 2222, на 8080 подключается сам сервер через loopback.

## Источники
Методичка практики 5; https://www.virtualbox.org/ ; https://cloud-images.ubuntu.com/noble/current/
