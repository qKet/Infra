output "role_arn" {
  description = "ALB Controller IRSA IAM 역할 ARN"
  value       = aws_iam_role.alb_controller.arn
}
