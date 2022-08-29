# k8s-study-vanilla
Kubernetes single node automation

# Features

This script will create only 1 node which the server is control-plane and worker node.

This single k8s node includes local repository, minio, nfs server for nfs driver

Storage class: Longhorn/nfs-sub/vSphere CSI. 

![Slide3](https://user-images.githubusercontent.com/624501/144965922-82ed2fae-6411-4879-952e-b17f1ed83691.jpeg)

![Slide5](https://user-images.githubusercontent.com/624501/165000833-f9e10191-0ce7-4ab0-aa4f-972d49fbe9b0.jpeg)


# Requirement

-Ubuntu Linux Server 20.04.4 amd64 4vCPU minimum 8GB RAM Recommend 16GB RAM 200GB HDD. (ARM is experimental)

-If you want to use vSphre CSI Driver, You need to have vCenter 6.7U3 above and any VM need to be set "disk.EnableUUID" and "ctkEnabled" in option. At least 1 vCenter and 1 ESX. vCenter cluster is option.

![Untitled](https://user-images.githubusercontent.com/624501/146712111-9c0d6b9d-a644-4c1c-b3c1-4bb0fda0e06c.jpg)

![image](https://user-images.githubusercontent.com/624501/185821252-2a1b4295-7b8a-4e7f-a588-fdd96d430135.png)

-Network segment 24bit is required

# Installation

Configure your clone. Before execute script, please change following.

* 3-configk8s.sh:   IPRANGE: loadbalancer will be assigned this subnet, thus you need to set unused IP subnet.

* 5-csi-vsphere.sh: vCenter configuration in vSphere  CSI driver and Kasten Storage setting.

Please read 00-Detailed_Instruction-En.txt (English) / 00-Detailed_Instruction-Ja.txt (Japanese) also.



# Usage (deploy kubernetes)

```bash
sudo -i
git clone https://github.com/masezou/k8s-study-vanilla
cd k8s-study-vanilla
```
Execute each step.
```bash
./0-minio.sh ;./1-tools.sh ; ./2-buildk8s-lnx.sh ; ./3-configk8s.sh ; ./4-csi-storage.sh
```

Then if your Ubuntu VM is on vSphere with vCenter 6.7U3 above. 
```bash
./5-csi-vsphere.sh
```


After Installation, you can review installation result.
```bash
./result.sh
```

# Note

* If you want to add separate storage volume, you can mount extra volume to /disk.

* Windows environment is not supported
