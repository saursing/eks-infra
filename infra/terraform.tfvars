# Committed on purpose: the pipeline reads these. Nothing secret goes here.
# Your IP for kubectl is NOT here: it comes from the GitHub repo variable KUBE_API_CIDRS,
# so it never shows up in a public repo.

# The pipeline's apply role creates the cluster, so it gets admin automatically.
# Add your own role here so YOU can run kubectl.
# Check the exact ARN with: aws iam get-role --role-name AccountFullAccessRole --query Role.Arn --output text
admin_principal_arns = [
  "arn:aws:iam::610331149376:role/managed/AccountFullAccessRole",
]
