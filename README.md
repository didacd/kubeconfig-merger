# Script to merge kubeconfig files

#### Prerequisites:

> kubectl and [yq](https://linuxcommandlibrary.com/man/yq) will be necessary. Install them before using the script.

- To install yq please refer to the [official git repo](https://github.com/mikefarah/yq?tab=readme-ov-file#install).
- kubectl can be installed from the official [kubernetes.io install tools documentation](https://kubernetes.io/docs/tasks/tools/).

#### Usage:

```bash
./merge-kubeconfig.sh /path/to/kubeconfig
```

The script will take the kubeconfig file you want to merge as an argument.
The "user" will be renamed to `{cluster_name}-{user}` to avoid conflict between user & certificates.
