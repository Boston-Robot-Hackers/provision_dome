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

variable "vnc_access" {
  description = "VNC desktop access mode (F14). \"public\" opens the single noVNC port 48210 to 0.0.0.0/0 for a controllable, VNC-password-protected desktop reachable by URL; \"tunnel\" and \"none\" keep the box SSH-only (tunnel reaches the loopback desktop over `ssh -L`). Must match DOME_VNC_ACCESS in the box's manifest/user.txt. `make vnc-up`/`vnc-down` toggle it as a manual override."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "tunnel", "public"], var.vnc_access)
    error_message = "vnc_access must be one of: none, tunnel, public."
  }
}

variable "vnc_allowed_cidr" {
  description = "Source CIDR allowed to reach the public noVNC port 48210 (F15.5). Defaults to the whole internet so a plain apply keeps working; `make vnc-up` overrides it with your own address as a /32, which is the path you should normally use. SSH (22) is unaffected — it is key-only and locking it to one address locks you out from anywhere else."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrhost(var.vnc_allowed_cidr, 0))
    error_message = "vnc_allowed_cidr must be a valid CIDR block, e.g. 203.0.113.4/32."
  }
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
