## Install necessary packages and latest virtualbox
wget -q -O - http://download.virtualbox.org/virtualbox/debian/oracle_vbox_2016.asc | sudo apt-key add -
sudo sh -c 'echo "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian bionic non-free contrib" >> /etc/apt/sources.list.d/virtualbox.org.list' 
sudo apt update
sudo apt install virtualbox-5.2 qemu-utils genisoimage cloud-utils

## get kvm unloaded so virtualbox can load
## WARNING: not needed?
#sudo modprobe -r kvm_amd kvm_intel
#sudo service virtualbox stop
#sudo service virtualbox start

## version for the image in numbers (14.04, 16.04, 18.04, etc.)
ubuntuversion="18.04"
## image type: ova, vmdk, img, tar.gz
imagetype="img"

## URL to most recent cloud image
releases_url="https://cloud-images.ubuntu.com/releases/${ubuntuversion}/release/"
img_url="${releases_url}/ubuntu-${ubuntuversion}-server-cloudimg-amd64.${imagetype}"

## download a cloud image to run, and convert it to virtualbox 'vdi' format
img_dist="${img_url##*/}"
img_raw="${img_dist%.img}.raw"
my_disk1="ubuntu-${ubuntuversion}-cloud-virtualbox.vdi"
wget $img_url -O "$img_dist"
qemu-img convert -O raw "${img_dist}" "${img_raw}"
vboxmanage convertfromraw "$img_raw" "$my_disk1"

## Name the iso file for the cloud-config data
seed_iso="my-seed.iso"

## create meta-data file 
cat > meta-data <<EOF
instance-id: ubuntucloud-001
local-hostname: ubuntucloud1
EOF

## Generate a hashed password from stdin for the /etc/passwd file
mkpasswd -m sha-512 -s

## create user-data file 
seed_iso="my-seed.iso"
cat > user-data <<EOF
#cloud-config
users:
  - default
  - name: USER-NAME-HERE
    passwd: PASTE-HASHED-PASSWORD-HERE
    ssh_pwauth: True
    chpasswd: { expire: False }
    gecos: usuario
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    ssh_authorized_keys:
      - ssh-rsa PASTE-YOUR-PUBLIC-KEY-HERE
EOF


## Feed user-data and meta-data to the ISO seed / requieres cloud-utils package
cloud-localds "$seed_iso" user-data meta-data

## We can also create the ISO with genisoimage / requires genisoimage package
#genisoimage -output ${seed_iso} -volid cidata -joliet -rock user-data meta-data

##
## create a virtual machine using vboxmanage
##
vmname="ubuntu-${ubuntuversion}-1"
vboxmanage createvm --name "$vmname" --register
vboxmanage modifyvm "$vmname" \
   --memory 512 --boot1 disk --acpi on \
   --nic1 nat --natpf1 "guestssh,tcp,,2222,,22"
## Another option for networking would be:
##   --nic1 bridged --bridgeadapter1 eth0
vboxmanage storagectl "$vmname" --name "IDE_0"  --add ide
vboxmanage storageattach "$vmname" \
    --storagectl "IDE_0" --port 0 --device 0 \
    --type hdd --medium "$my_disk1"
vboxmanage storageattach "$vmname" \
    --storagectl "IDE_0" --port 1 --device 0 \
    --type dvddrive --medium "$seed_iso"
## Enable a serial COM device, the cloud image won't boot otherwise
vboxmanage modifyvm "$vmname" \
 --uart1 0x3F8 4 --uartmode1 server my.ttyS0

## start up the VM
vboxheadless --vnc --startvm "$vmname"

## You should be able to connect to the vnc port that vboxheadless
## showed was used.  The default would be '5900', so 'xvcviewer :5900'
## to connect.
##
## Also, after the system boots, you can ssh in with 'ubuntu:passw0rd'
## via 'ssh -p 2222 ubuntu@localhost'
##
## To see the serial console, where kernel output goes, you
## can use 'socat', like this:
##   socat UNIX:my.socket -

## vboxmanage controlvm "$vmname" poweroff
vboxmanage controlvm "$vmname" poweroff

## clean up after ourselves
vboxmanage storageattach "$vmname" \
   --storagectl "IDE_0" --port 0 --device 0 --medium none
vboxmanage storageattach "$vmname" \
   --storagectl "IDE_0" --port 1 --device 0 --medium none
vboxmanage closemedium dvd "${seed_iso}"
vboxmanage closemedium disk "${my_disk1}"
vboxmanage unregistervm $vmname --delete
