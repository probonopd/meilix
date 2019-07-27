#!/bin/bash

echo "Download the ISO to be customized..."
URL=http://cdimage.ubuntu.com/xubuntu/releases/18.04/release/xubuntu-18.04.2-desktop-amd64.iso
wget -q "$URL"

mv *.iso original.iso

echo "Mount the ISO..."

mkdir mnt
sudo mount -o loop,ro original.iso mnt/

echo "Extract .iso contents into dir 'extract-cd'..."

mkdir extract-cd
sudo rsync --exclude=/casper/filesystem.squashfs -a mnt/ extract-cd

echo "Extract the SquashFS filesystem..."

sudo unsquashfs -n mnt/casper/filesystem.squashfs
sudo mv squashfs-root edit

echo "Prepare chroot..."

# Mount needed pseudo-filesystems for the chroot
sudo mount --rbind /sys edit/sys
sudo mount --rbind /dev edit/dev
sudo mount -t proc none edit/proc
sudo mount -o bind /run/ edit/run
sudo cp /etc/hosts edit/etc/
# sudo mount --bind /dev/ edit/dev
# sudo cp -vr /etc/resolvconf edit/etc/resolvconf
sudo rm -rf edit/etc/resolv.conf || true
sudo cp /etc/resolv.conf edit/etc/

echo "Moving customization script to chroot..."
sudo mv customize.sh edit/customize.sh

echo "Entering chroot..."

sudo chroot edit <<EOF

echo "In chroot: Change host name..."
hostname ${TRAVIS_TAG}

echo "In chroot: Run customization script..."
chmod +x customize.sh && ./customize.sh && rm ./customize.sh

echo "In chroot: Removing packages..."
apt-get -y remove libreoffice-* gigolo thunderbird pidgin 
apt-get -y autoremove

echo "In chroot: Installing NVidia drivers..."
sudo -E add-apt-repository -y ppa:graphics-drivers
sudo apt-get -y install nvidia-340 nvidia-settings # run ubuntu-drivers devices on a local machine on this OS to find out the recmomended versions

echo "In chroot: Disabling nouveau..."
sudo apt-get -y purge xserver-xorg-video-nouveau || true
# https://linuxconfig.org/how-to-disable-nouveau-nvidia-driver-on-ubuntu-18-04-bionic-beaver-linux
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"

echo "In chroot: Installing proper Broadcom driver..."
sudo apt-get -y install b43-fwcutter 
sudo apt-get -y --reinstall install bcmwl-kernel-source

echo "In chroot: Disabling b43 which makes the screen flicker..."
sudo bash -c "echo blacklist b43 > /etc/modprobe.d/blacklist-b43.conf"

echo "In chroot: Delete temporary files..."
( cd /etc ; sudo rm resolv.conf ; sudo ln -s ../run/systemd/resolve/stub-resolv.conf resolv.conf )

rm -rf /tmp/* ~/.bash_history
exit
EOF

echo "Exiting chroot..."

# Unmount pseudo-filesystems for the chroot
sudo umount -lfr edit/proc
sudo umount -lfr edit/sys
sudo umount -lfr edit/dev

echo "Repacking..."

sudo chmod +w extract-cd/casper/filesystem.manifest

sudo su <<HERE
chroot edit dpkg-query -W --showformat='${Package} ${Version}\n' > extract-cd/casper/filesystem.manifest <<EOF
exit
EOF
HERE

sudo cp extract-cd/casper/filesystem.manifest extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/ubiquity/d' extract-cd/casper/filesystem.manifest-desktop
sudo sed -i '/casper/d' extract-cd/casper/filesystem.manifest-desktop

sudo mksquashfs edit extract-cd/casper/filesystem.squashfs -noappend
echo ">>> Recomputing MD5 sums"

sudo su <<HERE
( cd extract-cd/ && find . -type f -not -name md5sum.txt -not -path '*/isolinux/*' -print0 | xargs -0 -- md5sum > md5sum.txt )
exit
HERE

cd extract-cd 	
sudo mkisofs \
    -V "Custom OS" \
    -r -cache-inodes -J -l \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
	-o ../custom-desktop-amd64.iso .

cd ..

rm original.iso

# Write update information for use by AppImageUpdate; https://github.com/AppImage/AppImageSpec/blob/master/draft.md#update-information
echo "gh-releases-zsync|probonopd|system|latest|custom-*amd64.iso.zsync" | dd of="custom-desktop-amd64.iso" bs=1 seek=33651 count=512 conv=notrunc 2>/dev/null || true

# Write zsync file
zsyncmake *.iso

ls -lh *.iso
