apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-secrets
  namespace: ${namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: db-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: ${connection_arn}
        property: DB_HOST
    - secretKey: DB_USERNAME
      remoteRef:
        key: ${rds_secret_arn}
        property: username
    - secretKey: DB_PASSWORD
      remoteRef:
        key: ${rds_secret_arn}
        property: password
