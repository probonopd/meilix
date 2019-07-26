#!/bin/bash

echo "Download the ISO to be customized..."
URL=http://cdimage.ubuntu.com/lubuntu/releases/18.10/release/lubuntu-18.10-desktop-amd64.iso
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

echo "Moving customization script to chroot..."
sudo mv customize.sh edit/customize.sh

echo "Entering chroot..."

sudo chroot edit <<EOF

echo "In chroot: Change host name..."
hostname ${TRAVIS_TAG}

echo "In chroot: Run customization script..."
chmod +x customize.sh && ./customize.sh && rm ./customize.sh

echo "In chroot: Removing packages..."
apt-get -y remove libreoffice-* onboard-*
apt-get -y autoremove

#echo "In chroot: Installing packages..."
#apt-yet -y install libreoffice-* onboard-*

echo "In chroot: Install NVidia drivers..."

# sudo -E add-apt-repository -y ppa:graphics-drivers
# Ugly workaround because the line before does not work
sudo bash -c 'echo "deb http://ppa.launchpad.net/graphics-drivers/ppa/ubuntu cosmic main" > /etc/apt/sources.list.d/graphics-drivers-ubuntu-ppa-cosmic.list'

sudo apt update
sudo apt-get -y install nvidia-driver-396 nvidia-settings
# https://www.pcsuggest.com/install-nvidia-drivers-ubuntu/ says # sudo apt-get -y install nvidia-378 nvidia-settings
# sudo apt-get -y install libcuda1-396 # nvidia-415

echo "In chroot: Delete temporary files..."

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
echo "gh-releases-zsync|probonopd|meilix|latest|custom-*amd64.iso.zsync" | dd of="custom-desktop-amd64.iso" bs=1 seek=33651 count=512 conv=notrunc 2>/dev/null || true

# Write zsync file
zsyncmake *.iso

ls -lh *.iso
