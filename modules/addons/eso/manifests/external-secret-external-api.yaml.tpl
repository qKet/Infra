apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: external-api-secrets
  namespace: ${namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: external-api-secrets
    creationPolicy: Owner
  data:
%{ for key in keys ~}
    - secretKey: ${key}
      remoteRef:
        key: ${external_api_arn}
        property: ${key}
%{ endfor ~}
