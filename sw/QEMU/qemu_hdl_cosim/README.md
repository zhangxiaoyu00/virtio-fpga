<span style="display: inline-block;">
    
The original work can be found at [qemu-hdl-cosim](https://github.com/RSPwFPGAs/qemu-hdl-cosim)

# Table of Contents
1. [Overview of qemu-hdl-cosim](#overview)
2. [Install Qemu and Create a VM image](#installhost)
3. [Run Co-Simulation](#runcosim)
    - [Start Vivado XSim in Host Machine](#runxsim)
    - [Start QEMU in Host Machine](#runqemu)
    - [Test with Ping in Guest Machine](#testping)
    - [Test with ixy in Guest Machine](#testixy)

<a name="overview"></a>
Overview
----------------------------
This folder contains the necessary patch to QEMU and script to launch the VM with a FPGA cosim card attached.


Prerequisites
----------------------------
This release has been tested with the following tools:
>
>```
>Ubuntu 18.04.3, Ubuntu 20.04.1
>Vivado 2018.3, Vivado 2020.2
>QEMU 2.10 rc3
>```

Environment variables to set
----------------------------
>
>```
>COSIM_REPO_HOME -> Current dir
>COSIM_PORT -> Any 4-digit number. If you want to run multiple instances on 
>              the same machine, each one needs to have a different number.
>```

<a name="installhost"></a>
# Install Qemu and Create a VM image

Compile QEMU
----------------------------
1. Install Dependencies:
>
>```bash
>    sudo apt update && sudo apt upgrade
>    sudo apt-get install build-essential autoconf libtool python vim 
>    sudo apt-get install libzmq3-dev libczmq-dev libncurses5-dev libncursesw5-dev libsdl2-dev

2. Download QEMU 2.10 rc3

>
>```bash
>    cd $COSIM_REPO_HOME/qemu
>    wget http://download.qemu-project.org/qemu-2.10.0-rc3.tar.xz
>    tar -xJf qemu-2.10.0-rc3.tar.xz

3. Apply the patches

    Apply one patch for the co-simulation and [another patch for memfd.c](https://git.qemu.org/?p=qemu.git;a=commitdiff;h=75e5b70e6b5dcc4f2219992d7cffa462aa406af0).

>
>```bash
>    patch -s -p0 < qemu-cosim.patch
>    patch -s -p0 < qemu-memfd.patch
>    patch -s -p0 < qemu-iotrace.patch

4. Configure and build

>
>```bash
>    cd qemu-2.10.0-rc3
>    mkdir build
>    cd build
>    ../configure --target-list=x86_64-softmmu --disable-vnc --enable-sdl --enable-curses
>
>    sed -i 's/LIBS+=/LIBS+=-lzmq -lczmq /g' config-host.mak
>
>    make -j32

5. Copy the launch script

>
>```bash
>    cp ../../../scripts/launch_fpga.sh .
>    cd ../../

Create a QEMU image
----------------------------
1. Create a QEMU image file called cosim.qcow2 in $COSIM_REPO_HOME/qemu and install Ubuntu 16.04.3.

>
>```bash
>    qemu-2.10.0-rc3/build/qemu-img create -f qcow2 cosim.qcow2 16G
>    sudo qemu-2.10.0-rc3/build/x86_64-softmmu/qemu-system-x86_64 -boot d -cdrom /path/to/ubuntu-18.04.4-live-server-amd64.iso -smp cpus=2 -accel kvm -m 4096 -hda cosim.qcow2
>    (name: user; passwd: user)

2. Launch QEMU in one terminal

>
>```bash
>    cd $COSIM_REPO_HOME/qemu/qemu-2.10.0-rc3/build
>    ./launch_fpga.sh
>    (sudo -E x86_64-softmmu/qemu-system-x86_64 -m 4G -enable-kvm -cpu host -smp cores=1 -drive file=../../cosim.qcow2,cache=writethrough -device accelerator-pcie -redir tcp:2200::22 -display none -device virtio-net-pci,disable-modern=on)

3. Log in to the VM in another terminal

>
>```bash
>    ssh -p 2200 user@localhost

4. In the VM, Install necessary packages

>
>```bash
>    sudo apt-get update
>    sudo apt-get upgrade -y
>    sudo apt-get install build-essential

Upgrade kernel(Ubuntu 18.04 only, reboot needed)
----------------------------
1.  In the VM, upgrade the Ubuntu 18.04 kernel to version 5.3

>
>```bash
>    sudo apt-get install --install-recommends linux-generic-hwe-18.04

Shutdown and Backup the image
----------------------------
1. In the VM, Shutdown the VM

>
>```bash
>    sudo poweroff

2. In the host, Backup the installed image
>
>```bash
>    cd $COSIM_REPO_HOME/qemu
>    zip cosim.qcow2.zip cosim.qcow2

<a name="runcosim"></a>
# Run co-simulation

<a name="runxsim"></a>
## Start Vivado XSim in Host Machine

1. In the host, Launch Vivado XSim Simulation in the 1st terminal

>
>```bash
>    cd $COSIM_REPO_HOME/../../../hw/prj/qemu_hdl_cosim/
>    make build-cosim

The waveform window will show AXI transactions when the application is launched in the VM.

<a name="runqemu"></a>
## Start QEMU in Host Machine

1. In the host, Launch QEMU with accelerator in the 2nd terminal

>
>```bash
>    cd $COSIM_REPO_HOME/qemu/qemu-2.10.0-rc3/build
>    ./launch_fpga.sh
>    (sudo -E x86_64-softmmu/qemu-system-x86_64 -m 4G -enable-kvm -cpu host -smp cores=1 -drive file=../../cosim.qcow2,cache=writethrough -device accelerator-pcie -redir tcp:2200::22 -display none -device virtio-net-pci,disable-modern=on)

2. In the host, Log in to the VM in the 3rd terminal

>
>```bash
>    ssh -p 2200 user@localhost

<a name="testping"></a>
## Test with Ping in Guest Machine

1. In the VM, Test the interface with Ping 

>
>```bash
>    sudo ifconfig ens4 up
>    ping -I ens4 10.10.10.10
>    sudo ifconfig ens4 down

<a name="testixy"></a>
## Test with ixy in Guest Machine

1. In the VM, Test the interface with [ixy](https://github.com/RSPwFPGAs/ixy)

>
>```bash
>    cd ixy
>    sudo ./setup-hugetlbfs.sh
>    cd build
>    cmake .
>    make
>    sudo ./ixy-pktgen  0000:00:04.0



