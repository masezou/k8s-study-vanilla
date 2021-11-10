# k8s-study-vanilla
Kubernetes single node automation

# Features

This script will create only 1 node which the server is control-plane and worker node.

This single k8s node includes local repository, minio, nfs server for nfs-csi driver

Storage class: hostpath-csi/nfs-csi/vSphere CSI. 

![Diagram1](https://user-images.githubusercontent.com/624501/140580948-258eb6a8-dbc4-42ff-8337-0e044d416a42.jpeg)

![contanierd1](https://user-images.githubusercontent.com/624501/141034401-efa5c990-212b-4591-847e-e85ab53c16c8.jpeg)

# Requirement

-Ubuntu Linux Server 20.04.3 amd64 4vCPU minimum 8GB RAM Recommend 16GB RAM 100G HDDB. (ARM is experimental)

-If you want to use vSphre CSI Driver, You need to have vCenter 6.7U3 above and any VM need to be set DISKUUID in option. At least 1 vCenter and 1 ESX. vCenter cluster is option.

![vsphere](https://user-images.githubusercontent.com/624501/140580806-104d5fb6-3c94-40fe-8f9c-1af4c85f9af1.png)

![DiskUUID](https://user-images.githubusercontent.com/624501/140580848-8a36ba87-3fa8-4ae2-b41d-9abfe690216c.png)

-Network segment 24bit is required

# Installation

Configure your clone. Before execute script, please change following.

* 3-configk8s.sh:IPRANGE: loadbalancer will be assigned this subnet, thus you need to set unused IP subnet.

* 5-csi-vsphere.sh/K3-kasten-vsphere.sh: vCenter configuration in vSphere  CSI driver and Kasten Storage setting.

Please see 00-Detailed_Instruction-En.txt



# Usage (Linux)

```bash
sudo -i
git clone https://github.com/masezou/k8s-study-vanilla
cd k8s-study-vanilla
./0-minio.sh ; ./1-tools.sh ; ./2-buildk8s-lnx.sh ; ./3-configk8s.sh; ./4-csi-storage.sh

If your environment is vSphere with vCenter 6.7U3 above. ./5-csi-vsphere.sh
```

# Note

* If you want to add separate storage volume, you can mount extra volume to /disk.

* Windows environment is not supported
