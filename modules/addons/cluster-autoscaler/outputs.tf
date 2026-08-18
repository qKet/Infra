output "role_arn" {
  description = "Cluster Autoscaler IRSA IAM 역할 ARN"
  value       = aws_iam_role.cluster_autoscaler.arn
}
