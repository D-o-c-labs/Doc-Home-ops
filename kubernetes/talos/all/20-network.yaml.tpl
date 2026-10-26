---
apiVersion: v1alpha1
kind: LinkAliasConfig
name: bond0-m0
selector:
  match: link.type == 1
---
apiVersion: v1alpha1
kind: BondConfig
name: bond0
links:
  - bond0-m0
bondMode: active-backup
---
apiVersion: v1alpha1
kind: DHCPv4Config
name: bond0
---
apiVersion: v1alpha1
kind: VLANConfig
name: bond0.40
vlanID: 40
parent: bond0
mtu: 1500
addresses:
  - address: {{ .Node.Data.domusAddress }}
---
apiVersion: v1alpha1
kind: StaticHostConfig
name: 192.168.32.120
hostnames:
  - k8s.piscio.net
