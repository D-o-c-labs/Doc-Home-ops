---
machine:
  certSANs: {{ .Data.certSANs | toJson }}
