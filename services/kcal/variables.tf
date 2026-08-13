variable "kcal_session_secret" {
  description = "Secret used to sign kcal session cookies (generate with: openssl rand -base64 32)"
  type        = string
  sensitive   = true
}

variable "kcal_image_tag" {
  description = "kcal image tag to deploy"
  type        = string
  default     = "latest"
}
