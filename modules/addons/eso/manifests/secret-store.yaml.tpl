apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: ${namespace}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${aws_region}
