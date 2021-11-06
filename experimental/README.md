# Experimental File

Longhorn deployment

![Singlenode](https://user-images.githubusercontent.com/624501/140608524-71338149-8783-4f71-95f7-2bbf98601aec.jpeg)

![Multinode](https://user-images.githubusercontent.com/624501/140608527-963febc4-7165-4591-b235-54a7f79a9abf.jpeg)

## Files

* 4-csi-storage-longhorn.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. But longhorn will consume huge CPU resource. If you want to use Longhorn, You should use vCPU 8 core or add another worker node.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.

## Instruction.

replace 4-csi-storage.sh to 4-csi-storage-longhorn.sh.
