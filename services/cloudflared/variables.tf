variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "tunnel_secret" {
  type        = string
  sensitive   = true
  description = "Base64-encoded secret for the Cloudflare Tunnel (generate with: openssl rand -base64 32)"
}