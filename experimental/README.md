# Experimental File

## Caution
Alternetive approach, Rook Ceph vs. csi-hostpath. I recommend to set vCPU 8 above. Ceph spends much cpu resource on node.

## Diagram

Rook Ceph deployment

![5-single vm ceph](https://user-images.githubusercontent.com/624501/141036193-7acbc09c-ff08-44be-9c6f-fba0acad3aa5.jpeg)

![8-vm2](https://user-images.githubusercontent.com/624501/141036237-ab5886f3-55cf-4f65-9a11-4f6142563b6c.jpeg)

## Files

* 5-csi-storage-ceph.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. You need to addtional block device. ex /dev/sdb with no parition.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.

## Instruction.

replace 4-csi-storage.sh to 4-csi-storage-ceph.sh.
