# Experimental File

## Caution
Longhorn single node doesn't work volumesnapshot. (Deploy application was OK.)　--> Give up orz...

Alternetive approach, Rook Ceph. I have replaced from Longhorn to Ceph. 

## Diagram

Rook Ceph deployment

![containerd2](https://user-images.githubusercontent.com/624501/141034286-7468198b-b267-4107-b91e-da186dc2b80f.jpeg)

![containerd3](https://user-images.githubusercontent.com/624501/141034298-91f53b80-1ed1-4e7d-9c94-4d37e4c369d0.jpeg)

## Files

* 4-csi-storage-ceph.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. You need to addtional block device. ex /dev/sdb with no parition.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.

## Instruction.

replace 4-csi-storage.sh to 4-csi-storage-ceph.sh.
