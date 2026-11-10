output "state_bucket" {
  description = "Bucket name used in infra/backend.tf"
  value       = aws_s3_bucket.state.bucket
}

output "plan_user" {
  description = "Create its access key with the AWS CLI -> repo secrets PLAN_AWS_*"
  value       = aws_iam_user.plan.name
}

output "apply_user" {
  description = "Create its access key with the AWS CLI -> eks-sandbox environment secrets APPLY_AWS_*"
  value       = aws_iam_user.apply.name
}
