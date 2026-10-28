variable "minepanel_jwt_secret" {
  type        = string
  sensitive   = true
  description = "Session signing secret for MinePanel. Generate with: openssl rand -base64 32"
}
