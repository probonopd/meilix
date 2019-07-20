#!/bin/bash

sudo apt update
sudo apt-get -y install -qq squashfs-tools genisoimage

echo "Download the ISO to be customized..."
wget -q http://cdimage.ubuntu.com/lubuntu/releases/16.04/release/lubuntu-16.04.6-desktop-amd64.iso

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

sudo mount -o bind /run/ edit/run
sudo cp /etc/hosts edit/etc/
sudo mount --bind /dev/ edit/dev

echo "Moving customization script to chroot..."
sudo mv set-wallpaper.sh edit/set-wallpaper.sh

echo "Entering chroot..."

sudo chroot edit <<EOF

echo "In chroot: Change host name..."
hostname ${TRAVIS_TAG}

echo "In chroot: Run customization script..."
chmod +x set-wallpaper.sh && ./set-wallpaper.sh && rm ./set-wallpaper.sh

echo "In chroot: Removing packages..."
apt-get -y remove libreoffice-* onboard-*

#echo "In chroot: Installing packages..."
#apt-yet -y install libreoffice-* onboard-*

# echo "In chroot: Install NVidia drivers..."
#
# sudo add-apt-repository -y ppa:graphics-drivers/ppa
# sudo apt update
# sudo apt install nvidia-415

echo "In chroot: Delete temporary files..."

rm -rf /tmp/* ~/.bash_history
exit
EOF

echo "Exiting chroot..."

sudo umount edit/dev

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
	-o ../custom_lubuntu-16.04.6-desktop-amd64.iso .
cd ..

rm original.iso
ls -lh *.iso
