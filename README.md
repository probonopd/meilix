# Ubuntu Live ISO customizer

Building a remastered System ISO using Travis CI and tools from https://github.com/fossasia/meilix

## Note

For smaller customizations, we could be even quicker by appending to the original squashfs rather than extracting it.

```
sudo su
mount SYSTEM /mnt
cp /mnt/specific_dir $home  ##modify $home/specific_dir as needed
mksquashfs /mnt new_squashfs_file -wildcards -e specific_dir
mksquashfs $home/specific_dir new_squashfs_file -keep-as-directory
umount /mnt  # cleanup
```

Source: https://unix.stackexchange.com/a/402658
