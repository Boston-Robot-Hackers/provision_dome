variable "config_profile" {
  description = "Profile in ~/.oci/config to authenticate with."
  type        = string
  default     = "DEFAULT"
}

variable "region" {
  description = "OCI region. Must be your home region for Always Free resources."
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "Compartment for all resources. Use the tenancy OCID for the root compartment (grep '^tenancy=' ~/.oci/config)."
  type        = string
}

variable "availability_domain" {
  description = "AD to place the instance in. A1 capacity varies by AD; try another on 'Out of host capacity'."
  type        = string
  default     = "OePW:US-ASHBURN-AD-1"
}

variable "instance_name" {
  description = "Display name for the instance and its network resources. Change it to stand up a second box without name collision."
  type        = string
  default     = "dome-cloud-1"
}

variable "ssh_public_key_path" {
  description = "Public key placed in the instance's authorized_keys. Only the public half leaves your Mac."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vnc_test" {
  description = "TEMPORARY: when true, open the public noVNC test ports (48210 view-only, 48211 control) to 0.0.0.0/0. Steady state is false (SSH-only). Driven by `make vnc-up` / `make vnc-down`; do not commit as true."
  type        = bool
  default     = false
}

variable "ocpus" {
  description = "A1.Flex OCPU count. The Always Free arm allowance is 4 OCPU total across all A1 instances."
  type        = number
  default     = 4
}

variable "memory_gb" {
  description = "A1.Flex memory in GB. The Always Free arm allowance is 24 GB total across all A1 instances."
  type        = number
  default     = 24
}

variable "boot_volume_gb" {
  description = "Boot volume size in GB."
  type        = number
  default     = 100
}
