# Filebeat is broken right now wrt gomodules
variable "GO111MODULE" {
  default = "auto"
}

target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Elastic Filebeat"
    BUILD_DESCRIPTION = "A dubo image for Filebeat"
    GO111MODULE = "${GO111MODULE}"
  }
  tags = [
    "dubodubonduponey/filebeat",
  ]
}
