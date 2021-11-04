# k8s-study-vanilla
Kubernetes single node automation

# Features

This script will create only 1 node which the server is control-plane and worker node

# Requirement

-Ubuntu Linux Server 20.04.3 amd64 or arm64 4vCPU 16GB RAM 100GB

-If you want to use vSphre CSI Driver, You need to have vCenter 6.7U3 above and any VM need to set DISKUUID in option

-Network segment 24bit is required

# Installation

Configure your clone with ssh key then git clone this.


# Usage (Linux)

* Linux
```bash
sudo -i
git clone https://github.com/masezou/k8s-study-vanilla
cd k8s-study-vanilla
./0-minio.sh ; ./1-tools.sh ; ./2-buildk8s-lnx.sh ; ./3-configk8s.sh; ./4-csi-storage.sh

If your environment is vSphere with vCenter 6.7U3 above. ./5-csi-vsphere.sh
```

# Note

* Windows environment is not supported
