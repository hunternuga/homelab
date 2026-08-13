# kcal is deployed via its Helm chart (services/kcal/chart/kcal) rather than
# raw kubernetes_* resources — the first service in this repo to use Helm.
# The chart itself is reusable standalone by anyone else self-hosting kcal;
# this resource is just this cluster's install of it.

resource "helm_release" "kcal" {
  name      = "kcal"
  namespace = "homelab"
  chart     = "${path.module}/chart/kcal"

  set_sensitive {
    name  = "sessionSecret"
    value = var.kcal_session_secret
  }

  set {
    name  = "image.tag"
    value = var.kcal_image_tag
  }

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "ingress.host"
    value = "kcal.nuga.dev"
  }

  set {
    name  = "nodeSelector.homelab/role"
    value = "apps"
  }
}
