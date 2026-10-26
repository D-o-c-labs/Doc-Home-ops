---
# The kubelet stays in v1alpha1: KubeletConfig has no extraMounts, and Talos rejects .machine.kubelet next to it
machine:
  kubelet:
    image: ghcr.io/siderolabs/kubelet:{{ .KubernetesVersion }}
    defaultRuntimeSeccompProfileEnabled: true
    disableManifestsDirectory: true
    extraConfig:
      maxPods: 150
      # Prune images before Ceph's MON_DISK_LOW (<30% avail) fires on the shared /var
      imageGCHighThresholdPercent: 65
      imageGCLowThresholdPercent: 55
    # openebs-hostpath local PVs live under /var/mnt/extra; the kubelet bind-mounts them itself,
    # and the default /var/mnt mount it gets is read-only
    extraMounts:
      - destination: /var/mnt/extra
        type: bind
        source: /var/mnt/extra
        options:
          - rbind
          - rshared
          - rw
---
apiVersion: v1alpha1
kind: KubeletConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeIP:
  validSubnets:
    - 192.168.32.0/24
