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

cleanup() {
        unmount
        root="${HOME}/gentoo"
        echo "will cite" | parallel --citation
        parallel --use-cpus-instead-of-cores sudo rm -rf -- {} 2>/dev/null ::: /opt/hostedtoolcache ::: /usr/local/lib/android ::: /usr/share/gradle* /usr/bin/gradle /usr/share/apache-maven* /usr/bin/mvn

parallel --use-cpus-instead-of-cores sudo rm -rf -- {} 2>/dev/null ::: /usr/local/share/vcpkg /usr/local/bin/vcpkg ::: /usr/share/miniconda ::: /usr/bin/conda /usr/local/lib/lein /usr/local/bin/lein \
/usr/local/bin/pulumi* /usr/share/java/selenium-server-standalone.jar /usr/local/share/phantomjs* \
/usr/local/bin/phantomjs /usr/local/share/chrome_driver /usr/bin/chromedriver /usr/local/share/gecko_driver \
/usr/bin/geckodriver /etc/php /usr/bin/composer /usr/local/bin/phpunit /var/lib/mysql /etc/mysql \
/usr/local/bin/sqlcmd /usr/local/bin/bcp /usr/local/bin/session-manager-plugin \
/usr/local/julia* /usr/bin/julia /usr/share/rust /home/runner/.cargo /home/runner/.rustup \
/home/runner/.ghcup /usr/local/bin/rake /usr/local/bin/rdoc /usr/local/bin/ri /usr/local/bin/racc \
/usr/local/bin/rougify /usr/local/bin/bundle /usr/local/bin/bundler /var/lib/gems /usr/share/swift /usr/local/bin/swift /usr/local/bin/swiftc /usr/bin/ghc /usr/local/.ghcup /usr/local/bin/stack \
/usr/local/bin/rebar3 /usr/share/sbt /usr/bin/sbt /usr/bin/go /usr/bin/gofmt /usr/local/bin/aws /usr/local/bin/aws_completer /usr/local/aws-cli /usr/local/aws /usr/local/bin/aliyun /usr/share/az_* \
/opt/az /usr/bin/az /usr/local/bin/azcopy* /usr/bin/azcopy /usr/lib/azcopy /usr/local/bin/oc /usr/local/bin/oras /usr/local/bin/packer /usr/local/bin/terraform /usr/local/bin/helm /usr/local/bin/kubectl \
/usr/local/bin/kind /usr/local/bin/kustomize /usr/local/bin/minikube /usr/libexec/catatonit/catatonit \
/usr/share/dotnet /usr/local/graalvm /usr/share/man /var/lib/apt/lists/* /var/cache/apt/archives/*

        sudo rm -rf "${root}"{/var/cache/,/var/tmp/portage/,/tmp/portage/,/var/db/repos/}
        docker rmi -f $(docker images -q) &>/dev/null
}
        
compress() {
    
        sudo tar cpf "${root}.tar" "$root" --strip-components=1 --xattrs-include='*.*' --numeric-owner || true
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

# Exec functions when called as args
for cmd; do $cmd; done
trap 'unmount' EXIT
