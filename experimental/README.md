# Experimental File

## Caution
Longhorn single node doesn't work volumesnapshot. (Deploy application was OK.)　--> Give up orz...

Alternetive approach, Rook Ceph. I have replaced from Longhorn to Ceph. 

## Diagram

Rook Ceph deployment

![Slide5](https://user-images.githubusercontent.com/624501/140750370-5fd5f89b-d2b7-4943-a0ab-333f222aac89.jpeg)

![Slide8](https://user-images.githubusercontent.com/624501/140750397-390323f0-2d32-4767-982f-b3e84d02ceca.jpeg)

## Files

* 4-csi-storage-ceph.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. You need to addtional block device. ex /dev/sdb with no parition.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.

## Instruction.

replace 4-csi-storage.sh to 4-csi-storage-ceph.sh.
