# The only automated cost guard in the stack. `terraform destroy` is a manual
# control; a forgotten cluster is the most likely real incident for a POC, and
# these budgets are what makes it announce itself.

resource "aws_budgets_budget" "monthly" {
  count = var.enable_budget_alarm ? 1 : 0

  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Scope to THIS stack's resources, not the whole account. Requires the cost
  # allocation tags below to have been activated (up to 24h) — see aws_ce_cost_allocation_tag.
  #
  # NOTE: the AWS Budgets TagKeyValue format is "user:<Key>$<Value>" — a literal
  # "$" separator. Writing that "$" next to a Terraform interpolation ("$${...}")
  # is the classic HCL escaping trap: "$${" is Terraform's escape sequence for a
  # LITERAL "${", so it does not interpolate at all and the filter matches
  # nothing. format() sidesteps the ambiguity entirely.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project_name)]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED" # warns BEFORE you spend it
    subscriber_email_addresses = [var.budget_notification_email]
  }
}

# Day-zero backstop: the tag-filtered budget above is blind until cost allocation
# tags are activated in Billing (a manual step, up to 24h to take effect) — precisely
# the window in which a first-time apply goes wrong. This budget has no cost_filter,
# so it covers the whole account and costs nothing extra.
resource "aws_budgets_budget" "account_backstop" {
  count = var.enable_budget_alarm ? 1 : 0

  name         = "${local.name}-account-backstop"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd * 2)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}

# Activated in Terraform rather than documented as a manual Billing-console step.
# Two caveats stay true even automated: activation can take up to 24h to take
# effect (the budget filter above matches nothing until then), and
# Karpenter-launched instances only carry these tags because Phase 5 renders them
# into EC2NodeClass.spec.tags — the provider's default_tags never reaches them.
resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "environment" {
  tag_key = "Environment"
  status  = "Active"
}
