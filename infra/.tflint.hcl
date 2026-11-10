config {
  call_module_type = "local" # lint our code, not the registry modules' internals
}

plugin "terraform" {
  enabled = true
  preset  = "recommended" # unused vars, missing types, deprecated syntax, ...
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  # catches invalid instance types, bad regions, etc. before AWS does
}
