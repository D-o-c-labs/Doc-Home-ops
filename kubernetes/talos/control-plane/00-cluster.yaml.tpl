---
cluster:
  etcd:
    advertisedSubnets:
      - 192.168.32.0/24
---
apiVersion: v1alpha1
kind: KubeAPIServerConfig
certExtraSANs: {{ .Data.certSANs | toJson }}
extraArgs:
  # Enable MutatingAdmissionPolicy
  runtime-config: admissionregistration.k8s.io/v1beta1=true
  feature-gates: MutatingAdmissionPolicy=true
---
# Drop the default PodSecurity admission plugin (enforce: baseline)
apiVersion: v1alpha1
kind: KubeAdmissionControlConfig
name: PodSecurity
$patch: delete
---
apiVersion: v1alpha1
kind: KubeSchedulerConfig
config:
  apiVersion: kubescheduler.config.k8s.io/v1
  kind: KubeSchedulerConfiguration
  profiles:
    - schedulerName: default-scheduler
      pluginConfig:
        - name: PodTopologySpread
          args:
            defaultingType: List
            defaultConstraints:
              - maxSkew: 1
                topologyKey: kubernetes.io/hostname
                whenUnsatisfiable: ScheduleAnyway
---
# Cilium replaces kube-proxy, Flannel and CoreDNS
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
---
apiVersion: v1alpha1
kind: KubeCoreDNSConfig
enabled: false
---
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
---
# Schedule workloads on the control planes
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  topology.kubernetes.io/region: {{ .ClusterName }}
  topology.kubernetes.io/zone: m
taints:
  node-role.kubernetes.io/control-plane:
    $patch: delete
