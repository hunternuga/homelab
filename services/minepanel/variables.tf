variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}
