variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  default     = "changeme"
  description = "Grafana admin password. Override in terraform.tfvars — do not commit the real value."
}
