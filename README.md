# eks-infra

Terraform for a sandbox EKS cluster (`devsecops-demo`) in AWS account **610331149376**, region **us-east-2**,
deployed only through GitHub Actions.

```
PR to main      ->  fmt -> init -> validate -> tflint -> checkov -> plan   (plan shown in the run summary)
merge to main   ->  same checks -> plan saved as tfplan -> WAIT for your approval -> apply that exact tfplan
```

| Folder | What | Who runs it |
| --- | --- | --- |
| `bootstrap/` | State bucket + `github-tf-plan` / `github-tf-apply` IAM users | You, once, from your Mac |
| `infra/` | VPC (2 AZs, 1 NAT) + EKS 1.36 with 2 x t3.medium nodes | The pipeline only |
| `.github/workflows/terraform.yml` | The pipeline | GitHub |

Why IAM users instead of GitHub OIDC: this account's org SCP denies every OIDC-provider call.
The plan user is read-only; the apply user's keys live in the `eks-sandbox` environment, so only an approved job can use them.

## One-time setup (Mac terminal)

### 1. Log in to the right AWS account
```bash
export AWS_PROFILE=eks-sandbox
aws sts get-caller-identity          # "Account": "610331149376"
```

### 2. GitHub CLI
```bash
brew install gh
gh auth login
gh api user --jq .login               # saursing
```

### 3. Bootstrap (state bucket + two pipeline users)
```bash
cd ~/eks-infra/bootstrap
sed -i '' 's/your-github-username/saursing/' terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
Keep `bootstrap/terraform.tfstate` safe (it's git-ignored on purpose).

### 4. Check your role ARN in infra/terraform.tfvars
```bash
aws iam get-role --role-name AccountFullAccessRole --query Role.Arn --output text
```
If it prints something different (e.g. with a path like `/aws-reserved/...`), paste it into `infra/terraform.tfvars`.

### 5. Create the GitHub repo (don't push yet)
```bash
cd ~/eks-infra
gh repo create eks-infra --public --description "Sandbox EKS via Terraform + GitHub Actions"
```
Why public: on GitHub Free/Pro/Team, **required reviewers** (the approval gate) only work on public repos.
Nothing secret is in the code: keys live in GitHub secrets, and your IP is a repo variable.

### 6. Approval gate: `eks-sandbox` environment with you as required reviewer
```bash
MYID=$(gh api user --jq .id)
gh api -X PUT repos/saursing/eks-infra/environments/eks-sandbox \
  -F "reviewers[][type]=User" -F "reviewers[][id]=$MYID"
```
Check: repo **Settings -> Environments -> eks-sandbox** shows you under "Required reviewers".

### 7. Keys -> GitHub secrets, IP -> repo variable
Keys go straight from AWS into GitHub; they're never printed or saved to a file.
```bash
# plan user -> repo secrets (read-only user)
read -r PK PS <<< "$(aws iam create-access-key --user-name github-tf-plan --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)"
gh secret set PLAN_AWS_ACCESS_KEY_ID     -R saursing/eks-infra --body "$PK"
gh secret set PLAN_AWS_SECRET_ACCESS_KEY -R saursing/eks-infra --body "$PS"

# apply user -> ENVIRONMENT secrets (only the approved apply job can read them)
read -r AK AS <<< "$(aws iam create-access-key --user-name github-tf-apply --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)"
gh secret set APPLY_AWS_ACCESS_KEY_ID     -R saursing/eks-infra --env eks-sandbox --body "$AK"
gh secret set APPLY_AWS_SECRET_ACCESS_KEY -R saursing/eks-infra --env eks-sandbox --body "$AS"
unset PK PS AK AS

# your IP for kubectl
MYIP=$(curl -s https://checkip.amazonaws.com)
gh variable set KUBE_API_CIDRS -R saursing/eks-infra --body "[\"$MYIP/32\"]"

# check
gh secret list -R saursing/eks-infra                    # 2 PLAN_* secrets
gh secret list -R saursing/eks-infra --env eks-sandbox  # 2 APPLY_* secrets
gh variable list -R saursing/eks-infra                  # KUBE_API_CIDRS
```

### 8. First push: starts the first pipeline run
```bash
cd ~/eks-infra
git init -b main
git add .
git commit -m "EKS sandbox: Terraform + pipeline"
git remote add origin https://github.com/saursing/eks-infra.git
git push -u origin main
```
This push runs the pipeline on main: checks -> plan -> **waits for your approval**.

## Every change after that

```bash
git checkout -b my-change
# edit infra/*.tf
git commit -am "what changed" && git push -u origin my-change
gh pr create --fill                   # checks + plan run on the PR
gh pr checks --watch                  # wait for them
gh pr merge --squash                  # merge -> main run -> waits for approval
gh run watch                          # follow the main run
```

Approve: open the run (`gh run view --web`) -> **Review deployments** -> tick `eks-sandbox` -> **Approve and deploy**.
Read the plan in the run summary before approving. That review is the manual check.

## Use the cluster
```bash
aws eks update-kubeconfig --region us-east-2 --name devsecops-demo
kubectl get nodes                     # 2 nodes, Ready
```

## Cost and teardown
About **$5-6/day** (EKS control plane, 2 x t3.medium, 1 NAT gateway). To tear down, from your Mac:
```bash
cd ~/eks-infra/infra
MYIP=$(curl -s https://checkip.amazonaws.com)
export TF_VAR_endpoint_public_access_cidrs="[\"$MYIP/32\"]"
terraform init
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```
(Run as your own admin role; the pipeline doesn't destroy on purpose.)

## Notes
- **Stale plan:** if main changed after the plan was saved, apply fails with "Saved plan is stale". Re-run the workflow (`gh workflow run terraform-eks`) and approve the new plan.
- **No changes:** if the plan says "No changes", the apply job is skipped and nobody gets asked to approve.
- **Long-lived keys:** delete them when you're done with the sandbox:
  `aws iam list-access-keys --user-name github-tf-apply`, then `aws iam delete-access-key --user-name github-tf-apply --access-key-id <id>` (same for `github-tf-plan`).
- **No IRSA:** it needs an IAM OIDC provider, which the SCP blocks. Use EKS Pod Identity for pod AWS access.
- **Sandbox shortcuts:** the apply user has AdministratorAccess, and there's one NAT gateway. Scope both down before reusing this pattern for anything real.
