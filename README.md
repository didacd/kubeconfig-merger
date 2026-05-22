# Script to merge kubeconfig files

#### Prerequisites:

> kubectl is necessary. Install it before using the script.

- kubectl can be installed from the official [kubernetes.io install tools documentation](https://kubernetes.io/docs/tasks/tools/).

#### Usage:

```bash
./merge-kubeconfig.sh /path/to/kubeconfig
```

The script will take the kubeconfig file you want to merge as an argument.
It performs a standard safe merge with:

`KUBECONFIG=<default>:<incoming> kubectl config view --merge --flatten`

The merged kubeconfig is written to a temporary file, validated, and only then atomically replaces `~/.kube/config`. If an existing default kubeconfig is present, a timestamped backup is created first.
