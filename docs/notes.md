# Notes for using this repository

1. After running bootstrap on master, update cluster/argocd/root-app.yaml's repoURL to your repository URL and apply it with kubectl or import via Argo CD UI.

2. The repository uses HelmChart CRD placeholders for installing charts via Argo CD. Your Argo CD installation must support the HelmChart CRD (provided by the Helm Operator or via Flux HelmRelease). If your Argo CD doesn't support HelmChart, you can instead commit rendered manifests or use Argo CD's native Helm support by creating Application objects that point at charts.

3. Ensure MetalLB's IP range is appropriate for your LAN and not overlapping DHCP scopes.

4. Adjust Longhorn default replica count in cluster/components/longhorn/longhorn-helm.yaml if you have more than 3 nodes.
