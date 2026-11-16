#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cp -a /etc/samba/smb.conf /etc/samba/smb.conf.pre-vesper 2>/dev/null || true
cat > /etc/samba/smb.conf <<'SMB'
[global]
   server role = standalone server
   server string = Vesper NAS
   workgroup = WORKGROUP
   server min protocol = SMB3
   server max protocol = SMB3
   disable netbios = yes
   smb ports = 445
   map to guest = never
   usershare allow guests = no
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   unix extensions = no
   ea support = yes
   store dos attributes = yes
   vfs objects = fruit streams_xattr
   fruit:aapl = yes
   fruit:nfs_aces = no
   fruit:copyfile = yes
   fruit:model = MacSamba
   fruit:metadata = stream
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   hosts allow = 127.0.0.1 192.168.0.0/24

[VesperTimeMachine]
   path = /srv/vesper/time-machine
   browseable = yes
   available = yes
   read only = no
   valid users = vesper
   force user = vesper
   force group = vesper
   create mask = 0660
   directory mask = 0770
   vfs objects = fruit streams_xattr
   fruit:time machine = yes
   fruit:time machine max size = 800G
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes

[VesperFiles]
   path = /srv/vesper/files
   browseable = yes
   available = yes
   read only = no
   valid users = vesper
   force user = vesper
   force group = vesper
   create mask = 0660
   directory mask = 0770
   vfs objects = fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
SMB

cat > /etc/avahi/services/vesper-timemachine.service <<'AVAHI'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Vesper NAS</name>
  <service>
    <type>_adisk._tcp</type>
    <port>9</port>
    <txt-record>sys=waMa=0,adVF=0x100</txt-record>
    <txt-record>dk0=adVN=VesperTimeMachine,adVF=0x82</txt-record>
  </service>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
AVAHI

testparm -s >/tmp/testparm.out 2>&1
cat /tmp/testparm.out
systemctl restart smbd.service
systemctl restart avahi-daemon.service
sleep 2
systemctl is-active smbd.service avahi-daemon.service

echo '=== shares ==='
smbclient -L localhost -N 2>&1 | sed -n '1,80p' || true
