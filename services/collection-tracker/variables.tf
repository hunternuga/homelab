variable "collection_postgres_password" {
  type      = string
  sensitive = true
}

variable "collection_ebay_client_id" {
  type      = string
  sensitive = true
}

variable "collection_ebay_client_secret" {
  type      = string
  sensitive = true
}

variable "collection_ha_token" {
  type      = string
  sensitive = true
}

variable "collection_ha_notify_service" {
  type        = string
  description = "Home Assistant notify service name, e.g. notify.mobile_app_hunters_iphone"
}

variable "collection_image_tag" {
  type    = string
  default = "latest"
}
