#!/bin/bash
set -e
chroot="${HOME}/gentoo"

unmount() {
        mount | grep "$HOME/gentoo" | awk '{print $3}' |
                while read -r i
                do
                        umount -Rf "$i" > /dev/null 2>&1 || true
                done
}

rootch() {
        sudo mount --rbind /dev "${chroot}/dev"
        sudo mount --make-rslave "${chroot}/dev"
        sudo mount -t proc /proc "${chroot}/proc"
        sudo mount --rbind /sys "${chroot}/sys"
        sudo mount --make-rslave "${chroot}/sys"
        sudo mount --rbind /tmp "${chroot}/tmp"
        sudo mount --bind /run "${chroot}/run"
        sudo cp -L /etc/resolv.conf "${chroot}/etc/"
        sudo cp -a ./* "${chroot}/root/"
        sudo chroot "${chroot}" /root/docker.sh "$@"
}

bashin() {
        rootch /bin/bash
}

setup_chroot() {
        url="https://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd/"
        file="$(curl -s "$url" | grep -Eo 'href=".*"' | awk -F '>' '{print $1}' |
                sed -e 's/href=//g' -e 's/"//g' | grep -o "stage3-amd64-desktop-systemd-$(date +%Y).*.tar.xz" | uniq)"

        curl -sSL "${url}${file}" -o "/var/tmp/${file}"
        mkdir "$chroot"
        sudo tar -C "${chroot}" -xpf "/var/tmp/${file}" --xattrs-include='*.*' --numeric-owner 2>/dev/null
        sudo rm -rf "/var/tmp/${file}"
}

setup_build_cmd() {
        cd "$HOME" || exit
        rm -rf /etc/portage/
        emerge-webrsync
        cp -af "${HOME}/portage" /etc/
        sed -i "s/^J=.*/J=\"$(nproc --all)\"/" /etc/portage/make.conf
        ln -sf /var/db/repos/gentoo/profiles/default/linux/amd64/17.1/desktop/systemd /etc/portage/make.profile
        emerge dev-vcs/git app-accessibility/at-spi2-core
        rm -rf /var/db/repos/* 
        emerge --sync
}

build_cmd() {
        emerge -uDN --with-bdeps=y @world || exit 1
}

compress_cmd() {
        unmount
        root="${HOME}/gentoo"
        sudo rm -rf "${root}"{/var/cache/,/var/tmp/portage/,/tmp/portage/,/var/db/repos/}
        sudo tar cpf - "$root" "${root}.tar" --strip-components=1 --xattrs-include='*.*' --numeric-owner || true
        pigz -cf -p "$(nproc --all)" "${root}.tar" > "${root}.tar.gz"

}

upload() {
        docker import "gentoo.tar.gz" thecatvoid/gentoo:latest
        docker login -u thecatvoid -p "$PASS"
        docker push thecatvoid/gentoo:latest
}

# We got to do exec function inside gentoo chroot not on runner
setup_build() {
        rootch setup_build_cmd
}

build() {
        rootch build_cmd
}

compress() {
        rootch compress_cmd
}

# Exec functions when called as args
for cmd; do $cmd; done
trap 'unmount' EXIT
