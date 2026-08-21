apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: redis-secrets
  namespace: ${namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: redis-secrets
    creationPolicy: Owner
  data:
    - secretKey: REDIS_HOST
      remoteRef:
        key: ${connection_arn}
        property: REDIS_HOST
