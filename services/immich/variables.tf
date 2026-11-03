variable "timezone" {
  type    = string
  default = "America/Denver"
}

variable "immich_db_password" {
  type        = string
  sensitive   = true
  description = "Password for Immich's Postgres database. Letters/digits only, no special characters (Immich's own recommendation)."
}
