# Experimental File

## Files

* 4-csi-storage-longhorn.sh : csi-hostpath driver only supports single node. Longhorn supports single and multi node. But longhorn will consume huge CPU resource. If you want to use Longhorn, You should use vCPU 8 core or add another worker node.

* buildk8s-worker.sh : Adding worker node. Once install Ubuntu VM, then run this script, next, create token in Master node, then join the worker node.
