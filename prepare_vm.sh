#!/bin/bash

install_mininet() {
    echo "Install Mininet"
    # Prefer relying on last version of mininet
    git clone https://github.com/mininet/mininet.git
    pushd mininet
    git checkout 2.3.0d6
    popd
    ./mininet/util/install.sh
    # And avoid the famous trap of IP forwarding
    echo '
# Mininet: allow IP forwarding
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf
}

install_clang() {
    echo "Install CLANG"
    # Install clang 10
    echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-10 main" | sudo tee -a /etc/apt/sources.list
    echo "deb-src http://apt.llvm.org/bionic/ llvm-toolchain-bionic-10 main" | sudo tee -a /etc/apt/sources.list
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key|sudo apt-key add -
    sudo apt-get update
    sudo apt-get install -y clang-10 lldb-10 lld-10
}

install_dependencies() {
    echo "Install dependencies"
    sudo apt-get update
    sudo apt-get install -y flex bison automake make autoconf pkg-config cmake libarchive-dev libgoogle-perftools-dev openssl libssl-dev git virtualbox-guest-dkms tcpdump xterm iperf
    install_clang
}

install_iproute() {
    echo "Install MPTCP-aware version of ip route"
    # Install an MPTCP-aware version of ip route
    git clone https://github.com/multipath-tcp/iproute-mptcp.git
    pushd iproute-mptcp
    # Note: you might need to change this if you install another version of MPTCP
    git checkout mptcp_v0.94
    make
    sudo make install
    popd
}

install_minitopo() {
    echo "Install minitopo"
    # First, install mininet
    install_mininet
    # Then fetch the repository
    git clone https://github.com/qdeconinck/minitopo.git
    pushd minitopo
    # Install the right version of minitopo
    git checkout minitopo2
    # Get the current dir, and insert an mprun helper command
    echo "mprun() {" | sudo tee -a /etc/bash.bashrc
    printf 'sudo python %s/runner.py "$@"\n' $(pwd) | sudo tee -a /etc/bash.bashrc
    echo "}" | sudo tee -a /etc/bash.bashrc
    popd
}

install_pquic() {
    echo "Install PQUIC"
    # We first need to have picotls
    git clone https://github.com/p-quic/picotls.git
    pushd picotls
    git submodule update --init
    cmake .
    make
    popd

    # Now we can prepare pquic
    git clone https://github.com/p-quic/pquic.git
    pushd pquic
    # Go on a special branch for an additional multipath plugin
    git checkout mobicom20_mptp
    git submodule update --init
    cd ubpf/vm/
    make
    cd ../../picoquic/michelfralloc
    make
    cd ../..
    cmake .
    make
    # And also prepare plugins
    cd plugins
    CLANG=clang-10 LLC=llc-10 make
    cd ..
    popd
}

install_mptcp() {
    echo "Install MPTCP"
    # Let us rely on APT repo. For more details to build this, go to
    # http://multipath-tcp.org/pmwiki.php/Users/DoItYourself
    #sudo apt-key adv --keyserver hkps://keyserver.ubuntu.com:443 --recv-keys 379CE192D401AB61
    #sudo sh -c "echo 'deb https://dl.bintray.com/multipath-tcp/mptcp_deb stable main' > /etc/apt/sources.list.d/mptcp.list"
    #sudo apt-get update
    #sudo apt-get install -y linux-mptcp-4.14 linux-image-4.14.146.mptcp linux-headers-4.14.146.mptcp

    # On May 2021, our APT repository has been suspended because it was hosted on Bintray which is no longer available.
    # All packages are now available on Github Releases page only.
    # https://github.com/multipath-tcp/mptcp/releases
    # Download and install MPTCP packages manually.
    mkdir mptcp_packages
    wget -nv -O mptcp_packages/linux-headers https://github.com/multipath-tcp/mptcp/releases/download/v0.95.1/linux-headers-4.19.126.mptcp_20200611235134_amd64.deb
    sudo dpkg -i mptcp_packages/linux-headers
    wget -nv -O mptcp_packages/linux-image https://github.com/multipath-tcp/mptcp/releases/download/v0.95.1/linux-image-4.19.126.mptcp_20200611235134_amd64.deb
    sudo dpkg -i mptcp_packages/linux-image
    wget -nv -O mptcp_packages/linux-libc https://github.com/multipath-tcp/mptcp/releases/download/v0.95.1/linux-libc-dev_20200611235134_amd64.deb
    sudo dpkg -i mptcp_packages/linux-libc
    wget -nv -O mptcp_packages/linux-mptcp https://github.com/multipath-tcp/mptcp/releases/download/v0.95.1/linux-mptcp_v0.95.1_20200611235134_all.deb
    sudo dpkg -i mptcp_packages/linux-mptcp

    # The following runs the MPTCP kernel version 4.14.146 as the default one
    sudo cat /etc/default/grub | sed -e "s/GRUB_DEFAULT=0/GRUB_DEFAULT='Advanced options for Ubuntu>Ubuntu, with Linux 4.19.126.mptcp'/" > tmp_grub
    sudo mv tmp_grub /etc/default/grub
    sudo update-grub

    # Finally ask for MPTCP module loading at the loadtime
    echo "
# Load MPTCP modules
sudo modprobe mptcp_olia
sudo modprobe mptcp_coupled
sudo modprobe mptcp_balia
sudo modprobe mptcp_wvegas

# Schedulers
sudo modprobe mptcp_rr
sudo modprobe mptcp_redundant
# The following line will likely not work with versions of MPTCP < 0.95
sudo modprobe mptcp_blest

# Path managers
sudo modprobe mptcp_ndiffports
sudo modprobe mptcp_binder" | sudo tee -a /etc/bash.bashrc
}

install_dependencies
install_minitopo
install_iproute
install_pquic
install_mptcp

echo "+------------------------------------------------------+"
echo "|                                                      |"
echo "| The vagrant box is now provisioned.                  |"
echo "| If not done yet, please reload the vagrant box using |"
echo "|                                                      |"
echo "| vagrant reload                                       |"
echo "|                                                      |"
echo "| Once reloaded, you can get SSH access to the VM with |"
echo "|                                                      |"
echo "| vagrant ssh                                          |"
echo "|                                                      |"
echo "| Once connected, check that you have a mptcp running  |"
echo "| kernel using the following command in the VM         |"
echo "|                                                      |"
echo "| uname -a                                             |"
echo "|                                                      |"
echo "+------------------------------------------------------+"
