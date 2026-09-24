terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }
}

# Authentication comes from ~/.oci/config (tenancy, user, fingerprint, key_file
# for the chosen profile). Only the region is surfaced as a variable, so it is
# visible and overridable without editing the config file.
provider "oci" {
  config_file_profile = var.config_profile
  region              = var.region
}
