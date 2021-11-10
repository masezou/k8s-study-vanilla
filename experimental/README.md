# Experimental File

## Caution
Longhorn single node doesn't work volumesnapshot. (Deploy application was OK.)　--> Give up orz...

Alternetive approach, Rook Ceph. I have replaced from Longhorn to Ceph. 

## Diagram

Rook Ceph deployment

![5-single vm ceph](https://user-images.githubusercontent.com/624501/141036193-7acbc09c-ff08-44be-9c6f-fba0acad3aa5.jpeg)

![8-vm2](https://user-images.githubusercontent.com/624501/141036237-ab5886f3-55cf-4f65-9a11-4f6142563b6c.jpeg)

## Files

* 4-csi-storage-ceph.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. You need to addtional block device. ex /dev/sdb with no parition.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.

## Instruction.

replace 4-csi-storage.sh to 4-csi-storage-ceph.sh.
